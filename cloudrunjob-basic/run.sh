#!/usr/bin/env bash
# vault_commons.sh - Common setup for HCP Vault Secrets API calls

# Exit on error, treat unset variables as error, propagate pipeline errors
set -euo pipefail

# --- Configuration ---
# Define the path to the environment file containing credentials and IDs
# Expected variables in the file:
# HCP_CLIENT_ID=...
# HCP_CLIENT_SECRET=...
# HCP_ORG_ID=... (Must be the UUID, e.g., dcbeb41a-7899-46d6-81e4-e8bb45573d3f)
# HCP_PROJ_ID=... (e.g., 6cb3eace-c7b8-4b9c-a636-8c4aef6d6376)
# VLT_APPS_NAME=... (e.g., safe-web-app)
ENV_FILE="${HOME}/projects/devops/environment-center/hvault-credentials/vault.env"
API_VERSION="2023-11-28"

# --- Helper Functions ---

# Function to log messages
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $@" >&2 # Log to stderr
}

# Function to load environment variables from a file
# Skips comments and empty lines
load_env() {
  local env_file="$1"
  if [[ ! -f "$env_file" ]]; then
    log "ERROR: Environment file not found: $env_file"
    return 1
  fi
  log "Loading environment variables from $env_file..."
  # Use process substitution and source for cleaner export
  # Exclude lines starting with # or empty lines
  # Ensure values are quoted properly
  source <(grep -Ev '^\s*(#|$)' "$env_file" | sed -E 's/^([^=]+)=(.*)$/export \1="\2"/')
  log "Environment variables loaded."
}
# 1) Load HCP credentials + identifiers
load_env "$ENV_FILE"

# 2) Check required variables are set and build base URL
log "Validating required environment variables..."
: "${HCP_CLIENT_ID?ERROR: HCP_CLIENT_ID is not set. Check $ENV_FILE}"
: "${HCP_CLIENT_SECRET?ERROR: HCP_CLIENT_SECRET is not set. Check $ENV_FILE}"
: "${HCP_ORG_ID?ERROR: HCP_ORG_ID is not set. Check $ENV_FILE}"
# Add a check for the expected format (UUID) - adjust regex if needed
if [[ ! "$HCP_ORG_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    log "WARNING: HCP_ORG_ID ('$HCP_ORG_ID') does not look like a UUID. API calls may fail."
    log "         Please ensure it's the Organization UUID from the HCP Portal."
fi
: "${HCP_PROJ_ID?ERROR: HCP_PROJ_ID is not set. Check $ENV_FILE}"
: "${VLT_APPS_NAME?ERROR: VLT_APPS_NAME is not set. Check $ENV_FILE}"
log "Required variables seem to be set."

# Build and export the base API URL
export BASE_URL="https://api.cloud.hashicorp.com/secrets/${API_VERSION}/organizations/${HCP_ORG_ID}/projects/${HCP_PROJ_ID}/apps/${VLT_APPS_NAME}"
log "Base API URL set to: $BASE_URL"

java -jar target/cloud-transfer-webapp-0.0.1-SNAPSHOT.jar
