# functions/pubsub_event_processor/main.py
import functions_framework
import os
import json
import base64
from google.cloud import run_v2

# Environment variables (set these in Terraform for the Cloud Function)
PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
REGION = os.environ.get("GCP_REGION")
CLOUD_RUN_JOB_NAME = os.environ.get("CLOUD_RUN_JOB_NAME") # The short name of the job

@functions_framework.cloud_event
def process_pubsub_message_and_run_job(cloud_event):
    """
    Cloud Function triggered by a Pub/Sub message.
    Decodes the message, extracts data, and triggers a Cloud Run Job,
    passing message data as environment variables to the job.
    """
    print("Pub/Sub Event Processor V1 (Job Invoker) function was triggered.")

    if not cloud_event.data or not cloud_event.data.get("message"):
        print("Error: No message data found in the CloudEvent.")
        return "Error: Invalid Pub/Sub message format.", 400

    message_payload = cloud_event.data["message"]
    
    if "data" not in message_payload:
        print("Error: 'data' field missing in Pub/Sub message.")
        return "Error: Missing 'data' field in Pub/Sub message.", 400

    try:
        # Data is base64 encoded
        message_data_encoded = message_payload["data"]
        message_data_decoded_bytes = base64.b64decode(message_data_encoded)
        message_data_str = message_data_decoded_bytes.decode('utf-8')
        
        print(f"Received raw message data (decoded): {message_data_str}")
        
        # Attempt to parse the decoded string as JSON
        # This assumes the Pub/Sub message data is a JSON string.
        job_parameters = json.loads(message_data_str)
        if not isinstance(job_parameters, dict):
            print("Error: Decoded message data is not a JSON object (dictionary).")
            # Fallback: pass the raw string if not a dict, or handle error differently
            # For this example, we'll error out if not a dict.
            return "Error: Message data must be a JSON object.", 400

        print(f"Parsed job parameters from Pub/Sub message: {job_parameters}")

    except (json.JSONDecodeError, UnicodeDecodeError, TypeError) as e:
        print(f"Error decoding or parsing message data: {e}")
        print("Treating message data as a raw string for a single parameter 'PUBSUB_MESSAGE_DATA'.")
        # Fallback: if data is not JSON or can't be decoded as expected,
        # pass the raw decoded string as a single environment variable.
        # Or, you could choose to error out.
        job_parameters = {"PUBSUB_MESSAGE_RAW_DATA": message_data_str if 'message_data_str' in locals() else "DECODING_ERROR"}


    print(f"Event ID: {cloud_event.id}")
    print(f"Message ID: {message_payload.get('messageId')}")
    print(f"Publish Time: {message_payload.get('publishTime')}")

    if not PROJECT_ID or not REGION or not CLOUD_RUN_JOB_NAME:
        print("Error: Missing required environment variables for Project ID, Region, or Cloud Run Job Name.")
        return "Error: Function configuration incomplete.", 500

    try:
        print(f"Attempting to run Cloud Run Job: {CLOUD_RUN_JOB_NAME} in project {PROJECT_ID}, region {REGION}")

        client = run_v2.JobsClient()
        job_parent = f"projects/{PROJECT_ID}/locations/{REGION}"
        job_path = f"{job_parent}/jobs/{CLOUD_RUN_JOB_NAME}"

        # Prepare environment variables for the Cloud Run Job from the parsed message data
        job_env_vars = []
        if isinstance(job_parameters, dict):
            for key, value in job_parameters.items():
                # Ensure keys are valid env var names (alphanumeric and underscores)
                # For simplicity, this example assumes keys are already valid.
                # Convert values to string if they are not.
                job_env_vars.append(run_v2.types.EnvVar(name=str(key).upper(), value=str(value)))
        else: # Should not happen if we error out above for non-dict
             job_env_vars.append(run_v2.types.EnvVar(name="PUBSUB_MESSAGE_ERROR", value="Non-dict parameters received"))


        print(f"Passing to job - Environment Variables: {[(v.name, v.value) for v in job_env_vars]}")

        overrides = run_v2.types.RunJobRequest.Overrides(
            container_overrides=[
                run_v2.types.RunJobRequest.Overrides.ContainerOverride(
                    name="", # Assuming the first/only container in the job
                    env=job_env_vars,
                )
            ]
        )

        request = run_v2.types.RunJobRequest(
            name=job_path,
            overrides=overrides,
        )

        operation = client.run_job(request=request)
        print(f"Job execution requested. Operation: {operation.operation.name}")
        
        print(f"Successfully triggered Cloud Run job '{CLOUD_RUN_JOB_NAME}' with data from Pub/Sub.")
        return "Cloud Run Job triggered successfully from Pub/Sub.", 200

    except Exception as e:
        print(f"Error triggering Cloud Run job: {e}")
        return f"Error triggering Cloud Run job: {e}", 500

