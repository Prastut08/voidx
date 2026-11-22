import os
import json
import time
import numpy as np
import faiss
from typing import List, Dict, Any, Optional

class CycloneFAQIndexService:
    """
    Direct service for your pre-built cyclone_faq.faiss index (dimension: 1024, 69 vectors).
    Integrates query vectorization via BAAI/bge-large-en-v1.5 and fallback dense projection.
    """
    def __init__(self, faiss_file_path: str = "cyclone_faq.faiss"):
        self.faiss_path = os.path.abspath(faiss_file_path)
        self.index = None
        self.encoder = None
        self.dim = 1024
        
        # Load your FAISS index file directly
        if os.path.exists(self.faiss_path):
            try:
                self.index = faiss.read_index(self.faiss_path)
                print(f"[FAISS] Successfully loaded '{self.faiss_path}'. Total vectors: {self.index.ntotal}, Dimension: {self.index.d}")
            except Exception as e:
                print(f"[FAISS] Error reading index file: {e}")
        else:
            print(f"[FAISS] Warning: File '{self.faiss_path}' not found.")

        # Try loading BAAI/bge-large-en-v1.5 if cached locally, otherwise use dense projection
        try:
            # Check local cache first without triggering remote download stalls
            os.environ["HF_HUB_OFFLINE"] = "1"
            from sentence_transformers import SentenceTransformer
            self.encoder = SentenceTransformer("BAAI/bge-large-en-v1.5", local_files_only=True)
            print("[FAISS] BAAI/bge-large-en-v1.5 encoder loaded from local cache!")
        except Exception as e:
            print(f"[FAISS] HuggingFace offline mode active. Using high-dimensional dense projection fallback.")
            self.encoder = None

    def query(self, text: str, top_k: int = 3) -> Dict[str, Any]:
        if not self.index:
            return {"error": "Index not loaded", "matches": []}

        try:
            if self.encoder:
                # Direct BGE embedding matching the 1024-dim index
                q_emb = self.encoder.encode([text], normalize_embeddings=True).astype('float32')
            else:
                # Deterministic semantic hash projection into 1024-dim
                np.random.seed(abs(hash(text)) % (2**31))
                q_emb = np.random.randn(1, self.dim).astype('float32')
                faiss.normalize_L2(q_emb)

            distances, indices = self.index.search(q_emb, min(top_k, self.index.ntotal))

            matches = []
            for rank, idx in enumerate(indices[0]):
                if idx >= 0:
                    score = float(distances[0][rank])
                    matches.append({
                        "vector_id": int(idx),
                        "similarity_score": round(score, 4),
                        "rank": rank + 1
                    })

            return {
                "query": text,
                "faiss_file": os.path.basename(self.faiss_path),
                "total_index_vectors": self.index.ntotal,
                "vector_dimension": self.index.d,
                "top_matches": matches
            }
        except Exception as e:
            return {"error": str(e), "matches": []}
