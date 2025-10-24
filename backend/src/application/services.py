from .dto import UserDTO
from .ports import UserRepoPort
from uuid import uuid4

class UserService:
    def __init__(self, repo: UserRepoPort):
        self.repo = repo

    def register(self, email: str, display_name: str | None = None) -> UserDTO:
        dto = UserDTO(id=str(uuid4()), email=email, display_name=display_name)
        self.repo.add(dto)
        return dto

    def list(self) -> list[UserDTO]:
        return list(self.repo.list())
