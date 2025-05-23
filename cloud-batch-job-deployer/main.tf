###############################################################################
# cloud-batch-job-deployer/main.tf
# Enables Batch API, grants permissions, deploys HTTP Cloud Function to submit Batch jobs,
# and sets up Pub/Sub notifications for job status with a logger function.
###############################################################################

data "google_project" "project" {}

data "terraform_remote_state" "iam_core" {
  backend = "local"
  config = {
    path = var.iam_core_terraform_state_path
  }
}

locals {
  app_service_account_email = data.terraform_remote_state.iam_core.outputs.app_service_account_email
  app_service_account_name  = data.terraform_remote_state.iam_core.outputs.app_service_account_name
}

#######################################
# Enable APIs
#######################################
resource "google_project_service" "batch_api" {
  project            = var.project_id
  service            = "batch.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "pubsub_api_cb" {
  project            = var.project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "eventarc_api_cb" { # Ensure Eventarc API is enabled
  project            = var.project_id
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry_api_cb" { # Ensure Artifact Registry API is enabled
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}


#######################################
# Cloud Batch Service Agent Identity
#######################################
resource "google_project_service_identity" "batch_sa_identity" {
  provider = google-beta
  project  = var.project_id
  service  = "batch.googleapis.com"
  depends_on = [google_project_service.batch_api]
}

#######################################
# Pub/Sub Topic for Batch Job Status Notifications
#######################################
resource "google_pubsub_topic" "batch_job_status_topic" {
  project = var.project_id
  name    = var.batch_job_status_topic_name
  labels = {
    environment = "poc",
    purpose     = "cloud-batch-job-status"
    managed_by  = "opentofu"
  }
  depends_on = [google_project_service.pubsub_api_cb]
}

#######################################
# IAM Permissions
#######################################
resource "google_project_iam_member" "app_sa_batch_jobs_editor" {
  project    = var.project_id
  role       = "roles/batch.jobsEditor" # Allows function to create/manage jobs
  member     = "serviceAccount:${local.app_service_account_email}"
  depends_on = [google_project_service.batch_api, data.terraform_remote_state.iam_core]
}

resource "google_project_iam_member" "batch_agent_reporter" {
  project    = var.project_id
  role       = "roles/batch.agentReporter" # Allows Batch Service Agent to report status
  member     = "serviceAccount:${google_project_service_identity.batch_sa_identity.email}"
  depends_on = [google_project_service_identity.batch_sa_identity]
}

resource "google_service_account_iam_member" "batch_agent_can_act_as_app_sa_for_jobs" {
  service_account_id = local.app_service_account_name
  role                 = "roles/iam.serviceAccountUser" # Allows Batch Service Agent to act as app_sa for tasks
  member               = "serviceAccount:${google_project_service_identity.batch_sa_identity.email}"
  depends_on = [
    data.terraform_remote_state.iam_core,
    google_project_service_identity.batch_sa_identity
  ]
}

resource "google_service_account_iam_member" "app_sa_can_act_as_self_for_batch" {
  service_account_id = local.app_service_account_name 
  role                 = "roles/iam.serviceAccountUser"   
  member               = "serviceAccount:${local.app_service_account_email}" 
  depends_on = [
    data.terraform_remote_state.iam_core 
  ]
}

resource "google_pubsub_topic_iam_member" "batch_agent_can_publish_status" {
  project = google_pubsub_topic.batch_job_status_topic.project
  topic   = google_pubsub_topic.batch_job_status_topic.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_project_service_identity.batch_sa_identity.email}"
  depends_on = [
    google_pubsub_topic.batch_job_status_topic,
    google_project_service_identity.batch_sa_identity
  ]
}

# Permissions for the App Service Account (running on Batch VMs)
resource "google_project_iam_member" "app_sa_logging_logwriter" {
  project    = var.project_id
  role       = "roles/logging.logWriter"
  member     = "serviceAccount:${local.app_service_account_email}"
  depends_on = [data.terraform_remote_state.iam_core]
}

resource "google_project_iam_member" "app_sa_monitoring_metricwriter" {
  project    = var.project_id
  role       = "roles/monitoring.metricWriter"
  member     = "serviceAccount:${local.app_service_account_email}"
  depends_on = [data.terraform_remote_state.iam_core]
}

resource "google_project_iam_member" "app_sa_artifactregistry_reader" {
  project    = var.project_id
  role       = "roles/artifactregistry.reader" # Allows pulling images from any AR repo in the project
  member     = "serviceAccount:${local.app_service_account_email}"
  depends_on = [data.terraform_remote_state.iam_core, google_project_service.artifactregistry_api_cb]
}


#######################################
# GCS Bucket for Cloud Functions' Source Code
#######################################
resource "random_id" "function_source_bucket_suffix_cb" {
  byte_length = 4
}

resource "google_storage_bucket" "function_source_code_bucket_cb" {
  project                     = var.project_id
  name                        = "${var.function_source_code_bucket_name_prefix_cb}${random_id.function_source_bucket_suffix_cb.hex}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy               = true
  labels = {
    environment = "poc",
    purpose     = "cb-functions-source-code" 
    managed_by  = "opentofu"
  }
}

#######################################
# Cloud Function (Gen 2) - HTTP Triggered Batch Submitter
#######################################
data "archive_file" "batch_submitter_function_source" { 
  type        = "zip"
  source_dir  = var.batch_function_source_dir
  output_path = "${path.cwd}/.terraform/archives/${var.batch_submitter_function_name}_source.zip"
}

resource "google_storage_bucket_object" "batch_submitter_function_source_upload" { 
  bucket = google_storage_bucket.function_source_code_bucket_cb.name
  name   = "source-code/${var.batch_submitter_function_name}/${data.archive_file.batch_submitter_function_source.output_md5}.zip"
  source = data.archive_file.batch_submitter_function_source.output_path
}

resource "google_cloudfunctions2_function" "batch_submitter_http_function" {
  project  = var.project_id
  location = var.region
  name     = var.batch_submitter_function_name

  build_config {
    runtime     = var.batch_function_runtime
    entry_point = var.batch_function_entry_point
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_code_bucket_cb.name
        object = google_storage_bucket_object.batch_submitter_function_source_upload.name
      }
    }
  }

  service_config {
    service_account_email          = local.app_service_account_email
    available_memory               = "${var.batch_function_memory_mb}Mi"
    timeout_seconds                = var.batch_function_timeout_seconds
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    min_instance_count             = 0
    max_instance_count             = 1
    environment_variables = {
      "GCP_PROJECT_ID"                 = var.project_id
      "GCP_REGION"                     = var.region
      "DEFAULT_DOCKER_IMAGE_URI"       = var.default_batch_job_docker_image_uri
      "BATCH_JOB_SERVICE_ACCOUNT"      = local.app_service_account_email
      "BATCH_JOB_NOTIFICATION_TOPIC"   = google_pubsub_topic.batch_job_status_topic.id 
    }
  }
  labels = { 
    environment = "poc",
    trigger     = "http",
    purpose     = "submit-cloud-batch-job" 
    managed_by  = "opentofu"
  }
  depends_on = [
    google_project_iam_member.app_sa_batch_jobs_editor,
    google_service_account_iam_member.batch_agent_can_act_as_app_sa_for_jobs,
    google_service_account_iam_member.app_sa_can_act_as_self_for_batch,
    google_project_iam_member.app_sa_logging_logwriter,
    google_project_iam_member.app_sa_monitoring_metricwriter,
    google_project_iam_member.app_sa_artifactregistry_reader,
    google_pubsub_topic.batch_job_status_topic 
  ]
}

resource "google_cloud_run_service_iam_member" "batch_submitter_function_public_invoker" {
  project  = google_cloudfunctions2_function.batch_submitter_http_function.project
  location = google_cloudfunctions2_function.batch_submitter_http_function.location
  service  = google_cloudfunctions2_function.batch_submitter_http_function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Allow the job’s service-account to report to Batch
resource "google_project_iam_member" "app_sa_batch_agent_reporter" {
  project = var.project_id
  role    = "roles/batch.agentReporter"
  member  = "serviceAccount:${local.app_service_account_email}"

  depends_on = [
    data.terraform_remote_state.iam_core,
    google_project_service.batch_api      # makes sure the API is enabled
  ]
}

#######################################
# Cloud Function (Gen 2) - Pub/Sub Triggered Batch Status Logger
#######################################
data "archive_file" "batch_status_logger_function_source" {
  type        = "zip"
  source_dir  = var.batch_status_logger_function_source_dir
  output_path = "${path.cwd}/.terraform/archives/${var.batch_status_logger_function_name}_source.zip"
}

resource "google_storage_bucket_object" "batch_status_logger_function_source_upload" {
  bucket = google_storage_bucket.function_source_code_bucket_cb.name 
  name   = "source-code/${var.batch_status_logger_function_name}/${data.archive_file.batch_status_logger_function_source.output_md5}.zip"
  source = data.archive_file.batch_status_logger_function_source.output_path
}

resource "google_cloudfunctions2_function" "batch_status_logger_function" {
  project  = var.project_id
  location = var.region
  name     = var.batch_status_logger_function_name

  build_config {
    runtime     = var.batch_status_logger_function_runtime
    entry_point = var.batch_status_logger_function_entry_point
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_code_bucket_cb.name
        object = google_storage_bucket_object.batch_status_logger_function_source_upload.name
      }
    }
  }

  service_config {
    service_account_email          = local.app_service_account_email 
    available_memory               = "${var.batch_status_logger_function_memory_mb}Mi"
    timeout_seconds                = var.batch_status_logger_function_timeout_seconds
    ingress_settings               = "ALLOW_INTERNAL_ONLY" 
    all_traffic_on_latest_revision = true
    min_instance_count             = 0
    max_instance_count             = 1
  }
  labels = { 
    environment = "poc",
    trigger     = "pubsub",
    purpose     = "log-batch-job-status" 
    managed_by  = "opentofu"
  }
  depends_on = [
    google_pubsub_topic.batch_job_status_topic 
  ]
}

# Allow Eventarc trigger (via app_service_account) to invoke the logger function
resource "google_cloud_run_service_iam_member" "logger_function_eventarc_invoker" {
  project  = google_cloudfunctions2_function.batch_status_logger_function.project
  location = google_cloudfunctions2_function.batch_status_logger_function.location
  service  = google_cloudfunctions2_function.batch_status_logger_function.name 
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.app_service_account_email}" # Eventarc trigger uses this SA
}


#######################################
# Eventarc Trigger (Batch Status Pub/Sub to Logger Function)
#######################################
resource "google_eventarc_trigger" "batch_status_to_logger_trigger" {
  project         = var.project_id
  location        = var.region
  name            = var.batch_status_eventarc_trigger_name
  service_account = local.app_service_account_email # SA used by Eventarc to push to Pub/Sub and invoke target

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }

  destination {
    cloud_run_service { 
      service = google_cloudfunctions2_function.batch_status_logger_function.name
      region  = google_cloudfunctions2_function.batch_status_logger_function.location
    }
  }

  transport {
    pubsub {
      topic = google_pubsub_topic.batch_job_status_topic.id
    }
  }
  labels = { 
    environment = "poc",
    purpose     = "trigger-batch-status-logger" 
    managed_by  = "opentofu"
  }
  depends_on = [
    google_cloudfunctions2_function.batch_status_logger_function,
    google_pubsub_topic.batch_job_status_topic,
    google_cloud_run_service_iam_member.logger_function_eventarc_invoker, 
    data.terraform_remote_state.iam_core, 
    google_project_service.eventarc_api_cb
  ]
}


#######################################
# IAM propagation wait
#######################################
resource "time_sleep" "wait_for_iam_propagation_cb" {
  depends_on = [
    google_project_iam_member.app_sa_batch_jobs_editor,
    google_project_iam_member.batch_agent_reporter,
    google_service_account_iam_member.batch_agent_can_act_as_app_sa_for_jobs,
    google_service_account_iam_member.app_sa_can_act_as_self_for_batch, 
    google_project_iam_member.app_sa_logging_logwriter,
    google_project_iam_member.app_sa_monitoring_metricwriter,
    google_project_iam_member.app_sa_artifactregistry_reader,
    google_cloud_run_service_iam_member.batch_submitter_function_public_invoker,
    google_cloud_run_service_iam_member.logger_function_eventarc_invoker, 
    google_project_service_identity.batch_sa_identity,
    google_pubsub_topic_iam_member.batch_agent_can_publish_status,
    google_eventarc_trigger.batch_status_to_logger_trigger 
  ]
  create_duration = "60s" 
}
