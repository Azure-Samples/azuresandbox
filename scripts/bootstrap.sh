#!/bin/bash

# This script generates a terraform.tfvars file for use with Azure Sandbox
#
# Package dependencies:
#   - Azure CLI 
#   - PyJWT python library to decode the JWT tokens

#region functions

usage() {
    printf "Usage: $0 \n" 1>&2
    exit 1
}

#endregion

#region constants

default_costcenter=mycostcenter
default_environment=dev
default_location=centralus
default_project=sand

#endregion

#region main

# Check if Azure CLI is installed
if ! command -v az &> /dev/null
then
    printf "Azure CLI could not be found. Please install Azure CLI.\n"
    usage
fi
# Check if Python 3 is installed
if ! command -v python3 &> /dev/null
then
    printf "Python 3 could not be found. Please install Python 3.\n"
    usage
fi
# Check if PyJWT is installed
if ! python3 -c "import jwt" &> /dev/null
then
    printf "PyJWT could not be found. Please install PyJWT.\n"
    usage
fi

# Get runtime defaults
printf "Retrieving runtime defaults ...\n"

# Validate TF_VAR_arm_client_secret
if [ -z "$TF_VAR_arm_client_secret" ]
then
  printf "Environment variable 'TF_VAR_arm_client_secret' must be set.\n"
  usage
fi

# Set default subscription from currently logged in Azure CLI user.
default_subscription_id=$(az account list --only-show-errors --query "[? isDefault]|[0].id" --output tsv)

if [ -z $default_subscription_id ]
then
  printf "Unable to retrieve Azure subscription details. Please run 'az login' first.\n"
  usage
fi

# Set default user from currently logged in Azure CLI user.
default_user_object_id=$(az account get-access-token --query accessToken --output tsv | tr -d '\n' | python3 -c "import jwt, sys; print(jwt.decode(sys.stdin.read(), algorithms=['RS256'], options={'verify_signature': False})['oid'])")

# Set default Microsoft Entra tenant id from currently logged in Azure CLI user.
default_aad_tenant_id=$(az account show --query tenantId --output tsv)

# Get user input
read -e                             -p "Service principal appId (arm_client_id) -----------------: " arm_client_id
read -e -i $default_aad_tenant_id   -p "Microsoft Entra tenant id (aad_tenant_id) ---------------: " aad_tenant_id
read -e -i $default_user_object_id  -p "Object id for Azure CLI signed in user (user_object_id) -: " user_object_id
read -e -i $default_subscription_id -p "Azure subscription id (subscription_id) -----------------: " subscription_id
read -e -i $default_location        -p "Azure location (location) -------------------------------: " location
read -e -i $default_environment     -p "Environment tag value (environment) ---------------------: " environment
read -e -i $default_costcenter      -p "Cost center tag value (costcenter) ----------------------: " costcenter
read -e -i $default_project         -p "Project tag value (project) -----------------------------: " project

# Validate user input
aad_tenant_id=${aad_tenant_id:-$default_aad_tenant_id}
costcenter=${costcenter:-$default_costcenter}
environment=${environment:-$default_environment}
location=${location:-$default_location}
user_object_id=${user_object_id:-$default_user_object_id}
project=${project:-$default_project}
subscription_id=${subscription_id:-$default_subscription_id}

# Validate arm_client_id
if [ -z "$arm_client_id" ]
then
  printf "arm_client_id is required.\n"
  usage
fi

# Validate TF_VAR_arm_client_secret
if [ -z "$TF_VAR_arm_client_secret" ]
then
  printf "Environment variable 'TF_VAR_arm_client_secret' must be set.\n"
  usage
fi

# Validate service principal
arm_client_display_name=$(az ad sp show --id $arm_client_id --query "appDisplayName" --output tsv)

if [ -n "$arm_client_display_name" ]
then 
  printf "Found service principal '$arm_client_display_name'...\n"
else
  printf "Invalid service principal AppId '$arm_client_id'...\n"
  usage
fi

# Validate subscription
subscription_name=$(az account list --query "[?id=='$subscription_id'].name" --output tsv)

if [ -n "$subscription_name" ]
then 
  printf "Found subscription '$subscription_name'...\n"
else
  printf "Invalid subscription id '$subscription_id'.\n"
  usage
fi

# Validate object id of Azure CLI signed in user
if [ -z "$user_object_id" ]
then
  printf "Object id for Azure CLI signed in user (user_object_id) not provided.\n"
  usage
fi

# Validate location
location_id=$(az account list-locations --query "[?name=='$location'].id" --output tsv)

if [ -z "$location_id" ]
then
  printf "Invalid location '$location'...\n"
  usage
fi

# Build tags map
tags=$(cat <<EOF
{
  project     = "$project",
  costcenter  = "$costcenter",
  environment = "$environment"
}
EOF
)

# Generate terraform.tfvars file
printf "\nGenerating terraform.tfvars file...\n\n"

printf "aad_tenant_id   = \"$aad_tenant_id\"\n"     > ./terraform.tfvars
printf "arm_client_id   = \"$arm_client_id\"\n"     >> ./terraform.tfvars
printf "location        = \"$location\"\n"          >> ./terraform.tfvars
printf "subscription_id = \"$subscription_id\"\n"   >> ./terraform.tfvars
printf "user_object_id  = \"$user_object_id\"\n"    >> ./terraform.tfvars
printf "\ntags = $tags\n"                           >> ./terraform.tfvars
printf "\n# Enable modules here\n\n"                >> ./terraform.tfvars
printf "# enable_module_vnet_app         = true\n"  >> ./terraform.tfvars
printf "# enable_module_vm_jumpbox_linux = true\n"  >> ./terraform.tfvars
printf "# enable_module_vm_mssql_win     = true\n"  >> ./terraform.tfvars
printf "# enable_module_mssql            = true\n"  >> ./terraform.tfvars
printf "# enable_module_mysql            = true\n"  >> ./terraform.tfvars
printf "# enable_module_vwan             = true\n"  >> ./terraform.tfvars
printf "# enable_module_vnet_onprem      = true\n"  >> ./terraform.tfvars

cat ./terraform.tfvars

exit 0
#endregion
