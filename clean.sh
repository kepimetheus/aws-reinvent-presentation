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

    access_keys=("$(aws iam list-access-keys --user-name $service | jq -r '.AccessKeyMetadata[] | .AccessKeyId')")
    if [[ "${#access_keys}" -gt "0" ]]; then
        for access_key in ${access_keys[@]}; do
            log -e "Deleting access key $access_key"
            aws iam delete-access-key --user-name $service --access-key-id $access_key
        done
    fi

    export policy_arn=$(aws iam list-policies \
    --query 'Policies[?PolicyName==`AllowKepimetheus`].Arn' --output text)
    aws iam detach-user-policy --user-name $service --policy-arn $policy_arn
    
    log "Delete IAM user"
    aws iam delete-user --user-name $service

    log "Delete IAM policy"    
    aws iam delete-policy --policy-arn $policy_arn

}


delete_service "kepimetheus" || exit 1

delete_aws_resources "kepimetheus" || exit 1

log "All resources have been deleted"