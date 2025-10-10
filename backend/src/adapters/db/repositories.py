from application.dto import UserDTO
from application.ports import UserRepoPort
from typing import Iterable
from uuid import UUID

class InMemoryUserRepo(UserRepoPort):
    def __init__(self):
        self._items: list[UserDTO] = []

    def add(self, dto: UserDTO) -> None:
        self._items.append(dto)

    def list(self) -> Iterable[UserDTO]:
        return list(self._items)

    def get(self, user_id: UUID) -> UserDTO | None:
        return next((u for u in self._items if u.id == user_id), None)
