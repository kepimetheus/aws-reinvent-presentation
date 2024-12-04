# AWS REINVENT DEMO

This tutorial describes how to set up Kepimetheus for usage within a Kubernetes cluster on AWS using Bedrock. 

## Requirements

1. AWS Account with Bedrock enabled and configured on your AWS CLI.
2. [kubectl](https://kubernetes.io/docs/tasks/tools/)
3. [helm](https://helm.sh/docs/intro/install/)
4. [jq](https://jqlang.github.io/jq/)

## IAM Policy

The following IAM Policy document allows Kepimetheus to use AWS Bedrock necessary resources. In 
our example, we'll call this policy `AllowKepimetheus` (but you can call
it whatever you prefer).

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ProvisionedThroughputModelInvocation",
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
            ],
            "Resource": "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-v2"
        }
    ]
}
```

If you are using the AWS CLI, you can run the following to install the above policy (saved as policy.json).

```bash
aws iam create-policy --policy-name "AllowKepimetheus" --policy-document file://policy.json

# example: arn:aws:iam::XXXXXXXXXXXX:policy/AllowKepimetheus
export POLICY_ARN=$(aws iam list-policies \
 --query 'Policies[?PolicyName==`AllowKepimetheus`].Arn' --output text)
```

## Provisioning a Kubernetes cluster

For this tutorial pourposes you can use [minikube](https://minikube.sigs.k8s.io/docs/) to provision a local Kubernetes cluster, or [eksctl](https://eksctl.io) to easily provision an [Amazon Elastic Kubernetes Service](https://aws.amazon.com/eks) ([EKS](https://aws.amazon.com/eks)) cluster that is suitable for this tutorial.  
- See this guide to install [minikube](https://minikube.sigs.k8s.io/docs/start/?arch=/macos/arm64/stable/binary+download).
- See this guide to install [eksctl](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html).

### Option 1: `minikube`
Provison a simple eks cluster using minikube:
```bash
minikube start
minikube update-context
```

### Option 2: `AWS EKS`
Provision a simple eks cluster using eksctl:
```bash
export EKS_CLUSTER_NAME="kepimetheus-cluster"
export EKS_CLUSTER_REGION="us-east-2"
export KUBECONFIG="$HOME/.kube/${EKS_CLUSTER_NAME}-${EKS_CLUSTER_REGION}.yaml"

eksctl create cluster --name $EKS_CLUSTER_NAME --region $EKS_CLUSTER_REGION
```

:warning: **WARNING**: this method is only suitable for limited test environments, kepimetheus team is building a role based tutorial.

### IAM User

Using the previously created policy is this tutorial, it's attached to an IAM user, and generated credentials secrets for this IAM user are then made available using a Kubernetes secret.

This method is recommended for production environments as the secrets in the credential file could be copied and used by an unauthorized threat actor. Given this situation, it's important to limit the associated privileges to just minimal required privileges and do not use an IAM User that has extra privileges beyond what is required.

#### Create IAM user and attach the policy

If you are using the AWS CLI, you can run the following to create the user and attach the policy created.
```bash
# create IAM user
aws iam create-user --user-name "kepimetheus"

# attach policy arn created earlier to IAM user
aws iam attach-user-policy --user-name "kepimetheus" --policy-arn $POLICY_ARN
```

#### Create the static credentials

```bash
SECRET_ACCESS_KEY=$(aws iam create-access-key --user-name "kepimetheus")
ACCESS_KEY_ID=$(echo $SECRET_ACCESS_KEY | jq -r '.AccessKey.AccessKeyId')

cat <<-EOF > credentials

[default]
aws_access_key_id = $(echo $ACCESS_KEY_ID)
aws_secret_access_key = $(echo $SECRET_ACCESS_KEY | jq -r '.AccessKey.SecretAccessKey')
EOF
```

#### Create Kubernetes secret from credentials

This step is optional, and you can create this secret passing your AWS credentials during kepimetheus installation.

```bash
kubectl create secret generic kepimetheus \
  --namespace ${kepimetheus_NS:-"default"} --from-file ./credentials
```
#### Create Kepimetheus plugin configmap 

This step is optional, and you can create this secret passing your AWS credentials during kepimetheus installation.

```bash
kubectl create secret generic kepimetheus \
  --namespace ${kepimetheus_NS:-"default"} --from-file ./credentials
```

#### Install Kepimetheus Using Helm

Create a values.yaml file to configure Kepimetheus:

```shell
volumes:
  - name: creds
    secret:  
      secretName: kepimetheus

volumeMounts:
  - name: creds
    mountPath: "/root/.aws/credentials"
    subPath: credentials

provider:
  name: awsBedrock
  secret:
    create: false
    name: kepimetheus

kube-prometheus-stack:
  enabled: true
  grafana:
    plugins:
      - https://kepimetheus.s3.us-east-1.amazonaws.com/kepimetheus-1.0.0.zip;kepimetheus
    extraConfigmapMounts:
       - name: kepimetheus-configmap
         mountPath: /etc/grafana/provisioning/plugins/kepimetheus.yaml
         subPath: kepimetheus.yaml
         configMap: kepimetheus-configmap
         readOnly: true
         optional: false

```

If you haven't created a secret in a previous step, use these values.yaml:

```shell
provider:
  name: awsBedrock
  secret:
    create: true
    name: kepimetheus
    stringData:
      AWS_ACCESS_KEY_ID: XXXXXXXXXXX
      AWS_SECRET_ACCESS_KEY: XXXXXXXXXXX
kube-prometheus-stack:
  enabled: true
  grafana:
    plugins:
      - https://kepimetheus.s3.us-east-1.amazonaws.com/kepimetheus-1.0.0.zip;kepimetheus
    extraConfigmapMounts:
       - name: kepimetheus-configmap
         mountPath: /etc/grafana/provisioning/plugins/kepimetheus.yaml
         subPath: kepimetheus.yaml
         configMap: kepimetheus-configmap
         readOnly: true
         optional: false

```

Add Kepimetheus helm repository:

```shell
helm repo add kepimetheus https://kepimetheus.github.io/helm-charts
```

Finally, install the Kepimetheus chart with Helm using the configuration specified in your values.yaml file:

```shell
helm upgrade --install kepimetheus kepimetheus/kepimetheus --values values.yaml
```

Access Kepimetheus instance on http://localhost:8000

```shell
kubectl port-forward service/kepimetheus 8000:8000
```

Access Grafana instance with Kepimetheus plugin installed on http://localhost:3000

```shell
kubectl port-forward service/kepimetheus-grafana 3000:80
```
