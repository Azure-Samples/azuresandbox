# Petstore Container App Module (petstore)

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Smoke Testing](#smoke-testing)
* [Documentation](#documentation)

## Architecture

![petstore-diagram](./images/petstore-diagram.drawio.svg)

## Overview

This module deploys a demo [petstore](https://petstore.swagger.io/) RESTful API using **Azure Container Apps**. The container app is network isolated, and Azure RBAC is used to pull container images from a network isolated shared container registry.

## Smoke Testing

Follow these steps after deployment to validate functionality.

1. Fetch the Petstore FQDN output:
   * In Terraform: `terraform output petstore_fqdn`

2. From *jumpwin1*, launch Edge and navigate to the petstore FQDN. This should display the Swagger UI for the petstore API.

3. Try navigating to the petstore FQDN from your local machine. This should fail, as the Container App network isolated.

## Documentation

Additional information about this module.

* [Dependencies](#dependencies)
* [Module Structure](#module-structure)
* [Input Variables](#input-variables)
* [Module Resources](#module-resources)
* [Output Variables](#output-variables)

### Dependencies

This module depends upon resources provisioned in the following modules:

* Root
* vnet-shared (key vault, log analytics)
* vnet-app (Windows jumpbox, virtual networks / subnets, private DNS zones, container registry)
* vm-jumpbox-linux (Linux jumpbox with Docker CLI for container image testing)

### Module Structure

```plaintext
├── scripts/
|   └── Set-ContainerRegistryConfiguration.ps1  # Script to import container image into ACR
├── locals.tf                                   # Local values (derived names, script parameters)
├── main.tf                                     # Container App & Environment resources
├── network.tf                                  # Private endpoint
├── outputs.tf                                  # Module outputs
├── terraform.tf                                # Terraform configuration block
└── variables.tf                                # Input variables 
```

### Input Variables

Variable | Default | Description
--- | --- | ---
arm_client_secret |  | The password for the service principal used for authenticating with Azure (sensitive).
container_apps_subnet_id |  | Resource ID of subnet for the Container Apps Environment infrastructure.
container_registry_id |  | The resource ID of an existing Azure Container Registry (ACR) containing / to receive the image.
enable_container_push | false | Enable (externally) AcrPush role assignment for managed identity (pull role provided in-module).
location |  | Azure region for deployment (lowercase, numbers, dashes only).
log_analytics_workspace_id |  | Resource ID of Log Analytics workspace used for diagnostics.
private_dns_zone_id |  | Resource ID of private DNS zone linked to the managed environment.
private_endpoint_subnet_id |  | Subnet where the private endpoint to the Container Apps Environment is placed.
resource_group_name |  | Name of the existing resource group.
source_container_image | swaggerapi/petstore31:latest | Source image (repo/image:tag) to seed into ACR / run.
source_container_registry | docker.io | Source registry domain of the image.
tags |  | Map of resource tags.
unique_seed |  | Unique seed appended to generated names (via Azure naming module).

### Module Resources

Address | Name | Notes
--- | --- | ---
azurerm_container_app.this | petstore | Runs the petstore container image pulled from the shared container registry.
azurerm_container_app_environment.this | cae-sand-dev-xxx | Managed Container Apps Environment.
azurerm_private_endpoint.this | pe-sand-dev-cae | Private endpoint for the Container Apps Environment.
azurerm_role_assignment.this | | Grants environment managed identity pull access to ACR.
null_resource.this | | Executes PowerShell script to import the container image into the shared container registry.
module.naming | | Azure naming module instance for consistent resource naming.

### Output Variables

Name | Description
--- | ---
petstore_fqdn | The public FQDN of the Petstore Container App ingress.
