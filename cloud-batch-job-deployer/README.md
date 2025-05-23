# Terraform: cloud-batch-job-deployer Project

This Terraform project provisions the infrastructure to dynamically submit and run Google Cloud Batch jobs. It deploys an HTTP-triggered Cloud Function that takes job parameters and uses the Cloud Batch API to create and execute a batch job running a specified Docker container (intended for a Java application).

This project relies on the `iam-core` project for the primary application service account.

## Table of Contents

1.  [Purpose](#purpose)
2.  [Prerequisites](#prerequisites)
3.  [Project Structure](#project-structure)
4.  [Configuration](#configuration)
5.  [Deployment](#deployment)
6.  [Workflow & Invoking the Function](#workflow--invoking-the-function)
7.  [Resources Created](#resources-created)
8.  [Outputs](#outputs)

## Purpose

* To enable the Google Cloud Batch API.
* To grant necessary permissions to the shared application service account (`app_service_account` from `iam-core`) for managing and running Cloud Batch jobs.
* To deploy an HTTP-triggered Cloud Function (Python) that acts as an API endpoint for submitting Cloud Batch jobs.
* To allow dynamic specification of parameters for the batch job, including Docker image arguments and environment variables.
* To run the Cloud Batch job tasks using the `app_service_account`, leveraging its existing permissions for accessing other GCP resources (e.g., GCS).

## Prerequisites

* Completion of the `iam-core` Terraform project deployment.
* Google Cloud SDK (`gcloud`) installed and authenticated.
* Terraform (or OpenTofu) installed.
* A GCP Project.
* A Service Account for Terraform to use for deployment, with sufficient permissions.
* The JSON key file for the Terraform deployment Service Account.
* A Docker image containing your Java application, hosted in a registry accessible by GCP Cloud Batch (e.g., Artifact Registry, Google Container Registry).

## Project Structure

cloud-batch-job-deployer/├── main.tf                 # Main Terraform configuration├── variables.tf            # Input variables├── outputs.tf              # Outputs from this project├── provider.tf             # Terraform provider configuration├── functions/              # Source code for Cloud Functions│   └── submit_cloud_batch_job/│       ├── main.py         # Python code for the Batch job submitter│       └── requirements.txt# Python dependencies└── README.md               # This file
## Configuration

1.  Ensure all files are in the `cloud-batch-job-deployer/` directory.
2.  Verify the Python Cloud Function code is in `functions/submit_cloud_batch_job/`.
3.  Create a `terraform.tfvars` file in this directory:

    ```tfvars
    project_id                            = "your-gcp-project-id"
    region                                = "your-gcp-region" // e.g., "us-central1"
    terraform_sa_key_path              = "/path/to/your/terraform-sa-key.json"
    iam_core_terraform_state_path        = "../iam-core/terraform.tfstate" 

    // *** THIS IS A REQUIRED VARIABLE ***
    default_batch_job_docker_image_uri = "gcr.io/your-project-id/your-java-app-image:latest" 

    // Optional: Override other defaults from variables.tf if needed
    // batch_submitter_function_name = "my-batch-api"
    ```
4.  **Crucially, you must provide `default_batch_job_docker_image_uri` in your `terraform.tfvars` file.** This is the Docker image containing your Java application.

## Deployment

1.  Navigate to the `cloud-batch-job-deployer/` directory.
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

## Workflow & Invoking the Function

1.  Once deployed, the Cloud Function (`http-submit-cloud-batch-job` by default) provides an HTTP endpoint.
2.  To submit a Cloud Batch job, send a `POST` request to this function's URI with a JSON payload.
    * Get the function URI from Terraform output: `terraform output batch_submitter_cloud_function_uri`
3.  **Example JSON Payload for the `POST` request:**
    ```json
    {
      "job_name_prefix": "my-java-job-run-",
      "docker_image_uri": "gcr.io/my-gcp-project/my-java-app:v2", // Optional: overrides function's default
      "java_app_args": ["--input", "gs://my-bucket/input-data.txt", "--output-prefix", "processed_"],
      "container_env_vars": {
        "MY_JAVA_ENV_VAR": "some_value",
        "ANOTHER_CONFIG": "true"
      },
      "machine_type": "n1-standard-4", // Optional: e.g., e2-medium, n1-standard-1
      "max_run_duration": "7200s"     // Optional: e.g., "3600s" for 1 hour
    }
    ```
    * `job_name_prefix` (optional): A prefix for the generated Cloud Batch job name.
    * `docker_image_uri` (optional): Overrides the default Docker image configured for the function.
    * `java_app_args` (optional): A list of strings passed as commands/arguments to your Docker container's entrypoint (i.e., to your Java `main` method).
    * `container_env_vars` (optional): A dictionary of environment variables to set within the Docker container.
    * `machine_type` (optional): The machine type for the Batch job VMs.
    * `max_run_duration` (optional): Maximum run duration for the job tasks (e.g., "3600s").

4.  **Example `curl` command:**
    ```bash
    FUNCTION_URI=$(terraform output -raw batch_submitter_cloud_function_uri)
    
    curl -X POST "${FUNCTION_URI}" \
      -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
      -H "Content-Type: application/json" \
      -d '{
            "job_name_prefix": "cli-test-job-",
            "java_app_args": ["config_file=gs://my-config-bucket/app_config.properties", "mode=production"],
            "container_env_vars": {"LOG_LEVEL": "INFO"}
          }'
    ```
    (Note: The function is set to `ALLOW_ALL` (public) by default for easier testing. For production, you'd secure this endpoint, e.g., by setting `ingress_settings = "ALLOW_INTERNAL_ONLY"` and invoking via VPC or an authenticated mechanism.)

5.  The Cloud Function receives the request, constructs a Cloud Batch job definition, and submits it to the Cloud Batch service.
6.  The Cloud Batch service then provisions resources and runs your Docker container (Java application) with the specified arguments and environment variables. The tasks run as the `app_service_account`.
7.  Monitor the job status in the GCP Console under "Batch". Logs will go to Cloud Logging.

## Resources Created

1.  **Google Project Service (`google_project_service.batch_api`):**
    * Enables the `batch.googleapis.com` API.

2.  **IAM Bindings for `app_service_account` (from `iam-core`):**
    * `google_project_iam_member.app_sa_batch_jobs_editor`: Grants `roles/batch.jobsEditor` to allow the `app_service_account` (used by the function) to create and manage Batch jobs.
    * `google_service_account_iam_member.batch_agent_can_act_as_app_sa_for_jobs`: Allows the Batch service agent to act as the `app_service_account` for tasks running within the job.

3.  **IAM Binding for Batch Service Agent:**
    * `google_project_iam_member.batch_agent_reporter`: Grants `roles/batch.agentReporter` to the GCP Batch service agent (`service-<project_number>@gcp-sa-batch.iam.gserviceaccount.com`).

4.  **GCS Bucket (`google_storage_bucket.function_source_code_bucket_cb`):**
    * Purpose: Stores the zipped source code for the Cloud Function.

5.  **Cloud Function Source Upload (`google_storage_bucket_object.batch_function_source_upload`):**
    * The zipped Python function code.

6.  **Cloud Function Gen2 (`google_cloudfunctions2_function.batch_submitter_http_function`):**
    * Purpose: Provides an HTTP endpoint to submit Cloud Batch jobs.
    * Trigger: HTTP.
    * Service Account: Runs as `app_service_account`.
    * Environment Variables: `GCP_PROJECT_ID`, `GCP_REGION`, `DEFAULT_DOCKER_IMAGE_URI`, `BATCH_JOB_SERVICE_ACCOUNT`.

7.  **Cloud Run Invoker (`google_cloud_run_invoker.batch_submitter_function_public_invoker`):**
    * Grants `allUsers` the permission to invoke the HTTP-triggered Cloud Function (for public access).

8.  **Helper Resources:** `random_id`, `data.archive_file`, `time_sleep`.

## Outputs

* `function_source_code_bucket_name_cb`: Name of the bucket storing the Batch submitter function's source.
* `batch_submitter_cloud_function_name`: Name of the deployed HTTP Cloud Function.
* `batch_submitter_cloud_function_uri`: Publicly accessible URI of the HTTP Cloud Function.
* `app_service_account_email_used_for_batch`: The service account email used by the function and for Batch job tasks.
