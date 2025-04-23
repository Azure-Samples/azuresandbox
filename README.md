# Azure Sandbox

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Features](#features)
* [Dependencies](#dependencies)
* [Prerequisites](#prerequisites)
* [Getting Started (Interactive Execution)](#getting-started-interactive-execution)
* [Documentation](#documentation)

## Architecture

![diagram](./images/azuresandbox.drawio.svg)

## Overview

Azure Sandbox is a Terraform-based project designed to simplify the deployment of sandbox environments in Microsoft Azure. It provides a modular and reusable framework for creating and managing Azure resources, enabling users to experiment, learn, and test in a controlled environment.

The project is ideal for developers, IT professionals, and organizations looking to explore Azure services, prototype solutions, or conduct training sessions. With its modular design, AzureSandbox allows users to customize their deployments to suit specific use cases, such as virtual networks, virtual machines, AI services, and more.

Key highlights of Azure Sandbox include:

* **Modular Architecture**: Reusable modules for common Azure resources like virtual networks, virtual machines, databases and storage solutions.
* **Secure Secrets Management**: Integration with Azure Key Vault for securely storing sensitive information.
* **Diagnostics and Monitoring**: Configurations for Log Analytics and diagnostic settings to monitor resource usage and performance.
* **Extensibility**: Additional configurations for specialized use cases, such as AI services, DevOps environments, and on-premises connectivity simulations.

Azure Sandbox is not intended for production use but serves as a powerful tool for learning and experimentation in Azure.

## Features

Azure Sandbox provides a comprehensive set of features to simplify the deployment and management of sandbox environments in Microsoft Azure. These features include:

### Modular and Extensible Architecture

Reusable Terraform modules for common Azure resources, such as:

* Virtual networks
* Virtual machines
* Storage services
* Database services

Enable only the modules you need for your specific environment. Disable the modules you don't need to reduce costs and complexity. Extend your sandbox environment with additional modules for specialized use cases, or create your own custom modules to meet specific requirements.

### Secure Networking and Connectivity

* **Virtual Networks**: Configures virtual networks for secure and isolated communication between resources.
  * Shared virtual network (`vnet-shared`) for hosting common services.
  * Application-specific virtual network (`vnet-app`) with pre-configured subnets.
  * Virtual network peering for seamless connectivity between networks.
  * Preconfigured network security groups (NSGs) for controlling inbound and outbound traffic.
* **Private DNS Server**: Configures a private DNS server for name resolution within the sandbox environment, ensuring secure and isolated DNS queries.
* **Private DNS Zones**: Supports private DNS zones for managing custom domain names for Azure resources, enabling seamless name resolution across virtual networks.
* **Private Endpoints**: Provides network isolated endpoints for PaaS services.
* **Azure Firewall**: Pre-configured firewall for secure outbound internet access and traffic filtering.
* **Azure Bastion**: Pre-configured Bastion for secure and seamless RDP/SSH access to virtual machines without exposing them to the public internet.
* **Point-to-site VPN Gateway**: Configures an optional point-to-site VPN gateway for secure remote access to your sandbox environment.

### Pre-configured Virtual Machines

Pre-configured virtual machines:

* **Domain Controller**: Configures Active Directory Domain Services (AD DS) with a pre-configured local domain and integrated private DNS server.
* **Windows Jumpbox**: Domain-joined Windows server for remote administration, management and development within the sandbox environment with a full suite of pre-configured tools.
* **Linux Jumpbox**: Domain-joined Ubuntu server for secure SSH access to the sandbox environment with a full suite of pre-configured tools.

### Storage Options

Pre-configured storage services:

* **Azure Blob Storage**: Preconfigured container for startup configuration scripts.
* **Azure Files with AD DS Integration**: Preconfigured Azure Files share configured for integrated Active Directory Domain Services (AD DS) authentication for secure file sharing.

### Database Options

Multiple database deployment options to suit various use cases and requirements:

* **SQL Server IaaS (SQL Virtual Machine)**:
  * Deploys a fully configured SQL Server instance on a domain-joined Windows virtual machine.
  * Ideal for scenarios requiring full control over the operating system and database configuration.
  * Supports custom configurations, such as SQL Server Agent jobs, linked servers, and advanced database settings.

* **SQL Server PaaS (Azure SQL Database)**:
  * Deploys a fully managed Azure SQL Database instance.
  * Simplifies database management by handling backups, scaling, and high availability.
  * Suitable for applications requiring a scalable and cost-effective relational database solution.

* **MySQL PaaS (Azure Database for MySQL)**:
  * Deploys a fully managed MySQL database instance.
  * Provides high availability, automated backups, and scaling options.
  * Ideal for applications built on open-source technologies requiring MySQL as the backend database.

These options allow users to choose the database solution that best fits their needs, whether they require full control, a managed service, or compatibility with open-source technologies.

### Secure by Default, Secure by Design

Azure Sandbox is built with security as a core principle, ensuring that all resources are deployed with secure configurations by default. Key security features include:

* **Azure Key Vault Integration**:
  * Securely stores sensitive information, such as:
    * Service principal credentials
    * Shared keys
    * Administrator passwords
  * Ensures secrets are encrypted at rest and accessed only by authorized users or services.

* **Role-Based Access Control (RBAC)**:
  * Enforces least-privilege access by assigning roles to users, groups, and services based on their specific needs.
  * Ensures that only authorized entities can access or manage Azure resources.
  * Simplifies access management by leveraging Azure Active Directory (AAD) for identity and access control.

* **Data Encryption**:
  * Ensures all data at rest is encrypted using Azure-managed keys or customer-managed keys (CMKs) stored in Azure Key Vault.
  * Supports end-to-end encryption for data in transit using HTTPS and TLS.

* **Compliance and Monitoring**:
  * Integrates with Azure Policy to enforce compliance with organizational or regulatory standards.
  * Configures diagnostic settings to log resource activity and monitor for potential security threats.
  * Supports integration with Microsoft Defender for Cloud to provide advanced threat protection and security recommendations.

By combining these features, Azure Sandbox ensures that your sandbox environment is secure by default and designed to meet the highest security standards.

### Documentation and Videos

* Comprehensive documentation for each module and configuration.
* Provides guided smoke testing procedures for validating deployments.
* Step-by-step video tutorials for setup, testing, and customization.

## Dependencies

This section covers the dependencies used in the Azure Sandbox project, including Terraform providers, modules, scripting technologies, and configuration management technologies.

### Terraform

Azure Sandbox is built using Terraform, a cross platform, open-source Infrastructure as Code (IaC) tool that allows users to define and provision and version infrastructure using declarative configuration language.

#### Providers

The following Terraform providers are used in the project:

* **azurerm**: The Azure provider, used to manage Azure resources.
* **azapi**: The Azure API provider, used to manage Azure resources that are not yet supported by the azurerm provider and for direct access to Azure APIs.
* **cloudinit**: The cloud-init utility provider is used to configure Linux virtual machines.
* **random**: The Random utility provider is used to generate random values for resource attributes.
* **time**: The time utility provider is used to implement wait cycles and other time based operations.
* **tls**: The TLS provider is used to generate SSH certificates.

#### Modules

The following Terraform modules are used in this project:

* **Azure/naming**: A module for generating consistent and compliant Azure resource names.

### Scripting Technologies

The following cross-platform scripting technologies are used in this project:

* **PowerShell**:  Used for running scripts and automating tasks within the Azure Sandbox environment.
* **Az PowerShell Module**: The Az module is used to manage Azure resources from PowerShell.
* **Azure CLI**: The Azure Command-Line Interface (CLI) is used to manage Azure resources from the command line.
* **Bash**: The Bash shell is used for running scripts and automating tasks within the Azure Sandbox environment.

### Configuration Management Technologies

The following configuration management technologies are used in this project to configure virtual machines:

* **PowerShell DSC**: PowerShell Desired State Configuration (DSC) is used to configure Windows virtual machines.
* **Azure Automation DSC**: Azure Automation Desired State Configuration is used to configure Windows virtual virtual machines using configurations written in PowerShell DSC.
* **cloud-init**: Cloud-init is used to configure Linux virtual machines. It is a standard tool for cloud instance initialization and is widely used in cloud environments.

## Prerequisites

This section describes the prerequisites required in order to provision an Azure Sandbox.

### Entra ID Tenant and Azure Subscription

* Identify the [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/fundamentals/whatis) tenant to be used for identity and access management, or create a new tenant using [Quickstart: Set up a tenant](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-create-new-tenant).
* Identify a single Azure [subscription](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#subscription) or create a new Azure subscription. See [Azure Offer Details](https://azure.microsoft.com/support/legal/offer-details/) and [Associate or add an Azure subscription to your Microsoft Entra tenant](https://learn.microsoft.com/entra/fundamentals/how-subscriptions-associated-directory) for more information.
* Identify the owner of the Azure subscription to be used to provision Azure Sandbox. This user should have an [Owner](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#owner) Azure RBAC role assignment on the subscription. See [Steps to assign an Azure role](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-steps) for more information.

### Azure RBAC Role Assignments

* Ask the subscription owner to create an [Owner](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#owner) Azure RBAC role assignment for each sandbox user. See [Steps to assign an Azure role](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-steps) for more information.

### Service Principal

* Verify the subscription owner has privileges to create a service principal on the Microsoft Entra tenant. See [Permissions required for registering an app](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal#permissions-required-for-registering-an-app) for more information.
* Ask the subscription owner to [Create an Azure service principal](https://learn.microsoft.com/en-us/cli/azure/azure-cli-sp-tutorial-1?tabs=bash) (SPN) for sandbox users using [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart). The service principal can be created with the following command:

  ```bash
  az ad sp create-for-rbac -n AzureSandboxSPN --role Owner --scopes /subscriptions/YOUR-SUBSCRIPTION-ID-HERE
  ```

  The output should look like this:

  ```json
  {
    "appId": "YOUR-SERVICE-PRINCIPAL-APP-ID-HERE",
    "displayName": "AzureSandboxSPN",
    "password": "YOUR-SERVICE-PRINCIPAL-PASSWORD-HERE",
    "tenant": "YOUR-ENTRA-TENANT-ID-HERE"
  }
  ```

Save the service principal *appId* and *password* in a secure location such as a password vault.

### Azure Policies and Quotas

* Some organizations may institute [Azure policy](https://learn.microsoft.com/azure/governance/policy/overview) which may cause some sandbox deployments to fail. This can be addressed by using custom settings which pass the policy checks, or by disabling the policies on the Azure subscription being used for the configurations.
* Some Azure subscriptions may have low quota limits for specific Azure resources which may cause sandbox deployments to fail. See [Resolve errors for resource quotas](https://learn.microsoft.com/azure/azure-resource-manager/templates/error-resource-quota) for more information.

### Terraform Execution Environment

#### Interactive Execution

A variety of Terraform execution environments can be used to provision Azure Sandbox interactively, including:

* **Windows-Only**: A Windows-only client can be used to run Terraform. The following software should be installed:
  * git
  * Azure CLI
  * PowerShell 7.x
  * Az PowerShell Module
  * Terraform
  * Visual Studio Code

* **Windows Subsystem for Linux (WSL)**: WSL offers the best of Windows and Linux in the same client environment and was used to develop this project. The following software should be installed:
  * Linux (WSL) software
    * Linux Distro: Ubuntu 24.04 LTS (Noble Numbat)
    * pip3 Python library package manager and the PyJWT Python library.
    * git
    * Azure CLI
    * PowerShell 7.x
    * Az PowerShell Module
    * Terraform
  * Windows software
    * Visual Studio Code configured for [Remote development in WSL](https://code.visualstudio.com/docs/remote/wsl-tutorial)

* **Linux / MacOs**: A Linux or MacOS client can be used to run Terraform. The following software should be installed:
  * git
  * Azure CLI
  * PowerShell 7.x
  * Az PowerShell Module
  * Terraform
  * Visual Studio Code

* **Azure Cloud Shell**: Azure Cloud Shell is not recommended but can be used. Most of the software dependencies are pre-installed.

* **GitHub Codespaces**: GitHub Codespaces has not been tested but should be okay. Most of the software dependencies should be pre-installed.

#### Automated Execution

Azure DevOps, GitHub Actions, or other CI/CD tools can be used to automate the deployment of Azure Sandbox. The following software should be installed:

* git
* Azure CLI
* PowerShell 7.x
* Az PowerShell Module
* Terraform

## Getting Started (Interactive Execution)

This section covers the steps to get started with Azure Sandbox using an interactive execution environment. The steps include cloning the repository, initializing Terraform, configuring variables, validating and applying the configuration, and smoke testing.

* [Step 1: Clone the Repository](#step-1-clone-the-repository)
* [Step 2: Initialize Terraform](#step-2-initialize-terraform)
* [Step 3: Configure Variables](#step-3-configure-variables)
* [Step 4: Validate and Apply Configuration](#step-4-validate-and-apply-configuration)
* [Step 5: Complete Smoke Testing](#step-5-complete-smoke-testing)
* [Step 6: Use Your Sandbox](#step-6-use-your-sandbox)
* [Step 7: Clean Up](#step-7-clean-up)

### Step 1: Clone the Repository

To get started, clone the Azure Sandbox repository to your local machine. You can do this using the following command:

```bash
git clone https://github.com/Azure-Samples/azuresandbox
```

### Step 2: Initialize Terraform

After cloning the repository, navigate to the `azuresandbox` directory and initialize Terraform. This step downloads the necessary provider plugins and modules.

```bash
cd azuresandbox
terraform init
```

**WARNING:** By default this configuration assumes you will be using a local Terraform state file which includes sensitive information. If you wish to use a remote state file, simply add a `backend.tf` file to the root directory of the project and include the configuration for your remote backend. For example, if you are using Azure Storage as a remote backend, the `backend.tf` file might look like this:

```hcl
# backend.tf
terraform {
  backend "azurerm" {
    use_azuread_auth     = true
    tenant_id            = "YOUR-TENANT-ID-HERE"
    storage_account_name = "YOUR-STORAGE-ACCOUNT-FOR-TFSTATE-HERE" 
    container_name       = "YOUR-STATE-CONTAINER-NAME-HERE" 
    key                  = "terraform.tfstate"
  }
}
```

### Step 3: Configure Variables

There are hundreds (maybe thousands) of variables in this configuration. Defaults have been set for most of them so only a few need to be set in advance to provision a sandbox. There are a few different ways to set variables in Terraform.

* Environment Variables: Set environment variables for sensitive information such as passwords and secrets used in the root module.
* `terraform.tfvars` file: Create a `terraform.tfvars` file in the root directory of the project to set variables for the root module.
* `main.tf` file: Override module default values in the `main.tf` file by customizing the module blocks.

First, create an environment variable for the service principal password. For security reasons this secret should not be stored in the `terraform.tfvars` file.

```bash
# Set environment variable in bash
export TF_VAR_arm_client_secret=YOUR-SERVICE-PRINCIPAL-PASSWORD-HERE
```

```pwsh
# Set  environment variable in PowerShell
$env:TF_VAR_arm_client_secret = "YOUR-SERVICE-PRINCIPAL-PASSWORD-HERE"
```

Next, create a `terraform.tfvars` file in the root directory of the project. This file should set the necessary variables for your deployment. Here is an example of what the `terraform.tfvars` file might look like:

```hcl
aad_tenant_id   = "YOUR-ENTRA-TENANT-ID-HERE"
arm_client_id   = "YOUR-SERVICE-PRINCIPAL-APP-ID-HERE"
location        = "YOUR-AZURE-REGION-HERE"
subscription_id = "YOUR-AZURE-SUBSCRIPTION-ID-HERE"
user_object_id  = "YOUR-USER-OBJECT-ID-HERE"

tags = {
  project     = "sand",
  costcenter  = "mycostcenter",
  environment = "dev"
}
```

Helper scripts are provided to generate the `terraform.tfvars` file:

```bash
# Bash bootstrap script
./scripts/bootstrap.sh
```

```pwsh
# PowerShell bootstrap script
./scripts/bootstrap.ps1
```

#### Enabling Modules

By default only the shared virtual network module (`vnet-shared`) is enabled which isn't very useful on it's own. You can enable additional modules by setting the `enable_module_*` variables in the `terraform.tfvars` file. At a minimum you should enable the application virtual network module (`vnet-app`) by setting `enable_vnet_app = true` like this:

```hcl
aad_tenant_id   = "YOUR-ENTRA-TENANT-ID-HERE"
arm_client_id   = "YOUR-SERVICE-PRINCIPAL-APP-ID-HERE"
location        = "YOUR-AZURE-REGION-HERE"
subscription_id = "YOUR-AZURE-SUBSCRIPTION-ID-HERE"
user_object_id  = "YOUR-USER-OBJECT-ID-HERE"

tags = {
  project     = "sand",
  costcenter  = "mycostcenter",
  environment = "dev"
}

# Enable modules here
enable_module_vnet_app = true
```

And here's how to enable all the modules:

```hcl
aad_tenant_id   = "YOUR-ENTRA-TENANT-ID-HERE"
arm_client_id   = "YOUR-SERVICE-PRINCIPAL-APP-ID-HERE"
location        = "YOUR-AZURE-REGION-HERE"
subscription_id = "YOUR-AZURE-SUBSCRIPTION-ID-HERE"
user_object_id  = "YOUR-USER-OBJECT-ID-HERE"

tags = {
  project     = "sand",
  costcenter  = "mycostcenter",
  environment = "dev"
}

# Enable modules here
enable_module_vnet_app          = true
enable_module_vm_jumpbox_linux  = true
enable_module_vm_mssql_win      = true
enable_module_mssql             = true
enable_module_mysql             = true
enable_module_vwan              = true
```

You can examine the `depends_on` blocks in the `main.tf` file to see which modules depend on each other.

#### Overriding Defaults

The variable defaults set in each module can be overridden by customizing the appropriate module block in `main.tf`. For example, the default value for the `vm_adds_name` variable in the `vnet-shared` module is `adds1`. You can override this value by adding the following to the `vnet-shared` module block in `main.tf`:

```hcl
module "vnet_shared" {
  source = "./modules/vnet-shared"

  key_vault_id        = azurerm_key_vault.this.id
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  depends_on = [azurerm_key_vault_secret.spn_password]

  # Override default values here
  vm_adds_name = "mydc1" # default was "adds1"
}

```

### Step 4: Validate and Apply Configuration

First, validate that the configuration is syntactically correct:

```bash
terraform validate
```

Next, run a plan to see what resources will be created:

```bash
terraform plan
```

If you are provisioning a brand new sandbox, you will see a lot of `+` signs in the output. This indicates that new resources will be created if this plan is applied. If you are updating an existing sandbox, you may see `~` signs indicating that existing resources will be updated. If you see `-` signs, this indicates that existing resources will be deleted. Be careful with these operations as they may cause data loss.

Public access is disabled by design for the Azure Storage account in the sandbox. This may cause errors during plan creation because your Terraform execution environment is blocked by the storage firewall. To work around this you can manually modify the storage firewall using a couple of different approaches:

* Add the client ip for your Terraform execution environment to the storage firewall whitelist. This should work from most home networks, but will not work on a private network that implements source network address translation (SNAT).
* Temporarily enable public network access on the storage account outside of Terraform.

Be sure to check that storage firewall public access is disabled again after you are done with Terraform operations.

Remember that Terraform will compare the state of existing resources in Azure with what it expects to be there when creating a plan. If the state of existing resources in Azure does not match what Terraform expects, the plan will modify existing resources to match the configuration. This can happen when resources are modified manually or via Policy outside of Terraform. This is known as "drift".

Finally, apply the configuration to create the resources:

```bash
terraform apply
```

Monitor the progress of the apply operation in the console. If errors occur, that may not be reflected in the console immediately. Terraform will try to apply as much of the plan as possible first, then will show the errors when it is done. It can take up to 90 minutes to provision a sandbox depending upon which modules you choose to enable. If everything goes well you should see a message like this:

```text
Apply complete! Resources: XX added, XX changed, XX destroyed.
```

**WARNING:** This configuration uses Terraform provisioners and Azure custom script extensions which increase the chance of transient errors during plan application. Addressing errors may require any of the following actions:

* An existing Azure resource may need to be manually deleted.
* An Azure resource may need to be manually removed from Terraform state (see `terraform state rm` command).
* An existing Azure resource may need to be imported into Terraform state (see `terraform import` command).

Once the error has been addressed, you can re-run the `terraform apply` command to continue provisioning the sandbox. Terraform will pick up where it left off.

### Step 5: Complete Smoke Testing

After the sandbox has been provisioned, complete the smoke testing procedures specific to each module. This will ensure that the resources are functioning as expected and that the configuration is correct.

### Step 6: Use Your Sandbox

You now have a fully provisioned Azure Sandbox environment! You can use it for experimentation, learning, development or testing purposes. Feel free to explore the additional resources and configurations available for your sandbox.

### Step 7: Clean Up

Don't forget to delete your sandbox when you're done. You don't want to have to explain to your boss why you left an unused sandbox laying around that costs your company money. The quickest way to clean up is to delete the sandbox resource group. Do this with care because data loss will occur.

## Documentation

This section provides documentation regarding the overall structure of the repository and the root module. See the README.md files in each module directory for more information about that module.

### Repository Structure

The Azure Sandbox repository is organized into the following structure:

Path / File | Description
--- | ---
`├── extras/`                     | Extend your sandbox with extra modules and configurations
`│   ├── configurations/`         | Extra configurations
`│   └── modules/`                | Extra modules
`├── images/`                     | Diagrams and visual assets
`│   └── azuresandbox.drawio.svg` | Architecture diagram for Azure Sandbox
`├── modules/`                    | Reusable Terraform modules
`│   ├── mssql/`                  | Azure SQL Database module
`│   ├── mysql/`                  | Azure Database for MySQL module
`│   ├── vm-jumpbox-linux/`       | Linux jumpbox virtual machine module
`│   ├── vnet-shared/`            | Shared services virtual network module
`│   ├── vnet-app/`               | Application virtual network module
`│   └── vwan/`                   | Point-to-site VPN module
`├── scripts/`                    | Helper scripts for setup and automation
`│   ├── bootstrap.sh`            | Bash script for generating `terraform.tfvars`
`│   └── bootstrap.ps1`           | PowerShell script for generating `terraform.tfvars`
`├── locals.tf`                   | Local variables for the root module
`├── main.tf`                     | Main Terraform configuration
`├── outputs.tf`                  | Output variables for the root module
`├── providers.tf`                | Provider configurations
`└── variables.tf`                | Input variables for the root module

### Root Module Resources

The root module includes a resource group, key vault and log analytics workspace used by the child modules. It also implements Azure RBAC role assignments for both the service principal used by Terraform as well as the interactive user.

Address | Sample Name | Notes
--- | --- | ---
data.azurerm_client_config.current |  | Used to get the object id of the service principal
azurerm_key_vault.this | `kv-sand-dev-xxxxxxxx` | Key vault for storing secrets
azurerm_key_vault_secret.log_primary_shared_key |  | Shared key secret for log analytics workspace
azurerm_key_vault_secret.spn_password | | Service principal password secret
azurerm_log_analytics_workspace.this | `log-sand-dev-xxxxxxxx` | Log analytics workspace
azurerm_monitor_diagnostic_setting.this | | Diagnostic settings for key vault
azurerm_resource_group.this | `rg-sand-dev-xxxxxxxx` | Resource group for the sandbox
azurerm_role_assignment.roles["kv_secrets_officer_spn"] | | Assigns the Key Vault Secrets Officer role to the service principal
azurerm_role_assignment.roles["kv_secrets_officer_user"] | | Assigns the Key Vault Secrets Officer role to the interactive user
time_sleep.wait_for_roles | | Waits for the role assignments to propagate

### Child Modules

Module | Required | Depends On | Notes
--- | --- | --- | ---
[vnet-shared](./modules/vnet-shared) | Yes | Root module | Shared services virtual network module.
[vnet-app](./modules/vnet-app) | No | `vnet-shared` module | Application virtual network module.
[vm-jumpbox-linux](./modules/vm-jumpbox-linux) | No | `vnet-shared` module | Linux jumpbox virtual machine module.
[vm-mssql-win](./modules/vm-mssql-win) | No | `vnet-shared` module | Windows SQL Server virtual machine module.
[mssql](./modules/mssql) | No | `vnet-shared` module | Azure SQL Database module.
[mysql](./modules/mysql) | No | `vnet-shared` module | Azure Database for MySQL module.
[vwan](./modules/vwan) | No | `vnet-shared` module | Point-to-site VPN module.

### Additional Resources

See [extras](./extras/) for other modules and configurations that can be used to extend your sandbox. Links to videos and other learning resources are also included.

## Disclaimer
