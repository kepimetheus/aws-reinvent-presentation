#!/bin/bash

# Shell output colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Functions for messages
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed or configured"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    error "helm is not installed or configured"
    exit 1
fi

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    error "minikube is not installed or configured"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    error "jq is not installed or configured"
    exit 1
fi

# Function to check if service exists
check_service() {
    local service=$1
    if ! kubectl get service "$service" &> /dev/null; then
        error "Service $service not found"
        return 1
    fi
    return 0
}

# Function to perform a port-forward for a service
forward_service() {
    local service=$1
    local local_port=$2
    local service_port=$3

    log "Starting port-forward to $service ($local_port:$service_port)..."
    kubectl port-forward "service/$service" "$local_port:$service_port" &
    sleep 2
}

# Create AWS resources (IAM policy, user and credentials)
create_aws_resources() {
    local service=$1
    
    log "Creating IAM policy"
    aws iam create-policy --policy-name "AllowKepimetheus" --policy-document file://policy.json
    export policy_arn=$(aws iam list-policies \
    --query 'Policies[?PolicyName==`AllowKepimetheus`].Arn' --output text)

    log "Creating IAM user"
    aws iam create-user --user-name $service

    log "Attaching IAM user"
    aws iam attach-user-policy --user-name $service --policy-arn $policy_arn

    log "Generating acess key"
    secret_access_key=$(aws iam create-access-key --user-name "kepimetheus")
    access_key_id=$(echo $secret_access_key | jq -r '.AccessKey.AccessKeyId')
    log $access_key_id
cat <<-EOF > credentials

[default]
aws_access_key_id = $(echo $access_key_id)
aws_secret_access_key = $(echo $secret_access_key | jq -r '.AccessKey.SecretAccessKey')
EOF

}

# Function to delete a service
delete_service() {
    local service=$1
    log "Deleting service $1"
    helm delete $service 2> /dev/null
    kubectl delete secret kepimetheus 2> /dev/null
    kubectl delete configmap kepimetheus-configmap 2> /dev/null
    return 0
}

delete_aws_resources() {
    local service=$1

    access_keys=("$(aws iam list-access-keys --user-name $service | jq -r '.AccessKeyMetadata[] | .AccessKeyId')")
    if [[ "${#access_keys}" -gt "0" ]]; then
        for access_key in ${access_keys[@]}; do
            log "Deleting access key $access_key"
            aws iam delete-access-key --user-name $service --access-key-id $access_key
        done
    fi

    export policy_arn=$(aws iam list-policies \
    --query 'Policies[?PolicyName==`AllowKepimetheus`].Arn' --output text)
    aws iam detach-user-policy --user-name $service --policy-arn $policy_arn 2> /dev/null

    log "Deleting IAM user"
    aws iam delete-user --user-name $service 2> /dev/null

    log "Deleting IAM policy"
    aws iam delete-policy --policy-arn $policy_arn 2> /dev/null
    return 0
}

# Executar minikube
start_minikube() {
    local minikube_status=`minikube status &> /dev/null;echo $?`
    if [[ $minikube_status -eq 0 ]]; then
        log "Minikube is already running"
        return 0
    fi
    log "Starting minikiube..."
    minikube start
    log "Updating kubectl context to minikiube..."
    minikube update-context
}

install_kepimetheus(){
    local service=$1

    log "Adding Kepimetheus repository"
    helm repo add kepimetheus https://kepimetheus.github.io/helm-charts

    log "Installing Kepimetheus on minikube"
    kubectl create secret generic kepimetheus \
    --from-file credentials
    kubectl create configmap kepimetheus-configmap --from-file kepimetheus.yaml
    helm upgrade --install $service kepimetheus/kepimetheus --values values.yaml --wait

}

delete_service "kepimetheus" || exit 1
delete_aws_resources "kepimetheus" || exit 1
log "All resources have been deleted"

create_aws_resources "kepimetheus" || exit 1
start_minikube || exit 1
install_kepimetheus "kepimetheus" || exit 1

# Check services
check_service "kepimetheus" || exit 1
check_service "kepimetheus-grafana" || exit 1

# Start port-forwards
forward_service "kepimetheus" 8000 8000
forward_service "kepimetheus-grafana" 3000 80

log "Port-forwards started:"
log "Kepimetheus: http://localhost:8000"
log "Grafana: http://localhost:3000"
log "Press Ctrl+C to exit all port-forwards"

# Wait for the interrupt signal
wait
