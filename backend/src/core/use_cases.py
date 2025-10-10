from .entities import User
from typing import Protocol, Iterable

class UserRepository(Protocol):
    def add(self, user: User) -> None: ...
    def list(self) -> Iterable[User]: ...

def register_user(repo: UserRepository, email: str, display_name: str | None = None) -> User:
    user = User.new(email=email, display_name=display_name)
    repo.add(user)
    return user
