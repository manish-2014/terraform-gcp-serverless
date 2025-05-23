###############################################################################
# iam-core/outputs.tf
# Outputs from the core IAM module.
###############################################################################

output "app_service_account_email" {
  description = "The email address of the created application Service Account."
  value       = google_service_account.app_sa.email
}

output "app_service_account_name" {
  description = "The full name of the application Service Account (projects/.../serviceAccounts/...)."
  value       = google_service_account.app_sa.name
}

output "app_service_account_key_base64" {
  description = "The private key for the application Service Account, base64 encoded. Treat this as highly sensitive."
  value       = google_service_account_key.app_sa_key.private_key
  sensitive   = true
}

output "custom_bucket_role_id" {
  description = "The full ID of the custom IAM role for bucket R/W/L access (projects/.../roles/...)."
  value       = google_project_iam_custom_role.bucket_rwl_role.id
}

output "cloudfunctions_service_agent_email" {
  description = "The email of the Cloud Functions service agent for the project."
  value       = google_project_service_identity.cloudfunctions_sa.email
}

output "app_secret_id" {
  description = "The full ID of the application secret container in Secret Manager."
  value       = google_secret_manager_secret.app_secret.id
}

output "ssh_key_secret_id" {
  description = "The full ID of the SSH private key secret container."
  value       = google_secret_manager_secret.ssh_key_secret.id
}

output "pgp_private_key_secret_id" {
  description = "The full ID of the PGP private key secret container."
  value       = google_secret_manager_secret.pgp_private_key_secret.id
}

output "pgp_public_key_secret_id" {
  description = "The full ID of the PGP public key secret container."
  value       = google_secret_manager_secret.pgp_public_key_secret.id
}