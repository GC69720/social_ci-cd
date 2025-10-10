from django.apps import AppConfig


class DbOrmConfig(AppConfig):
    name = "adapters.db.orm"
    label = "db_orm"  # étiquette courte de l'app (utilisée par migrations)
    verbose_name = "Adapters ORM"
