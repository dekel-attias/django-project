from django.db import models
# Create your models here.


class Skill(models.Model):
    skill_text = models.CharField(max_length=200)


class Candidate(models.Model):
    title = models.CharField(max_length=200)
    skills = models.ManyToManyField('Skill')


class Job(models.Model):
    title = models.CharField(max_length=200)
    skills = models.ManyToManyField('Skill')
