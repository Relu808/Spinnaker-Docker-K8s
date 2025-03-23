# Spinnaker Docker Kubernetes Setup

This repository contains configurations and scripts for setting up Spinnaker in a Docker Kubernetes environment.

## Prerequisites

- Docker Desktop with Kubernetes enabled
- kubectl CLI
- helm (optional, for package management)

## Setup Steps

### 1. Create Namespace

```bash
kubectl create namespace spinnaker
```

### 2. Deploy Minio for Storage

```bash
kubectl apply -f minio.yml -n spinnaker
```

### 3. Create Service Account and RBAC for Spinnaker

```bash
kubectl apply -f spinnaker-service-account.yml -n spinnaker
```

### 4. Generate Kubeconfig

```bash
# Get the service account token
TOKEN=$(kubectl -n spinnaker get secret $(kubectl -n spinnaker get serviceaccount spinnaker-service-account -o jsonpath='{.secrets[0].name}') -o jsonpath='{.data.token}' | base64 --decode)

# Get the cluster CA certificate
CLUSTER_CA=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}')

# Get the API server URL
API_SERVER=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')

# Create kubeconfig file
cat > spinnaker-kubeconfig << EOF
apiVersion: v1
kind: Config
current-context: docker-desktop
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${API_SERVER}
  name: docker-desktop
contexts:
- context:
    cluster: docker-desktop
    user: spinnaker-service-account
  name: docker-desktop
users:
- name: spinnaker-service-account
  user:
    token: ${TOKEN}
EOF
```

### 5. Create Minio Bucket

```bash
# Port forward Minio service
kubectl port-forward -n spinnaker svc/minio 9000:9000

# In another terminal, use mc (Minio Client) to create bucket
mc alias set minio http://localhost:9000 minioadmin minioadmin
mc mb minio/spinnaker
```

### 6. Deploy Halyard

```bash
kubectl apply -f halyard.yml -n spinnaker
```

### 7. Configure Halyard

Connect to the Halyard container:
```bash
kubectl exec -it -n spinnaker $(kubectl get pods -n spinnaker -l app=halyard -o jsonpath='{.items[0].metadata.name}') -- bash
```

Inside the container, configure the following:

1. Configure Minio as storage:
```bash
hal config storage s3 edit \
    --endpoint http://minio.spinnaker:9000 \
    --access-key-id minioadmin \
    --secret-access-key minioadmin \
    --bucket spinnaker \
    --path-style-access true

hal config storage edit --type s3
```

2. Configure Kubernetes provider:
```bash
hal config provider kubernetes enable
hal config provider kubernetes account add spinnaker-account \
    --context docker-desktop \
    --kubeconfig-file /home/spinnaker/.hal/kubeconfig
```

3. Configure deployment environment:
```bash
hal config deploy edit \
    --type distributed \
    --account-name spinnaker-account \
    --location spinnaker
```

4. Configure version:
```bash
hal config version edit --version 1.30.2
```

5. Configure timezone:
```bash
hal config edit --timezone America/Honolulu
```

6. Deploy Spinnaker:
```bash
hal deploy apply
```

### 8. Configure Front50 Service

After deployment, configure Front50 to properly connect with Minio:

```bash
# Apply Front50 configuration with Minio settings
kubectl apply -f front50-config.yml

# Restart Front50 to apply changes
kubectl rollout restart deployment spin-front50 -n spinnaker
```

### 9. Configure External Access

Apply the LoadBalancer service configuration:
```bash
kubectl apply -f spinnaker-services.yml
```

Verify the services are created and have external IPs assigned:
```bash
kubectl get svc -n spinnaker spin-deck-external spin-gate-external
```

You should see output similar to:
```
NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
spin-deck-external   LoadBalancer   10.110.106.23   localhost     9999:30999/TCP   1m
spin-gate-external   LoadBalancer   10.98.156.247   localhost     8084:30804/TCP   1m
```

## Accessing Spinnaker

### Using LoadBalancer Services (Recommended)
After applying the `spinnaker-services.yml` configuration, you can access Spinnaker directly through the exposed LoadBalancer services:

- Spinnaker UI (Deck): http://localhost:9999
- Spinnaker API (Gate): http://localhost:8084

The LoadBalancer services are configured specifically for Docker Desktop and will remain accessible as long as your Kubernetes cluster is running. No need to keep any port-forward commands running.

### Service Configuration
The services are configured in `spinnaker-services.yml` with Docker Desktop specific settings to ensure proper integration with the LoadBalancer implementation.

## Troubleshooting

### Check Service Status
```bash
kubectl get pods -n spinnaker
```

### View Service Logs
```bash
# View Front50 logs
kubectl logs -n spinnaker -l app=spin-front50

# View Clouddriver logs
kubectl logs -n spinnaker -l app=spin-clouddriver

# View other service logs by replacing the app label
```

### Common Issues

1. **Front50 CrashLoopBackOff**
   - Check Minio connectivity
   - Verify AWS credentials are properly set
   - Ensure Minio bucket exists
   - Check Front50 logs for specific errors

2. **Service Account Issues**
   - Verify service account token is correct
   - Check RBAC permissions
   - Ensure kubeconfig is properly mounted

3. **Storage Issues**
   - Verify Minio is running
   - Check bucket permissions
   - Ensure endpoints are correctly configured

### Restart Services
```bash
# Restart specific service (replace spin-front50 with service name)
kubectl rollout restart deployment spin-front50 -n spinnaker

# Restart all Spinnaker services
kubectl rollout restart deployment -n spinnaker
```

## Maintenance

### Updating Spinnaker Version
```bash
hal config version edit --version <new-version>
hal deploy apply
```

### Backup Configuration
```bash
# Backup Halyard config
kubectl cp spinnaker/$(kubectl get pods -n spinnaker -l app=halyard -o jsonpath='{.items[0].metadata.name}'):/home/spinnaker/.hal ./halyard-backup

# Backup Minio data
mc cp --recursive minio/spinnaker/ ./spinnaker-backup/
```

## Security Considerations

### Sensitive Files
The following files should not be committed to version control:
- `spinnaker-kubeconfig` - Contains service account tokens and API server details
- Any files containing Minio credentials
- Any other files containing secrets or tokens

Add these files to your `.gitignore`:
```gitignore
# Sensitive configuration files
spinnaker-kubeconfig
*.pem
*.key
*.crt
```

### Handling Secrets
When sharing this setup with others:
1. Document the required sensitive information
2. Provide instructions for generating their own service account tokens
3. Use Kubernetes secrets for storing sensitive data
4. Consider using a secrets management solution for production environments

## Known Issues and Solutions

### Service Account Permissions
- **Issue**: Spinnaker service account lacked permissions to access Kubernetes API server
- **Solution**: 
  1. Initially tried using default service account which lacked necessary permissions
  2. Created new service account with proper RBAC permissions:
     - Added ClusterRole with required permissions for Spinnaker operations
     - Created ClusterRoleBinding to associate the role with the service account
  3. Generated new service account token and updated kubeconfig
  4. Verified permissions by testing API access
  5. Ensured kubeconfig was properly mounted in Halyard pod
  6. Added proper environment variables in Halyard deployment for kubeconfig path

### Front50 Storage Configuration
- **Issue**: Front50 pods in CrashLoopBackOff state due to S3/Minio access issues
- **Solution**: 
  1. Initially tried using kubectl patch commands to add environment variables
  2. Later automated configuration using front50-config.yml manifest
  3. Properly configured Minio endpoint and credentials

### Port Forwarding and Service Exposure
- **Issue**: Port 9000 conflict with Portainer
- **Solution**: 
  1. Initially tried NodePort with port 30900
  2. Switched to LoadBalancer service with port 9999
  3. Added Docker Desktop specific annotations for proper LoadBalancer integration

### Minio Connection
- **Issue**: Initial Minio connection failures
- **Solution**: 
  1. Adjusted Minio client configuration
  2. Created bucket with proper permissions
  3. Updated service endpoints to use correct DNS names

### Spinnaker Deployment
- **Issue**: Multiple deployment failures and configuration challenges
- **Solution**: 
  1. Initial deployment issues:
     - Had to properly configure Halyard with correct Minio endpoint and credentials
     - Needed to ensure kubeconfig was correctly mounted in Halyard pod
     - Required proper RBAC permissions for service account
  2. Version compatibility:
     - Initially tried newer versions that had compatibility issues
     - Settled on version 1.30.2 which proved stable
  3. Storage configuration:
     - Had to properly configure S3/Minio storage before enabling other features
     - Required correct endpoint format and path-style access settings
  4. Kubernetes provider setup:
     - Needed to properly configure the Kubernetes account with correct context
     - Required proper kubeconfig file location and permissions
  5. Deployment environment:
     - Had to specify correct deployment type (distributed)
     - Required proper account name and location settings
