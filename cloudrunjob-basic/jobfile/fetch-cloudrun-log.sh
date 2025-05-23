#!/bin/bash

# ==============================================================================
# Script to download application logs from a Google Cloud Run service.
# Extracts only the application's stdout/stderr, excluding GCP's JSON wrapper.
#
# Requirements:
#   - Google Cloud SDK (`gcloud`) installed and authenticated.
#   - Necessary permissions (e.g., roles/logging.viewer).
# ==============================================================================

# --- Configuration (Extracted from your 'tofu output') ---
PROJECT_ID="scottycloudxferpoc1"
SERVICE_NAME="scotty-poc-service" # Derived from cloudrun_service_url

# --- Script Options (Customize as needed) ---
# How many hours back to fetch logs from? (Default: 1 hour)
HOURS_AGO=1
# Log severity threshold (e.g., DEFAULT, DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL, ALERT, EMERGENCY)
# Leave empty ("") to get all severities.
MIN_SEVERITY=""
# The field in the JSON log entry containing the actual application log line.
# Usually "textPayload" for simple stdout/stderr, or potentially
# "jsonPayload.message" if your app logs structured JSON.
PAYLOAD_FIELD="textPayload"
# Output file name
OUTPUT_FILE="${SERVICE_NAME}_app_logs_last_${HOURS_AGO}h.log"
# --- End Configuration ---

echo "--------------------------------------------------"
echo "Cloud Run Log Fetcher"
echo "--------------------------------------------------"
echo "Project:      $PROJECT_ID"
echo "Service:      $SERVICE_NAME"
echo "Time Range:   Last $HOURS_AGO hour(s)"
echo "Min Severity: ${MIN_SEVERITY:-All}"
echo "Payload Field: $PAYLOAD_FIELD"
echo "Output File:  $OUTPUT_FILE"
echo "--------------------------------------------------"

# Check if gcloud command exists
if ! command -v gcloud &> /dev/null; then
    echo "[Error] gcloud command not found. Please install the Google Cloud SDK and ensure it's in your PATH."
    exit 1
fi

# Calculate start time for the filter (in UTC RFC3339 format)
# Handle differences between GNU date (Linux) and BSD date (macOS)
if date --version > /dev/null 2>&1; then
  # GNU date
  START_TIME=$(date -u -d "$HOURS_AGO hours ago" +"%Y-%m-%dT%H:%M:%SZ")
else
  # BSD date (macOS)
  START_TIME=$(date -u -v-${HOURS_AGO}H +"%Y-%m-%dT%H:%M:%SZ")
fi

echo "Fetching logs from (UTC): $START_TIME onwards..."

# Construct the base filter
FILTER="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$SERVICE_NAME\" AND timestamp >= \"$START_TIME\""

# Add severity filter if specified
if [[ -n "$MIN_SEVERITY" ]]; then
    FILTER+=" AND severity >= $MIN_SEVERITY"
    echo "Applying severity filter: >= $MIN_SEVERITY"
fi

# Execute the gcloud command
echo "Running gcloud command..."
gcloud logging read "$FILTER" \
  --format="value($PAYLOAD_FIELD)" \
  --project="$PROJECT_ID" > "$OUTPUT_FILE"

# Check exit status of gcloud command
GCLOUD_EXIT_CODE=$?
if [ $GCLOUD_EXIT_CODE -eq 0 ]; then
    LOG_LINES=$(wc -l < "$OUTPUT_FILE")
    echo "[Success] Log fetching complete."
    echo "         Saved $LOG_LINES application log lines to: $OUTPUT_FILE"
else
    echo "[Error] Failed to fetch logs (gcloud exited with code $GCLOUD_EXIT_CODE)."
    echo "        Please check the gcloud error messages above, your filter, or IAM permissions."
    # Remove empty file if error occurred and file was created
    [ -f "$OUTPUT_FILE" ] && [ ! -s "$OUTPUT_FILE" ] && rm "$OUTPUT_FILE"
    exit 1
fi

exit 0