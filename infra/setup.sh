#!/bin/bash
set -e

# Create random string
generate_suffix() {
  local raw_suffix=""

  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    raw_suffix=$(cat /proc/sys/kernel/random/uuid)
  elif command -v uuidgen >/dev/null 2>&1; then
    raw_suffix=$(uuidgen)
  elif command -v openssl >/dev/null 2>&1; then
    raw_suffix=$(openssl rand -hex 12)
  else
    raw_suffix="$(date +%s)$RANDOM"
  fi

  raw_suffix=$(printf "%s" "$raw_suffix" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')

  if [[ ${#raw_suffix} -lt 3 ]]; then
    raw_suffix="$(date +%s)$RANDOM"
  fi

  printf "%.18s" "$raw_suffix"
}

suffix=$(generate_suffix)
echo "Suffix: $suffix"

# Set the necessary variables
RESOURCE_GROUP="rg-ai300-l${suffix}"
RESOURCE_PROVIDER="Microsoft.MachineLearningServices"
REGIONS=("eastus" "westus" "centralus" "northeurope" "westeurope")
RANDOM_REGION=${AZURE_REGION:-westeurope}
WORKSPACE_NAME="mlw-ai300-l${suffix}"
COMPUTE_INSTANCE="ci${suffix}"
COMPUTE_CLUSTER="aml-cluster"
COMPUTE_SIZE=${AZURE_ML_COMPUTE_SIZE:-STANDARD_D2S_V3}
CREATE_AZURE_ML_COMPUTE=${CREATE_AZURE_ML_COMPUTE:-false}
OWNER_TAG="nuno.oliveira.fernandes@devoteam.com"
ENV_TAG="dev"
PROJECT_TAG="mslearn-mlops"
COMMON_TAGS=("Owner=$OWNER_TAG" "Env=$ENV_TAG" "Project=$PROJECT_TAG")
ML_TAG_SET=("tags.Owner=$OWNER_TAG" "tags.Env=$ENV_TAG" "tags.Project=$PROJECT_TAG")

# Register the Azure Machine Learning resource provider in the subscription
echo "Register the Machine Learning resource provider:"
az provider register --namespace $RESOURCE_PROVIDER

# Create the resource group and workspace and set to default
echo "Create a resource group and set as default:"
az group create --name $RESOURCE_GROUP --location $RANDOM_REGION --tags "${COMMON_TAGS[@]}"
az configure --defaults group=$RESOURCE_GROUP

echo "Create an Azure Machine Learning workspace:"
az ml workspace create --name $WORKSPACE_NAME --tags "${COMMON_TAGS[@]}"
az configure --defaults workspace=$WORKSPACE_NAME 

echo "Using Azure region: $RANDOM_REGION"
echo "Using Azure ML compute size: $COMPUTE_SIZE"

if [[ "$CREATE_AZURE_ML_COMPUTE" == "true" ]]; then
  # Create compute instance
  echo "Creating a compute instance with name: " $COMPUTE_INSTANCE
  az ml compute create --name ${COMPUTE_INSTANCE} --size $COMPUTE_SIZE --type ComputeInstance --tags "${COMMON_TAGS[@]}"

  # Create compute cluster
  echo "Creating a compute cluster with name: " $COMPUTE_CLUSTER
  az ml compute create --name ${COMPUTE_CLUSTER} --size $COMPUTE_SIZE --min-instances 0 --max-instances 1 --type AmlCompute --tags "${COMMON_TAGS[@]}"
else
  echo "Skipping dedicated Azure ML compute creation. Jobs will use serverless compute when no compute is specified."
fi

# Create data assets
echo "Create training data asset:"
az ml data create --type mltable --name "diabetes-training" --path ../data/diabetes-data --set "${ML_TAG_SET[@]}"
az ml data create --type uri_file --name "diabetes-data" --path ../data/diabetes-data/diabetes.csv --set "${ML_TAG_SET[@]}"
az ml data create --type uri_folder --name "diabetes-dev-folder" --path ../experimentation/data --set "${ML_TAG_SET[@]}"
az ml data create --type uri_folder --name "diabetes-prod-folder" --path ../production/data --set "${ML_TAG_SET[@]}"
