from pydantic import BaseModel
import os

class Settings(BaseModel):
    env: str = os.getenv("ENV", "dev")
    api_base: str = os.getenv("API_BASE", "http://localhost:8000")

settings = Settings()
