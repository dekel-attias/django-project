# Create your views here.
from django.http import JsonResponse, Http404, HttpResponseBadRequest
from django.db.models import Count, Q
from matcher_app.models import Candidate, Job


DEFAULT_CANDIDATE_LIMIT = 10


def get_candidate(request, job_id):
    """
    Given job_id, returning JsonResponse with the top candidates for the job.
    Args:
        request: Django request
        job_id: The requested job id.
        limit(as GET param): The maximum number of the most qualified candidate
    Returns:
        A json response
        example: {"candidates": [{"id": 1,"match_percent": 70}, ...]}.
    """
    try:
        job = Job.objects.get(pk=job_id)
    except Job.DoesNotExist:
        raise Http404("Job does not exist")

    try:
        limit = int(request.GET.get("limit", default=str(DEFAULT_CANDIDATE_LIMIT)))
    except ValueError:
        return HttpResponseBadRequest("Limit is not an integer")

    result = []
    candidates = candidate_finder(job, limit=limit)
    for candidate_id, match in candidates:
        result.append({"id": candidate_id, "match_percent": match})
    return JsonResponse({"candidates": result})


def candidate_finder(job, limit=DEFAULT_CANDIDATE_LIMIT):
    """
    Given a job, return the most qualified candidates for the job, according to shared skills and job title.
    Args:
        job: The requested job.
        limit: The maximum number of the most qualified candidate
    Returns:
        A list of top [limit] candidate. Each item contains the (candidate_id, matching_percentage).
    """
    required_skills = job.skills.all()
    # Filter the candidates with the same title as the job's title, then count the number of skills in the intersection
    # between each candidate and the job. Order the candidates by the number of shared skills,
    # and return the candidate's ID.
    candidate_list = (Candidate.objects
                      .filter(title=job.title)
                      .values("id")
                      .annotate(skills=Count('skills', filter=Q(skills__in=required_skills)))
                      .order_by("-skills")[:limit])
    num_of_required_skills = len(required_skills)
    # For each candidate return the ID and the matching % with the job.
    candidates = []
    for candidate in candidate_list:
        candidates.append((candidate['id'], candidate['skills']*100/num_of_required_skills))
    return candidates
