from src.application.services import UserService
from src.application.dto import UserDTO


class _Repo:
    def __init__(self) -> None:
        self.items: list[UserDTO] = []

    def add(self, dto: UserDTO) -> None:
        self.items.append(dto)

    def list(self) -> list[UserDTO]:
        return list(self.items)

    def get(self, user_id):  # pragma: no cover - not used in this test
        return next((item for item in self.items if item.id == user_id), None)


def test_user_service_register_preserves_display_name():
    repo = _Repo()
    service = UserService(repo)

    dto = service.register("agent_mulder@xfiles.com", "Agent Mulder")

    assert dto.display_name == "Agent Mulder"
    assert repo.items[0].display_name == "Agent Mulder"