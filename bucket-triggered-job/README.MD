# Terraform: bucket-triggered-job Project

This Terraform project provisions a Google Cloud Platform (GCP) workflow where a file upload to a Cloud Storage (GCS) bucket triggers a Cloud Function. This Cloud Function then executes a specified Cloud Run Job to process the uploaded file.

This project depends on outputs from the `iam-core` Terraform project, specifically for the application service account and custom IAM roles.

## Table of Contents

1.  [Purpose](#purpose)
2.  [Prerequisites](#prerequisites)
3.  [Project Structure](#project-structure)
4.  [Configuration](#configuration)
5.  [Deployment](#deployment)
6.  [Workflow](#workflow)
7.  [Resources Created](#resources-created)
8.  [Outputs](#outputs)

## Purpose

* To create an event-driven pipeline initiated by GCS file uploads.
* To deploy a Cloud Function that acts as an orchestrator, receiving GCS events and launching a batch processing job.
* To deploy a Cloud Run Job using a custom container image for file processing.
* To demonstrate modular Terraform design by consuming outputs from a foundational IAM project.

## Prerequisites

* Completion of the `iam-core` Terraform project deployment (or an equivalent setup providing the necessary outputs like `app_service_account_email` and `custom_bucket_role_id`).
* Google Cloud SDK (`gcloud`) installed and authenticated.
* Terraform (or OpenTofu) installed.
* A GCP Project.
* A Service Account for Terraform to use for deployment, with sufficient permissions.
* The JSON key file for the Terraform deployment Service Account.
* A Docker image for the Cloud Run Job, accessible to your GCP project (e.g., hosted in Artifact Registry). The default is `us-central1-docker.pkg.dev/scottycloudxferpoc1/basicpocjob/basicpocjob:latest`.

## Project Structure

bucket-triggered-job/├── main.tf                 # Main Terraform configuration├── variables.tf            # Input variables├── outputs.tf              # Outputs from this project├── provider.tf             # Terraform provider configuration├── functions/              # Source code for Cloud Functions│   └── gcs_event_processor/│       ├── main.py         # Python code for the GCS event processor│       └── requirements.txt# Python dependencies└── README.md               # This file
## Configuration

1.  Ensure all files are in the `bucket-triggered-job/` directory.
2.  Make sure the Python Cloud Function code is present in `functions/gcs_event_processor/`.
3.  Create a `terraform.tfvars` file in this directory:

    ```tfvars
    project_id                 = "your-gcp-project-id"
    region                     = "your-gcp-region" // e.g., "us-central1"
    terraform_sa_key_path   = "/path/to/your/terraform-sa-key.json"

    // Path to the state file of the iam-core project
    // Adjust if iam-core uses a remote backend
    iam_core_terraform_state_path = "../iam-core/terraform.tfstate" 

    // Optional: Override default names or settings
    // trigger_bucket_name_prefix = "my-app-gcs-trigger-"
    // gcs_triggered_function_name = "my-gcs-handler"
    // cloud_run_job_name = "my-processing-job"
    // cloud_run_job_image_uri = "gcr.io/my-project/my-job-image:latest"
    // cloud_run_job_static_config_arg = "{ \"my_config\": \"my_value\" }"
    ```
4.  Review `variables.tf` for other configurable parameters, especially `cloud_run_job_image_uri` and `cloud_run_job_static_config_arg` to match your job's requirements. The Python function passes `SOURCE_BUCKET` and `SOURCE_OBJECT` as environment variables to the Cloud Run Job.

## Deployment

1.  Navigate to the `bucket-triggered-job/` directory.
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

1.  A file is uploaded to the GCS "trigger" bucket (`madladlab-btj-trigger-<random_hex>`).
2.  An Eventarc trigger (`madladlab-gcs-to-func-job-trigger`) detects the `google.cloud.storage.object.v1.finalized` event.
3.  Eventarc invokes the Cloud Function (`gcs-event-processor-job-invoker`).
4.  The Cloud Function:
    * Receives the event data (bucket and object name).
    * Constructs a request to run the Cloud Run Job (`basic-poc-processor-job`).
    * Passes the `SOURCE_BUCKET` and `SOURCE_OBJECT` as environment variable overrides to the job instance.
    * Executes the Cloud Run Job.
5.  The Cloud Run Job (using `us-central1-docker.pkg.dev/scottycloudxferpoc1/basicpocjob/basicpocjob:latest` or your configured image) runs, presumably processing the file specified by the environment variables.

## Resources Created

1.  **GCS Bucket (`google_storage_bucket.function_source_code_bucket`):**
    * Purpose: Stores the zipped source code for the Cloud Function.
    * Name: `${var.function_source_code_bucket_name_prefix}<random_hex>`

2.  **GCS Bucket (`google_storage_bucket.gcs_trigger_bucket`):**
    * Purpose: Files uploaded here trigger the workflow.
    * Name: `${var.trigger_bucket_name_prefix}<random_hex>`
    * IAM: The `app_service_account` (from `iam-core`) is granted the custom bucket role on this bucket.

3.  **Cloud Run Job (`google_cloud_run_v2_job.processor_job`):**
    * Purpose: Executes the batch processing task.
    * Name: `var.cloud_run_job_name` (e.g., `basic-poc-processor-job`)
    * Image: `var.cloud_run_job_image_uri`
    * Service Account: Runs as `app_service_account` (from `iam-core`).
    * IAM: `app_service_account` is granted `roles/run.invoker` on this job, allowing the Cloud Function (running as `app_sa`) to execute it.

4.  **Cloud Function Source Upload (`google_storage_bucket_object.gcs_function_source_upload`):**
    * The zipped Python function code uploaded to the function source code bucket.

5.  **Cloud Function Gen2 (`google_cloudfunctions2_function.gcs_event_processor`):**
    * Purpose: Receives GCS event and triggers the Cloud Run Job.
    * Name: `var.gcs_triggered_function_name` (e.g., `gcs-event-processor-job-invoker`)
    * Runtime: `var.gcs_function_runtime` (e.g., `python312`)
    * Entry Point: `var.gcs_function_entry_point`
    * Service Account: Runs as `app_service_account` (from `iam-core`).
    * Environment Variables: `GCP_PROJECT_ID`, `GCP_REGION`, `CLOUD_RUN_JOB_NAME` are passed to the function.

6.  **Eventarc Trigger (`google_eventarc_trigger.gcs_to_function_trigger`):**
    * Purpose: Links the GCS bucket events to the Cloud Function.
    * Name: `var.gcs_eventarc_trigger_name`
    * Event Type: `google.cloud.storage.object.v1.finalized` on `gcs_trigger_bucket`.
    * Destination: The `gcs_event_processor` Cloud Function.
    * Service Account: Uses `app_service_account` to invoke the function.

7.  **IAM Bindings:**
    * `google_storage_bucket_iam_member.app_sa_trigger_bucket_binding`: Grants `app_sa` access to the trigger bucket.
    * `google_cloud_run_v2_job_iam_member.app_sa_can_run_processor_job`: Allows `app_sa` to invoke the created Cloud Run Job.

8.  **Helper Resources:**
    * `random_id` resources for unique bucket names.
    * `data.archive_file` for zipping function source.
    * `time_sleep` for IAM propagation.

## Outputs

* `gcs_trigger_bucket_name`: Name of the GCS trigger bucket.
* `gcs_trigger_bucket_url`: URL of the GCS trigger bucket.
* `function_source_code_bucket_name`: Name of the bucket storing function source.
* `gcs_triggered_cloud_function_name`: Name of the deployed Cloud Function.
* `gcs_triggered_cloud_function_uri`: Internal URI of the Cloud Function.
* `gcs_eventarc_trigger_id`: ID of the Eventarc trigger.
* `cloud_run_job_name_out`: Full name of the Cloud Run Job.
* `cloud_run_job_short_name_out`: Short name of the Cloud Run Job.
