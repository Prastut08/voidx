import os
import math
import time
import json
import asyncio
import requests
from typing import Dict, Any, List, Optional
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()

from rescue_service import RescueCoordinationService, haversine_distance_km
from rag_service import EmergencyRAGService
from production_rag import ProductionRAGService
from cyclone_faq_service import CycloneFAQIndexService
from sos_manager import SOSManager, datetime_now_iso
from dtn_auth import DTNAuthService
from dtn_cyclone_service import DTNCycloneService

GROQ_API_KEY = os.getenv('GROQ_API_KEY')
GROQ_MODEL = os.getenv('GROQ_MODEL', 'qwen/qwen3.8-27b')

app = FastAPI(title="CycloneX Real-Time Emergency Coordination Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

rescue_service = RescueCoordinationService()
rag_service = EmergencyRAGService()
production_rag = ProductionRAGService()
cyclone_faq_service = CycloneFAQIndexService(os.path.join(os.path.dirname(__file__), '..', '..', 'cyclone_faq.faiss'))
sos_manager = SOSManager()
dtn_auth = DTNAuthService()
dtn_cyclone = DTNCycloneService(dtn_auth)

# Connected WebSocket Responders and Clients Manager
class ConnectionManager:
    def __init__(self):
        # socket_id -> {"ws": WebSocket, "user_id": str, "role": str, "lat": float, "lng": float}
        self.active_connections: Dict[str, Dict[str, Any]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, ws: WebSocket, user_id: str, role: str, lat: float, lng: float) -> str:
        await ws.accept()
        conn_id = f"{user_id}_{int(time.time() * 1000)}"
        async with self._lock:
            self.active_connections[conn_id] = {
                "ws": ws,
                "user_id": user_id,
                "role": role.upper(),
                "lat": lat,
                "lng": lng,
                "connected_at": time.time()
            }
        print(f"[WS] Client connected: {user_id} (Role: {role}, Lat: {lat}, Lng: {lng}) - Total: {len(self.active_connections)}")
        return conn_id

    async def disconnect(self, conn_id: str):
        async with self._lock:
            if conn_id in self.active_connections:
                del self.active_connections[conn_id]
        print(f"[WS] Client disconnected: {conn_id} - Remaining: {len(self.active_connections)}")

    async def broadcast_new_sos(self, sos_payload: Dict[str, Any], max_radius_km: float = 100.0) -> int:
        """Broadcast emergency alert to eligible connected responders based on distance & role."""
        delivered_count = 0
        sos_lat = float(sos_payload.get("latitude") or sos_payload.get("lat") or 0.0)
        sos_lng = float(sos_payload.get("longitude") or sos_payload.get("lng") or 0.0)
        category = str(sos_payload.get("category", "RESCUE")).upper()

        async with self._lock:
            for conn_id, client in list(self.active_connections.items()):
                client_lat = client["lat"]
                client_lng = client["lng"]
                role = client["role"]

                # Calculate Haversine distance from responder to emergency
                dist = haversine_distance_km(sos_lat, sos_lng, client_lat, client_lng)

                # Prioritize RESCUE_TEAM, VOLUNTEER, COORDINATOR, ADMIN within search radius
                is_eligible = role in ["VOLUNTEER", "RESCUE_TEAM", "COORDINATOR", "ADMIN", "USER"]
                if is_eligible and dist <= max_radius_km:
                    event = {
                        "type": "NEW_SOS_ALERT",
                        "event": "new_sos",
                        "sos": {
                            **sos_payload,
                            "distance_from_responder_km": round(dist, 2),
                        },
                        "timestamp": datetime_now_iso()
                    }
                    try:
                        await client["ws"].send_text(json.dumps(event))
                        delivered_count += 1
                    except Exception as e:
                        print(f"[WS] Error delivering to {conn_id}: {e}")

        return delivered_count

    async def broadcast_status_update(self, sos_id: str, status: str, responder_id: Optional[str] = None, extra: Optional[Dict[str, Any]] = None):
        """Two-way real-time notification to all connected parties about SOS claim or status transition."""
        event = {
            "type": "SOS_STATUS_UPDATE",
            "sos_id": sos_id,
            "status": status,
            "claimed_by": responder_id,
            "extra": extra or {},
            "timestamp": datetime_now_iso()
        }
        text = json.dumps(event)
        async with self._lock:
            for conn_id, client in list(self.active_connections.items()):
                try:
                    await client["ws"].send_text(text)
                except Exception as e:
                    print(f"[WS] Broadcast error to {conn_id}: {e}")

manager = ConnectionManager()

# Pydantic Schemas
class SOSCreateRequest(BaseModel):
    sos_id: Optional[str] = None
    user_id: Optional[str] = "CITIZEN_ANON"
    category: str = "RESCUE"
    description: str = "Emergency assistance requested"
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    severity: str = "HIGH"
    accuracy_meters: Optional[float] = 10.0
    people_affected: Optional[int] = 1
    preferred_assistance: Optional[List[str]] = []

class SOSAcceptRequest(BaseModel):
    responder_id: str
    responder_name: Optional[str] = "Volunteer Unit"
    responder_role: Optional[str] = "VOLUNTEER"

class SOSStatusUpdateRequest(BaseModel):
    status: str
    responder_id: Optional[str] = None
    note: Optional[str] = None

class NearbyFacilitiesRequest(BaseModel):
    lat: float
    lng: float
    facility_type: str = "hospital"  # hospital, pharmacy, clinic, medical
    radius_km: float = 10.0
    limit: int = 10

@app.post("/api/facilities/nearby")
async def find_nearby_facilities(request: NearbyFacilitiesRequest):
    """
    Find nearby medical facilities using Groq AI.
    Returns a list of facilities with name, address, distance, contact info.
    """
    if not GROQ_API_KEY:
        # Fallback to rescue service teams if Groq not available
        teams = rescue_service.find_nearest_teams(request.lat, request.lng, request.facility_type, max_results=request.limit)
        return {
            "facilities": teams,
            "source": "rescue_service_fallback",
            "user_location": {"lat": request.lat, "lng": request.lng}
        }

    prompt = f"""You are an emergency services locator. Find the nearest {request.facility_type} facilities to the coordinates:
Latitude: {request.lat}
Longitude: {request.lng}
Search radius: {request.radius_km} km
Maximum results: {request.limit}

Return a JSON array of facilities with this exact schema:
[
  {{
    "name": "Facility Name",
    "type": "hospital|clinic|pharmacy|medical_center",
    "address": "Full address",
    "lat": 12.3456,
    "lng": 78.9012,
    "distance_km": 2.5,
    "phone": "+91-XXXXXXXXXX",
    "is_24h": true,
    "specialties": ["emergency", "trauma", "cardiology"]
  }}
]

Only return verified real facilities. If exact coordinates unknown, estimate based on known landmarks.
Return empty array if none found. No extra text, just the JSON array."""

    try:
        response = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {GROQ_API_KEY}",
                "Content-Type": "application/json"
            },
            json={
                "model": GROQ_MODEL,
                "messages": [
                    {"role": "system", "content": "You are an emergency services locator. Respond strictly in valid JSON array format."},
                    {"role": "user", "content": prompt}
                ],
                "response_format": {"type": "json_object"},
                "temperature": 0.1,
                "max_tokens": 2000
            },
            timeout=15
        )

        if response.status_code == 200:
            data = response.json()
            content = data['choices'][0]['message']['content']
            facilities = json.loads(content)
            
            # Ensure it's a list
            if isinstance(facilities, dict):
                facilities = facilities.get("facilities", [])
            
            # Add distance calculation verification
            for f in facilities:
                if 'lat' in f and 'lng' in f:
                    f['distance_km'] = round(haversine_distance_km(request.lat, request.lng, f['lat'], f['lng']), 2)
            
            # Sort by distance
            facilities.sort(key=lambda x: x.get('distance_km', 999))
            
            return {
                "facilities": facilities[:request.limit],
                "source": "groq_ai",
                "user_location": {"lat": request.lat, "lng": request.lng}
            }
        else:
            print(f"Groq API error: {response.status_code} - {response.text}")
    except Exception as e:
        print(f"Error calling Groq for nearby facilities: {e}")

    # Fallback to rescue service
    teams = rescue_service.find_nearest_teams(request.lat, request.lng, request.facility_type, max_results=request.limit)
    return {
        "facilities": teams,
        "source": "rescue_service_fallback",
        "user_location": {"lat": request.lat, "lng": request.lng}
    }

@app.websocket("/ws/rescue")
async def websocket_rescue_endpoint(
    websocket: WebSocket,
    user_id: str = Query("ANON_USER"),
    role: str = Query("VOLUNTEER"),
    lat: float = Query(20.2961),
    lng: float = Query(85.8245)
):
    conn_id = await manager.connect(websocket, user_id=user_id, role=role, lat=lat, lng=lng)
    
    # Immediately send active pending emergency list on connect/reconnect
    active_requests = [
        s for s in sos_manager.requests.values() 
        if s.get("status") in ["PENDING", "SOS CREATED", "SERVER RECEIVED"]
    ]
    if active_requests:
        try:
            await websocket.send_text(json.dumps({
                "type": "PENDING_SOS_SYNC",
                "count": len(active_requests),
                "requests": active_requests
            }))
        except Exception:
            pass

    try:
        while True:
            data_text = await websocket.receive_text()
            try:
                msg = json.loads(data_text)
                action = msg.get("action")
                if action == "UPDATE_LOCATION":
                    if conn_id in manager.active_connections:
                        manager.active_connections[conn_id]["lat"] = float(msg.get("lat", lat))
                        manager.active_connections[conn_id]["lng"] = float(msg.get("lng", lng))
                elif action == "PING":
                    await websocket.send_text(json.dumps({"type": "PONG", "time": time.time()}))
            except Exception:
                pass
    except WebSocketDisconnect:
        await manager.disconnect(conn_id)
    except Exception as e:
        print(f"[WS Error]: {e}")
        await manager.disconnect(conn_id)

@app.post("/api/sos/create")
async def create_sos_endpoint(payload: SOSCreateRequest):
    data = payload.dict()
    # Normalize coordinates dynamically
    real_lat = data.get("latitude") if data.get("latitude") is not None else data.get("lat", 0.0)
    real_lng = data.get("longitude") if data.get("longitude") is not None else data.get("lng", 0.0)
    data["lat"] = real_lat
    data["lng"] = real_lng
    data["latitude"] = real_lat
    data["longitude"] = real_lng
    data["status"] = "PENDING"

    record = sos_manager.create_sos(data)
    record["status"] = "PENDING"

    # Find ranked nearby verified rescue units using Haversine
    nearest = rescue_service.find_nearest_teams(real_lat, real_lng, data.get("category"), max_results=3)

    # Real-Time WebSocket Broadcast to all connected volunteer/responder dashboards!
    delivered = await manager.broadcast_new_sos(record, max_radius_km=150.0)
    record["ws_broadcast_delivered_count"] = delivered

    return {
        "success": True,
        "sos": record,
        "nearest_teams": nearest,
        "responders_notified": delivered,
        "message": "SOS created and dispatched to real-time responders"
    }

@app.get("/api/sos/active")
async def get_active_sos():
    active = [
        s for s in sos_manager.requests.values()
        if s.get("status") not in ["RESOLVED", "CANCELLED"]
    ]
    return {"count": len(active), "sos_list": active}

@app.get("/api/sos/{sos_id}")
async def get_sos_detail(sos_id: str):
    sos = sos_manager.get_sos(sos_id)
    if not sos:
        raise HTTPException(status_code=404, detail="SOS request not found")
    return sos

@app.get("/api/sos/{sos_id}/status")
async def get_sos_status(sos_id: str):
    sos = sos_manager.get_sos(sos_id)
    if not sos:
        raise HTTPException(status_code=404, detail="SOS request not found")
    return {
        "sos_id": sos["sos_id"],
        "status": sos["status"],
        "assigned_team": sos.get("assigned_team"),
        "status_history": sos.get("status_history", [])
    }

@app.post("/api/sos/{sos_id}/accept")
async def accept_sos_endpoint(sos_id: str, accept_data: SOSAcceptRequest):
    sos = sos_manager.get_sos(sos_id)
    if not sos:
        raise HTTPException(status_code=404, detail="SOS request not found")

    # Atomic claiming check: prevent two responders from simultaneously claiming the same request
    current_status = sos.get("status")
    if current_status not in ["PENDING", "SOS CREATED", "SERVER RECEIVED"]:
        return {
            "success": False,
            "error": "ALREADY_CLAIMED",
            "message": f"SOS has already been claimed by {sos.get('assigned_team', {}).get('team_name', 'another responder')}",
            "sos": sos
        }

    sos["status"] = "ACCEPTED"
    assigned_info = {
        "responder_id": accept_data.responder_id,
        "team_name": accept_data.responder_name,
        "role": accept_data.responder_role,
        "accepted_at": datetime_now_iso(),
        "status": "RESPONDER_ASSIGNED"
    }
    sos["assigned_team"] = assigned_info
    sos["status_history"].append({
        "status": "ACCEPTED",
        "by": accept_data.responder_id,
        "timestamp": datetime_now_iso()
    })
    sos["status_history"].append({
        "status": "RESPONDER_ASSIGNED",
        "by": accept_data.responder_id,
        "timestamp": datetime_now_iso()
    })

    # Broadcast real-time two-way update to the original creator and other responders
    await manager.broadcast_status_update(
        sos_id=sos_id,
        status="ACCEPTED",
        responder_id=accept_data.responder_id,
        extra={"team_name": accept_data.responder_name}
    )

    return {
        "success": True,
        "sos": sos,
        "message": f"SOS claimed successfully by {accept_data.responder_name}"
    }

@app.post("/api/sos/{sos_id}/status")
async def update_sos_status(sos_id: str, body: SOSStatusUpdateRequest):
    sos = sos_manager.get_sos(sos_id)
    if not sos:
        raise HTTPException(status_code=404, detail="SOS request not found")

    new_status = body.status.upper()
    sos["status"] = new_status
    sos["status_history"].append({
        "status": new_status,
        "by": body.responder_id,
        "note": body.note,
        "timestamp": datetime_now_iso()
    })

    await manager.broadcast_status_update(sos_id, new_status, body.responder_id, {"note": body.note})
    return {"success": True, "sos": sos}

@app.get("/api/rescue/teams")
async def get_all_teams():
    return {"teams": rescue_service.get_all_teams()}

@app.get("/api/rescue/nearby")
async def get_nearby_teams(
    lat: float = Query(20.2961),
    lng: float = Query(85.8245),
    category: Optional[str] = None,
    limit: int = 5
):
    teams = rescue_service.find_nearest_teams(lat, lng, category, max_results=limit)
    return {
        "user_location": {"lat": lat, "lng": lng},
        "category": category,
        "teams": teams
    }

@app.post("/api/offline/relay")
async def offline_relay_endpoint(payload: Dict[str, Any]):
    messages = payload.get("messages", [])
    if isinstance(messages, dict):
        messages = [messages]
    result = sos_manager.receive_offline_relay(messages)
    return {"success": True, "relay_result": result}

@app.post("/api/offline/sync")
async def offline_sync_endpoint(payload: Dict[str, Any]):
    return await offline_relay_endpoint(payload)

@app.get("/api/cyclones/health")
async def get_cyclone_api_health():
    return dtn_cyclone.get_health()

@app.get("/api/cyclones/active")
async def get_active_cyclones():
    return dtn_cyclone.get_active_cyclones()

@app.get("/api/cyclones/{storm_id}")
async def get_cyclone_by_id(storm_id: str):
    data = dtn_cyclone.get_cyclone_details(storm_id)
    if not data:
        raise HTTPException(status_code=404, detail="Cyclone not found")
    return data

@app.get("/api/cyclones/{storm_id}/track")
async def get_cyclone_track(storm_id: str):
    return dtn_cyclone.get_cyclone_track(storm_id)

@app.get("/api/cyclones/{storm_id}/forecast")
async def get_cyclone_forecast(storm_id: str):
    return dtn_cyclone.get_cyclone_forecast(storm_id)

@app.get("/api/cyclones/{storm_id}/radii")
async def get_cyclone_radii(storm_id: str):
    return dtn_cyclone.get_cyclone_radii(storm_id)

@app.get("/api/cyclones/{storm_id}/swaths")
async def get_cyclone_swaths(storm_id: str):
    return dtn_cyclone.get_cyclone_swaths(storm_id)

@app.get("/api/cyclones/faq/search")
async def search_cyclone_faq_index(query: str = Query(...), limit: int = 3):
    return cyclone_faq_service.query(query, top_k=limit)

@app.get("/api/chat/emergency")
async def emergency_rag_chat(query: str = Query(...), category: Optional[str] = None):
    # Retrieve live cyclone context to ground answers with verified DTN data
    live_context = dtn_cyclone.get_active_cyclones()
    result = production_rag.answer_query(query, live_cyclone_context=live_context)
    guidance = rag_service.generate_guidance(query, category)
    
    # Also query your custom cyclone_faq.faiss index
    faiss_match = cyclone_faq_service.query(query, top_k=2)

    # Merge grounded answer and sources
    guidance["advice"] = result["answer"]
    guidance["sources"] = result["sources"]
    guidance["is_grounded"] = result["grounded"]

    return {
        "query": query,
        "guidance": guidance,
        "rag_metadata": {
            "faiss_verified": True,
            "citations": result["sources"],
            "retrieved_count": result["retrieved_count"],
            "custom_faiss_index": faiss_match
        }
    }

@app.get("/api/v1/")
async def v1_compatibility():
    return {
        "need": rescue_service.get_all_teams(),
        "give": []
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
