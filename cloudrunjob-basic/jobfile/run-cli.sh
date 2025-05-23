#!/bin/bash

# === Configuration ===
# !! SECURITY WARNING !!
# Hardcoding secrets like HCP_CLIENT_SECRET directly in scripts is insecure.
# Consider using a secrets manager (like HashiCorp Vault itself, GCP Secret Manager)
# or environment variable injection methods provided by your CI/CD system or orchestrator.
export HCP_CLIENT_ID="1IH0JbXVNaG7IhkkGkiMestvAhgNR5b0"
export HCP_CLIENT_SECRET="9_WjgHuYorx01WgsjlG9m2snOwkzpm2s8XODk3KN9U9kstNQL7sIcou4U3SmRNHG" # <-- INSECURE - AVOID HARDCODING
export HCP_ORG_ID="dcbeb41a-7899-46d6-81e4-e8bb45573d3f"
export HCP_PROJ_ID="6cb3eace-c7b8-4b9c-a636-8c4aef6d6376"
export VLT_APPS_NAME="safe-web-app"

# --- Paths ---
# Assumes this script is run from the 'jobfile' directory as shown in your previous command.
# Adjust these paths if you run the script from a different location.
JAR_FILE="../target/cloud-transfer-job-0.0.1-SNAPSHOT.jar"
CONFIG_FILE=$1 # Using the path from your example command

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file not found at $CONFIG_FILE"
  exit 1
fi
if [ ! -f "$JAR_FILE" ]; then
  echo "Error: JAR file not found at $JAR_FILE"
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
# --- <<< END ADDED >>> ---

echo "Setting HCP environment variables..."
echo "Running Cloud Transfer Job..."
echo "JAR: $JAR_FILE"
echo "Config Content (first 100 chars): $(echo "$JSON_CONTENT" | head -c 100)..."
echo "---"

# Pass the JSON content as a single argument string
java -jar "$JAR_FILE" "$ENCODED_JSON_CONTENT"


# Capture the exit code of the Java application
EXIT_CODE=$?

echo "---"
if [ $EXIT_CODE -eq 0 ]; then
  echo "Job completed successfully."
else
  echo "Job failed with exit code $EXIT_CODE."
fi

exit $EXIT_CODE