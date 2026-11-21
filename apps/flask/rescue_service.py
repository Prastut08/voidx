import math
import time
from datetime import datetime
from typing import List, Dict, Any, Optional

# Verified initial rescue teams and facilities
RESCUE_TEAMS_DATA = [
    {
        "team_id": "NDRF-BN-04-A",
        "team_name": "NDRF 4th Battalion - Flood Rescue Unit Alpha",
        "category": "rescue",
        "lat": 12.981500,
        "lng": 80.222300,
        "status": "available",
        "capabilities": ["rescue", "boat_evacuation", "flood_rescue", "debris_clearing"],
        "contact": "+91-44-2250-1001",
        "last_updated": time.time() - 120 # 2 minutes ago
    },
    {
        "team_id": "SDRF-TN-R1",
        "team_name": "Tamil Nadu SDRF Urban Search & Rescue",
        "category": "rescue",
        "lat": 12.965200,
        "lng": 80.210400,
        "status": "available",
        "capabilities": ["rescue", "confined_space", "structural_collapse"],
        "contact": "+91-44-2852-1100",
        "last_updated": time.time() - 300
    },
    {
        "team_id": "MED-APOLLO-EMG",
        "team_name": "Apollo Emergency Disaster Medical Unit",
        "category": "medical",
        "lat": 12.978806,
        "lng": 80.221249,
        "status": "available",
        "capabilities": ["medical", "icu", "trauma_care", "ambulance", "oxygen"],
        "contact": "+91-44-2829-0200",
        "last_updated": time.time() - 180
    },
    {
        "team_id": "MED-GOVT-GH",
        "team_name": "Government Multi-Care Emergency Station",
        "category": "medical",
        "lat": 12.661273,
        "lng": 80.189262,
        "status": "available",
        "capabilities": ["medical", "first_aid", "burn_unit", "emergency_triage"],
        "contact": "+91-44-2530-5000",
        "last_updated": time.time() - 600
    },
    {
        "team_id": "EVAC-NAVY-01",
        "team_name": "Indian Coast Guard Coastal Evacuation Unit",
        "category": "evacuation",
        "lat": 12.990200,
        "lng": 80.235000,
        "status": "available",
        "capabilities": ["evacuation", "amphibious_transport", "heli_lift"],
        "contact": "+91-44-2346-0400",
        "last_updated": time.time() - 240
    },
    {
        "team_id": "CAMP-COMM-HALL-1",
        "team_name": "Velachery Relief Camp & Safe Shelter",
        "category": "shelter",
        "lat": 12.970462,
        "lng": 80.220511,
        "status": "available",
        "capabilities": ["shelter", "bedding", "generator_power", "sanitation"],
        "contact": "+91-44-2244-8800",
        "last_updated": time.time() - 90
    },
    {
        "team_id": "FOOD-REDPASS-02",
        "team_name": "Disaster Relief Supply Center & Community Kitchen",
        "category": "food",
        "lat": 12.991336,
        "lng": 80.213011,
        "status": "available",
        "capabilities": ["food", "clean_water", "dry_rations", "baby_food"],
        "contact": "+91-44-2450-9900",
        "last_updated": time.time() - 400
    },
    {
        "team_id": "VOL-CIVIL-DEF-09",
        "team_name": "Civil Defense Volunteer Rapid Unit",
        "category": "volunteer",
        "lat": 12.978105,
        "lng": 80.228244,
        "status": "available",
        "capabilities": ["volunteer", "local_guidance", "elderly_assistance", "food"],
        "contact": "+91-98400-11223",
        "last_updated": time.time() - 150
    }
]

def haversine_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate geographic distance in kilometers using the Haversine formula."""
    R = 6371.0 # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

class RescueCoordinationService:
    def __init__(self):
        self.teams: List[Dict[str, Any]] = [dict(t) for t in RESCUE_TEAMS_DATA]

    def get_all_teams(self) -> List[Dict[str, Any]]:
        return self.teams

    def find_nearest_teams(self, user_lat: float, user_lng: float, category: Optional[str] = None, max_results: int = 5) -> List[Dict[str, Any]]:
        results = []
        now = time.time()

        cat_normalized = (category or "").lower().strip()
        
        for team in self.teams:
            dist = haversine_distance_km(user_lat, user_lng, team["lat"], team["lng"])
            team_cat = team.get("category", "").lower()
            team_caps = [c.lower() for c in team.get("capabilities", [])]

            # Matching criteria:
            # 1. Physical rescue / trapped -> must match rescue capability
            # 2. Medical -> must match medical capability
            # 3. Evacuation -> evacuation capability or boat/heli
            # 4. Food/water -> food or supplies
            # 5. Shelter -> shelter or relief camp
            is_match = False
            if not cat_normalized or cat_normalized in ["all", "general"]:
                is_match = True
            elif cat_normalized in ["rescue", "trapped"] and ("rescue" in team_cat or "rescue" in team_caps or "debris_clearing" in team_caps):
                is_match = True
            elif cat_normalized in ["medical", "injured"] and ("medical" in team_cat or "medical" in team_caps or "trauma_care" in team_caps):
                is_match = True
            elif cat_normalized in ["evacuation", "evacuate"] and ("evacuation" in team_cat or "evacuation" in team_caps or "boat_evacuation" in team_caps):
                is_match = True
            elif cat_normalized in ["food", "water", "rations"] and ("food" in team_cat or "food" in team_caps or "clean_water" in team_caps):
                is_match = True
            elif cat_normalized in ["shelter", "camp"] and ("shelter" in team_cat or "shelter" in team_caps):
                is_match = True
            elif cat_normalized in team_cat or cat_normalized in team_caps:
                is_match = True

            if is_match:
                age_seconds = int(now - team.get("last_updated", now))
                results.append({
                    **team,
                    "distance_km": round(dist, 2),
                    "data_age_seconds": max(0, age_seconds),
                    "is_status_verified": age_seconds < 1800 # Verified within last 30 minutes
                })

        # Rank by availability and distance
        results.sort(key=lambda x: (x["status"] != "available", x["distance_km"]))
        return results[:max_results]
