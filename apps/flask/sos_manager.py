import time
import uuid
from typing import Dict, Any, List, Optional

# Emergency Request Status Lifecycle
VALID_STATUSES = [
    "SOS CREATED",
    "LOCATION ACQUIRED",
    "RESCUE OPTIONS IDENTIFIED",
    "MESSAGE QUEUED",
    "OFFLINE RELAY",
    "SERVER RECEIVED",
    "TEAM ACKNOWLEDGED",
    "TEAM ASSIGNED",
    "TEAM EN ROUTE",
    "RESOLVED",
    "CANCELLED"
]

class SOSManager:
    def __init__(self):
        # In-memory store + persistent dictionary
        self.requests: Dict[str, Dict[str, Any]] = {}
        self.relayed_messages: Dict[str, Dict[str, Any]] = {}

    def create_sos(self, data: Dict[str, Any]) -> Dict[str, Any]:
        sos_id = data.get("sos_id") or f"SOS-{int(time.time())}-{uuid.uuid4().hex[:6].upper()}"
        
        now = time.time()
        record = {
            "sos_id": sos_id,
            "user_id": data.get("user_id", "ANON-DEVICE"),
            "device_id": data.get("device_id", "DEVICE-01"),
            "lat": float(data.get("lat", 0.0)),
            "lng": float(data.get("lng", 0.0)),
            "accuracy_meters": float(data.get("accuracy_meters", 10.0)),
            "category": data.get("category", "general"),
            "description": data.get("description", "Emergency assistance requested"),
            "severity": data.get("severity", "HIGH"),
            "people_affected": int(data.get("people_affected", 1)),
            "preferred_assistance": data.get("preferred_assistance", []),
            "created_at": data.get("timestamp") or datetime_now_iso(),
            "expires_at": data.get("expires_at", now + 86400), # 24 hrs
            "status": "SERVER RECEIVED",
            "assigned_team": None,
            "status_history": [
                {"status": "SOS CREATED", "timestamp": datetime_now_iso()},
                {"status": "SERVER RECEIVED", "timestamp": datetime_now_iso()}
            ],
            "relay_hops": int(data.get("relay_hops", 0)),
            "is_offline_synced": bool(data.get("is_offline_synced", False))
        }

        self.requests[sos_id] = record
        return record

    def get_sos(self, sos_id: str) -> Optional[Dict[str, Any]]:
        return self.requests.get(sos_id)

    def acknowledge_sos(self, sos_id: str, team_id: str, team_name: str) -> Optional[Dict[str, Any]]:
        sos = self.requests.get(sos_id)
        if not sos:
            return None

        sos["status"] = "TEAM ASSIGNED"
        sos["assigned_team"] = {
            "team_id": team_id,
            "team_name": team_name,
            "assigned_at": datetime_now_iso(),
            "status": "TEAM EN ROUTE"
        }
        sos["status_history"].append({
            "status": "TEAM ACKNOWLEDGED",
            "timestamp": datetime_now_iso()
        })
        sos["status_history"].append({
            "status": "TEAM ASSIGNED",
            "timestamp": datetime_now_iso()
        })
        sos["status_history"].append({
            "status": "TEAM EN ROUTE",
            "timestamp": datetime_now_iso()
        })
        return sos

    def receive_offline_relay(self, messages: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Store-carry-forward batch sync with deduplication and TTL expiration check."""
        synced_count = 0
        duplicate_count = 0
        expired_count = 0
        now = time.time()

        for msg in messages:
            msg_id = msg.get("sos_id")
            if not msg_id:
                continue

            expires_at = msg.get("expires_at", now + 3600)
            if expires_at < now:
                expired_count += 1
                continue

            if msg_id in self.requests:
                duplicate_count += 1
                continue

            # Ingest relayed message
            msg["is_offline_synced"] = True
            msg["relay_hops"] = int(msg.get("relay_hops", 0)) + 1
            self.create_sos(msg)
            synced_count += 1

        return {
            "synced_count": synced_count,
            "duplicate_count": duplicate_count,
            "expired_count": expired_count,
            "total_active_sos": len(self.requests)
        }

def datetime_now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
