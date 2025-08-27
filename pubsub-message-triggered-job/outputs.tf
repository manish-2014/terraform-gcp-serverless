###############################################################################
# pubsub-message-triggered-job/outputs.tf
###############################################################################

output "pubsub_job_request_topic_name" {
  description = "The full name of the Pub/Sub topic for job requests."
  value       = google_pubsub_topic.job_request_topic.name
}

output "pubsub_job_request_topic_id" {
  description = "The ID of the Pub/Sub topic for job requests."
  value       = google_pubsub_topic.job_request_topic.id
}

output "function_source_code_bucket_name_ps" {
  description = "The name of the GCS bucket storing this Pub/Sub function's source code."
  value       = google_storage_bucket.function_source_code_bucket_ps.name
}

output "pubsub_triggered_cloud_function_name" {
  description = "The name of the deployed Pub/Sub-triggered Cloud Function (Gen 2)."
  value       = google_cloudfunctions2_function.pubsub_event_processor.name
}

output "pubsub_triggered_cloud_function_uri" {
  description = "The HTTPS endpoint URI of the deployed Pub/Sub Cloud Function (internal access only by default)."
  value       = google_cloudfunctions2_function.pubsub_event_processor.service_config[0].uri
}

output "pubsub_eventarc_trigger_id" {
  description = "The ID of the Eventarc trigger for Pub/Sub to Cloud Function."
  value       = google_eventarc_trigger.pubsub_to_function_trigger.id
}

output "cloud_run_job_name_ps_out" {
  description = "The name of the deployed Cloud Run Job for Pub/Sub triggered flow."
  value       = google_cloud_run_v2_job.processor_job_ps.name # Full name
}

output "cloud_run_job_short_name_ps_out" {
  description = "The short name of the deployed Cloud Run Job for Pub/Sub triggered flow."
  value       = local.cloud_run_job_short_name_ps
}
