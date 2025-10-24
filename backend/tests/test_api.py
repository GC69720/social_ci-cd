import pytest
from django.test import Client

from adapters.db.orm.models import UserORM
from adapters.db.orm.repository import DjangoUserRepo

pytestmark = pytest.mark.django_db


def test_users_orm_get_returns_expected_payload_structure(client: Client) -> None:
    existing_users = [
        UserORM.objects.create(email="alice@example.com"),
        UserORM.objects.create(email="bob@example.com"),
    ]

    response = client.get("/api/users/orm")

    assert response.status_code == 200
    payload = response.json()
    assert isinstance(payload, list)
    assert len(payload) == len(existing_users)

    expected_keys = {"id", "email", "display_name", "created_at", "updated_at"}
    returned_emails = []
    for entry in payload:
        assert set(entry.keys()) == expected_keys
        assert entry["id"]
        assert entry["created_at"]
        assert entry["updated_at"]
        assert entry["display_name"] is None
        returned_emails.append(entry["email"])

    assert returned_emails == [user.email for user in existing_users]


def test_users_orm_post_creates_user_and_persists_in_repository(client: Client) -> None:
    email = "charlie@example.com"

    response = client.post("/api/users/orm", data={"email": email})

    assert response.status_code == 201
    payload = response.json()
    expected_keys = {"id", "email", "display_name", "created_at", "updated_at"}
    assert set(payload.keys()) == expected_keys
    assert payload["email"] == email
    assert payload["id"]

    repo_user = DjangoUserRepo.get_user_by_email(email)
    assert repo_user is not None
    assert repo_user.email == email
    assert repo_user.id == payload["id"]
    assert repo_user.created_at is not None
    assert repo_user.updated_at is not None

    assert UserORM.objects.filter(email=email).exists()
