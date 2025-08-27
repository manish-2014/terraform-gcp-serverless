#!/bin/bash

# Source the environment file
source /home/manish/projects/devops/environment-center/project-information/gcp-madladlab/madladlab.env

# Set variables
JOB_NAME="basicpocjob"
REGION="us-central1"
REPOSITORY="basicpocjob"
IMAGE_NAME="basicpocjob"
IMAGE_TAG="latest"

# Function to get the latest execution ID
get_latest_execution_id() {
    gcloud run jobs executions list --job=${JOB_NAME} --region=${REGION} --limit=1 --format="get(name)" | cut -d'/' -f6
}

# Function to check job status
check_job_status() {
    local execution_id=$1
    local status=$(gcloud run jobs executions describe ${execution_id} --region=${REGION} --format="get(status)")
    echo "Job Status: ${status}"
    return 0
}

# Function to get job logs
get_job_logs() {
    local execution_id=$1
    echo "Fetching logs for execution ${execution_id}..."
    gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=${JOB_NAME} AND labels.run.googleapis.com/execution_name=${execution_id}" --format="table(timestamp,severity,textPayload)" --limit=50
}

# Full image path
IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"
echo "Image URI: ${IMAGE_PATH}"

# Create or update the Cloud Run job
echo "Creating/Updating Cloud Run job..."
gcloud run jobs create ${JOB_NAME} \
  --image=${IMAGE_PATH} \
  --region=${REGION} \
  --tasks=1 \
  --memory=512Mi \
  --cpu=1 \
  --max-retries=0 \
  --task-timeout=3600s \
  --set-env-vars="SPRING_PROFILES_ACTIVE=prod" \
  || gcloud run jobs update ${JOB_NAME} \
     --image=${IMAGE_PATH} \
     --region=${REGION}

# Execute the job with a Base64 encoded test string
echo "Executing Cloud Run job..."
gcloud run jobs execute ${JOB_NAME} \
  --region=${REGION} \
  --args="SGVsbG8gV29ybGQ=" \
  --wait

# Get the latest execution ID
EXECUTION_ID=$(get_latest_execution_id)
echo "Latest execution ID: ${EXECUTION_ID}"

# Check job status
echo "Checking job status..."
check_job_status ${EXECUTION_ID}

# Get job logs
echo "Retrieving job logs..."
get_job_logs ${EXECUTION_ID} 