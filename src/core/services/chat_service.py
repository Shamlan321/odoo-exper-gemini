from typing import List, Dict, Optional, Tuple
import google.generativeai as genai
from src.core.services.embedding import EmbeddingService
from src.core.services.db_service import DatabaseService
from src.config.settings import settings
from src.utils.logging import logger

class ChatService:
    def __init__(
        self,
        db_service: DatabaseService,
        embedding_service: EmbeddingService
    ):
        self.db_service = db_service
        self.embedding_service = embedding_service
        genai.configure(api_key=settings.GOOGLE_API_KEY)
        self.model = genai.GenerativeModel(settings.LLM_MODEL)

    async def retrieve_relevant_chunks(
        self,
        query: str,
        version: int,
        limit: int = 6
    ) -> List[Dict]:
        try:
            query_embedding = await self.embedding_service.get_embedding(query)
            chunks = await self.db_service.search_documents(
                query_embedding,
                version,
                limit
            )
            return chunks
        except Exception as e:
            logger.error(f"Error retrieving chunks: {e}")
            raise

    def prepare_context(self, chunks: List[Dict]) -> Tuple[str, List[Dict[str, str]]]:
        """Prepare context and sources from retrieved chunks."""
        context_parts = []
        sources = []
        
        for i, chunk in enumerate(chunks, 1):
            source_info = (
                f"Context:\n"
                f"Document: {chunk['url']}\n"
                f"Title: {chunk['title']}\n"
                f"Content: {chunk['content']}"
            )
            context_parts.append(source_info)
            sources.append({
                "url": chunk["url"],
                "title": chunk["title"]
            })
        
        return "\n\n---\n\n".join(context_parts), sources

    async def generate_response(
        self,
        query: str,
        context: str,
        conversation_history: Optional[List[Dict]] = None,
        stream: bool = False
    ):
        """Generate AI response based on query and context."""
        try:
            prompt = []
            prompt.append(settings.SYSTEM_PROMPT)
            
            if conversation_history:
                for message in conversation_history[-3:]:
                    prompt.append(f"User: {message['user']}")
                    prompt.append(f"Assistant: {message['assistant']}")
            
            prompt.append(f"Question: {query}\n\nRelevant documentation:\n{context}")
            
            response = self.model.generate_content(
                "\n".join(prompt),
                stream=stream
            )
            
            if stream:
                return response
            return response.text
            
        except Exception as e:
            logger.error(f"Error generating response: {e}")
            raise
