#!/bin/bash

# === Configuration ===
# These values should match your deployed resources (from tofu output)
JOB_NAME="scotty-poc-job"
REGION="us-central1"         # From your variables.tf
PROJECT_ID="scottycloudxferpoc1" # From your variables.tf

# === Script Logic ===

# Check if a config file path was provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <path_to_config.json>"
  exit 1
fi

CONFIG_FILE=$1

# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at '$CONFIG_FILE'"
  exit 1
fi

# Read JSON content from the file
JSON_CONTENT=$(cat "$CONFIG_FILE")
# --- <<< ADDED: Encode JSON to Base64 >>> ---
# Use -w 0 to prevent line wrapping if your base64 supports it (common on Linux)
ENCODED_JSON_CONTENT=$(echo "$JSON_CONTENT" | base64 -w 0)
if [ $? -ne 0 ]; then
  echo "Error: Failed to Base64 encode JSON content."
  exit 1
fi
echo "--------------------------------------------------"
echo "Invoking Cloud Run Job: $JOB_NAME"
echo "Region:               $REGION"
echo "Project:              $PROJECT_ID"
echo "Using config file:    $CONFIG_FILE"
echo "Config Content (start): $(echo "$JSON_CONTENT" | head -c 100)..."
echo "--------------------------------------------------"
echo "Executing command:"
echo "gcloud run jobs execute \"$JOB_NAME\" \\"
echo "  --args=\"\$JSON_CONTENT\" \\" # Note: \$JSON_CONTENT shows the variable name, actual content will be passed
echo "  --region=\"$REGION\" \\"
echo "  --project=\"$PROJECT_ID\" \\"
echo "  --wait"                     # Wait for the job execution to complete
echo "--------------------------------------------------"

# Execute the Cloud Run Job using gcloud
# The --args flag takes the JSON content directly.
# Environment variables (HCP_*) are already set on the job via Terraform.
gcloud run jobs execute "$JOB_NAME" \
  --args="$ENCODED_JSON_CONTENT" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --wait

# Capture the exit code of the gcloud command
EXIT_CODE=$?

echo "--------------------------------------------------"
if [ $EXIT_CODE -eq 0 ]; then
  echo "Cloud Run Job execution completed successfully."
else
  echo "Cloud Run Job execution failed or gcloud command encountered an error (Exit Code: $EXIT_CODE)."
fi
echo "--------------------------------------------------"

exit $EXIT_CODE