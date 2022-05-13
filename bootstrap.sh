#!/bin/sh

slp(){
    sleep 3
}

echo "Installing Folio wallet dependencies............" && slp
sudo apt update
sudo apt install zip unzip -y
echo "Installing awscli............" && slp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -o awscliv2.zip
sudo ./aws/install -i /usr/local/aws-cli -b /usr/local/bin
echo "Installing eksctl............" && slp
curl --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
echo "Installing kubectl............" && slp
curl -o kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.22.6/2022-03-09/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
echo "Installing helm............" && slp
curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
echo "You might need to enter your AWS credentials for this process............" && slp
aws configure
echo -e "\nAWESOME! Now, let's setup our AWS infrastructure............" && slp
export AWS_REGION_1=us-west-2
export AWS_REGION_2=eu-west-2
export EKS_CLUSTER_1=Folio-BD-EKS
export EKS_CLUSTER_2=Folio-BD-EKS-2
echo "This script will create 2 clusters, 1 each in ($AWS_REGION_1 , $AWS_REGION_2)............" && slp
export ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
eksctl create cluster -f cluster-1.yaml
eksctl create cluster -f cluster-2.yaml

eksctl utils associate-iam-oidc-provider \
  --region $AWS_REGION_1 \
  --cluster $EKS_CLUSTER_1 \
  --approve

eksctl utils associate-iam-oidc-provider \
  --region $AWS_REGION_2 \
  --cluster $EKS_CLUSTER_2 \
  --approve

curl https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json > awslb-policy.json
aws iam create-policy \
    --policy-name FolioAWSLoadBalancerControllerIAMPolicy \
    --policy-document file://awslb-policy.json

eksctl create iamserviceaccount \
  --cluster $EKS_CLUSTER_1 \
  --namespace kube-system \
  --region $AWS_REGION_1 \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FolioAWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

eksctl create iamserviceaccount \
  --cluster $EKS_CLUSTER_2 \
  --namespace kube-system \
  --region $AWS_REGION_2 \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/FolioAWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

aws eks update-kubeconfig \
  --name $EKS_CLUSTER_1 \
  --region $AWS_REGION_1  

helm repo add eks https://aws.github.io/eks-charts
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
helm upgrade -i aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_1 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

aws eks update-kubeconfig \
  --name $EKS_CLUSTER_2 \
  --region $AWS_REGION_2 
  
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
helm upgrade -i aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_2 \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

curl http://13.40.16.17/ekssetup | sh