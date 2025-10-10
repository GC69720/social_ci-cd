from __future__ import annotations
from typing import Optional, List

from application.dto import UserDTO
from adapters.db.orm.models import UserORM


def _to_dto(obj: UserORM) -> UserDTO:
    return UserDTO(
        id=str(obj.id) if getattr(obj, "id", None) is not None else None,
        email=obj.email,
        created_at=getattr(obj, "created_at", None),
        updated_at=getattr(obj, "updated_at", None),
    )


def list_users() -> List[UserDTO]:
    return [_to_dto(u) for u in UserORM.objects.all().order_by("id")]


def get_user_by_email(email: str) -> Optional[UserDTO]:
    try:
        return _to_dto(UserORM.objects.get(email=email))
    except UserORM.DoesNotExist:
        return None


def create_user(email: str) -> UserDTO:
    return _to_dto(UserORM.objects.create(email=email))


class DjangoUserRepo:
    @staticmethod
    def list_users() -> List[UserDTO]:
        return list_users()

    @staticmethod
    def get_user_by_email(email: str) -> Optional[UserDTO]:
        return get_user_by_email(email)

    @staticmethod
    def create_user(email: str) -> UserDTO:
        return create_user(email)
