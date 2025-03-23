#!/bin/bash

# if you need to reset use this command: kubectl delete -f spinnaker-service-account.yml && kubectl delete namespace spinnaker && ./create-spinnaker-svc-acct.sh

# Set the context explicitly
CONTEXT="docker-desktop"
kubectl config use-context ${CONTEXT}

# First, make sure we have the namespace
kubectl create namespace spinnaker

# Apply the service account and RBAC configuration
kubectl apply -f spinnaker-service-account.yml

# Wait for the secret to be created
echo "Waiting for service account secret to be created..."
sleep 5

# Use the known secret name
SECRET_NAME="spinnaker-service-account-token"
TOKEN=$(kubectl -n spinnaker get secret ${SECRET_NAME} -o jsonpath='{.data.token}' | base64 --decode)
if [ -z "$TOKEN" ]; then
    echo "Error: Could not get token from secret"
    exit 1
fi

# Get the cluster CA certificate
CLUSTER_CA=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="docker-desktop")].cluster.certificate-authority-data}')
CLUSTER_SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="docker-desktop")].cluster.server}')

# Create a new kubeconfig file specifically for Spinnaker
cat > spinnaker-kubeconfig <<EOF
apiVersion: v1
kind: Config
current-context: ${CONTEXT}
contexts:
- context:
    cluster: ${CONTEXT}
    user: ${CONTEXT}-token-user
    namespace: spinnaker
  name: ${CONTEXT}
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
  name: ${CONTEXT}
users:
- name: ${CONTEXT}-token-user
  user:
    token: ${TOKEN}
EOF

echo "Created spinnaker-kubeconfig file successfully"
