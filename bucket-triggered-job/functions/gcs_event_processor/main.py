# functions/gcs_event_processor/main.py
import functions_framework
import os
import json
from google.cloud import run_v2

# Environment variables (set these in Terraform for the Cloud Function)
PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
REGION = os.environ.get("GCP_REGION")
CLOUD_RUN_JOB_NAME = os.environ.get("CLOUD_RUN_JOB_NAME") # The short name of the job

@functions_framework.cloud_event
def process_gcs_event_and_run_job(cloud_event):
    """
    Cloud Function triggered by a GCS event.
    Extracts file information and triggers a Cloud Run Job.
    """
    print("GCS Event Processor V2 (Job Invoker) function was triggered.")

    data = cloud_event.data
    bucket_name = data.get("bucket")
    object_name = data.get("name")
    metageneration = data.get("metageneration")
    time_created = data.get("timeCreated")
    updated = data.get("updated")

    if not bucket_name or not object_name:
        print("Error: Bucket name or object name not found in the event payload.")
        return "Error: Missing bucket or object name.", 400

    print(f"Event ID: {cloud_event.id}")
    print(f"Event Type: {cloud_event.type}")
    print(f"Bucket: {bucket_name}")
    print(f"File: {object_name}")
    print(f"Metageneration: {metageneration}")
    print(f"Created: {time_created}")
    print(f"Updated: {updated}")

    if not PROJECT_ID or not REGION or not CLOUD_RUN_JOB_NAME:
        print("Error: Missing required environment variables for Project ID, Region, or Cloud Run Job Name.")
        return "Error: Function configuration incomplete.", 500

    try:
        print(f"Attempting to run Cloud Run Job: {CLOUD_RUN_JOB_NAME} in project {PROJECT_ID}, region {REGION}")

        client = run_v2.JobsClient()

        job_parent = f"projects/{PROJECT_ID}/locations/{REGION}"
        job_path = f"{job_parent}/jobs/{CLOUD_RUN_JOB_NAME}"

        # --- Configuration for the Cloud Run Job execution ---
        # You can override arguments or environment variables for the job run.
        # The example below passes the GCS bucket and object as environment variables.
        # Your Cloud Run Job container (basicpocjob:latest) needs to be able to read these.
        overrides = run_v2.types.RunJobRequest.Overrides(
            container_overrides=[
                run_v2.types.RunJobRequest.Overrides.ContainerOverride(
                    name="", # If your job has only one container, its name is often not needed or is the job name.
                             # Or find the container name from `gcloud run jobs describe YOUR_JOB_NAME --format 'value(template.template.containers[0].name)'`
                             # If your image `basicpocjob:latest` is the only container, often you can leave this empty or use the job name.
                             # For this example, we assume the first container is the target.
                    env=[
                        run_v2.types.EnvVar(name="SOURCE_BUCKET", value=bucket_name),
                        run_v2.types.EnvVar(name="SOURCE_OBJECT", value=object_name),
                        # You can add more environment variables here if your job needs them.
                        # e.g., run_v2.types.EnvVar(name="JOB_SPECIFIC_CONFIG", value="some_value")
                    ],
                    # If your job expects arguments instead of/in addition to env vars:
                    # args=["--input-file", f"gs://{bucket_name}/{object_name}"]
                )
            ],
            # You can also override task_count and timeout here if needed
            # task_count = 1,
            # timeout = "600s" # 10 minutes
        )

        request = run_v2.types.RunJobRequest(
            name=job_path,
            overrides=overrides,
            # You can set `validate_only=True` to test the request without actually running the job.
            # validate_only=False
        )

        operation = client.run_job(request=request)
        print(f"Job execution requested. Operation: {operation.operation.name}")
        # You can wait for the operation to complete if needed, but for a Cloud Function,
        # it's often better to return quickly and let the job run asynchronously.
        # result = operation.result() # This would block until the job run is initiated.
        # print(f"Job run initiated: {result}")

        print(f"Successfully triggered Cloud Run job '{CLOUD_RUN_JOB_NAME}' for file 'gs://{bucket_name}/{object_name}'.")
        return "Cloud Run Job triggered successfully.", 200

    except Exception as e:
        print(f"Error triggering Cloud Run job: {e}")
        # Consider more specific error handling based on exception types
        return f"Error triggering Cloud Run job: {e}", 500

