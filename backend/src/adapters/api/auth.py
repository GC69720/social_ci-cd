from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
import os

@api_view(["GET"])
@permission_classes([IsAuthenticated])
def me(request):
    user = request.user
    return Response({"id": user.id, "username": user.get_username(), "email": user.email})

@api_view(["GET"])
def ping_mongo(_request):
    mongo_url = os.getenv("MONGO_URL", "mongodb://localhost:27017")
    try:
        from pymongo import MongoClient
        client = MongoClient(mongo_url, serverSelectionTimeoutMS=500)
        client.admin.command("ping")
        return Response({"mongo": "ok", "url": mongo_url})
    except Exception as e:
        return Response({"mongo": "error", "detail": str(e)}, status=503)
