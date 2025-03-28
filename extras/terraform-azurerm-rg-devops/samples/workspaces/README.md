# \#AzureSandbox extras - workspaces sample

## Contents

* [Overview](#overview)
* [Before you start](#before-you-start)
* [Getting started](#getting-started)

## Overview

This configuration demonstrates how to use Terraform [workspaces](https://developer.hashicorp.com/terraform/cli/workspaces) to manage multiple environments (e.g. `dev`, `stage`, `prod`) from a single configuration.

## Before you start

* Create a dedicated resource group for your DevOps infrastructure, e.g. `rg-mydevopsinfra`.
* Create a storage account in the `rg-mydevopsinfra` resource group to be used as Terraform state [backend](https://developer.hashicorp.com/terraform/language/backend/azurerm), e.g. `stmystatebackendxxx`.
* Create a container in the storage account for Terraform state files, e.g. `workspaces-tfstate`.
* Add a `Storage Blob Data Contributor` role assignment for the Terraform user scoped to the new storage account.

## Getting started

* Update line 4 of [010-common.tf](010-common.tf) with the your Microsoft Entra Tenant ID.
* Update line 5 of [010-common.tf](010-common.tf) with the name of the storage account for storing the Terraform state, e.g. `stmystatebackendxxx`.
* Create three `terraform.tfvars` files for each environment in the same directory as the main configuration files. The files should be named `terraform.dev.tfvars`, `terraform.stage.tfvars`, and `terraform prod.tfvars` respectively. Initialize the variables defined in [variables.tf](./variables.tf) in each of the files with different values for each environment. For example:

    ```hcl
    # terraform.dev.tfvars

    location            = "centralus"
    resource_group_name = "rg-workspaces-dev"
    subscription_id     = "MY-DEV-SUBSCRIPTION-ID"
    vnet_address_space  = "10.1.0.0/16"
    vnet_name           = "vnet-dev"
    workspace           = "dev"

    ```

    ```hcl
    # terraform.stage.tfvars

    location            = "centralus"
    resource_group_name = "rg-workspaces-stage"
    subscription_id     = "MY-STAGE-SUBSCRIPTION-ID"
    vnet_address_space  = "10.2.0.0/16"
    vnet_name           = "vnet-stage"
    workspace           = "stage"
    ```

    ```hcl
    # terraform.prod.tfvars

    location            = "centralus"
    resource_group_name = "rg-workspaces-prod"
    subscription_id     = "MY-PROD-SUBSCRIPTION-ID"
    vnet_address_space  = "10.3.0.0/16"
    vnet_name           = "vnet-prod"
    workspace           = "prod"
    ```

* Run the following commands to initialize the Terraform backend and create the workspaces:

    ```bash
    terraform init
    terraform workspace new dev
    terraform workspace new stage
    terraform workspace new prod
    ```

* Examine the container with your tfstate files, there should be four files there:

    File | Environment
    --- | ---
    terraform.tfstate | default environment (empty state file that will not be used)
    terraform.tfstateenv:dev | dev environment
    terraform.tfstateenv:stage | stage environment
    terraform.tfstateenv:prod | prod environment

* Set the current workspace to `dev` and run the following command to create the resources in the `dev` environment:

    ```bash
    terraform workspace select dev
    terraform apply -var-file=terraform.dev.tfvars
    ```

* Set the current workspace to `stage` and run the following command to create the resources in the `stage` environment:

    ```bash
    terraform workspace select stage
    terraform apply -var-file=terraform.stage.tfvars
    ```

* Set the current workspace to `prod` and run the following command to create the resources in the `prod` environment:

    ```bash
    terraform workspace select prod
    terraform apply -var-file=terraform.prod.tfvars
    ```

* Examine the resources in the portal. You should see a separate resource group for each environment that contains a single virtual network specific to that environment.

* To clean up the resources, run the following command for each environment:

    ```bash
    terraform workspace select dev
    terraform destroy -var-file=terraform.dev.tfvars

    terraform workspace select stage
    terraform destroy -var-file=terraform.stage.tfvars

    terraform workspace select prod
    terraform destroy -var-file=terraform.prod.tfvars
    ```
