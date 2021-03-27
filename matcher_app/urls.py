from django.urls import path

from . import views

urlpatterns = [
	path('<int:job_id>/candidate', views.get_candidate, name='candidate_finder'),
]
