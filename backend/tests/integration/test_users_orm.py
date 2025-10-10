import pytest
from django.urls import reverse
from django.test import Client
from adapters.db.orm.models import UserAccount

pytestmark = pytest.mark.django_db

def test_users_orm_crud(client: Client):
    # List initial
    resp = client.get("/users/orm")
    assert resp.status_code == 200
    assert resp.json() == []

    # Create
    resp = client.post("/users/orm", data={"email": "foo@example.com"})
    assert resp.status_code == 201
    data = resp.json()
    assert data["email"] == "foo@example.com"

    # Ensure persisted
    assert UserAccount.objects.count() == 1

    # List again
    resp = client.get("/users/orm")
    assert resp.status_code == 200
    assert len(resp.json()) == 1
