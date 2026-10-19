#!/bin/bash

# This script generates a terraform.tfvars file for use with this configuration.
# Terraform authenticates as the operator signed in to Azure CLI (az login), so no service principal is needed.
#
# Package dependencies:
#   - Azure CLI

#region functions

usage() {
    printf "Usage: $0 \n" 1>&2
    exit 1
}

#endregion

#region constants
default_costcenter=mycostcenter
default_environment=dev
default_location=southcentralus
default_project=devops
#endregion

#region main
# Check if Azure CLI is installed
if ! command -v az &> /dev/null
then
    printf "Azure CLI could not be found. Please install Azure CLI.\n"
    usage
fi

# Get runtime defaults
printf "Retrieving runtime defaults ...\n"

# Set default subscription from currently logged in Azure CLI user.
default_subscription_id=$(az account list --only-show-errors --query "[? isDefault]|[0].id" --output tsv)

if [ -z $default_subscription_id ]
then
  printf "Unable to retrieve Azure subscription details. Please run 'az login' first.\n"
  usage
fi

# Set default Microsoft Entra tenant id from currently logged in Azure CLI user.
default_entra_tenant_id=$(az account show --query tenantId --output tsv)

# Get user input
read -e -i $default_entra_tenant_id     -p "Microsoft Entra tenant id (entra_tenant_id) --: " entra_tenant_id
read -e -i $default_subscription_id     -p "Azure subscription id (subscription_id) ------: " subscription_id
read -e -i $default_location            -p "Azure location (location) --------------------: " location
read -e -i $default_environment         -p "Environment tag value (environment) ----------: " environment
read -e -i $default_costcenter          -p "Cost center tag value (costcenter) -----------: " costcenter
read -e -i $default_project             -p "Project tag value (project) ------------------: " project

# Validate user input
entra_tenant_id=${entra_tenant_id:-$default_entra_tenant_id}
costcenter=${costcenter:-$default_costcenter}
environment=${environment:-$default_environment}
location=${location:-$default_location}
project=${project:-$default_project}
subscription_id=${subscription_id:-$default_subscription_id}

# Validate subscription
subscription_name=$(az account list --query "[?id=='$subscription_id'].name" --output tsv)

if [ -n "$subscription_name" ]
then 
  printf "Found subscription '$subscription_name'...\n"
else
  printf "Invalid subscription id '$subscription_id'.\n"
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

printf "entra_tenant_id = \"$entra_tenant_id\"\n" >  ./terraform.tfvars
printf "location        = \"$location\"\n"        >> ./terraform.tfvars
printf "subscription_id = \"$subscription_id\"\n" >> ./terraform.tfvars
printf "\ntags = $tags\n"                         >> ./terraform.tfvars
cat ./terraform.tfvars

exit 0
#endregion
