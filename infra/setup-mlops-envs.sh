#!/bin/bash
set -e
# setup-mlops-envs.sh
# Complete provisioning script for the "Plan and prepare an MLOps solution" lab.
# Creates a dev workspace, a prod workspace, and a shared Azure ML registry,
# each in their own resource group with isolated data assets.

# ---------------------------------------------------------------------------
# Shared variables
# ---------------------------------------------------------------------------
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

RESOURCE_PROVIDER="Microsoft.MachineLearningServices"
REGIONS=("italynorth" "swedencentral" "polandcentral" "germanywestcentral" "spaincentral")
DEFAULT_REGION="spaincentral"
RANDOM_REGION=${AZURE_REGION:-$DEFAULT_REGION}
if [[ ! " ${REGIONS[*]} " =~ " ${RANDOM_REGION} " ]]; then
    echo "Region '$RANDOM_REGION' is not allowed. Allowed regions: ${REGIONS[*]}" >&2
    exit 1
fi

# Dev environment
DEV_RESOURCE_GROUP="rg-ai300-dev-${suffix}"
DEV_WORKSPACE_NAME="mlw-ai300-dev-${suffix}"

# Prod environment
PROD_RESOURCE_GROUP="rg-ai300-prod-${suffix}"
PROD_WORKSPACE_NAME="mlw-ai300-prod-${suffix}"

# Shared registry
REGISTRY_RESOURCE_GROUP="rg-ai300-reg-${suffix}"
REGISTRY_NAME="mlr-ai300-shared-${suffix}"

# Compute
COMPUTE_INSTANCE="ci${suffix}"
COMPUTE_CLUSTER="aml-cluster"
COMPUTE_SIZE=${AZURE_ML_COMPUTE_SIZE:-STANDARD_D2S_V3}
CREATE_AZURE_ML_COMPUTE=${CREATE_AZURE_ML_COMPUTE:-false}
OWNER_TAG="nuno.oliveira.fernandes@devoteam.com"
ENV_TAG="dev"
PROJECT_TAG="mslearn-mlops"
COMMON_TAGS=("Owner=$OWNER_TAG" "Env=$ENV_TAG" "Project=$PROJECT_TAG")
ML_TAG_SET=("tags.Owner=$OWNER_TAG" "tags.Env=$ENV_TAG" "tags.Project=$PROJECT_TAG")

# ---------------------------------------------------------------------------
# Register the Azure Machine Learning resource provider
# ---------------------------------------------------------------------------
echo "Registering the Machine Learning resource provider..."
az provider register --namespace $RESOURCE_PROVIDER

# ---------------------------------------------------------------------------
# Dev environment
# ---------------------------------------------------------------------------
echo "Creating dev resource group: $DEV_RESOURCE_GROUP"
az group create --name $DEV_RESOURCE_GROUP --location $RANDOM_REGION --tags "${COMMON_TAGS[@]}"

echo "Creating dev workspace: $DEV_WORKSPACE_NAME"
az ml workspace create --name $DEV_WORKSPACE_NAME --resource-group $DEV_RESOURCE_GROUP --tags "${COMMON_TAGS[@]}"

az configure --defaults group=$DEV_RESOURCE_GROUP workspace=$DEV_WORKSPACE_NAME

echo "Using Azure region: $RANDOM_REGION"
echo "Using Azure ML compute size: $COMPUTE_SIZE"

if [[ "$CREATE_AZURE_ML_COMPUTE" == "true" ]]; then
    echo "Creating compute instance for dev workspace..."
    az ml compute create --name $COMPUTE_INSTANCE --size $COMPUTE_SIZE --type ComputeInstance --tags "${COMMON_TAGS[@]}"

    echo "Creating compute cluster for dev workspace..."
    az ml compute create --name $COMPUTE_CLUSTER --size $COMPUTE_SIZE --min-instances 0 --max-instances 1 --type AmlCompute --tags "${COMMON_TAGS[@]}"
else
    echo "Skipping dedicated Azure ML compute creation. Jobs will use serverless compute when no compute is specified."
fi

echo "Creating dev data assets..."
az ml data create --type mltable --name "diabetes-training" --path ../data/diabetes-data --set "${ML_TAG_SET[@]}"
az ml data create --type uri_file --name "diabetes-data" --path ../data/diabetes-data/diabetes.csv --set "${ML_TAG_SET[@]}"
az ml data create --type uri_folder --name "diabetes-dev-folder" --path ../data/diabetes-data --set "${ML_TAG_SET[@]}"

# ---------------------------------------------------------------------------
# Prod environment
# ---------------------------------------------------------------------------
echo "Creating prod resource group: $PROD_RESOURCE_GROUP"
az group create --name $PROD_RESOURCE_GROUP --location $RANDOM_REGION --tags "${COMMON_TAGS[@]}"

echo "Creating prod workspace: $PROD_WORKSPACE_NAME"
az ml workspace create --name $PROD_WORKSPACE_NAME --resource-group $PROD_RESOURCE_GROUP --tags "${COMMON_TAGS[@]}"

az configure --defaults group=$PROD_RESOURCE_GROUP workspace=$PROD_WORKSPACE_NAME

echo "Creating prod data asset..."
az ml data create \
    --type uri_folder \
    --name "diabetes-prod-folder" \
    --path ../production/data \
    --set "${ML_TAG_SET[@]}"

# ---------------------------------------------------------------------------
# Shared registry
# ---------------------------------------------------------------------------
echo "Creating registry resource group: $REGISTRY_RESOURCE_GROUP"
az group create --name $REGISTRY_RESOURCE_GROUP --location $RANDOM_REGION --tags "${COMMON_TAGS[@]}"

echo "Rendering registry.yml with dynamic values..."
sed \
    -e "s|REGISTRY_NAME_PLACEHOLDER|$REGISTRY_NAME|g" \
    -e "s|PRIMARY_REGION_PLACEHOLDER|$RANDOM_REGION|g" \
    registry.yml > registry.generated.yml

echo "Creating shared Azure Machine Learning registry: $REGISTRY_NAME"
az ml registry create \
    --file registry.generated.yml \
    --resource-group $REGISTRY_RESOURCE_GROUP
    

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Provisioning complete."
echo "  Dev workspace:   $DEV_WORKSPACE_NAME  ($DEV_RESOURCE_GROUP)"
echo "  Prod workspace:  $PROD_WORKSPACE_NAME  ($PROD_RESOURCE_GROUP)"
echo "  Shared registry: $REGISTRY_NAME  ($REGISTRY_RESOURCE_GROUP)"
