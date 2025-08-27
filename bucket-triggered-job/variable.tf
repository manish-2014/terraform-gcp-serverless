###############################################################################
# bucket-triggered-job/variables.tf
###############################################################################

variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The primary GCP region for resources."
  type        = string
  default     = "us-central1"
}



variable "service_account_key_path" {
  description = "Absolute path to the Service‐Account JSON key used by Terraform/OpenTofu for deployment."
  type        = string
  sensitive   = true
}

variable "iam_core_terraform_state_path" {
  description = "Path to the terraform.tfstate file of the iam-core project."
  type        = string
  default     = "../iam-core/terraform.tfstate" # Adjust if your iam-core state is elsewhere
}

############################
# Trigger Bucket
############################
variable "trigger_bucket_name_prefix" {
  description = "Prefix for the GCS bucket that triggers the Cloud Function. A random suffix is added."
  type        = string
  default     = "madladlab-btj-trigger-"
}

variable "trigger_bucket_storage_class" {
  description = "Storage class for the trigger bucket."
  type        = string
  default     = "STANDARD"
}

############################
# Function Source Code Bucket
############################
variable "function_source_code_bucket_name_prefix" {
  description = "Prefix for the GCS bucket to store the function's source code ZIP. A random suffix is added."
  type        = string
  default     = "madladlab-btj-func-src-"
}

############################
# Cloud Function (Gen 2) - GCS Trigger
############################
variable "gcs_triggered_function_name" {
  description = "Name of the Cloud Function triggered by GCS uploads."
  type        = string
  default     = "gcs-event-processor-job-invoker"
}

variable "gcs_function_source_dir" {
  description = "Local path to the source code for the GCS-triggered Function."
  type        = string
  default     = "./functions/gcs_event_processor" # Relative to this Terraform project root
}

variable "gcs_function_runtime" {
  description = "Runtime for the GCS-triggered Function (e.g., python311, python312)."
  type        = string
  default     = "python312" # Ensure your base image for the function supports this
}

variable "gcs_function_entry_point" {
  description = "Python entry-point (handler) for the GCS-triggered Function."
  type        = string
  default     = "process_gcs_event_and_run_job"
}

variable "gcs_function_memory_mb" {
  description = "Memory allocated to the GCS-triggered Cloud Function in MiB."
  type        = number
  default     = 256
}

variable "gcs_function_timeout_seconds" {
  description = "Timeout for the GCS-triggered Cloud Function in seconds."
  type        = number
  default     = 60 # Increased slightly as it now invokes a job
}

############################
# Eventarc Trigger
############################
variable "gcs_eventarc_trigger_name" {
  description = "Name of the Eventarc trigger for GCS bucket uploads."
  type        = string
  default     = "madladlab-gcs-to-func-job-trigger"
}

############################
# Cloud Run Job
############################
variable "cloud_run_job_name" {
  description = "Name of the Cloud Run Job to be invoked by the Function."
  type        = string
  default     = "basic-poc-processor-job" # This is the short name
}

variable "cloud_run_job_image_uri" {
  description = "Container image for the Cloud Run Job."
  type        = string
  # Defaulting to the image URI you provided
  default     = "us-central1-docker.pkg.dev/scottycloudxferpoc1/basicpocjob/basicpocjob:latest"
}

variable "cloud_run_job_container_cpu_limit" {
  description = "CPU limit for the Cloud Run Job container (e.g., '1000m')."
  type        = string
  default     = "1000m"
}

variable "cloud_run_job_container_memory_limit_mb" {
  description = "Memory limit for the Cloud Run Job container in MiB."
  type        = number
  default     = 512
}

variable "cloud_run_job_max_retries" {
  description = "Maximum number of retries for the Cloud Run Job task."
  type        = number
  default     = 1
}

variable "cloud_run_job_task_timeout_seconds" {
  description = "Timeout for each task in the Cloud Run Job in seconds."
  type        = number
  default     = 600 # 10 minutes
}

variable "cloud_run_job_static_config_arg" {
  description = "A static JSON configuration string to pass as an argument to the Cloud Run Job container, if your job expects one. The Python function will pass dynamic info via ENV vars."
  type        = string
  sensitive   = true
  default     = <<EOT
{
  "static_setting_1": "value1",
  "sftp_details": {
    "server": "sftp.example.com",
    "port": 22,
    "user": "sftp_user_placeholder",
    "path": "/upload/output_placeholder/"
  },
  "target_system_api_key_secret_ref": "projects/YOUR_PROJECT_ID/secrets/MY_API_KEY/versions/latest" 
}
EOT
  # Note: Update the above JSON, especially secret references, as needed for your actual job.
  # The Python function passes SOURCE_BUCKET and SOURCE_OBJECT as ENV vars.
  # If your job 'basicpocjob:latest' is designed to read this JSON from args, it can.
}
