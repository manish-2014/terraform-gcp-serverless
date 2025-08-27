###############################################################################
# bucket-triggered-job/outputs.tf
###############################################################################

output "gcs_trigger_bucket_name" {
  description = "The full name of the GCS bucket that triggers the Cloud Function."
  value       = google_storage_bucket.gcs_trigger_bucket.name
}

output "gcs_trigger_bucket_url" {
  description = "The gsutil URL of the GCS trigger bucket."
  value       = google_storage_bucket.gcs_trigger_bucket.url
}

output "function_source_code_bucket_name" {
  description = "The name of the GCS bucket storing the function's source code."
  value       = google_storage_bucket.function_source_code_bucket.name
}

output "gcs_triggered_cloud_function_name" {
  description = "The name of the deployed GCS-triggered Cloud Function (Gen 2)."
  value       = google_cloudfunctions2_function.gcs_event_processor.name
}

output "gcs_triggered_cloud_function_uri" {
  description = "The HTTPS endpoint URI of the deployed Cloud Function (internal access only by default)."
  value       = google_cloudfunctions2_function.gcs_event_processor.service_config[0].uri
}

output "gcs_eventarc_trigger_id" {
  description = "The ID of the Eventarc trigger for GCS to Cloud Function."
  value       = google_eventarc_trigger.gcs_to_function_trigger.id
}

output "cloud_run_job_name_out" {
  description = "The name of the deployed Cloud Run Job."
  value       = google_cloud_run_v2_job.processor_job.name # This will be the full name projects/.../jobs/...
}

output "cloud_run_job_short_name_out" {
  description = "The short name of the deployed Cloud Run Job."
  value       = local.cloud_run_job_short_name
}
