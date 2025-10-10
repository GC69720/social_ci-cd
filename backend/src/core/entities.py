from dataclasses import dataclass
from uuid import UUID, uuid4

@dataclass(frozen=True)
class User:
    id: UUID
    email: str
    display_name: str | None = None

    @staticmethod
    def new(email: str, display_name: str | None = None) -> "User":
        return User(id=uuid4(), email=email, display_name=display_name)
