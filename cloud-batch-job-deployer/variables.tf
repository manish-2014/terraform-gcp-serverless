###############################################################################
# cloud-batch-job-deployer/variables.tf
###############################################################################

variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The primary GCP region for Cloud Function and Batch Job submissions."
  type        = string
  default     = "us-central1"
}

variable "service_account_key_path" { # Renamed from service_account_key_path for clarity
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
# Function Source Code Bucket
############################
variable "function_source_code_bucket_name_prefix_cb" {
  description = "Prefix for the GCS bucket to store Cloud Functions' source code ZIPs. A random suffix is added."
  type        = string
  default     = "madladlab-cb-func-src-"
}

############################
# Cloud Function (Gen 2) - HTTP Triggered Batch Submitter
############################
variable "batch_submitter_function_name" {
  description = "Name of the HTTP-triggered Cloud Function that submits Batch jobs."
  type        = string
  default     = "http-submit-cloud-batch-job"
}

variable "batch_function_source_dir" {
  description = "Local path to the source code for the Batch submitting Function."
  type        = string
  default     = "./functions/submit_cloud_batch_job"
}

variable "batch_function_runtime" {
  description = "Runtime for the Batch submitting Function."
  type        = string
  default     = "python312"
}

variable "batch_function_entry_point" {
  description = "Python entry-point for the Batch submitting Function."
  type        = string
  default     = "submit_batch_job_http"
}

variable "batch_function_memory_mb" {
  description = "Memory allocated to the Batch submitting Cloud Function in MiB."
  type        = number
  default     = 256
}

variable "batch_function_timeout_seconds" {
  description = "Timeout for the Batch submitting Cloud Function in seconds."
  type        = number
  default     = 60
}

############################
# Cloud Batch Job Defaults (for the Submitter Function's environment)
############################
variable "default_batch_job_docker_image_uri" {
  description = "Default Docker image URI for the Cloud Batch job (containing the Java main). Can be overridden by function's HTTP request."
  type        = string
}

############################
# Pub/Sub for Batch Job Status Notifications
############################
variable "batch_job_status_topic_name" {
  description = "Name of the Pub/Sub topic for Cloud Batch job status notifications."
  type        = string
  default     = "cloud-batch-job-status-notifications"
}

############################
# Cloud Function (Gen 2) - Pub/Sub Triggered Batch Status Logger
############################
variable "batch_status_logger_function_name" {
  description = "Name of the Pub/Sub-triggered Cloud Function that logs Batch job status."
  type        = string
  default     = "pubsub-log-batch-job-status"
}

variable "batch_status_logger_function_source_dir" {
  description = "Local path to the source code for the Batch status logging Function."
  type        = string
  default     = "./functions/log_batch_job_status"
}

variable "batch_status_logger_function_runtime" {
  description = "Runtime for the Batch status logging Function."
  type        = string
  default     = "python312"
}

variable "batch_status_logger_function_entry_point" {
  description = "Python entry-point for the Batch status logging Function."
  type        = string
  default     = "log_batch_job_status_event"
}

variable "batch_status_logger_function_memory_mb" {
  description = "Memory allocated to the Batch status logging Cloud Function in MiB."
  type        = number
  default     = 256
}

variable "batch_status_logger_function_timeout_seconds" {
  description = "Timeout for the Batch status logging Cloud Function in seconds."
  type        = number
  default     = 60
}

############################
# Eventarc Trigger for Status Logger Function
############################
variable "batch_status_eventarc_trigger_name" {
  description = "Name of the Eventarc trigger for Batch status Pub/Sub to the logger function."
  type        = string
  default     = "trigger-log-batch-job-status"
}

