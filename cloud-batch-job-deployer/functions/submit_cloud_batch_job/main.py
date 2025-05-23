# functions/submit_cloud_batch_job/main.py
import functions_framework
import os
import json
import uuid
from google.cloud import batch_v1
from google.protobuf.duration_pb2 import Duration

# Environment variables (set these in Terraform for the Cloud Function)
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
GCP_REGION = os.environ.get("GCP_REGION")
DEFAULT_DOCKER_IMAGE_URI = os.environ.get("DEFAULT_DOCKER_IMAGE_URI")
BATCH_JOB_SERVICE_ACCOUNT = os.environ.get("BATCH_JOB_SERVICE_ACCOUNT")
# New environment variable for the Pub/Sub topic for notifications
BATCH_JOB_NOTIFICATION_TOPIC = os.environ.get("BATCH_JOB_NOTIFICATION_TOPIC") # e.g., projects/my-project/topics/my-batch-notifications


@functions_framework.http
def submit_batch_job_http(request):
    """
    HTTP-triggered Cloud Function to submit a Google Cloud Batch job.
    Expects a JSON payload with job parameters.
    Configures job notifications to a Pub/Sub topic.
    """
    if request.method != "POST":
        return "Only POST requests are accepted", 405

    try:
        request_json = request.get_json(silent=True)
        if not request_json:
            return "Invalid JSON payload", 400
    except Exception as e:
        print(f"Error parsing JSON: {e}")
        return "Error parsing JSON payload", 400

    print(f"Received request to submit batch job: {request_json}")

    if not GCP_PROJECT_ID or not GCP_REGION or not DEFAULT_DOCKER_IMAGE_URI or not BATCH_JOB_SERVICE_ACCOUNT:
        print("Error: Missing critical environment variables for Project ID, Region, Docker Image, or Batch SA.")
        return "Function configuration error: Missing environment variables.", 500
    
    if not BATCH_JOB_NOTIFICATION_TOPIC:
        print("Warning: BATCH_JOB_NOTIFICATION_TOPIC environment variable is not set. Job notifications will not be configured.")


    job_name_prefix = request_json.get("job_name_prefix", "java-batch-job-")
    job_name_suffix = str(uuid.uuid4()).split('-')[0]
    job_name = f"{job_name_prefix.lower().strip()[:50]}{job_name_suffix}"
    job_name = ''.join(filter(lambda x: x.isalnum() or x == '-', job_name))
    if not job_name or not job_name[0].islower(): 
        job_name = "job-" + job_name if job_name else "job-" + job_name_suffix


    docker_image = request_json.get("docker_image_uri", DEFAULT_DOCKER_IMAGE_URI)
    if not docker_image:
        return "Docker image URI must be provided either in request or as default in function config.", 400

    java_app_args = request_json.get("java_app_args", [])
    if not isinstance(java_app_args, list):
        return "'java_app_args' must be a list of strings.", 400

    # Environment variables for the container
    container_env_vars_dict = request_json.get("container_env_vars", {})
    if not isinstance(container_env_vars_dict, dict):
        return "'container_env_vars' must be a dictionary.", 400
    
    # Ensure all values in container_env_vars_dict are strings, as required by Batch API
    processed_container_env_vars = {k: str(v) for k, v in container_env_vars_dict.items()}


    machine_type = request_json.get("machine_type", "e2-standard-2")
    max_run_duration_str = request_json.get("max_run_duration", "3600s")
    
    try:
        if max_run_duration_str.endswith('s'):
            seconds = int(max_run_duration_str[:-1])
        else:
            seconds = int(max_run_duration_str)
        max_duration_proto = Duration(seconds=seconds)
    except ValueError:
        print(f"Invalid max_run_duration format: {max_run_duration_str}. Using default 3600s.")
        max_duration_proto = Duration(seconds=3600)


    client = batch_v1.BatchServiceClient()

    runnable = batch_v1.types.Runnable()
    runnable.container = batch_v1.types.Runnable.Container(
        image_uri=docker_image,
        commands=java_app_args,
    )
    
    task = batch_v1.types.TaskSpec(
        runnables=[runnable],
        compute_resource=batch_v1.types.ComputeResource(
            cpu_milli=1000,
            memory_mib=2048
        ),
        max_run_duration=max_duration_proto,
        # Corrected way to set environment variables for the task
        environment=batch_v1.types.Environment(variables=processed_container_env_vars)
    )

    group = batch_v1.types.TaskGroup(task_count=1, task_spec=task)

    allocation_policy = batch_v1.types.AllocationPolicy(
        instances=[
            batch_v1.types.AllocationPolicy.InstancePolicyOrTemplate(
                policy=batch_v1.types.AllocationPolicy.InstancePolicy(
                    machine_type=machine_type,
                )
            )
        ],
        service_account=batch_v1.types.ServiceAccount(email=BATCH_JOB_SERVICE_ACCOUNT)
    )

    logs_policy = batch_v1.types.LogsPolicy(
        destination=batch_v1.types.LogsPolicy.Destination.CLOUD_LOGGING
    )

    job_notifications = []
    if BATCH_JOB_NOTIFICATION_TOPIC:
        notification = batch_v1.types.JobNotification(
            pubsub_topic=BATCH_JOB_NOTIFICATION_TOPIC,
            message=batch_v1.types.JobNotification.Message(
                type=batch_v1.types.JobNotification.Type.JOB_STATE_CHANGED
            )
        )
        job_notifications.append(notification)
        print(f"Configuring job notifications to Pub/Sub topic: {BATCH_JOB_NOTIFICATION_TOPIC}")


    job = batch_v1.types.Job(
        task_groups=[group],
        allocation_policy=allocation_policy,
        logs_policy=logs_policy,
        notifications=job_notifications if job_notifications else None,
        labels={"env": "dev", "function_triggered": "true", "app": "java-processor"}
    )

    try:
        created_job = client.create_job(
            parent=f"projects/{GCP_PROJECT_ID}/locations/{GCP_REGION}",
            job=job,
            job_id=job_name,
        )
        print(f"Successfully created Cloud Batch job: {created_job.name}")
        return {
            "message": "Cloud Batch job created successfully.",
            "job_name": created_job.name,
            "job_id": job_name,
            "notifications_configured": bool(job_notifications)
        }, 201
    except Exception as e:
        print(f"Error creating Cloud Batch job: {e}")
        # Consider logging the full traceback for detailed debugging
        import traceback
        print(traceback.format_exc())
        return f"Error creating Cloud Batch job: {str(e)}", 500
