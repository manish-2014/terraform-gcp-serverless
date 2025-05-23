###############################################################################
# cloud-batch-job-deployer/outputs.tf
# Outputs from the Cloud Batch Job Deployer module.
###############################################################################

output "http_batch_submitter_function_name" {
  description = "The name of the deployed HTTP-triggered Cloud Function for submitting Batch jobs."
  value       = google_cloudfunctions2_function.batch_submitter_http_function.name
}

output "http_batch_submitter_function_uri" {
  description = "The HTTPS endpoint URI of the deployed Batch submitter Cloud Function."
  value       = google_cloudfunctions2_function.batch_submitter_http_function.service_config[0].uri
}

output "pubsub_batch_status_logger_function_name" {
  description = "The name of the Pub/Sub-triggered Cloud Function that logs Batch job status."
  value       = google_cloudfunctions2_function.batch_status_logger_function.name
}

output "batch_job_status_pubsub_topic_name" {
  description = "The name of the Pub/Sub topic for Cloud Batch job status notifications."
  value       = google_pubsub_topic.batch_job_status_topic.name
}

output "batch_job_status_pubsub_topic_id" {
  description = "The full ID of the Pub/Sub topic for Cloud Batch job status notifications."
  value       = google_pubsub_topic.batch_job_status_topic.id
}

output "function_source_code_gcs_bucket_name" {
  description = "The name of the GCS bucket storing Cloud Functions' source code for this module."
  value       = google_storage_bucket.function_source_code_bucket_cb.name
}

output "application_service_account_email" {
  description = "The application service account email used by Cloud Functions and for Batch job tasks in this module."
  value       = local.app_service_account_email
}

output "default_docker_image_uri_for_batch_jobs" {
  description = "The default Docker image URI configured for the Cloud Batch jobs submitted by the HTTP function."
  value       = var.default_batch_job_docker_image_uri
}

output "iam_permissions_for_application_sa" {
  description = "Key IAM roles granted to the Application Service Account within this module at the project level."
  value = {
    batch_jobs_editor      = google_project_iam_member.app_sa_batch_jobs_editor.role
    logging_log_writer     = google_project_iam_member.app_sa_logging_logwriter.role
    monitoring_metric_writer = google_project_iam_member.app_sa_monitoring_metricwriter.role
    artifact_registry_reader = google_project_iam_member.app_sa_artifactregistry_reader.role
    act_as_self_for_batch  = google_service_account_iam_member.app_sa_can_act_as_self_for_batch.role # Granted on the SA itself
  }
}

output "iam_permissions_for_batch_service_agent" {
  description = "Key IAM roles granted to the Google Cloud Batch Service Agent."
  value = {
    agent_reporter          = google_project_iam_member.batch_agent_reporter.role # Project level
    act_as_app_sa_for_jobs  = google_service_account_iam_member.batch_agent_can_act_as_app_sa_for_jobs.role # On App SA
    publish_to_status_topic = google_pubsub_topic_iam_member.batch_agent_can_publish_status.role # On Pub/Sub topic
  }
}

output "batch_service_agent_email" {
  description = "The email of the Google Cloud Batch service agent for this project."
  value       = google_project_service_identity.batch_sa_identity.email
}
