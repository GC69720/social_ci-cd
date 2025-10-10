from django.contrib import admin
from .models import UserORM


@admin.register(UserORM)
class UserORMAdmin(admin.ModelAdmin):
    list_display = ("id", "email", "created_at", "updated_at")
    search_fields = ("email",)
    ordering = ("id",)
