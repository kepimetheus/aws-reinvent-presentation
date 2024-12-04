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


# Função para fazer port-forward de um serviço
delete_service() {
    local service=$1
    
    helm delete $service
    minikube delete
}

# Criar policy, user e credenciais
delete_aws_resources() {
    local service=$1
    
    log "Delete IAM user"
    aws iam delete-user --user-name $service

    log "Delete IAM policy"
    export policy_arn=$(aws iam list-policies \
    --query 'Policies[?PolicyName==`AllowKepimetheus`].Arn' --output text)
    aws iam delete-policy --policy-arn $policy_arn

}


delete_service "kepimetheus" || exit 1

delete_aws_resources "kepimetheus" || exit 1

log "All resources have been deleted"