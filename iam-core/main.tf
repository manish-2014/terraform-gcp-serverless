###############################################################################
# iam-core/main.tf
# Defines core IAM, Service Accounts, Custom Roles, APIs, and Secret containers.
###############################################################################

data "google_project" "project" {}

locals {
  apply_timestamp = timestamp()
  datetime_suffix = formatdate("YYYYMMDDhhmmss", local.apply_timestamp)
}

#######################################
# APIs (enable core APIs needed by this module or dependent modules)
#######################################
resource "google_project_service" "iam_api" {
  project                    = var.project_id
  service                    = "iam.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "serviceusage_api" {
  project                    = var.project_id
  service                    = "serviceusage.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "cloudresourcemanager_api" {
  project                    = var.project_id
  service                    = "cloudresourcemanager.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "eventarc_api" {
  project            = var.project_id
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
  depends_on         = [google_project_service.serviceusage_api]
}

resource "google_project_service" "cloudfunctions_api" {
  project            = var.project_id
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
  depends_on         = [google_project_service.serviceusage_api]
}

resource "google_project_service" "run_api" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
  depends_on         = [google_project_service.serviceusage_api]
}

resource "google_project_service" "pubsub_api" {
  project            = var.project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
  depends_on         = [google_project_service.serviceusage_api]
}

resource "google_project_service" "secretmanager_api" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
  depends_on         = [google_project_service.serviceusage_api]
}

#######################################
# Cloud Functions service‐agent identity (needed for functions in other modules using app_sa)
#######################################
resource "google_project_service_identity" "cloudfunctions_sa" {
  provider = google-beta
  project  = var.project_id
  service  = "cloudfunctions.googleapis.com"

  depends_on = [google_project_service.cloudfunctions_api]
}

#######################################
# Custom bucket role (defined once, used by other modules)
#######################################
resource "google_project_iam_custom_role" "bucket_rwl_role" {
  project     = var.project_id
  role_id     = "${var.custom_role_id}_${local.datetime_suffix}"
  title       = "Bucket Read Write List Role (Core)"
  description = "Allows R/W/L/D access to GCS bucket objects - defined in iam-core"
  stage       = "GA"
  permissions = [
    "storage.buckets.get",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
  ]
  depends_on = [google_project_service.iam_api]
}

#######################################
# Application service‐account
#######################################
resource "google_service_account" "app_sa" {
  project      = var.project_id
  account_id   = var.app_service_account_id
  display_name = "Core Application Service Account (madladlab Cloud Xfer)"
  description  = "Managed by OpenTofu from iam-core module"
  depends_on   = [google_project_service.iam_api]
}

# Allow OpenTofu runner (Terraform SA) to impersonate app_sa
resource "google_service_account_iam_member" "tofu_sa_can_act_as_app_sa" {
  service_account_id = google_service_account.app_sa.name
  role                 = "roles/iam.serviceAccountUser"
  member               = "serviceAccount:${var.tofu_manager_sa_account_id}@${var.project_id}.iam.gserviceaccount.com"
}

# Allow Cloud Functions control‐plane to impersonate app_sa
# This allows functions (created in other modules) to run as app_sa
resource "google_service_account_iam_member" "cloudfunctions_sa_can_act_as_app_sa" {
  service_account_id = google_service_account.app_sa.name
  role                 = "roles/iam.serviceAccountUser"
  member               = "serviceAccount:${google_project_service_identity.cloudfunctions_sa.email}"

  depends_on = [google_project_service_identity.cloudfunctions_sa]
}

# app_sa receives Eventarc events (general permission)
resource "google_project_iam_member" "app_sa_eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = google_service_account.app_sa.member
  depends_on = [
    google_project_service.eventarc_api,
    google_service_account.app_sa
  ]
}

# Cloud Storage service‐agent can publish to Pub/Sub (general project-level permission)
resource "google_project_iam_member" "storage_service_agent_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.project.number}@gs-project-accounts.iam.gserviceaccount.com"
  depends_on = [
    google_project_service.pubsub_api,
    google_service_account.app_sa # Implicit dependency on project data source
  ]
}

#######################################
# Service‐account key (optional – for app_sa)
# Consider if this is truly needed or if Workload Identity Federation / other methods can be used by applications.
# If generated, its output is sensitive.
#######################################
resource "google_service_account_key" "app_sa_key" {
  service_account_id = google_service_account.app_sa.name
}

#######################################
# Secret Manager – secret containers and core bindings for app_sa
#######################################
resource "google_secret_manager_secret" "app_secret" {
  project   = var.project_id
  secret_id = var.app_secret_name
  replication {
    auto {}
  }
  labels     = { environment = "poc", managed_by = "opentofu-iam-core" }
  depends_on = [google_project_service.secretmanager_api]
}

resource "google_secret_manager_secret" "ssh_key_secret" {
  project   = var.project_id
  secret_id = var.ssh_key_secret_name
  replication {
    auto {}
  }
  labels     = { environment = "poc", managed_by = "opentofu-iam-core", secret_type = "ssh-private-key" }
  depends_on = [google_project_service.secretmanager_api]
}

resource "google_secret_manager_secret" "pgp_private_key_secret" {
  project   = var.project_id
  secret_id = var.pgp_private_key_secret_name
  replication {
    auto {}
  }
  labels     = { environment = "poc", managed_by = "opentofu-iam-core", secret_type = "pgp-private-key" }
  depends_on = [google_project_service.secretmanager_api]
}

resource "google_secret_manager_secret" "pgp_public_key_secret" {
  project   = var.project_id
  secret_id = var.pgp_public_key_secret_name
  replication {
    auto {}
  }
  labels     = { environment = "poc", managed_by = "opentofu-iam-core", secret_type = "pgp-public-key" }
  depends_on = [google_project_service.secretmanager_api]
}

# IAM bindings for app_sa to access the secrets
resource "google_secret_manager_secret_iam_member" "app_sa_secret_accessor" {
  project   = google_secret_manager_secret.app_secret.project
  secret_id = google_secret_manager_secret.app_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.app_sa.member
}

resource "google_secret_manager_secret_iam_member" "app_sa_ssh_key_accessor" {
  project   = google_secret_manager_secret.ssh_key_secret.project
  secret_id = google_secret_manager_secret.ssh_key_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.app_sa.member
}

resource "google_secret_manager_secret_iam_member" "app_sa_pgp_private_accessor" {
  project   = google_secret_manager_secret.pgp_private_key_secret.project
  secret_id = google_secret_manager_secret.pgp_private_key_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.app_sa.member
}

resource "google_secret_manager_secret_iam_member" "app_sa_pgp_public_accessor" {
  project   = google_secret_manager_secret.pgp_public_key_secret.project
  secret_id = google_secret_manager_secret.pgp_public_key_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.app_sa.member
}

#######################################
# IAM propagation wait (can be useful if subsequent modules apply immediately)
#######################################
resource "time_sleep" "wait_for_iam_propagation_core" {
  depends_on = [
    google_service_account_iam_member.tofu_sa_can_act_as_app_sa,
    google_service_account_iam_member.cloudfunctions_sa_can_act_as_app_sa,
    google_project_iam_member.app_sa_eventarc_receiver,
    google_project_iam_member.storage_service_agent_pubsub_publisher,
    google_secret_manager_secret_iam_member.app_sa_secret_accessor,
    google_secret_manager_secret_iam_member.app_sa_ssh_key_accessor,
    google_secret_manager_secret_iam_member.app_sa_pgp_private_accessor,
    google_secret_manager_secret_iam_member.app_sa_pgp_public_accessor
  ]
  create_duration = "45s"
}

###############################################################################
# End of iam-core/main.tf
###############################################################################