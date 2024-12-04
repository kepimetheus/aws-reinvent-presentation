#!/bin/bash

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Função para mensagens
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verifica se kubectl está instalado
if ! command -v kubectl &> /dev/null; then
    error "kubectl não está instalado"
    exit 1
fi

# Verifica se helm está instalado
if ! command -v helm &> /dev/null; then
    error "helm não está instalado"
    exit 1
fi

# Verifica se minikube está instalado
if ! command -v minikube &> /dev/null; then
    error "minikube não está instalado"
    exit 1
fi

# Função para verificar se o serviço existe
check_service() {
    local service=$1
    if ! kubectl get service "$service" &> /dev/null; then
        error "Service $service not found"
        return 1
    fi
    return 0
}

# Função para fazer port-forward de um serviço
forward_service() {
    local service=$1
    local local_port=$2
    local service_port=$3

    log "Starting port-forward to $service ($local_port:$service_port)..."
    kubectl port-forward "service/$service" "$local_port:$service_port" &
    sleep 2
}

# Criar policy, user e credenciais
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

cat <<-EOF > credentials

[default]
aws_access_key_id = $(echo $access_key_id)
aws_secret_access_key = $(echo $secret_access_key | jq -r '.AccessKey.SecretAccessKey')
EOF

}

# Executar minikube
start_minikube() {

    log "Starting minikiube..."
    minikube start
    log "Updating kubectl context to minikiube..."
    minikube update-context

}

install_kepimetheus(){
    local service=$1
    
    log "Adding Kepimetheus repository"
    helm repo add kepimetheus https://kepimetheus.github.io/helm-charts

    log "Installing kepimetheus on minikube"
    kubectl create secret generic kepimetheus \
    --from-file credentials
    helm upgrade --install $service kepimetheus/kepimetheus --values values.yaml --wait

}

create_aws_resources "kepimetheus" || exit 1

start_minikube || exit 1

install_kepimetheus "kepimetheus" || exit 1

# Verifica os serviços
check_service "kepimetheus" || exit 1
check_service "kepimetheus-grafana" || exit 1

# Inicia os port-forwards
forward_service "kepimetheus" 8000 8000
forward_service "kepimetheus-grafana" 3000 80

log "Port-forwards iniciados:"
log "Kepimetheus: localhost:8000"
log "Grafana: localhost:3000"
log "Press Ctrl+C to exit all port-forwards"

# Aguarda o sinal de interrupção
wait
