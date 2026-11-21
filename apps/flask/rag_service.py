import re
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from typing import Dict, Any, List, Optional

# Cyclone Emergency Knowledge Base Documents
KNOWLEDGE_BASE = [
    {
        "id": "faq-cyclone-safety-01",
        "category": "cyclone_safety",
        "title": "Immediate Actions During Cyclone Landfall",
        "content": "During cyclone landfall, stay strictly indoors away from glass windows and doors. Seek shelter in an interior room or reinforced hallway on the lowest floor above potential flood surge. Turn off main electrical switches and gas supply. Do not venture out when the eye of the storm passes as extreme winds will resume suddenly from the opposite direction."
    },
    {
        "id": "faq-cyclone-flooding-02",
        "category": "flooding",
        "title": "Severe Water Logging and Flooding Protocol",
        "content": "If flood water enters your home, move to a higher floor immediately. Avoid attics without a roof escape route. Do not walk or drive through moving flood waters as 15 cm of moving water can knock you down. Disconnect all electric appliances to prevent electrocution."
    },
    {
        "id": "faq-cyclone-trapped-03",
        "category": "trapped",
        "title": "Trapped in Debris or Flooded Building",
        "content": "If you are trapped in collapsed structures or rising water: Conserve energy and phone battery. Cover your mouth to avoid inhaling dust. Tap rhythmically on pipes or walls rather than shouting continuously so rescue teams with acoustic sensors can locate you. Signal with a whistle or flashlight if available."
    },
    {
        "id": "faq-cyclone-medical-04",
        "category": "medical",
        "title": "First Aid and Emergency Medical Protocol",
        "content": "For heavy bleeding, apply firm, direct pressure with a clean cloth or bandage. Keep injured limbs elevated above heart level if no fractures are suspected. For hypothermia, remove wet clothing, wrap in dry blankets, and provide warm fluids if conscious. Keep emergency medication sealed in waterproof bags."
    },
    {
        "id": "faq-cyclone-shelter-05",
        "category": "shelter",
        "title": "Cyclone Safe Shelters and Evacuation",
        "content": "If instructed to evacuate by authorities, leave immediately along designated safe elevated corridors. Carry a lightweight disaster emergency kit with dry food, water purification tablets, identification documents, torch, power bank, and vital medicines. Seek official reinforced cyclone relief camps."
    },
    {
        "id": "faq-cyclone-food-water-06",
        "category": "food_water",
        "title": "Emergency Drinking Water and Food Safety",
        "content": "Assume tap water is contaminated after cyclone damage to pipelines. Boil water for at least 1 minute or use chlorine purification tablets before drinking. Eat only packaged or non-perishable canned food. Do not consume food that came in direct contact with flood waters."
    }
]

class EmergencyRAGService:
    def __init__(self):
        self.kb = KNOWLEDGE_BASE
        self.vectorizer = TfidfVectorizer(stop_words='english', ngram_range=(1, 2))
        corpus = [f"{item['title']} {item['content']}" for item in self.kb]
        self.doc_vectors = self.vectorizer.fit_transform(corpus)

    def retrieve(self, query: str, top_k: int = 2) -> List[Dict[str, Any]]:
        query_vec = self.vectorizer.transform([query])
        sims = cosine_similarity(query_vec, self.doc_vectors).flatten()
        top_indices = np.argsort(sims)[::-1][:top_k]
        
        matches = []
        for idx in top_indices:
            score = float(sims[idx])
            if score > 0.05: # Minimum relevance threshold
                matches.append({
                    "score": round(score, 3),
                    "document": self.kb[idx]
                })
        return matches

    def classify_emergency(self, text: str) -> Dict[str, Any]:
        """Deterministic category extraction from user description."""
        t = text.lower()
        
        if any(w in t for w in ["trap", "stuck", "under debris", "collapsed", "cannot escape", "pinned"]):
            return {"category": "rescue", "urgency": "CRITICAL", "needs": ["heavy_rescue", "debris_clearing"]}
        if any(w in t for w in ["medic", "bleed", "wound", "heart", "injur", "fracture", "pain", "unconscious", "hospital", "doctor"]):
            return {"category": "medical", "urgency": "HIGH", "needs": ["ambulance", "trauma_care", "first_aid"]}
        if any(w in t for w in ["evacuat", "rising water", "submerged", "flood level", "boat"]):
            return {"category": "evacuation", "urgency": "HIGH", "needs": ["boat_evacuation", "coastal_evacuation"]}
        if any(w in t for w in ["food", "water", "starv", "thirsty", "milk", "ration"]):
            return {"category": "food", "urgency": "MEDIUM", "needs": ["clean_water", "dry_rations"]}
        if any(w in t for w in ["shelter", "roof blown", "house broken", "stay", "camp"]):
            return {"category": "shelter", "urgency": "MEDIUM", "needs": ["safe_shelter", "relief_camp"]}
            
        return {"category": "general", "urgency": "MEDIUM", "needs": ["volunteer"]}

    def generate_guidance(self, query: str, user_category: Optional[str] = None) -> Dict[str, Any]:
        classification = self.classify_emergency(query)
        effective_category = user_category or classification["category"]
        
        retrieved_docs = self.retrieve(f"{query} {effective_category}")
        
        # Build factual guidance from retrieved documents
        if retrieved_docs:
            primary_doc = retrieved_docs[0]["document"]
            advice = primary_doc["content"]
            source = primary_doc["title"]
        else:
            advice = "Stay indoors in an interior reinforced room away from windows. Keep your phone charged and do not step into flood waters."
            source = "Standard Cyclone Emergency Protocol"

        return {
            "category": effective_category,
            "urgency": classification["urgency"],
            "suggested_needs": classification["needs"],
            "advice": advice,
            "source_doc": source,
            "citations": [d["document"]["title"] for d in retrieved_docs]
        }
