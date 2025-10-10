from django.db import models


class UserORM(models.Model):
    email = models.EmailField(unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "users"
        app_label = "db_orm"

    def __str__(self) -> str:
        return self.email
