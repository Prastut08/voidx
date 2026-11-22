"""
ProductionRAGService - Thin wrapper that uses cyclone_faq.faiss via EmergencyRAGService.
Hardcoded CYCLONE_KNOWLEDGE_DOCS removed. All retrieval is from the FAISS index.
"""
import os
from typing import Dict, Any, Optional, List

# Import the now-unified service so there is a single source of truth
from rag_service import EmergencyRAGService


class ProductionRAGService:
    """
    Wraps EmergencyRAGService to satisfy the existing answer_query() call-site
    in fastapi_server.py without changing its interface.
    """

    def __init__(self):
        self._rag = EmergencyRAGService()

    def answer_query(
        self,
        query: str,
        live_cyclone_context: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Returns a dict with keys: answer, grounded, sources, retrieved_count, top_score
        Compatible with the existing fastapi_server.py caller.
        """
        # Retrieve docs from cyclone_faq.faiss
        docs = self._rag.retrieve(query, top_k=3)

        citations: List[str] = [f"CycloneFAQ #{d['id']} [{d['category']}]" for d in docs]
        context_chunks: List[str] = [d["text"] for d in docs]

        # Optionally prepend live DTN cyclone telemetry as first context chunk
        if live_cyclone_context:
            total = live_cyclone_context.get("total_cyclones", 0)
            if total and total > 0:
                lines = [f"Live Cyclone Telemetry (DTN):"]
                for c in live_cyclone_context.get("cyclones", []):
                    lines.append(
                        f"- {c.get('storm_name')} | pos: {c.get('latitude')}, "
                        f"{c.get('longitude')} | wind: {c.get('max_sustained_wind_kmh', 0)} km/h"
                    )
                context_chunks.insert(0, "\n".join(lines))
                citations.insert(0, "DTN Tropical Cyclone API")
            elif live_cyclone_context.get("message"):
                context_chunks.insert(0, f"Live status: {live_cyclone_context['message']}")
                citations.insert(0, "DTN Tropical Cyclone API")

        # Generate answer
        answer = self._rag._groq_answer(query, context_chunks) if (self._rag.groq_ok and context_chunks) else None
        if not answer:
            answer = context_chunks[0] if context_chunks else (
                "No verified cyclone emergency guidance found. "
                "Press 'Send SOS' if you are in immediate danger."
            )

        return {
            "answer":          answer,
            "grounded":        bool(docs),
            "sources":         citations,
            "retrieved_count": len(docs),
            "top_score":       1.0,
        }
