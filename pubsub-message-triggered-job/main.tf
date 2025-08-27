###############################################################################
# pubsub-message-triggered-job/main.tf
# Defines Pub/Sub topic, Cloud Function (job invoker), Eventarc trigger,
# and the Cloud Run Job.
###############################################################################

data "google_project" "project" {}

data "terraform_remote_state" "iam_core" {
  backend = "local"
  config = {
    path = var.iam_core_terraform_state_path
  }
}

locals {
  app_service_account_email    = data.terraform_remote_state.iam_core.outputs.app_service_account_email
  cloud_run_job_short_name_ps  = var.cloud_run_job_name_ps # Use the specific variable for this project
}

#######################################
# GCS Bucket for Function Source Code
#######################################
resource "random_id" "function_source_bucket_suffix_ps" {
  byte_length = 4
}

resource "google_storage_bucket" "function_source_code_bucket_ps" {
  project                     = var.project_id
  name                        = "${var.function_source_code_bucket_name_prefix_ps}${random_id.function_source_bucket_suffix_ps.hex}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true # Set to false in production
  labels = {
    environment = "poc",
    purpose     = "pmtj-function-source-code"
    managed_by  = "opentofu"
  }
}

#######################################
# Pub/Sub Topic
#######################################
resource "google_pubsub_topic" "job_request_topic" {
  project = var.project_id
  name    = var.pubsub_topic_name
  labels = {
    environment = "poc",
    purpose     = "pmtj-job-request-queue"
    managed_by  = "opentofu"
  }
}

# Grant app_sa permissions to publish to this topic if other components need to (optional here if only external publishers)
# The function itself doesn't need to publish to *this* topic to be triggered by it.
# Eventarc handles function invocation.
# If the function needs to acknowledge messages or interact with the subscription, it runs as app_sa.
# The app_sa (as Eventarc trigger SA) needs roles/run.invoker on the function.
# The app_sa (as function SA) needs roles/run.invoker on the job.
# The iam-core module already grants app_sa roles/eventarc.eventReceiver.
# To allow app_sa to publish to this topic (e.g. from another service):
resource "google_pubsub_topic_iam_member" "app_sa_can_publish_to_job_topic" {
  project = google_pubsub_topic.job_request_topic.project
  topic   = google_pubsub_topic.job_request_topic.name
  role    = "roles/pubsub.publisher" # Or "roles/pubsub.editor" for more control
  member  = "serviceAccount:${local.app_service_account_email}"
}


#######################################
# Cloud Run Job
#######################################
resource "google_cloud_run_v2_job" "processor_job_ps" {
  project  = var.project_id
  location = var.region
  name     = local.cloud_run_job_short_name_ps

  template {
    template {
      service_account = local.app_service_account_email
      max_retries     = var.cloud_run_job_max_retries_ps
      timeout         = "${var.cloud_run_job_task_timeout_seconds_ps}s"

      containers {
        image = var.cloud_run_job_image_uri_ps
        # If your job expects a static config JSON as an argument:
        args = compact([var.cloud_run_job_static_config_arg_ps == "{}" || var.cloud_run_job_static_config_arg_ps == "" ? "" : var.cloud_run_job_static_config_arg_ps])
        # The Python function will pass data from Pub/Sub message as ENV vars dynamically.
        resources {
          limits = {
            cpu    = var.cloud_run_job_container_cpu_limit_ps
            memory = "${var.cloud_run_job_container_memory_limit_mb_ps}Mi"
          }
        }
      }
    }
  }
  labels = {
    environment = "poc",
    app         = "pmtj-processor"
    managed_by  = "opentofu"
  }
}

resource "google_cloud_run_v2_job_iam_member" "app_sa_can_run_processor_job_ps" {
  project  = google_cloud_run_v2_job.processor_job_ps.project
  location = google_cloud_run_v2_job.processor_job_ps.location
  name     = google_cloud_run_v2_job.processor_job_ps.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.app_service_account_email}"
}

#######################################
# Cloud Function (Gen 2) - Pub/Sub Triggered Job Invoker
#######################################
data "archive_file" "pubsub_function_source" {
  type        = "zip"
  source_dir  = var.pubsub_function_source_dir
  output_path = "${path.cwd}/.terraform/archives/${var.pubsub_triggered_function_name}_source.zip"
}

resource "google_storage_bucket_object" "pubsub_function_source_upload" {
  bucket = google_storage_bucket.function_source_code_bucket_ps.name
  name   = "source-code/${var.pubsub_triggered_function_name}/${data.archive_file.pubsub_function_source.output_md5}.zip"
  source = data.archive_file.pubsub_function_source.output_path
}

resource "google_cloudfunctions2_function" "pubsub_event_processor" {
  project  = var.project_id
  location = var.region
  name     = var.pubsub_triggered_function_name

  build_config {
    runtime     = var.pubsub_function_runtime
    entry_point = var.pubsub_function_entry_point
    environment_variables = {
      "GCP_PROJECT_ID"     = var.project_id
      "GCP_REGION"         = var.region
      "CLOUD_RUN_JOB_NAME" = local.cloud_run_job_short_name_ps
    }
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_code_bucket_ps.name
        object = google_storage_bucket_object.pubsub_function_source_upload.name
      }
    }
  }

  service_config {
    service_account_email          = local.app_service_account_email
    available_memory               = "${var.pubsub_function_memory_mb}Mi"
    timeout_seconds                = var.pubsub_function_timeout_seconds
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    min_instance_count             = 0
    max_instance_count             = 2
  }

  labels = {
    environment = "poc",
    trigger     = "pubsub-message"
    purpose     = "invoke-cloud-run-job-from-pubsub"
    managed_by  = "opentofu"
  }
  depends_on = [
    google_cloud_run_v2_job.processor_job_ps,
    google_cloud_run_v2_job_iam_member.app_sa_can_run_processor_job_ps
  ]
}

#######################################
# Eventarc Trigger (Pub/Sub to Cloud Function)
#######################################
resource "google_eventarc_trigger" "pubsub_to_function_trigger" {
  project         = var.project_id
  location        = var.region # Eventarc trigger region must match Pub/Sub topic region or be global for global topics
  name            = var.pubsub_eventarc_trigger_name
  service_account = local.app_service_account_email

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }
  # No bucket criteria here, this is for Pub/Sub

  destination {
    cloud_run_service { # For Gen2 functions, the destination is its underlying Cloud Run service
      service = google_cloudfunctions2_function.pubsub_event_processor.name
      region  = google_cloudfunctions2_function.pubsub_event_processor.location
    }
  }

  transport {
    pubsub {
      topic = google_pubsub_topic.job_request_topic.id # Link to the Pub/Sub topic
    }
  }

  labels = {
    environment = "poc",
    trigger-for = "pubsub-message-processing-job"
    managed_by  = "opentofu"
  }

  depends_on = [
    google_cloudfunctions2_function.pubsub_event_processor,
    google_pubsub_topic.job_request_topic,
    data.terraform_remote_state.iam_core,
  ]
}

#######################################
# IAM propagation wait
#######################################
resource "time_sleep" "wait_for_iam_propagation_pmtj" {
  depends_on = [
    google_cloud_run_v2_job_iam_member.app_sa_can_run_processor_job_ps,
    google_pubsub_topic_iam_member.app_sa_can_publish_to_job_topic
  ]
  create_duration = "30s"
}

