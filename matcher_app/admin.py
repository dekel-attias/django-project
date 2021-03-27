from django.contrib import admin

# Register your models here.
from .models import Skill, Job, Candidate

admin.site.register(Skill)
admin.site.register(Candidate)
admin.site.register(Job)
