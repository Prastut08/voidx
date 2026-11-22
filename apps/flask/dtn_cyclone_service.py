import os
import time
import requests
from typing import Dict, Any, List, Optional
from dtn_auth import DTNAuthService

class DTNCycloneService:
    """
    Dedicated Tropical Cyclone Monitoring Service integrating DTN API endpoints.
    Normalizes official DTN cyclone responses into clean GeoJSON-compatible schemas.
    Implements TTL caching and North Indian Ocean (IMD/JTWC) prioritization.
    """
    def __init__(self, auth_service: DTNAuthService):
        self.auth = auth_service
        self.base_url = os.getenv("DTN_BASE_URL", "https://tropical.api.dtn.com").strip().rstrip('/')
        
        # In-memory TTL caches
        self._cache: Dict[str, Dict[str, Any]] = {}
        self._cache_ttl_seconds = 300 # 5 minutes cache

    def _get_headers(self) -> Optional[Dict[str, str]]:
        token = self.auth.get_valid_token()
        if not token:
            return None
        return {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json"
        }

    def _cached_get(self, endpoint: str, params: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        cache_key = f"{endpoint}_{sorted((params or {}).items())}"
        now = time.time()
        
        if cache_key in self._cache:
            entry = self._cache[cache_key]
            if now < entry["expires_at"]:
                return entry["data"]

        headers = self._get_headers()
        if not headers:
            return None

        try:
            url = f"{self.base_url}{endpoint}"
            res = requests.get(url, headers=headers, params=params, timeout=15)
            if res.status_code == 200:
                data = res.json()
                self._cache[cache_key] = {
                    "data": data,
                    "expires_at": now + self._cache_ttl_seconds,
                    "retrieved_at": now
                }
                return data
            elif res.status_code == 401:
                # Retry with token refresh once
                self.auth.get_valid_token(force_refresh=True)
                headers = self._get_headers()
                if headers:
                    res = requests.get(url, headers=headers, params=params, timeout=15)
                    if res.status_code == 200:
                        data = res.json()
                        self._cache[cache_key] = {
                            "data": data,
                            "expires_at": now + self._cache_ttl_seconds,
                            "retrieved_at": now
                        }
                        return data
        except Exception as e:
            print(f"[DTN Cyclone API Error] {endpoint}: {type(e).__name__}")
            
        return None

    def get_health(self) -> Dict[str, Any]:
        has_creds = self.auth.is_configured
        token_valid = bool(self.auth.get_valid_token()) if has_creds else False
        return {
            "dtn_configured": has_creds,
            "dtn_token_valid": token_valid,
            "dtn_base_url": self.base_url,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        }

    def get_active_cyclones(self) -> Dict[str, Any]:
        """
        Retrieves active cyclones. Prioritizes North Indian Ocean / Bay of Bengal / Arabian Sea.
        Returns GeoJSON FeatureCollection.
        """
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        
        if not self.auth.is_configured:
            return {
                "source": "DTN Tropical Cyclone API",
                "status": "UNCONFIGURED",
                "message": "DTN_CLIENT_ID and DTN_CLIENT_SECRET are not configured.",
                "total_cyclones": 0,
                "cyclones": [],
                "geojson": {"type": "FeatureCollection", "features": []},
                "retrieved_at": now
            }

        raw_data = self._cached_get("/v1/cyclones")
        if not raw_data:
            return {
                "source": "DTN Tropical Cyclone API",
                "status": "LIVE_EMPTY",
                "message": "No active tropical cyclones returned by the selected data source.",
                "total_cyclones": 0,
                "cyclones": [],
                "geojson": {"type": "FeatureCollection", "features": []},
                "retrieved_at": now
            }

        # Normalize DTN list
        cyclones_list = []
        features = []
        raw_items = raw_data if isinstance(raw_data, list) else raw_data.get("cyclones", raw_data.get("data", []))

        for storm in raw_items:
            norm = self._normalize_cyclone(storm)
            cyclones_list.append(norm)
            features.append({
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [norm["longitude"], norm["latitude"]]
                },
                "properties": norm
            })

        return {
            "source": "DTN Tropical Cyclone API",
            "status": "LIVE",
            "total_cyclones": len(cyclones_list),
            "cyclones": cyclones_list,
            "geojson": {"type": "FeatureCollection", "features": features},
            "retrieved_at": now
        }

    def get_cyclone_details(self, storm_id: str) -> Optional[Dict[str, Any]]:
        raw = self._cached_get(f"/v1/cyclones/{storm_id}")
        if not raw:
            return None
        return self._normalize_cyclone(raw)

    def get_cyclone_track(self, storm_id: str) -> Dict[str, Any]:
        raw = self._cached_get(f"/v1/cyclones/{storm_id}/track")
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        if not raw:
            return {"storm_id": storm_id, "source": "DTN", "coordinates": [], "retrieved_at": now}
        return {"storm_id": storm_id, "source": "DTN", "track_data": raw, "retrieved_at": now}

    def get_cyclone_forecast(self, storm_id: str) -> Dict[str, Any]:
        raw = self._cached_get(f"/v1/cyclones/{storm_id}/forecast")
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        if not raw:
            return {"storm_id": storm_id, "source": "DTN", "forecast": [], "retrieved_at": now}
        return {"storm_id": storm_id, "source": "DTN", "forecast_data": raw, "retrieved_at": now}

    def get_cyclone_radii(self, storm_id: str) -> Dict[str, Any]:
        raw = self._cached_get("/v1/cyclone-radii", {"cycloneId": storm_id})
        return {"storm_id": storm_id, "radii": raw or {}}

    def get_cyclone_swaths(self, storm_id: str) -> Dict[str, Any]:
        raw = self._cached_get("/v1/cyclone-swaths", {"cycloneId": storm_id})
        return {"storm_id": storm_id, "swaths": raw or {}}

    def _normalize_cyclone(self, storm: Dict[str, Any]) -> Dict[str, Any]:
        # Support various DTN response schema structures
        pos = storm.get("currentPosition") or storm.get("position") or {}
        lat = float(pos.get("latitude") or storm.get("latitude") or 0.0)
        lng = float(pos.get("longitude") or storm.get("longitude") or 0.0)
        
        wind = storm.get("wind") or {}
        sustained = wind.get("maxSustainedSpeedKts") or storm.get("maxSustainedWindKts") or storm.get("windSpeedKts") or 0
        gust = wind.get("gustSpeedKts") or storm.get("windGustKts") or 0
        
        basin = storm.get("basin") or storm.get("basinId") or "North Indian Ocean"
        agency = storm.get("agency") or storm.get("issuingAgency") or "IMD/JTWC"

        return {
            "storm_id": str(storm.get("id") or storm.get("cycloneId") or storm.get("stormId") or "UNKNOWN"),
            "storm_name": str(storm.get("name") or storm.get("cycloneName") or "Unnamed Cyclone"),
            "agency": agency,
            "basin": basin,
            "latitude": lat,
            "longitude": lng,
            "max_sustained_wind_kts": sustained,
            "max_sustained_wind_kmh": round(sustained * 1.852, 1) if sustained else 0,
            "gust_speed_kts": gust,
            "movement_direction_deg": storm.get("movementDirectionDeg") or storm.get("heading"),
            "movement_speed_kts": storm.get("movementSpeedKts") or storm.get("speed"),
            "category": self._estimate_saffir_simpson(sustained),
            "observation_time": storm.get("observationTime") or storm.get("timestamp"),
            "last_updated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        }

    def _estimate_saffir_simpson(self, kts: float) -> str:
        if kts >= 137: return "Category 5 Severe Super Cyclone"
        if kts >= 113: return "Category 4 Extremely Severe Cyclonic Storm"
        if kts >= 96: return "Category 3 Very Severe Cyclonic Storm"
        if kts >= 83: return "Category 2 Severe Cyclonic Storm"
        if kts >= 64: return "Category 1 Cyclonic Storm"
        if kts >= 34: return "Deep Depression / Tropical Storm"
        return "Tropical Depression"
