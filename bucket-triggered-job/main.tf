###############################################################################
# bucket-triggered-job/main.tf
# Defines GCS trigger bucket, Cloud Function (job invoker), Eventarc trigger,
# and the Cloud Run Job.
###############################################################################

data "google_project" "project" {} # To get project number if needed

# Fetch outputs from the iam-core project
data "terraform_remote_state" "iam_core" {
  backend = "local" # Assuming local backend for iam-core
  config = {
    path = var.iam_core_terraform_state_path
  }
}

locals {
  app_service_account_email = data.terraform_remote_state.iam_core.outputs.app_service_account_email
  custom_bucket_role_id     = data.terraform_remote_state.iam_core.outputs.custom_bucket_role_id
  # Ensure the Cloud Run Job name used in Python env var is the short name
  cloud_run_job_short_name  = var.cloud_run_job_name
}

#######################################
# GCS Bucket for Function Source Code
#######################################
resource "random_id" "function_source_bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "function_source_code_bucket" {
  project                     = var.project_id
  name                        = "${var.function_source_code_bucket_name_prefix}${random_id.function_source_bucket_suffix.hex}"
  location                    = var.region
  storage_class               = "STANDARD" # Or REGIONAL for lower cost if appropriate
  uniform_bucket_level_access = true
  force_destroy               = true # Set to false in production
  labels = {
    environment = "poc",
    purpose     = "btj-function-source-code"
    managed_by  = "opentofu"
  }
}

#######################################
# GCS Trigger Bucket (where users upload files)
#######################################
resource "random_id" "trigger_bucket_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "gcs_trigger_bucket" {
  project                     = var.project_id
  name                        = "${var.trigger_bucket_name_prefix}${random_id.trigger_bucket_suffix.hex}"
  location                    = var.region
  storage_class               = var.trigger_bucket_storage_class
  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
  force_destroy = true # Set to false in production
  labels = {
    environment = "poc",
    purpose     = "btj-file-trigger-input"
    managed_by  = "opentofu"
  }
}

# Grant the app_service_account permissions on the trigger bucket using the custom role
resource "google_storage_bucket_iam_member" "app_sa_trigger_bucket_binding" {
  bucket = google_storage_bucket.gcs_trigger_bucket.name
  role   = local.custom_bucket_role_id
  member = "serviceAccount:${local.app_service_account_email}"
}

#######################################
# Cloud Run Job
#######################################
resource "google_cloud_run_v2_job" "processor_job" {
  project  = var.project_id
  location = var.region
  name     = local.cloud_run_job_short_name # Use the local for consistency

  template {
    template {
      service_account = local.app_service_account_email
      max_retries     = var.cloud_run_job_max_retries
      timeout         = "${var.cloud_run_job_task_timeout_seconds}s"

      containers {
        image = var.cloud_run_job_image_uri
        # If your job 'basicpocjob:latest' expects a static config JSON as an argument:
        args = [var.cloud_run_job_static_config_arg]
        # The Python function will pass SOURCE_BUCKET and SOURCE_OBJECT as ENV vars dynamically.
        # If your job also needs other static ENV vars, define them here:
        # env {
        #   name = "STATIC_JOB_ENV_VAR"
        #   value = "some_static_value"
        # }
        resources {
          limits = {
            cpu    = var.cloud_run_job_container_cpu_limit
            memory = "${var.cloud_run_job_container_memory_limit_mb}Mi"
          }
        }
      }
    }
  }

  labels = {
    environment = "poc",
    app         = "btj-processor"
    managed_by  = "opentofu"
  }
}

# Allow the app_service_account (running the Cloud Function) to execute this Cloud Run Job
resource "google_cloud_run_v2_job_iam_member" "app_sa_can_run_processor_job" {
  project  = google_cloud_run_v2_job.processor_job.project
  location = google_cloud_run_v2_job.processor_job.location
  name     = google_cloud_run_v2_job.processor_job.name
  role     = "roles/run.invoker" # Allows invoking the job
  member   = "serviceAccount:${local.app_service_account_email}"
}


#######################################
# Cloud Function (Gen 2) - GCS Triggered Job Invoker
#######################################
data "archive_file" "gcs_function_source" {
  type        = "zip"
  source_dir  = var.gcs_function_source_dir
  output_path = "${path.cwd}/.terraform/archives/${var.gcs_triggered_function_name}_source.zip"
}

resource "google_storage_bucket_object" "gcs_function_source_upload" {
  bucket = google_storage_bucket.function_source_code_bucket.name
  name   = "source-code/${var.gcs_triggered_function_name}/${data.archive_file.gcs_function_source.output_md5}.zip"
  source = data.archive_file.gcs_function_source.output_path # Path to the zipped function source
}

resource "google_cloudfunctions2_function" "gcs_event_processor" {
  project  = var.project_id
  location = var.region
  name     = var.gcs_triggered_function_name

  build_config {
    runtime     = var.gcs_function_runtime
    entry_point = var.gcs_function_entry_point
    environment_variables = {
      # These are passed to the function's runtime environment
      "GCP_PROJECT_ID"     = var.project_id
      "GCP_REGION"         = var.region
      "CLOUD_RUN_JOB_NAME" = local.cloud_run_job_short_name # Pass the short name of the job
    }
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_code_bucket.name
        object = google_storage_bucket_object.gcs_function_source_upload.name
      }
    }
  }

  service_config {
    service_account_email          = local.app_service_account_email
    available_memory               = "${var.gcs_function_memory_mb}Mi"
    timeout_seconds                = var.gcs_function_timeout_seconds
    ingress_settings               = "ALLOW_INTERNAL_ONLY" # Triggered by Eventarc
    all_traffic_on_latest_revision = true
    min_instance_count             = 0 # For cost-effectiveness in PoC
    max_instance_count             = 2 # Adjust as needed
  }

  labels = {
    environment = "poc",
    trigger     = "gcs-upload"
    purpose     = "invoke-cloud-run-job"
    managed_by  = "opentofu"
  }

  depends_on = [
    # Ensure job and its IAM binding exist before function tries to use related env vars
    google_cloud_run_v2_job.processor_job,
    google_cloud_run_v2_job_iam_member.app_sa_can_run_processor_job
  ]
}

#######################################
# Eventarc Trigger (GCS to Cloud Function)
#######################################
resource "google_eventarc_trigger" "gcs_to_function_trigger" {
  project         = var.project_id
  location        = var.region # Eventarc trigger must be in the same region as the destination or "global" for some event types
  name            = var.gcs_eventarc_trigger_name
  service_account = local.app_service_account_email # SA that Eventarc uses to call the function

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized" # Event for new object creation
  }
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.gcs_trigger_bucket.name
  }
  # Optional: filter by object name prefix if needed
  # matching_criteria {
  #   attribute = "name"
  #   operator = "match" # Can be "match-path-pattern" for more complex patterns
  #   value = "uploads/**" # Example: only files in 'uploads/' folder
  # }

  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.gcs_event_processor.name
      region  = google_cloudfunctions2_function.gcs_event_processor.location
      # path is not typically needed when targeting a Cloud Function directly
    }
  }

  labels = {
    environment = "poc",
    trigger-for = "gcs-file-processing-job"
    managed_by  = "opentofu"
  }

  depends_on = [
    google_cloudfunctions2_function.gcs_event_processor,
    data.terraform_remote_state.iam_core, # Ensure app_sa exists and has eventarc.eventReceiver
  ]
}

#######################################
# IAM propagation wait (Optional, if experiencing delays)
#######################################
resource "time_sleep" "wait_for_iam_propagation_btj" {
  depends_on = [
    google_storage_bucket_iam_member.app_sa_trigger_bucket_binding,
    google_cloud_run_v2_job_iam_member.app_sa_can_run_processor_job
    # Add other IAM resources from this module if needed
  ]
  create_duration = "30s" # Shorter wait, adjust if needed
}
