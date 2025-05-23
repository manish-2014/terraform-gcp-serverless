#!/bin/bash

# Source the environment file
source /home/manish/projects/devops/environment-center/project-information/gcp-madladlab/madladlab.env

# Set variables
IMAGE_NAME="basicpocjob"
# Generate a date‑time tag: YY-MM-DD-H-M-S
IMAGE_TAG=$(date +'%y-%m-%d-%H-%M-%S')
REGION="us-central1"  # Replace with your desired region
REPOSITORY="basicpocjob"

mvn clean package -Dmaven.test.skip=true

# Build the Docker image
echo "Building Docker image..."
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

# Configure Docker to use Google Cloud as a registry
echo "Configuring Docker for Google Cloud..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Tag the image for Google Cloud
echo "Tagging image for Google Cloud..."
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}

# Push the image to Google Cloud
echo "Pushing image to Google Cloud..."
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}

echo "Done! Image pushed to: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${IMAGE_TAG}"