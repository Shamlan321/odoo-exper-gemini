from typing import List
import google.generativeai as genai
from src.utils.logging import logger
from src.config.settings import settings

class EmbeddingService:
    def __init__(self):
        genai.configure(api_key=settings.GOOGLE_API_KEY)

    async def get_embedding(self, text: str) -> List[float]:
        try:
            text = text.replace("\n", " ")
            if len(text) > 8000:
                text = text[:8000] + "..."
                
            response = genai.embed_content(
                model=settings.EMBEDDING_MODEL,
                content=text,
                task_type="retrieval_document"
            )
            return response['embedding']
        except Exception as e:
            logger.error(f"Error getting embedding: {e}")
            raise

