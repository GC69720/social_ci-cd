from src.core.use_cases import register_user
from src.core.entities import User

class _Repo:
    def __init__(self): self.items = []
    def add(self, u: User): self.items.append(u)
    def list(self): return list(self.items)

def test_register_user():
    repo = _Repo()
    u = register_user(repo, "agent_mulder@xfiles.com", "Agent Mulder")
    assert u.display_name == "Agent Mulder"
    assert u.email == "agent_mulder@xfiles.com"
    assert len(repo.list()) == 1
