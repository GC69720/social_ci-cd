from django import forms
from .models import UserORM


class UserForm(forms.ModelForm):
    class Meta:
        model = UserORM
        fields = ["email"]
