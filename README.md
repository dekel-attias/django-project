# django-project  
Relevant files:  
  matcher_app/views.py - contains the core function (candidate_finder).  
  matcher_app/models.py - contains the DB tables schema.  
  
# Set up instructions
First we need to install django:  
`python -m pip install Django`  
Then we need to run the server  
`python manage.py runserver`  
open the web browser on the localhost path (http://127.0.0.1:8000/[job_id]/candidate)  
(optional: (http://127.0.0.1:8000/[job_id]/candidate?limit=[max_number_of_candidates]))  

# test the project
I added a sample database (SQLite) with 1 job(job_id=1) and 8 candidates. Each one has some skills.
There are 5 suitable candidates for the job in the sample.

to add candidates/jobs/skils, run `python manage.py createsuperuser` and go to (http://127.0.0.1:8000/admin).
