from src.core.use_cases import register_user
from src.core.entities import User

class _Repo:
    def __init__(self): self.items = []
    def add(self, u: User): self.items.append(u)
    def list(self): return list(self.items)

def test_register_user():
    repo = _Repo()
    u = register_user(repo, "john@example.com", "John")
    assert u.email == "john@example.com"
    assert len(repo.list()) == 1
