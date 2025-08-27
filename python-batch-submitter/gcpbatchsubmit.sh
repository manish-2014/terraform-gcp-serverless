# Define variables
export JOB_NAME="direct-submit-job-$(date +%s)"
export REGION="us-central1"
export PROJECT_ID="your-gcp-project-id" # Make sure this is set
export IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/basicpocjob/basicpocjob:latest"
export SERVICE_ACCOUNT_EMAIL="madladlab-xfer-app-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# The direct gcloud command to submit the job
gcloud batch jobs submit "${JOB_NAME}" \
    --location="${REGION}" \
    --project="${PROJECT_ID}" \
    --config=- <<EOF
{
  "taskGroups": [
    {
      "taskSpec": {
        "runnables": [
          {
            "container": {
              "imageUri": "${IMAGE_PATH}",
              "commands": [
                "SGVsbG8gV29ybGQ="
              ]
            }
          }
        ],
        "computeResource": {
          "cpuMilli": 1000,
          "memoryMib": 512
        },
        "environment": {
          "variables": {
            "SPRING_PROFILES_ACTIVE": "prod"
          }
        }
      },
      "taskCount": 1
    }
  ],
  "allocationPolicy": {
    "instances": [
      {
        "policy": {
          "machineType": "e2-medium"
        }
      }
    ],
    "serviceAccount": {
      "email": "${SERVICE_ACCOUNT_EMAIL}"
    }
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOF