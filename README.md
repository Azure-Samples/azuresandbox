# Azure Sandbox

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Features](#features)
* [Prerequisites](#prerequisites)
* [Getting Started (Interactive Execution)](#getting-started-interactive-execution)
* [Documentation](#documentation)

## Architecture

![diagram](./images/azuresandbox.drawio.svg)

## Overview

Azure Sandbox is a Terraform-based project designed to simplify the deployment of sandbox environments in Microsoft Azure. It provides a modular and reusable framework for implementing foundational infrastructure which can accelerate the development of innovative new solutions in Azure.

This project is ideal for developers, IT professionals, and organizations looking to explore Azure services, prototype solutions, or conduct training sessions. With its modular design, Azure Sandbox allows users to customize their deployments to suit specific use cases, such as virtual networks, virtual machines, AI services, and more.

Azure Sandbox is not intended for production use but serves as a powerful tool for learning and experimentation in Azure.

## Features

Azure Sandbox provides a comprehensive set of features to simplify the deployment and management of sandbox environments in Microsoft Azure.

* [Modular and Extensible Architecture](#modular-and-extensible-architecture)
* [Secure Networking and Connectivity](#secure-networking-and-connectivity)
* [Pre-configured Virtual Machines](#pre-configured-virtual-machines)
* [Pre-configured Storage Options](#pre-configured-storage-options)
* [Pre-configured Database Options](#pre-configured-sql-database-options)
* [Secure by Default, Secure by Design](#secure-by-default-secure-by-design)
* [Documentation and Videos](#documentation-and-videos)

### Modular and Extensible Architecture

Reusable Terraform modules for common Azure resources, such as:

* Virtual networks
* Virtual machines
* Storage services
* Database services
* AI services

Enable only the modules you need for your specific sandbox environment. Disable the modules you don't need to reduce costs and complexity. Extend your sandbox environment with additional modules for specialized use cases, or create your own custom modules to meet specific requirements.

### Secure Networking and Connectivity

* **Virtual Networks**: Configures virtual networks for secure and isolated communication between resources.
  * Shared virtual network (vnet-shared) for hosting common services.
  * Application-specific virtual network (vnet-app) with pre-configured subnets.
  * Virtual network peering for seamless connectivity between networks.
  * Pre-configured network security groups (NSGs) for controlling inbound and outbound traffic.
* **Private DNS Server**: Pre-configured  private DNS server for name resolution within the sandbox environment, ensuring secure and isolated DNS queries.
* **Private DNS Zones**: Pre-configured private DNS zones for popular Azure services.
* **Private Endpoints**: Pre-configured network isolated endpoints for PaaS services.
* **Azure Firewall**: Pre-configured firewall for secure outbound internet access and threat intelligence.
* **Azure Bastion**: Pre-configured Bastion for secure and seamless RDP/SSH access to virtual machines without exposing them to the public internet.
* **Point-to-site VPN Gateway**: Pre-configured point-to-site VPN gateway for secure remote access to your sandbox environment.

### Pre-configured Virtual Machines

A variety of Windows and Linux virtual machines are include and are fully configured for use in the sandbox.

* **Domain Controller / DNS Server**: Active Directory Domain Services (AD DS) domain controller with a pre-configured local domain and integrated private DNS server.
* **Windows Jumpbox**: Domain-joined Windows server for remote administration, management and development within the sandbox environment with a full suite of pre-configured tools.
* **Linux Jumpbox**: Domain-joined Ubuntu server for secure SSH access to the sandbox environment with a full suite of pre-configured tools.

### Pre-configured Storage Options

Two storage options are included and are fully configured for use in the sandbox.

* **Azure Blob Storage**: Container for startup configuration scripts with network isolated endpoints for secure access.
* **Azure Files**:  Azure Files share configured for integrated Active Directory Domain Services (AD DS) authentication and network isolated endpoints for secure file sharing.

### Pre-configured SQL Database Options

Multiple SQL database options are provided to suit various use cases and requirements. The combination of these features helps ensure that your sandbox environment is secure by default and designed to meet the highest security standards. These options allow users to choose the database solution that best fits their needs, whether they require full control, a managed service, or compatibility with open-source technologies.

* **SQL Server Virtual Machine (IaaS)**:
  * Deploys a fully configured SQL Server instance on a domain-joined Windows virtual machine.
  * Ideal for scenarios requiring full control over the operating system and database configuration.
  * Supports custom configurations, such as SQL Server Agent jobs, linked servers, and advanced database settings.

* **Azure SQL Database (PaaS)**:
  * Deploys a fully managed Azure SQL Database instance.
  * Network isolated endpoints for secure access.
  * Simplifies database management by handling backups, scaling, and high availability.
  * Suitable for applications requiring a scalable and cost-effective relational database solution.

* **Azure Database for MySQL (PaaS)**:
  * Deploys a fully managed MySQL database instance.
  * Network isolated endpoints for secure access.
  * Provides high availability, automated backups, and scaling options.
  * Ideal for applications built on open-source technologies requiring MySQL as the backend database.

### Secure by Default, Secure by Design

Azure Sandbox is built with security as a core principle, ensuring that all resources are deployed with secure configurations by default. Key security features include:

* **Azure Key Vault Integration**:
  * Securely stores sensitive information, such as:
    * Service principal credentials
    * Shared keys
    * Administrator passwords
  * Ensures secrets are encrypted at rest and accessed only by authorized users or services.
  * Network isolated endpoints for secure access to secrets.

* **Role-Based Access Control (RBAC)**:
  * Enforces least-privilege access by assigning roles to users, groups, and services based on their specific needs.
  * Ensures that only authorized entities can access or manage Azure resources.
  * Simplifies access management by leveraging Microsoft Entra ID for identity and access control.

  **IMPORTANT**: Both the interactive user and the service principal used to provision the sandbox environment must have an `Owner` role assignment scoped to the sandbox subscription. This is required for the service principal to be able to create and manage resources in the subscription including role assignments. All other role assignments follow the principle of least privilege and leverage managed identities where applicable.

* **Data Encryption**:
  * All data stored in the sandbox environment is encrypted at rest using platform-managed keys.
  * Supports end-to-end encryption for data in transit using TLS and host encryption for virtual machines.

* **Compliance and Monitoring**:
  * Integrates with Azure Policy to enforce compliance with organizational or regulatory standards.
  * Configures diagnostic settings to log resource activity and monitor for potential security threats.
  * Supports integration with Microsoft Defender for Cloud to provide advanced threat protection and security recommendations.

* **Network Isolation**:
  * All sandbox resources are deployed within separate virtual networks, ensuring that they are isolated from the public internet and other Azure resources.

### Documentation and Videos

This project includes valuable resources to help you get started quickly and easily. The content is designed to be user-friendly and accessible, making it easy for users of all skill levels to understand and utilize the features of Azure Sandbox.

* Comprehensive documentation for each module and configuration.
* Prescriptive smoke testing procedures for validating deployments.
* Step-by-step video tutorials for setup, testing, and customization.

## Prerequisites

This section describes the prerequisites required in order to provision an Azure Sandbox.

* [Microsoft Entra ID Tenant and Azure Subscription](#microsoft-entra-id-tenant-and-azure-subscription)
* [Azure RBAC Role Assignments](#azure-rbac-role-assignments)
* [Service Principal](#service-principal)
* [Other Prerequisites](#other-prerequisites)
* [Terraform Execution Environment](#terraform-execution-environment)

### Microsoft Entra ID Tenant and Azure Subscription

* Identify the [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/fundamentals/whatis) tenant to be used for identity and access management, or create a new tenant using [Quickstart: Set up a tenant](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-create-new-tenant).
* Identify a single Azure [subscription](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/considerations/fundamental-concepts#azure-terminology) or create a new Azure subscription. See [Azure Offer Details](https://azure.microsoft.com/support/legal/offer-details/) and [Associate or add an Azure subscription to your Microsoft Entra tenant](https://learn.microsoft.com/entra/fundamentals/how-subscriptions-associated-directory) for more information.
* Identify the owner of the Azure subscription to be used to provision Azure Sandbox. This user should have an [Owner](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#owner) Azure RBAC role assignment on the subscription. See [Steps to assign an Azure role](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-steps) for more information.

### Azure RBAC Role Assignments

* Ask the subscription owner to create an [Owner](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#owner) Azure RBAC role assignment for each sandbox user. See [Steps to assign an Azure role](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-steps) for more information.

### Service Principal

* Verify the subscription owner has privileges to create a service principal on the Microsoft Entra tenant. See [Permissions required for registering an app](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal#permissions-required-for-registering-an-app) for more information.
* Ask the subscription owner to [Create an Azure service principal](https://learn.microsoft.com/en-us/cli/azure/azure-cli-sp-tutorial-1?tabs=bash) (SPN) for sandbox users with [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart). The service principal can be created with the following command:

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

### Other Prerequisites

* Some Azure subscriptions may have low quota limits for specific Azure resources which may cause sandbox deployments to fail. See [Resolve errors for resource quotas](https://learn.microsoft.com/azure/azure-resource-manager/templates/error-resource-quota) for more information.
* Some Azure subscriptions may not have the required resource providers registered. Terraform is configured to automatically register the required resource providers, but this may take some time on first use.
* Some Azure subscriptions may not have the required features enabled, such has host encryption for virtual machines. Monitor your plan application for errors related to specific subscription features and enable them as needed.
* Some organizations may institute [Azure policy](https://learn.microsoft.com/azure/governance/policy/overview) which may cause some sandbox deployments to fail. This can be addressed by using custom settings which pass the policy checks, or by disabling the policies on the Azure subscription being used for the configurations.

### Terraform Execution Environment

#### Interactive Execution

A variety of Terraform execution environments can be used to provision Azure Sandbox interactively, including:

* **Windows-Only Client**: A Windows-only client can be used to run Terraform. The following software should be installed:
  * git
  * PowerShell 7.x
  * Az PowerShell Module
  * Terraform
  * Visual Studio Code

* **Windows Subsystem for Linux (WSL) Client**: WSL offers the best of Windows and Linux in the same client environment and was used to develop this project. The following software should be installed:
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

* **Linux / MacOs Client**: A Linux or MacOS client can be used to run Terraform. The following software should be installed:
  * git
  * Azure CLI
  * PowerShell 7.x
  * Az PowerShell Module
  * Terraform
  * Visual Studio Code

* **Azure Virtual Machine**: An Azure virtual machine (Windows or Linux) can be used to run Terraform. This may be your only option if your client device is managed by strict corporate security policies that restrict developer use cases. See [rg-devops-iac](./extras/configurations/rg-devops-iac/) in extras for a complete configuration that can be used as a Terraform execution environment, either interactive or automated as part of a DevOps pipeline. This configuration has been tested as a Linux Terraform execution environment for Azure Sandbox. If you build your own Azure Virtual Machine to use as a Terraform execution environment, the following software should be installed:
  * git
  * Azure CLI
  * PowerShell 7.x
  * Az PowerShell Module
  * Terraform
  
* **Azure Cloud Shell**: Azure Cloud Shell is not recommended but can be used. Most of the software dependencies are pre-installed.

* **GitHub Codespaces**: GitHub Codespaces has not been tested but should be okay. Most of the software dependencies should be pre-installed.

#### Automated Execution

Azure DevOps, GitHub Actions, or other CI/CD tools can be used to automate the deployment of Azure Sandbox. The following software should be installed in your Terraform execution environment:

* git
* PowerShell 7.x
* Az PowerShell Module
* Terraform

## Getting Started (Interactive Execution)

This section covers the steps to get started with Azure Sandbox using an interactive Terraform execution environment. The steps include logging into Azure, cloning the repository, initializing Terraform, configuring variables, validating and applying the configuration, and smoke testing.

* [Step 0: Login](#step-0-login)
* [Step 1: Clone the Repository](#step-1-clone-the-repository)
* [Step 2: Initialize Terraform](#step-2-initialize-terraform)
* [Step 3: Configure Variables](#step-3-configure-variables)
* [Step 4: Validate and Apply Configuration](#step-4-validate-and-apply-configuration)
* [Step 5: Complete Smoke Testing](#step-5-complete-smoke-testing)
* [Step 6: Use Your Sandbox](#step-6-use-your-sandbox)
* [Step 7: Clean Up](#step-7-clean-up)

### Step 0: Login

Before you can provision an Azure Sandbox interactively, you need to log in to your Azure account. Use the following steps to log in

* Open a terminal window and run one of the following commands to log in to Azure according to your preference:

  ```bash
  # Log in using Azure CLI
  az login --use-device-code
  ```

  ```pwsh
  # Log in using PowerShell
  Connect-AzAccount -UseDeviceAuthentication
  ```

* Check the terminal for a message like this:

  ```text
  To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code XXXXXXXXX to authenticate.
  ```

* Open a browser and navigate to the URL provided in the terminal. Enter the code displayed in the terminal to authenticate your Azure account.
* Sign in with an account that has an Azure RBAC `Owner` role assignment on the subscription you will be using to provision the sandbox.
* Depending upon how your Entra ID tenant is configured, you may be prompted to enter your password and/or approve a sign-in request on your mobile device.
* Click **Continue** when asked if you are trying to sign in to Azure.
* Check the terminal for a prompt like this:

  ```text
  Retrieving tenants and subscriptions for the selection...

  [Tenant and subscription selection]

  No     Subscription name               Subscription ID                       Tenant
  -----  ------------------------------  ------------------------------------  ----------------
  [1] *  SUBSCRIPTION1-NAME-HERE         SUBSCRIPTION1-ID-HERE                 TENANT-NAME-HERE
  [2]    SUBSCRIPTION2-NAME-HERE         SUBSCRIPTION2-ID-HERE                 TENANT-NAME-HERE

  The default is marked with an *; the default tenant is 'TENANT-NAME-HERE' and subscription is 'SUBSCRIPTION1-NAME-HERE' (SUBSCRIPTION1-ID-HERE).

  Select a subscription and tenant (Type a number or Enter for no changes):
  ```

* Select the subscription you will be using to provision the sandbox by entering the number next to it. If you only have one subscription, just press Enter.

### Step 1: Clone the Repository

Clone the Azure Sandbox repository to your local machine using the following command:

```bash
git clone https://github.com/Azure-Samples/azuresandbox
```

### Step 2: Initialize Terraform

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

After cloning the repository, navigate to the `azuresandbox` directory and initialize Terraform. This step downloads the necessary provider plugins and modules.

```bash
cd azuresandbox
terraform init
```

### Step 3: Configure Variables

There are hundreds of variables in this configuration. Defaults have been set for most of them so only a few need to be set in advance to provision a sandbox. There are a few different ways to set variables in Terraform.

* **Environment Variables**: Set environment variables for sensitive information such as passwords and secrets used in the root module.
* **terraform.tfvars file**: Create a `terraform.tfvars` file in the root directory of the project to set variables for the root module.
* **main.tf file**: Override module default values in the `main.tf` file by customizing the module blocks.

Follow these steps to configure the variables for your sandbox:

* First, create an environment variable for the service principal password. For security reasons this secret should not be stored in the `terraform.tfvars` file.

  ```bash
  # Set environment variable in bash
  export TF_VAR_arm_client_secret=<service-principal-password-here>
  ```

  ```pwsh
  # Set environment variable in PowerShell
  $env:TF_VAR_arm_client_secret = "<service-principal-password-here>"
  ```

* Next, create a `terraform.tfvars` file in the root directory of the project. This file should set the necessary variables for your deployment. Here is an example of what the `terraform.tfvars` file might look like:

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
  # Bash bootstrap script, run from the root directory of the project
  ./scripts/bootstrap.sh
  ```

  ```pwsh
  # PowerShell bootstrap script, run from the root directory of the project
  ./scripts/bootstrap.ps1
  ```

#### **Enable Modules**

By default only the shared virtual network module (vnet-shared) is enabled which isn't very useful on it's own. You can enable additional modules by setting the `enable_module_*` variables in the `terraform.tfvars` file. At a minimum you should enable the application virtual network module (vnet-app) like this:

```hcl
aad_tenant_id   = "<entra-tenant-id-here>"
arm_client_id   = "<service-principal-app-id-here>"
location        = "<azure-region-here>"
subscription_id = "<azure-subscription-id-here>"
user_object_id  = "<user-object-id-here>"

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
aad_tenant_id   = "<entra-tenant-id-here>"
arm_client_id   = "<service-principal-app-id-here>"
location        = "<azure-region-here>"
subscription_id = "<azure-subscription-id-here>"
user_object_id  = "<user-object-id-here>"

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

#### **Overriding Defaults**

The variable defaults set in each module can be overridden by customizing the appropriate module block in `main.tf`. For example, the default value for the `vm_adds_name` variable in the vnet-shared module is `adds1`. You can override this value by adding the following to the vnet-shared module block in `main.tf`:

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

Remember that Terraform will compare the state of existing resources in Azure with what it expects to be there when creating a plan. If the state of existing resources in Azure does not match what Terraform expects, the plan will modify existing resources to match the configuration. This can happen when resources are modified manually or via Policy outside of Terraform. This is known as "drift".

**WARNING:** This configuration uses Terraform provisioners and Azure custom script extensions which increase the chance of transient errors during plan application. Addressing errors may require any of the following actions:

* An existing Azure resource may need to be manually deleted.
* An Azure resource may need to be manually removed from Terraform state (see `terraform state rm` command).
* An existing Azure resource may need to be imported into Terraform state (see `terraform import` command).

Once the error has been addressed, you can re-run the `terraform apply` command to continue provisioning the sandbox. Terraform will pick up where it left off.

Follow these steps to validate and apply the configuration:

* First, validate that the configuration is syntactically correct:

  ```bash
  terraform validate
  ```

* Next, create a plan to see what resources will be created:

  ```bash
  terraform plan
  ```

  * If you are provisioning a brand new sandbox, you will see a lot of `+` signs in the output. This indicates that new resources will be created if this plan is applied. If you are updating an existing sandbox, you may see `~` signs indicating that existing resources will be updated. If you see `-` signs, this indicates that existing resources will be deleted. Be careful with these operations as they may cause data loss.

  * Public access is disabled by design for the Azure Storage account in the sandbox. This may cause errors during plan creation because your Terraform execution environment is blocked by the storage firewall. To work around this you can manually modify the storage firewall using a couple of different approaches:

    * Add the client ip for your Terraform execution environment to the storage firewall whitelist. This should work from most home networks, but will not work on a private network that implements source network address translation (SNAT).
    * Temporarily enable public network access on the storage account outside of Terraform.

  * Be sure to check that storage firewall public access is disabled again after you are done with Terraform operations.

* Finally, apply the configuration to create the resources:

  ```bash
  terraform apply
  ```

* Monitor the progress of the apply operation in the console. If errors occur, that may not be reflected in the console immediately. Terraform will try to apply as much of the plan as possible first, then will show the errors when it is done. It can take up to 90 minutes to provision a sandbox depending upon which modules you choose to enable. If everything goes well you should see a message like this:

  ```text
  Apply complete! Resources: XX added, XX changed, XX destroyed.
  ```

### Step 5: Complete Smoke Testing

After the sandbox has been provisioned, complete the smoke testing procedures specific to each module. This will ensure that the resources are functioning as expected and that the configuration is correct. You can find smoke testing guidance in the *README.md* files in each module directory. The smoke testing procedures are designed to be simple and quick, allowing you to verify the functionality of the deployed resources without extensive testing. Start with the *vnet-shared* module and work your way through the other modules as needed. See [Child Modules](#child-modules) for a list of modules included in the configuration.

### Step 6: Use Your Sandbox

You now have a fully provisioned Azure Sandbox environment! You can use it for experimentation, learning, development or testing purposes. Feel free to explore the additional resources and configurations available for your sandbox.

### Step 7: Clean Up

Don't forget to delete your sandbox when you're done. You don't want to have to explain to your boss why you left an unused sandbox laying around that costs your company money. The quickest way to clean up is to delete the sandbox resource group. 

**IMPORTANT:** Do this with care because data loss will occur.

## Documentation

This section provides documentation regarding the overall structure of the repository and the root module. See the README.md files in each module directory for more information about that module.

* [Root Module Structure](#root-module-structure)
* [Root Module Input Variables](#root-module-input-variables)
* [Root Module Resources](#root-module-resources)
* [Root Module Output Variables](#root-module-output-variables)
* [Child Modules](#child-modules)
* [Virtual Network Design](#virtual-network-design)
* [Dependencies](#dependencies)
* [Additional Resources](#additional-resources)

### Root Module Structure

The Azure Sandbox project is organized into the following structure:

```plaintext
├── extras/                     # Extend your sandbox with extra modules and configurations
│   ├── configurations/         # 
│   └── modules/                # 
├── images/                     # 
│   └── azuresandbox.drawio.svg # Architecture diagram
├── modules/                    # 
│   ├── mssql/                  # Azure SQL Database module
│   ├── mysql/                  # Azure Database for MySQL module
│   ├── vm-jumpbox-linux/       # Linux jumpbox virtual machine module
│   ├── vm-msssql-win/          # SQL Server virtual machine module
│   ├── vnet-app/               # Application virtual network module
│   ├── vnet-shared/            # Shared services virtual network module
│   └── vwan/                   # Point-to-site VPN module
├── scripts/                    # 
│   ├── bootstrap.sh            # Bash helper script for generating terraform.tfvars
│   └── bootstrap.ps1           # PowerShell helper script for generating terraform.tfvars
├── locals.tf                   # Local variables 
├── main.tf                     # Resource configurations
├── outputs.tf                  # Output variables 
├── providers.tf                # Provider configuration blocks
├── terraform.tf                # Terraform configuration block
└── variables.tf                # Variable definitions
```

---

### Root Module Input Variables

This section lists input variables used in the root module. Defaults can be overridden by specifying a different value in terraform.tfvars.

Variable | Default | Description
--- | --- | ---
aad_tenant_id | | The Microsoft Entra tenant id.
arm_client_id | | The AppId of the service principal used for authenticating with Azure. Must have an `Owner` role assignment scoped to the subscription.
arm_client_secret | | The password for the service principal used for authenticating with Azure. Set interactively or using an environment variable 'TF_VAR_arm_client_secret'.
enable_module_mssql | false | Set to true to enable the Azure SQL Database (mssql) module, false to skip it.
enable_module_mysql | false | Set to true to enable the Azure Database for MySQL (mysql) module, false to skip it.
enable_module_vm_jumpbox_linux | false | Set to true to enable the vm_jumpbox_linux module, false to skip it.
enable_module_vm_mssql_win | false | Set to true to enable the vm_mssql_win module, false to skip it.
enable_module_vnet_app | false | Set to true to enable the vnet_app module, false to skip it.
enable_module_vwan | false | Set to true to enable the vwan module, false to skip it.
location | | The name of the Azure Region where resources will be provisioned.
subscription_id | | The Azure subscription id used to provision sandbox resources.
tags | { costcenter = "mycostcenter", environment = "dev", project = "sand" } | Tags in map format to be applied to the sandbox resource group and used for resource naming.
user_object_id | | The object id of the interactive user (e.g. Azure CLI or Az PowerShell signed in user).

---

### Root Module Resources

The root module includes a resource group.

Address | Name | Notes
--- | --- | ---
azurerm_resource_group.this | rg&#8209;sand&#8209;dev&#8209;xxxxxxxx | Resource group for the sandbox environment.

---

### Root Module Output Variables

This section includes a list of output variables returned by the root module.

Name | Comments
--- | ---
client_cert_pem | The client certificate in PEM format for use with point-to-site VPN clients.
resource_ids | A map of resource IDs for key resources in the configuration.
resource_names | A map of resource names for key resources in the configuration.
root_cert_pem | The root certificate in PEM format for use with point-to-site VPN clients.

---

### Child Modules

The following [modules](./modules/) are included in this configuration:

Name | Required | Depends On | Description
--- | --- | --- | ---
[vnet-shared](./modules/vnet-shared/) | Yes | Root module | Includes a shared services virtual network including a Bastion Host, Azure Firewall, Key Vault, Log Analytics Workspace and an AD domain controller/DNS server VM.
[vnet-app](./modules/vnet-app/) | No | vnet-shared module | Includes an application virtual network, a network isolated Azure Files share and a preconfigured Windows jumpbox VM.
[vm-jumpbox-linux](./modules/vm-jumpbox-linux/) | No | vnet-app module | Creates a preconfigured Linux jumpbox VM in the application virtual network.
[vm-mssql-win](./modules/vm-mssql-win/) | No | vnet-app module | Creates a preconfigured SQL Server VM in the application virtual network.
[mssql](./modules/mssql/) | No | vnet-app module | Creates a network isolated Azure SQL Database in the application virtual network.
[mysql](./modules/mysql/) | No | vnet-app module | Creates a network isolated Azure MySQL Database in the application virtual network.
[vwan](./modules/vwan/) | No | vnet-app module | Creates a Point-to-Site VPN gateway to securely connect to your sandbox environment from your local machine.

---

### Virtual Network Design

The Azure Sandbox project uses a structured IPv4 address scheme to ensure proper segmentation and isolation of resources within the virtual networks and subnets. The following sections describe the IP address ranges and their usage in the *vnet-shared* and *vnet-app* virtual networks. Minimum prefix lengths are provided for each virtual network and subnet to allow for customization if you need to adapt the IP address scheme to your own requirements. Note the default CIDR ranges used are intentionally large for readability and can easily be condensed. Network security groups (NSGs) are also configured for each subnet to control inbound and outbound traffic.

* [Shared Services Virtual Network](#shared-services-virtual-network)
* [Application Virtual Network](#application-virtual-network)
* [Virtual Network Peering](#virtual-network-peering)
* [Routing and Security](#routing-and-security)
* [Secure VPN Access](#secure-vpn-access)

#### **Shared Services Virtual Network**

The shared services virtual network (vnet-shared) is used to host common services that are shared across the sandbox environment, including a domain controllers / DNS server VM, bastions host and firewall.

Setting | Value | Notes
--- | --- | ---
Default CIDR | `10.1.0.0/16` | Min prefix length is `/24`
Primary DNS Server | `10.1.1.4` | Private IP domain controller VM
Secondary DNS Server | `168.63.129.16` | Azure Recursive DNS Resolver

The following subnets are configured in *vnet-shared*:

Subnet Name | Default CIDR | Min prefix length | NSG | Purpose
--- | --- | --- | --- | ---
AzureBastionSubnet | `10.1.0.0/27` | `/27` | Yes | Reserved for Azure Bastion to provide secure RDP/SSH access to virtual machines.
snet-adds-01 | `10.1.1.0/24` | `/27` | Yes | Hosts the Active Directory Domain Services (AD DS) domain controller and DNS server.
snet-misc-01 | `10.1.2.0/24` | `/27` | Yes | Reserved for optional configurations requiring connectivity in the shared virtual network.
snet-misc-02 | `10.1.3.0/24` | `/27` | Yes | Reserved for optional configurations requiring connectivity in the shared virtual network.
AzureFirewallSubnet | `10.1.4.0/26` | `/26` | No | Reserved for Azure Firewall to provide network security.
snet-privatelink-02 | `10.1.5.0/24` | `/27` | Yes | Reserved for private endpoints using Azure Private Link.

The following private endpoints are configured in the *snet-privatelink-02* subnet to provide secure, network-isolated access to the following Azure PaaS services:

Service | Module
--- | ---
Key Vault | vnet-shared

#### **Application Virtual Network**

The application virtual network (vnet-app) is used to host application-specific resources, such as virtual machines, databases, and private endpoints. The virtual network is configured as follows:

Setting | Value | Notes
--- | --- | ---
Default CIDR | `10.2.0.0/16` | Min prefix length is `/24`
Primary DNS Server | `10.1.1.4` | Private IP domain controller VM in vnet-shared
Secondary DNS Server | `168.63.129.16` | Azure Recursive DNS Resolver

The following subnets are configured in *vnet-app*:

Subnet Name | Default CIDR | Min prefix length | NSG | Purpose
--- | --- | --- | --- | ---
snet-app-01 | `10.2.0.0/24` | `/27` | Yes | Reserved for web server, application server, and jumpbox VMs.
snet-db-01 | `10.2.1.0/24` | `/27` | Yes | Reserved for Database Server VMs.
snet-privatelink-01 | `10.2.2.0/24` | `/27` | Yes |Reserved for private endpoints using Azure Private Link.
snet-misc-03 | `10.2.3.0/24` | `/27` | Yes | Reserved for future use.
snet-appservice-01 | `10.2.4.0/24` | `/27` | Yes | Reserved for Azure App Service with delegation to `Microsoft.Web/serverFarms`.

The following private endpoints are configured in the *snet-privatelink-01* subnet to provide secure, network-isolated access to the following Azure PaaS services:

Service | Module
--- | ---
Azure Blob Storage | vnet-app
Azure Files | vnet-app
Azure SQL Database | mssql
Azure Database for MySQL | mysql

#### **Virtual Network Peering**

Bi-directional virtual network peering is enabled between the virtual networks in *vnet-shared* and *vnet-app* to allow network connectivity between resources in both virtual networks.

#### **Routing and Security**

* **Azure Firewall**: Configured in the dedicated *AzureFirewallSubnet* of *vnet-shared* to provide secure outbound internet access and threat intelligence.
* **Route Tables**: A custom route table is used to direct traffic through the Azure Firewall for secure internet access. The route table sets the next hop for the default route to go to Azure Firewall for all sandbox subnets except those used for the Firewall itself and for Azure Bastion.
* **Network Security Groups (NSGs)**: Associated with each subnet to control inbound and outbound traffic based on security rules.

#### **Secure VPN Access**

The optional *vwan* module implements an Azure Virtual WAN point-to-site VPN gateway for secure remote connectivity to your sandbox environment from a remote computer. This is ideal for scenarios where access via Bastion is not sufficient, for example if you need to transfer data into your sandbox environment or use tools that are only available on a remote computer. A self-signed certificate is used for authentication. The virtual WAN hub is connected to both the *vnet-shared* and *vnet-app* virtual networks, allowing secure VPN access to resources in your sandbox environment.

The following address ranges are used for the point-to-site VPN gateway:

Name | Default CIDR | Min prefix length | Purpose
--- | --- | --- | ---
vwan_hub_address_prefix | `10.3.0.0/16` | `/24` | Address range for the Azure Virtual WAN Hub.
client_address_pool | `10.4.0.0/16` | `/27` | Address range for VPN clients connecting to the point-to-site VPN gateway.

---

### Dependencies

This section covers the dependencies in this configuration.

* [Source Control](#source-control)
* [Terraform](#terraform)
* [Scripting Technologies](#scripting-technologies)
* [Configuration Management Technologies](#configuration-management-technologies)
* [Operating Systems](#operating-systems)

#### **Source Control**

The configuration is hosted on GitHub and uses Git for source control. The repository includes a *.gitignore* file to exclude sensitive information and temporary files from being tracked by Git. The repository is organized into modules and configurations, making it easy to navigate and understand the structure of the project.

#### **Terraform**

Sandbox environments are built using Terraform, a cross platform, open-source Infrastructure as Code (IaC) tool that allows users to define, provision and version cloud infrastructure using a declarative configuration language called HCL (HashiCorp Configuration Language).

* **Providers**: The following Terraform providers are used in the project:
  * **azapi**: Used to manage Azure resources that are not yet supported by the azurerm provider and for direct access to Azure APIs.
  * **azurerm**: Used to manage Azure resources.
  * **cloudinit**: Used to configure Linux virtual machines.
  * **null**: Used to implement provisioners and other operations that do not require a specific resource.
  * **random**: Used to generate random values for resource attributes.
  * **time**: Used to implement wait cycles and other time based operations.
  * **tls**: Used to generate certificates.
* **Modules**: The following Terraform modules are used in this project:
  * **Azure/naming**: A module for generating consistent and compliant Azure resource names.

#### **Scripting Technologies**

The following cross-platform scripting technologies are used in this project:

* **PowerShell**:  Used for general purpose scripting and to implement Terraform provisioners and Azure custom script extensions.
* **Az PowerShell Module**: Used to connect to and configure Azure resources from PowerShell scripts.
* **Bash**: Used for general purpose scripting.
* **Azure CLI**: Used for connecting to Azure resources from Bash scripts.

#### **Configuration Management Technologies**

The following configuration management technologies are used in this project to configure virtual machines:

* **PowerShell DSC**: PowerShell Desired State Configuration is used to configure Windows virtual machines.
* **Azure Automation DSC**: Used to configure Windows virtual machines using configurations written in PowerShell DSC.
* **cloud-init**: Used to configure Linux virtual machines.

#### **Operating Systems**

The following operating systems are used for the various virtual machines in the sandbox:

Virtual Machine | Role | Module | Operating System
--- | --- | --- | ---
adds1 | AD DS Domain Controller / DNS Server | vnet-shared | Windows Server 2025 Datacenter Azure Edition Core
jumpwin1 | Windows Jumpbox VM | vnet-app | Windows Server 2025 Datacenter Azure Edition
mssqlwin1 | Windows SQL Server VM | vm-mssql-win | Windows Server 2022 / SQL Server 2022 Developer Edition
jumplinux1 | Linux Jumpbox VM | vm-jumpbox-linux | Ubuntu Server LTS 24.04 (Nobel Numbat)

---

### Additional Resources

See [extras](./extras/) for other modules and configurations that can be used to extend your sandbox. Links to videos and other learning resources are also included.
