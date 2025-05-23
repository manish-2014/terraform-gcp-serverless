###############################################################################
# iam-core/variables.tf
# Variables for core IAM, Service Accounts, Custom Roles, APIs, and Secrets.
###############################################################################

############################
# Core project / location
############################
variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The primary GCP region for resources like function service agent."
  type        = string
  default     = "us-central1"
}

variable "service_account_key_path" {
  description = "Absolute path to the Service‐Account JSON key used by Terraform/OpenTofu for deployment."
  type        = string
  sensitive   = true
}

############################
# IAM / service‐accounts
############################
variable "app_service_account_id" {
  description = "Account ID for the application runtime service‐account (e.g., 'my-app-sa')."
  type        = string
  default     = "madladlab-xfer-app-sa"
}

variable "custom_role_id" {
  description = "Base ID for the custom IAM role for bucket access (e.g., 'bucketReadWriteListRole'). A timestamp suffix will be added."
  type        = string
  default     = "bucketReadWriteListRole"
}

variable "tofu_manager_sa_account_id" {
  description = "Account ID (email prefix) of the service‐account running Terraform/OpenTofu (e.g., 'tofu-manager-sa')."
  type        = string
  default     = "tofu-manager-sa"
}

############################
# Secret‐Manager secret IDs
############################
variable "app_secret_name" {
  description = "Secret ID for app DB password."
  type        = string
  default     = "my-app-database-password"
}

variable "ssh_key_secret_name" {
  description = "Secret ID for SSH private key."
  type        = string
  default     = "my-ssh-private-key"
}

variable "pgp_private_key_secret_name" {
  description = "Secret ID for PGP private key."
  type        = string
  default     = "my-pgp-private-key"
}

variable "pgp_public_key_secret_name" {
  description = "Secret ID for PGP public key."
  type        = string
  default     = "my-pgp-public-key"
}