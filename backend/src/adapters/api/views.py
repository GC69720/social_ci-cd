from __future__ import annotations
import json
from django.http import JsonResponse, HttpRequest
from django.views.decorators.csrf import csrf_exempt
from adapters.db.orm.repository import DjangoUserRepo


def health(request: HttpRequest):
    return JsonResponse({"status": "ok"})


@csrf_exempt
def users_orm(request: HttpRequest):
    if request.method == "GET":
        users = DjangoUserRepo.list_users()
        data = [u.model_dump() if hasattr(u, "model_dump") else u.__dict__ for u in users]
        return JsonResponse(data, safe=False)

    if request.method == "POST":
        try:
            data = request.POST or json.loads(request.body.decode() or "{}")
        except json.JSONDecodeError:
            data = {}
        email = (data.get("email") or "").strip()
        if not email:
            return JsonResponse({"error": "email required"}, status=400)
        user = DjangoUserRepo.create_user(email=email)
        payload = user.model_dump() if hasattr(user, "model_dump") else user.__dict__
        return JsonResponse(payload, status=201)

    return JsonResponse({"detail": "Method not allowed"}, status=405)
