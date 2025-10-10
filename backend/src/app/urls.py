from django.contrib import admin
from django.urls import path
from adapters.api import views as api_views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("health", api_views.health),
    path("users/orm", api_views.users_orm),
]
