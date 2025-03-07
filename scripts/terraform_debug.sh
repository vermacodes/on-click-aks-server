#!/bin/bash

action=$1

# Read the instructions very carefully.

# no need to update these variable.
export ROOT_DIR=$(pwd)
source $ROOT_DIR/scripts/helper.sh

# change to 'trace' if thats what you want. But in most cases 'debug' is good enough.
export TF_LOG=debug

# Following variables are used by terraform. Change them as you need.
# You will get these from the output on the UI.
# just run terraform plan and copy the environment variables which start with TF_VAR
# modify them to be on liners and paste them here.
export TF_VAR_resource_group='{"location": "East US"}'
export TF_VAR_network_security_groups='[]'
export TF_VAR_container_registries='[]'
export TF_VAR_subnets='[]'
export TF_VAR_firewalls='[]'
export TF_VAR_app_gateways='[]'
export TF_VAR_jumpservers='[]'
export TF_VAR_virtual_networks='[]'
export TF_VAR_kubernetes_clusters='[]'
# Following variables are used by the helper script. No need to change them.
export terraform_directory="tf"
export root_directory=$(pwd)
export resource_group_name="repro-project"
export container_name="tfstate"
export tf_state_file_name="terraform.tfstate"

# add the storage account name here. you will find that on UI in settings.
export storage_account_name="iv3p7230nbdw"

# Update tf/provers.tf to remove backend configuration.
sed -i '/backend "azurerm" {}/d' $root_directory/$terraform_directory/providers.tf

# Remove existing terraform init
rm -rf $root_directory/$terraform_directory/.terraform*

# Terraform Init - Sourced from helper script.
$root_directory/scripts/terraform.sh init

function plan() {
  log "Planning"
  terraform plan
}

function apply() {
  log "Applying"
  terraform apply -auto-approve
  if [ $? -ne 0 ]; then
    err "Terraform Apply Failed"
    exit 1
  fi
}

function destroy() {
  log "Destroying"
  terraform destroy -auto-approve
  if [ $? -ne 0 ]; then
    err "Terraform Destroy Failed"
    exit 1
  fi
}

function list() {
  log "Listing"
  terraform state list
}

function getSecertsFromKeyVault() {
  # Following two are already availabe.
  export ARM_SUBSCRIPTION_ID=$(az account show --output json | jq -r .id)
  export ARM_TENANT_ID=$(az account show --output json | jq -r .tenantId)

  # Resource group need not be changed.
  RESOURCE_GROUP_NAME="repro-project"

  log "Pulling secrets from keyvault. This will take just a few moments."

  # Get the name of the Key Vault in the resource group
  KEY_VAULT_NAME=$(az keyvault list --resource-group "${RESOURCE_GROUP_NAME}" --query "[].name" -o tsv)
  if [ $? -ne 0 ]; then
    err "Failed to get key vault name in resource group ${RESOURCE_GROUP_NAME}"
    return 1
  fi
  # Get a list of all secrets in the Key Vault
  SECRET_NAMES=$(az keyvault secret list --vault-name "${KEY_VAULT_NAME}" --query "[].name" -o tsv)
  if [ $? -ne 0 ]; then
    err "Failed to get secrets from key vault ${KEY_VAULT_NAME}"
    return 1
  fi

  # Loop through the list of secrets and set them as environment variables
  for SECRET_NAME in $SECRET_NAMES; do
    ENV_VAR_NAME=$(echo "$SECRET_NAME" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    SECRET_VALUE=$(az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name "${SECRET_NAME}" --query "value" -o tsv)
    if [ $? -ne 0 ]; then
      err "Failed to get secret ${SECRET_NAME} from key vault ${KEY_VAULT_NAME}"
      return 1
    fi
    export "${ENV_VAR_NAME}"="${SECRET_VALUE}"
  done

  return 0
}

##
## Script starts here.
##

# Getting secrets from keyvault.
# if getSecertsFromKeyVault; then
#     ok "Secrets pulled from keyvault."
# else
#     err "Failed to pull secrets from keyvault."
#     exit 1
# fi

if [[ "$ARM_SUBSCRIPTION_ID" == "" ]]; then
  export ARM_SUBSCRIPTION_ID=$(az account show --output json | jq -r .id)
fi

cd $root_directory/$terraform_directory
log "Terraform Environment Variables"
env | grep "TF_VAR" | awk -F"=" '{printf "%s=", $1; print $2 | "jq ."; close("jq ."); }'
echo ""

# Delete existing if init
if [[ "$action" == "init" ]]; then
  rm -rf .terraform*
fi

# Terraform Init - Sourced from helper script.
tf_init

if [[ "$action" == "plan" ]]; then
  plan
elif [[ "$action" == "apply" ]]; then
  apply
elif [[ "$action" == "destroy" ]]; then
  destroy
fi

ok "Terraform Action End"
