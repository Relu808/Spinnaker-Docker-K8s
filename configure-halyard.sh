#!/bin/bash

# Wait for container to be ready
sleep 5

# Set Halyard daemon endpoint
export HALYARD_ENDPOINT=http://localhost:8064

# Create the bucket first
MINIO_ACCESS_KEY=minioadmin MINIO_SECRET_KEY=minioadmin mc config host add minio http://minio:9000 minioadmin minioadmin
mc mb minio/spinnaker

# Configure Minio as storage
hal config storage s3 edit \
    --endpoint http://minio:9000 \
    --access-key-id minioadmin \
    --secret-access-key minioadmin \
    --bucket spinnaker \
    --path-style-access true

# Enable Minio storage
hal config storage edit --type s3

# Configure Kubernetes provider
hal config provider kubernetes enable

# Add Kubernetes account
hal config provider kubernetes account add spinnaker-account \
    --context docker-desktop \
    --kubeconfig-file /home/spinnaker/.hal/kubeconfig

# Configure deployment environment
hal config deploy edit \
    --type distributed \
    --account-name spinnaker-account \
    --location spinnaker

# Configure version
hal config version edit --version 1.30.2

# Configure timezone
hal config edit --timezone America/Honolulu

# Deploy Spinnaker
hal deploy apply 