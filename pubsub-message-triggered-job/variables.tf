###############################################################################
# pubsub-message-triggered-job/variables.tf
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
  description = "Absolute path to the Service Account JSON key used by Terraform for deployment."
  type        = string
  sensitive   = true
}

variable "iam_core_terraform_state_path" {
  description = "Path to the terraform.tfstate file of the iam-core project."
  type        = string
  default     = "../iam-core/terraform.tfstate"
}

############################
# Pub/Sub Topic
############################
variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic that triggers the Cloud Function."
  type        = string
  default     = "madladlab-pmtj-job-requests"
}

############################
# Function Source Code Bucket
############################
variable "function_source_code_bucket_name_prefix_ps" { # Added _ps to differentiate from btj
  description = "Prefix for the GCS bucket to store this function's source code ZIP. A random suffix is added."
  type        = string
  default     = "madladlab-pmtj-func-src-"
}

############################
# Cloud Function (Gen 2) - Pub/Sub Trigger
############################
variable "pubsub_triggered_function_name" {
  description = "Name of the Cloud Function triggered by Pub/Sub messages."
  type        = string
  default     = "pubsub-event-processor-job-invoker"
}

variable "pubsub_function_source_dir" {
  description = "Local path to the source code for the Pub/Sub-triggered Function."
  type        = string
  default     = "./functions/pubsub_event_processor" # Relative to this Terraform project root
}

variable "pubsub_function_runtime" {
  description = "Runtime for the Pub/Sub-triggered Function (e.g., python311, python312)."
  type        = string
  default     = "python312"
}

variable "pubsub_function_entry_point" {
  description = "Python entry-point (handler) for the Pub/Sub-triggered Function."
  type        = string
  default     = "process_pubsub_message_and_run_job"
}

variable "pubsub_function_memory_mb" {
  description = "Memory allocated to the Pub/Sub-triggered Cloud Function in MiB."
  type        = number
  default     = 256
}

variable "pubsub_function_timeout_seconds" {
  description = "Timeout for the Pub/Sub-triggered Cloud Function in seconds."
  type        = number
  default     = 60
}

############################
# Eventarc Trigger
############################
variable "pubsub_eventarc_trigger_name" {
  description = "Name of the Eventarc trigger for Pub/Sub messages."
  type        = string
  default     = "madladlab-pubsub-to-func-job-trigger"
}

############################
# Cloud Run Job (Can be the same job as bucket-triggered, or a different one)
############################
variable "cloud_run_job_name_ps" { # Added _ps to allow differentiation if needed
  description = "Name of the Cloud Run Job to be invoked by the Pub/Sub-triggered Function."
  type        = string
  default     = "basic-poc-processor-job-ps" # Defaulting to a potentially different name for clarity
                                           # Can be set to the same as bucket-triggered job if it's the same job.
}

variable "cloud_run_job_image_uri_ps" {
  description = "Container image for the Cloud Run Job invoked by Pub/Sub."
  type        = string
  default     = "us-central1-docker.pkg.dev/scottycloudxferpoc1/basicpocjob/basicpocjob:latest" # Reusing your image
}

variable "cloud_run_job_container_cpu_limit_ps" {
  description = "CPU limit for the Cloud Run Job container (e.g., '1000m')."
  type        = string
  default     = "1000m"
}

variable "cloud_run_job_container_memory_limit_mb_ps" {
  description = "Memory limit for the Cloud Run Job container in MiB."
  type        = number
  default     = 512
}

variable "cloud_run_job_max_retries_ps" {
  description = "Maximum number of retries for the Cloud Run Job task."
  type        = number
  default     = 1
}

variable "cloud_run_job_task_timeout_seconds_ps" {
  description = "Timeout for each task in the Cloud Run Job in seconds."
  type        = number
  default     = 600 # 10 minutes
}

variable "cloud_run_job_static_config_arg_ps" {
  description = "A static JSON configuration string to pass as an argument to the Cloud Run Job container if needed. The Python function passes dynamic info from Pub/Sub via ENV vars."
  type        = string
  sensitive   = true
  default     = "{}" # Default to empty JSON if job primarily uses ENV vars from Pub/Sub
  # Example:
  # default     = <<EOT
# {
#   "job_type": "pubsub_triggered_process",
#   "static_param": "value_for_ps_job"
# }
# EOT
}
