# Terraform: iam-core Project

This Terraform project is responsible for provisioning the foundational Identity and Access Management (IAM) resources and core service configurations for the MadLadLab Cloud Transfer solutions. It sets up essential service accounts, custom roles, enables necessary APIs, and creates Secret Manager secret containers.

The resources created by this project are intended to be consumed by other Terraform projects that deploy specific application workflows (e.g., bucket-triggered jobs, Pub/Sub-triggered jobs).

## Table of Contents

1.  [Purpose](#purpose)
2.  [Prerequisites](#prerequisites)
3.  [Configuration](#configuration)
4.  [Deployment](#deployment)
5.  [Resources Created](#resources-created)
6.  [Service Accounts Managed](#service-accounts-managed)
7.  [IAM Roles and Permissions Created/Assigned](#iam-roles-and-permissions-createdassigned)
8.  [Outputs](#outputs)

## Purpose

* To centralize the creation and management of shared IAM resources.
* To ensure consistent API enablement across dependent projects.
* To define a core application service account with specific permissions.
* To establish a custom IAM role for granular bucket access.
* To create containers for application secrets in Secret Manager.

## Prerequisites

* Google Cloud SDK (`gcloud`) installed and authenticated.
* Terraform (or OpenTofu) installed.
* A GCP Project.
* A Service Account for Terraform to use for deployment, with sufficient permissions to manage the resources defined in this project (e.g., Project IAM Admin, Service Account Admin, Service Usage Admin, Secret Manager Admin).
* The JSON key file for the Terraform deployment Service Account.

## Configuration

1.  Ensure all files (`main.tf`, `variables.tf`, `outputs.tf`, `provider.tf`) are in the `iam-core/` directory.
2.  Create a `terraform.tfvars` file in this directory to specify your project-specific values:

    ```tfvars
    project_id                 = "your-gcp-project-id"
    region                     = "your-gcp-region" # e.g., "us-central1"
    service_account_key_path   = "/path/to/your/terraform-sa-key.json"
    tofu_manager_sa_account_id = "terraform-sa-name" // The part of the SA email before @
    
    # Optional: Override default service account or role IDs
    # app_service_account_id   = "custom-app-sa"
    # custom_role_id           = "customBucketAccessRole"

    # Optional: Override default secret names
    # app_secret_name          = "my-custom-app-password"
    # ssh_key_secret_name      = "my-custom-ssh-key"
    # ... and so on for other secrets
    ```

## Deployment

1.  Navigate to the `iam-core/` directory.
2.  Initialize Terraform:
    ```bash
    terraform init
    ```
3.  Review the plan:
    ```bash
    terraform plan -var-file="terraform.tfvars"
    ```
4.  Apply the configuration:
    ```bash
    terraform apply -var-file="terraform.tfvars"
    ```
    Confirm by typing `yes` when prompted.

## Resources Created

This project provisions the following GCP resources:

1.  **Google Project Services (APIs Enabled):**
    * `iam.googleapis.com` (Identity and Access Management API)
    * `serviceusage.googleapis.com` (Service Usage API)
    * `cloudresourcemanager.googleapis.com` (Cloud Resource Manager API)
    * `eventarc.googleapis.com` (Eventarc API)
    * `cloudfunctions.googleapis.com` (Cloud Functions API)
    * `run.googleapis.com` (Cloud Run API)
    * `pubsub.googleapis.com` (Cloud Pub/Sub API)
    * `secretmanager.googleapis.com` (Secret Manager API)

2.  **Google Project Service Identity:**
    * `google_project_service_identity.cloudfunctions_sa`: Retrieves/Ensures the existence of the Google-managed service account for the Cloud Functions service (`service-<project_number>@gcp-sa-cloudfunctions.iam.gserviceaccount.com`).

3.  **Custom IAM Role:**
    * `google_project_iam_custom_role.bucket_rwl_role`: A project-level custom IAM role (default ID prefix: `bucketReadWriteListRole_YYYYMMDDhhmmss`).

4.  **Service Account:**
    * `google_service_account.app_sa`: The primary application service account (default ID: `madladlab-xfer-app-sa`).

5.  **Service Account Key:**
    * `google_service_account_key.app_sa_key`: A JSON key generated for the `app_sa` service account. **This key is sensitive and its value is outputted by Terraform.**

6.  **Secret Manager Secrets (Containers only):**
    * `google_secret_manager_secret.app_secret` (default ID: `my-app-database-password`)
    * `google_secret_manager_secret.ssh_key_secret` (default ID: `my-ssh-private-key`)
    * `google_secret_manager_secret.pgp_private_key_secret` (default ID: `my-pgp-private-key`)
    * `google_secret_manager_secret.pgp_public_key_secret` (default ID: `my-pgp-public-key`)

7.  **IAM Policy Bindings:**
    * Numerous `google_service_account_iam_member` and `google_project_iam_member` resources to grant permissions (detailed below).
    * `google_secret_manager_secret_iam_member` resources to grant the `app_sa` access to the created secret containers.

8.  **Time Sleep:**
    * `time_sleep.wait_for_iam_propagation_core`: A 45-second pause to allow IAM changes to propagate.

## Service Accounts Managed

1.  **`google_service_account.app_sa` (Created):**
    * **ID (Variable):** `var.app_service_account_id` (default: `madladlab-xfer-app-sa`)
    * **Purpose:** This is the central service account intended to be used by application components (Cloud Functions, Cloud Run services/jobs) in downstream Terraform projects.
    * **Key Generated:** Yes, `google_service_account_key.app_sa_key`.

2.  **Terraform Deployment Service Account (Modified - Granted Permissions):**
    * **ID (Variable):** `var.tofu_manager_sa_account_id` (e.g., `tofu-manager-sa`)
    * **Modification:** Granted the `roles/iam.serviceAccountUser` role on the `app_sa`. This allows the Terraform deployment SA to impersonate `app_sa` if needed during resource provisioning that requires acting as the SA.

3.  **Cloud Functions Service Agent (Google-Managed) (Modified - Granted Permissions):**
    * **Identity:** `service-<project_number>@gcp-sa-cloudfunctions.iam.gserviceaccount.com` (retrieved via `google_project_service_identity.cloudfunctions_sa`)
    * **Modification:** Granted the `roles/iam.serviceAccountUser` role on the `app_sa`. This allows the Google Cloud Functions service to deploy functions that run *as* the `app_sa`.

4.  **Cloud Storage Service Agent (Google-Managed) (Granted Project-Level Role):**
    * **Identity:** `service-<project_number>@gs-project-accounts.iam.gserviceaccount.com`
    * **Modification:** Granted the `roles/pubsub.publisher` role at the project level. This allows Cloud Storage to publish events to Pub/Sub (a general permission, useful if direct GCS to Pub/Sub notifications are ever configured).

## IAM Roles and Permissions Created/Assigned

1.  **Custom Role Created:**
    * **`google_project_iam_custom_role.bucket_rwl_role`**:
        * **Title:** "Bucket Read Write List Role (Core)"
        * **ID:** `${var.custom_role_id}_${local.datetime_suffix}`
        * **Permissions:**
            * `storage.buckets.get`
            * `storage.objects.create`
            * `storage.objects.delete`
            * `storage.objects.get`
            * `storage.objects.list`
        * **Purpose:** This role will be assigned to the `app_sa` on specific buckets in other Terraform projects to grant it necessary GCS access.

2.  **Permissions Assigned to `app_sa` (`google_service_account.app_sa`):**
    * **`roles/eventarc.eventReceiver` (Project Level):**
        * Bound via `google_project_iam_member.app_sa_eventarc_receiver`.
        * Allows `app_sa` to be the identity that Eventarc uses to invoke target services (like Cloud Functions or Cloud Run) when an event occurs.
    * **`roles/secretmanager.secretAccessor` (On each created Secret):**
        * Bound via:
            * `google_secret_manager_secret_iam_member.app_sa_secret_accessor`
            * `google_secret_manager_secret_iam_member.app_sa_ssh_key_accessor`
            * `google_secret_manager_secret_iam_member.app_sa_pgp_private_accessor`
            * `google_secret_manager_secret_iam_member.app_sa_pgp_public_accessor`
        * Allows `app_sa` to read the values of the secrets stored in the created Secret Manager containers.

3.  **Permissions Assigned to Other Service Accounts:**
    * **Terraform Deployment SA (`var.tofu_manager_sa_account_id`):**
        * `roles/iam.serviceAccountUser` on `app_sa` (via `google_service_account_iam_member.tofu_sa_can_act_as_app_sa`).
    * **Cloud Functions Service Agent:**
        * `roles/iam.serviceAccountUser` on `app_sa` (via `google_service_account_iam_member.cloudfunctions_sa_can_act_as_app_sa`).
    * **Cloud Storage Service Agent:**
        * `roles/pubsub.publisher` at the Project Level (via `google_project_iam_member.storage_service_agent_pubsub_publisher`).

## Outputs

This project provides the following outputs for use in other Terraform projects (via `terraform_remote_state`):

* `app_service_account_email`: Email of the created `app_sa`.
* `app_service_account_name`: Full name of the `app_sa`.
* `app_service_account_key_base64`: Base64 encoded JSON key for `app_sa` (sensitive).
* `custom_bucket_role_id`: Full ID of the `bucket_rwl_role`.
* `cloudfunctions_service_agent_email`: Email of the Cloud Functions service agent.
* `app_secret_id`: Full ID of the `app_secret` container.
* `ssh_key_secret_id`: Full ID of the `ssh_key_secret` container.
* `pgp_private_key_secret_id`: Full ID of the `pgp_private_key_secret` container.
* `pgp_public_key_secret_id`: Full ID of the `pgp_public_key_secret` container.

These outputs facilitate the linking of this core IAM setup with subsequent application-specific infrastructure deployments.
