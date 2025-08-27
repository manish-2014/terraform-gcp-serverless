# Terraform: pubsub-message-triggered-job Project

This Terraform project provisions a Google Cloud Platform (GCP) workflow where a message published to a Pub/Sub topic triggers a Cloud Function. This Cloud Function then executes a specified Cloud Run Job to process the data from the Pub/Sub message.

This project depends on outputs from the `iam-core` Terraform project for the application service account and potentially other core configurations.

## Table of Contents

1.  [Purpose](#purpose)
2.  [Prerequisites](#prerequisites)
3.  [Project Structure](#project-structure)
4.  [Configuration](#configuration)
5.  [Deployment](#deployment)
6.  [Workflow](#workflow)
7.  [Publishing a Test Message](#publishing-a-test-message)
8.  [Resources Created](#resources-created)
9.  [Outputs](#outputs)

## Purpose

* To create an event-driven pipeline initiated by Pub/Sub messages.
* To deploy a Cloud Function that acts as an orchestrator, receiving Pub/Sub messages, parsing their data, and launching a batch processing job.
* To deploy a Cloud Run Job using a custom container image for data processing based on Pub/Sub message content.
* To demonstrate modular Terraform design by consuming outputs from a foundational IAM project.

## Prerequisites

* Completion of the `iam-core` Terraform project deployment.
* Google Cloud SDK (`gcloud`) installed and authenticated.
* Terraform (or OpenTofu) installed.
* A GCP Project.
* A Service Account for Terraform to use for deployment, with sufficient permissions.
* The JSON key file for the Terraform deployment Service Account.
* A Docker image for the Cloud Run Job, accessible to your GCP project (e.g., hosted in Artifact Registry). The default is `us-central1-docker.pkg.dev/scottycloudxferpoc1/basicpocjob/basicpocjob:latest`.

## Project Structure


pubsub-message-triggered-job/
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Input variables
├── outputs.tf              # Outputs from this project
├── provider.tf             # Terraform provider configuration
├── functions/              # Source code for Cloud Functions
│   └── pubsub_event_processor/
│       ├── main.py         # Python code for the Pub/Sub event processor
│       └── requirements.txt# Python dependencies
└── README.md               # This file


## Configuration

1.  Ensure all files are in the `pubsub-message-triggered-job/` directory.
2.  Make sure the Python Cloud Function code is present in `functions/pubsub_event_processor/`.
3.  Create a `terraform.tfvars` file in this directory:

    ```tfvars
    project_id                    = "your-gcp-project-id"
    region                        = "your-gcp-region" // e.g., "us-central1"
    terraform_sa_key_path      = "/path/to/your/terraform-sa-key.json"

    // Path to the state file of the iam-core project
    iam_core_terraform_state_path = "../iam-core/terraform.tfstate" 

    // Optional: Override default names or settings
    // pubsub_topic_name = "my-app-job-queue"
    // pubsub_triggered_function_name = "my-pubsub-handler"
    // cloud_run_job_name_ps = "my-pubsub-processing-job"
    // cloud_run_job_image_uri_ps = "gcr.io/my-project/my-other-job-image:latest"
    ```
4.  Review `variables.tf` for other configurable parameters, especially related to the Cloud Run Job. The Python function is designed to take a JSON payload from the Pub/Sub message `data` field and pass its key-value pairs as environment variables (keys uppercased) to the Cloud Run Job.

## Deployment

1.  Navigate to the `pubsub-message-triggered-job/` directory.
2.  Initialize Terraform:
    ```bash
    terraform init
    ```
3.  Review the plan:
    ```bash
    terraform plan -var-file="terraform.tfvars"
    ```
4.  Apply the configuration:
    ```bash
    terraform apply -var-file="terraform.tfvars"
    ```
    Confirm by typing `yes` when prompted.

## Workflow

1.  A message is published to the Pub/Sub topic (default: `madladlab-pmtj-job-requests`). The message `data` field should contain a base64-encoded JSON string.
2.  An Eventarc trigger (`madladlab-pubsub-to-func-job-trigger`) detects the `google.cloud.pubsub.topic.v1.messagePublished` event.
3.  Eventarc invokes the Cloud Function (`pubsub-event-processor-job-invoker`).
4.  The Cloud Function:
    * Receives the Pub/Sub message via a CloudEvent.
    * Decodes the base64 `data` field from the message.
    * Parses the decoded data as a JSON object.
    * Constructs a request to run the Cloud Run Job (`basic-poc-processor-job-ps` or your configured job).
    * Passes the key-value pairs from the parsed JSON object as environment variable overrides to the job instance (keys are uppercased).
    * Executes the Cloud Run Job.
5.  The Cloud Run Job (using the configured image) runs, presumably using the environment variables derived from the Pub/Sub message to perform its task.

## Publishing a Test Message

After deployment, you can test the flow by publishing a message to the topic.

1.  Get the topic name from Terraform output:
    ```bash
    terraform output pubsub_job_request_topic_id 
    # This gives projects/YOUR_PROJECT/topics/YOUR_TOPIC_NAME
    ```
    Or use the short name: `terraform output pubsub_job_request_topic_name`

2.  Prepare your JSON payload, for example:
    ```json
    {
      "INPUT_FILE_PATH": "gs://my-source-bucket/data/input_for_job.csv",
      "OUTPUT_CONFIG_NAME": "daily_report_v1",
      "USER_ID": "user123"
    }
    ```

3.  Publish using `gcloud` (replace `YOUR_TOPIC_NAME` and adapt the payload):
    ```bash
    # Using --message (payload directly)
    gcloud pubsub topics publish YOUR_TOPIC_NAME \
      --message '{ "INPUT_FILE_PATH": "gs://my-source-bucket/data/input_for_job.csv", "OUTPUT_CONFIG_NAME": "daily_report_v1", "USER_ID": "user123" }'

    # Or, if your payload is complex or in a file (message.json):
    # gcloud pubsub topics publish YOUR_TOPIC_NAME --message "$(cat message.json)"
    ```
    The Python function expects the `data` field of the Pub/Sub message to be a base64 encoded JSON string. `gcloud pubsub topics publish --message ...` handles the base64 encoding automatically if you provide a plain string.

4.  Check the logs for the Cloud Function and the Cloud Run Job in the GCP Console (Logging -> Logs Explorer) to see the processing.

## Resources Created

1.  **GCS Bucket (`google_storage_bucket.function_source_code_bucket_ps`):**
    * Purpose: Stores the zipped source code for the Pub/Sub-triggered Cloud Function.
    * Name: `${var.function_source_code_bucket_name_prefix_ps}<random_hex>`

2.  **Pub/Sub Topic (`google_pubsub_topic.job_request_topic`):**
    * Purpose: Receives messages that trigger the workflow.
    * Name: `var.pubsub_topic_name`
    * IAM: `app_service_account` is granted `roles/pubsub.publisher` on this topic.

3.  **Cloud Run Job (`google_cloud_run_v2_job.processor_job_ps`):**
    * Purpose: Executes the batch processing task based on Pub/Sub message data.
    * Name: `var.cloud_run_job_name_ps`
    * Image: `var.cloud_run_job_image_uri_ps`
    * Service Account: Runs as `app_service_account` (from `iam-core`).
    * IAM: `app_service_account` is granted `roles/run.invoker` on this job.

4.  **Cloud Function Source Upload (`google_storage_bucket_object.pubsub_function_source_upload`):**
    * The zipped Python function code uploaded to its source code bucket.

5.  **Cloud Function Gen2 (`google_cloudfunctions2_function.pubsub_event_processor`):**
    * Purpose: Receives Pub/Sub message, parses it, and triggers the Cloud Run Job.
    * Name: `var.pubsub_triggered_function_name`
    * Service Account: Runs as `app_service_account` (from `iam-core`).
    * Environment Variables: `GCP_PROJECT_ID`, `GCP_REGION`, `CLOUD_RUN_JOB_NAME` are passed to the function.

6.  **Eventarc Trigger (`google_eventarc_trigger.pubsub_to_function_trigger`):**
    * Purpose: Links the Pub/Sub topic messages to the Cloud Function.
    * Name: `var.pubsub_eventarc_trigger_name`
    * Event Type: `google.cloud.pubsub.topic.v1.messagePublished`.
    * Transport: Configured for the `job_request_topic`.
    * Destination: The `pubsub_event_processor` Cloud Function.
    * Service Account: Uses `app_service_account` to invoke the function.

7.  **IAM Bindings & Helper Resources:** Similar to the `bucket-triggered-job` project.

## Outputs

* `pubsub_job_request_topic_name`: Short name of the Pub/Sub topic.
* `pubsub_job_request_topic_id`: Full ID of the Pub/Sub topic.
* `function_source_code_bucket_name_ps`: Name of the bucket storing this function's source.
* `pubsub_triggered_cloud_function_name`: Name of the deployed Cloud Function.
* `pubsub_triggered_cloud_function_uri`: Internal URI of the Cloud Function.
* `pubsub_eventarc_trigger_id`: ID of the Eventarc trigger.
* `cloud_run_job_name_ps_out`: Full name of the Cloud Run Job.
* `cloud_run_job_short_name_ps_out`: Short name of the Cloud Run Job.
