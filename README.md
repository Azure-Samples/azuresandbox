# #AzureSandbox

## Contents

* [Architecture](#architecture)
* [Overview](#overview)
* [Sandbox index](#sandbox-index)
* [Prerequisites](#prerequisites)
* [Getting started](#getting-started)
* [Next steps](#next-steps)
* [Videos](#videos)
* [Known issues](#known-issues)

## Architecture

![diagram](./diagram.drawio.svg)

## Overview

This repository contains a collection of inter-dependent [cloud computing](https://azure.microsoft.com/overview/what-is-cloud-computing) configurations for implementing common [Microsoft Azure](https://azure.microsoft.com/overview/what-is-azure/) services on a single [subscription](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#subscription). Collectively these configurations provide a flexible and cost effective sandbox environment useful for experimenting with various Azure services and capabilities. Depending upon your Azure offer type and region, a fully provisioned #AzureSandbox environment costs approximately $50 USD / day. These costs can be further reduced by stopping / deallocating virtual machines when not in use, or by skipping optional configurations that you do not plan to use ([Step-By-Step Video](https://youtu.be/2TN4SEq4wzM)).

*Disclaimer:* #AzureSandbox is not intended for production use. While some best practices are used, others are intentionally not used in favor of simplicity and cost. See [Known issues](#known-issues) for more information.

\#AzureSandbox is implemented using popular open source tools that are supported on Windows, macOS and Linux including:

* [git](https://git-scm.com/) for source control.
* [Bash](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) for scripting.
* [Azure CLI](https://learn.microsoft.com/cli/azure/what-is-azure-cli?view=azure-cli-latest) is a command line interface for Azure.
* [PowerShell](https://learn.microsoft.com/powershell/scripting/overview?view=powershell-7.1)
  * [PowerShell Core](https://learn.microsoft.com/powershell/scripting/whats-new/what-s-new-in-powershell-71?view=powershell-7.1)
  * [PowerShell 5.1](https://learn.microsoft.com/powershell/scripting/overview?view=powershell-5.1) for Windows Server configuration.
* [Terraform](https://www.terraform.io/intro/index.html#what-is-terraform-) v1.7.4 for [Infrastructure as Code](https://en.wikipedia.org/wiki/Infrastructure_as_code) (IaC).
  * [Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) (azuerrm) v3.95.0
  * [cloud-init Provider](https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs) (cloudinit) v2.3.3
  * [Random Provider](https://registry.terraform.io/providers/hashicorp/random/latest/docs) (random) v3.6.0

This repo was created by [Roger Doherty](https://www.linkedin.com/in/roger-doherty-805635b/).

## Sandbox index

\#AzureSandbox features a modular design and can be deployed as a whole or incrementally depending upon your requirements.

* [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) includes the following:
  * A [resource group](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#resource-group) which contains all the sandbox resources.
  * A [key vault](https://learn.microsoft.com/azure/key-vault/general/overview) for managing secrets.
  * A [log analytics workspace](https://learn.microsoft.com/azure/azure-monitor/data-platform#collect-monitoring-data) for log data and metrics.
  * A [storage account](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#storage-account) for blob storage.
  * An [automation account](https://learn.microsoft.com/azure/automation/automation-intro) for configuration management.
  * A [virtual network](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vnet) for hosting [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm).
  * A [bastion](https://learn.microsoft.com/azure/bastion/bastion-overview) for secure RDP and SSH access to virtual machines.
  * A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) running [Active Directory Domain Services](https://learn.microsoft.com/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) with a pre-configured domain and DNS server.
* [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/) includes the following:
  * A [virtual network](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vnet) for hosting [virtual machines](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) and private endpoints implemented using [PrivateLink](https://learn.microsoft.com/azure/private-link/private-link-overview) and [subnet delegation](https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview). [Virtual network peering](https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview) with [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) is automatically configured.
  * A Windows Server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
  * A Linux [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) for use as a DevOps agent.
  * A [PaaS](https://azure.microsoft.com/overview/what-is-paas/) SMB file share hosted in [Azure Files](https://learn.microsoft.com/azure/storage/files/storage-files-introduction) with a private endpoint implemented using [PrivateLink](https://learn.microsoft.com/azure/storage/common/storage-private-endpoints).
* [terraform-azurerm-vm-mssql](./terraform-azurerm-vm-mssql/) includes the following:
  * An [IaaS](https://azure.microsoft.com/overview/what-is-iaas/) database server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) based on the [SQL Server virtual machines in Azure](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/sql-server-on-azure-vm-iaas-what-is-overview#payasyougo) offering.
* [terraform-azurerm-msssql](./terraform-azurerm-mssql/) includes the following:
  * A [PaaS](https://azure.microsoft.com/overview/what-is-paas/) database hosted in [Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview) with a private endpoint implemented using [PrivateLink](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview).
* [terraform-azurerm-mysql](./terraform-azurerm-mysql/) includes the following:
  * A [PaaS](https://azure.microsoft.com/overview/what-is-paas/) database hosted in [Azure Database for MySQL - Flexible Server](https://learn.microsoft.com/azure/mysql/flexible-server/overview) with a private endpoint implemented using [PrivateLink](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-networking-private-link).
* [terraform-azurerm-vwan](./terraform-azurerm-vwan/) includes the following:
  * A [virtual wan](https://learn.microsoft.com/azure/virtual-wan/virtual-wan-about#resources).
  * A [virtual wan hub](https://learn.microsoft.com/azure/virtual-wan/virtual-wan-about#resources) with pre-configured [hub virtual network connections](https://learn.microsoft.com/azure/virtual-wan/virtual-wan-about#resources) with [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) and [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/). The hub is also pre-configured for [User VPN (point-to-site) connections](https://learn.microsoft.com/azure/virtual-wan/virtual-wan-about#uservpn).
* [extras](./extras/README.md) contains additional Terraform configurations and supporting resources.

## Prerequisites

The following prerequisites are required in order to get started. Note that once these prerequisite are in place, a [Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#contributor) Azure RBAC role assignment is sufficient to use the configurations.

* Identify the [Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/fundamentals/whatis) tenant to be used for identity and access management, or create a new tenant using [Quickstart: Set up a tenant](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-create-new-tenant).
* Identify a single Azure [subscription](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#subscription) or create a new Azure subscription. See [Azure Offer Details](https://azure.microsoft.com/support/legal/offer-details/) and [Associate or add an Azure subscription to your Microsoft Entra tenant](https://learn.microsoft.com/entra/fundamentals/how-subscriptions-associated-directory) for more information.
* Identify the owner of the Azure subscription to be used for \#AzureSandbox. This user should have an [Owner](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#owner) Azure RBAC role assignment on the subscription. See [Steps to assign an Azure role](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-steps) for more information.
* Ask the subscription owner to create a [Contributor](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#contributor) Azure RBAC role assignment for each sandbox user. See [Steps to assign an Azure role](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-steps) for more information.
* Verify the subscription owner has privileges to create a Service principal name on the Microsoft Entra tenant. See [Permissions required for registering an app](https://learn.microsoft.com/en-us/entra/identity-platform/howto-create-service-principal-portal#permissions-required-for-registering-an-app) for more information.
* Ask the subscription owner to [Create an Azure service principal with Azure CLI](https://learn.microsoft.com/en-us/cli/azure/azure-cli-sp-tutorial-1?tabs=bash) (SPN) for sandbox users by running the following Azure CLI command in [Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart).

  ```bash
  # Replace 00000000-0000-0000-0000-000000000000 with the subscription id
  az ad sp create-for-rbac -n AzureSandboxSPN --role Contributor --scopes /subscriptions/00000000-0000-0000-0000-000000000000
  ```

  Securely share the output with sandbox users, including *appId* and *password*:

  ```json
  {
    "appId": "00000000-0000-0000-0000-000000000000",
    "displayName": "AzureSandboxSPN",
    "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "tenant": "00000000-0000-0000-0000-000000000000"
  }
  ```

* Some organizations may institute [Azure policy](https://learn.microsoft.com/azure/governance/policy/overview) which may cause some sandbox deployments to fail. This can be addressed by using custom settings which pass the policy checks, or by disabling the policies on the Azure subscription being used for the configurations.
* Some Azure subscriptions may have low quota limits for specific Azure resources which may cause sandbox deployments to fail. See [Resolve errors for resource quotas](https://learn.microsoft.com/azure/azure-resource-manager/templates/error-resource-quota) for more information. Consult the following table to determine if quota increases are required to deploy the configurations using default settings:

Resource |  Quota required per deployment | Command
--- | :-: | ---
Public IP Addresses | ~2 | *az network list-usages*
Standard BS Family vCPUs | ~5 | *az vm list-usage*
Standard Sku Public IP Addresses | ~2 | *az network list-usages*
Static Public IP Addresses  | ~2 | *az network list-usages*

*Note:* This list is not comprehensive. Quotas vary by Azure subscription offer type and environment. More than one quota may need to be increased for a single resource type, such as [public ip addresses](https://learn.microsoft.com/azure/virtual-network/public-ip-addresses).

## Getting started

Before you begin, familiarity with the following topics will be helpful when working with \#AzureSandbox:

* Familiarize yourself with Terraform [Input Variables](https://www.terraform.io/docs/configuration/variables.html)  
* Familiarize yourself with Terraform [Output Values](https://www.terraform.io/docs/configuration/outputs.html) also referred to as *Output Variables*
* See [Authenticating to Azure using a Service Principal and a Client Secret](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret) to understand the type of authentication used by Terraform in \#AzureSandbox
* Familiarize yourself with [Recommended naming and tagging conventions](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)
* Familiarize yourself with [Naming rules and restrictions for Azure resources](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-name-rules)

### Configure client environment

---

\#AzureSandbox automation scripts are written in Linux [Bash](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) and Linux [PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.3). In order to deploy \#AzureSandbox you will need to configure a Linux client environment to execute these scripts. Detailed guidance is provided for users who are unfamiliar with Linux. Three different client environment options are described in this section, including:

* [Windows Subsystem for Linux](#windows-subsystem-for-linux) (preferred for completing smoke testing)
* [Azure Cloud Shell](#azure-cloud-shell) (zero configuration required but not optimal for serious use)
* [Linux / MacOS](#linux--macos)

#### Windows Subsystem for Linux

Windows users can use [WSL](https://learn.microsoft.com/windows/wsl/about) which supports a [variety of Linux distributions](https://learn.microsoft.com/en-us/windows/wsl/basic-commands#list-available-linux-distributions). The current default distribution `Ubuntu 22.04 LTS (Jammy Jellyfish)` is recommended. Please note these instructions may vary for different Linux releases and/or distributions.

* Windows prerequisites ([Step-By-Step Video](https://youtu.be/Q4dOoQspt90))
  * Install [Visual Studio Code on Windows](https://code.visualstudio.com/docs/setup/windows)
  * Optional Windows software
    * Install [SQL Server Management Studio with Azure Data Studio](https://learn.microsoft.com/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-ver15) if you plan to complete smoke testing for either [terraform-azurerm-vm-mssql](./terraform-azurerm-vm-mssql/) or [terraform-azurerm-mssql](./terraform-azurerm-mssql/).
    * Install [MySQL Workbench](https://www.mysql.com/products/workbench/) if you plan to complete smoke testing for [terraform-azurerm-mysql](./terraform-azurerm-mysql/)
    * Install [Azure VPN Client](https://www.microsoft.com/store/productId/9NP355QT2SQB) if you plan to complete smoke testing for [terraform-azurerm-vwan](./terraform-azurerm-vwan/).
* Linux prerequisites ([Step-By-Step Video](https://youtu.be/YW37uG0aX8c))
  * [Install Linux on Windows with WSL](https://learn.microsoft.com/windows/wsl/install). The current default distribution `Ubuntu 22.04 LTS (Jammy Jellyfish)` is recommended.
  * Install [pip3](https://pip.pypa.io/en/stable/) Python library package manager and the [PyJWT](https://pyjwt.readthedocs.io/en/latest/) Python library. This is used to determine the id of the security principal for the currently signed in Azure CLI user.
  
    ```bash
    # Install the must recent PyJWT Python library
    sudo apt update
    sudo apt install python3-pip
    pip3 install --upgrade pyjwt
    ```

  * [Install the Azure CLI on Linux | apt (Ubuntu, Debian)](https://learn.microsoft.com/cli/azure/install-azure-cli-linux?pivots=apt)
  * [Install Terraform | Linux | Ubuntu/Debian](https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform). Note: it is not necessary to complete the `Quick start tutorial`.
  * [Install PowerShell on Ubuntu](https://learn.microsoft.com/en-us/powershell/scripting/install/install-ubuntu?view=powershell-7.3)
    * Once PowerShell is installed follow these steps to configure it.

      ```bash
      # Download and execute PowerShell configuration script
      wget https://raw.githubusercontent.com/Azure-Samples/azuresandbox/main/configure-powershell.ps1
      chmod 755 configure-powershell.ps1
      sudo ./configure-powershell.ps1
      ```

* Configure VS Code for [Remote development in WSL](https://code.visualstudio.com/docs/remote/wsl-tutorial) ([Step-By-Step Video](https://youtu.be/01Qnw2r-SJE))
  * Launch VS Code
  * [Install WSL VS Code Extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl).
  * Install the [HashiCorp Terraform](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform) VS Code Extension in WSL.
  * Install the [PowerShell](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell) VS Code extension in WSL.

#### Azure Cloud Shell

[Azure Cloud Shell](https://aka.ms/cloudshell) is a free pre-configured cloud hosted container with a full complement of [tools](https://learn.microsoft.com/azure/cloud-shell/features#tools) needed to use \#AzureSandbox. This option will be preferred for users who do not wish to install any software and don't mind a web based command line user experience. Review the following content to get started:

* [Bash in Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/quickstart)
* [Persist files in Azure Cloud Shell](https://learn.microsoft.com/azure/cloud-shell/persisting-shell-storage)
* [Using the Azure Cloud Shell editor](https://learn.microsoft.com/azure/cloud-shell/using-cloud-shell-editor)

*Warning:* Cloud shell containers are ephemeral. Anything not saved in `~/clouddrive` will not be retained when your cloud shell session ends. Also, cloud shell sessions expire. This can interrupt a long running process.

#### Linux / macOS

Linux and macOS users can deploy the configurations natively by installing the following tools:

* [Azure CLI](https://learn.microsoft.com/cli/azure/what-is-azure-cli?view=azure-cli-latest)
  * Debian or Ubuntu: [Install Azure CLI with apt](https://learn.microsoft.com/cli/azure/install-azure-cli-apt?view=azure-cli-latest)
  * RHEL, Fedora or CentOS: [Install Azure CLI with yum](https://learn.microsoft.com/cli/azure/install-azure-cli-yum?view=azure-cli-latest)
  * openSUSE or SLES: [Install Azure CLI with zypper](https://learn.microsoft.com/cli/azure/install-azure-cli-zypper?view=azure-cli-latest)
  * [Install Azure CLI on macOS](https://learn.microsoft.com/cli/azure/install-azure-cli-macos?view=azure-cli-latest)
  * [Install Azure CLI on Linux manually](https://learn.microsoft.com/cli/azure/install-azure-cli-linux?view=azure-cli-latest)
* [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform)
  * Refer to the *Linux* tab then choose the corresponding tab for your distro if installing on Linux.
  * Refer to the *Homebrew on OS X* if installing on macOS.
  * Note: Skip the [Quick start tutorial](https://learn.hashicorp.com/tutorials/terraform/install-cli#quick-start-tutorial).
* [PowerShell](https://learn.microsoft.com/powershell/scripting/overview?view=powershell-7.1)
  * [Installing PowerShell on Linux](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7.1)
  * [Installing PowerShell on macOS](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-core-on-macos?view=powershell-7.1)
  * After installing, run [configure-powershell.ps1](./configure-powershell.ps1)
* [VS Code](https://aka.ms/vscode)
  * [Linux](https://code.visualstudio.com/docs/setup/linux)
  * [macOS](https://code.visualstudio.com/docs/setup/mac)
  * After installing, add the following extensions:
    * [Terraform](https://marketplace.visualstudio.com/items?itemName=mauve.terraform)
* Miscellaneous packages
  * [pip3](https://pip.pypa.io/en/stable/) Python library package manager.
  * [PyJWT](https://pyjwt.readthedocs.io/en/latest/) Python library. This is used to determine the id of the security principal for the currently signed in Azure CLI user.

Note the Bash scripts used in the configurations were developed and tested using *GNU bash, version 5.0.17(1)-release (x86_64-pc-linux-gnu)* and have not been tested on other popular shells like [zsh](https://www.zsh.org/).

## Next steps

Now that the client environment has been configured, here's how to clone a copy of this repo and start working with the latest release of code ([Step-By-Step Video](https://youtu.be/EtNrzs4ZCvM)).

```bash
# Run this command on cloudshell clients only
cd clouddrive

# Run these commands on all clients, including cloudshell 
git clone https://github.com/Azure-Samples/azuresandbox
cd azuresandbox
latestTag=$(git describe --tags $(git rev-list --tags --max-count=1))
git checkout $latestTag
```

### Perform default sandbox deployment

---

For the first deployment, the author recommends using defaults, which is ideal for speed, learning and testing. IP address ranges are expressed using [CIDR notation](https://en.wikipedia.org/wiki/Classless_Inter-Domain_Routing#CIDR_notation).

#### Default IP address ranges

The configurations use default IP address ranges for networking components. These ranges are artificially large and contiguous for simplicity, and customized IP address ranges can be much smaller. A suggested minimum is provided to assist in making the conversion. It's a good idea to start small. Additional IP address ranges can be added to the networking configuration in the future if you need them, but you can't modify an existing IP address range to make it smaller.

Address range | CIDR | First | Last | IP address count | Suggested minimum range
--- |--- | --- | --- | --: | ---
Reserved for private network | 10.0.0.0/16 | 10.0.0.0 | 10.0.255.255 | 65,536 | N/A
Default sandbox aggregate | 10.1.0.0/13 | 10.1.0.0 | 10.7.255.255 | 524,288 | /22 (1024 IP addresses)
Shared services virtual network | 10.1.0.0/16 | 10.1.0.0 | 10.1.255.255 | 65,536 | /24 (256 IP addresses)
Application virtual network | 10.2.0.0/16 | 10.2.0.0 | 10.2.255.255 | 65,536 | /24 (256 IP addresses)
Virtual wan hub | 10.3.0.0/16 | 10.3.0.0 | 10.3.255.255 | 65,536 | /24 (256 IP addresses)
P2S client VPN connections | 10.4.0.0/16 | 10.4.0.0 | 10.4.255.255 | 65,536 | /24 (256 IP addresses)
Reserved for future use | 10.5.0.0/16 | 10.5.0.0 | 10.5.255.255 | 65,536 | N/A
Reserved for future use | 10.6.0.0/15 | 10.6.0.0 | 10.7.255.255 | 131,072 | N/A

##### Default subnet IP address prefixes

This section documents the default subnet IP address prefixes used in the configurations. Subnets enable you to segment the virtual network into one or more sub-networks and allocate a portion of the virtual network's address space to each subnet. You can then connect network resources to a specific subnet, and control ingress and egress using [network security groups](https://learn.microsoft.com/azure/virtual-network/security-overview).

Virtual network | Subnet | IP address prefix | First | Last | IP address count
--- | --- | --- | --- | --- | --:
Shared services | AzureBastionSubnet | 10.1.0.0/27 | 10.1.0.0 | 10.1.0.31 | 32
Shared services | Reserved for future use | 10.1.0.32/27 | 10.1.0.32 | 10.1.0.63 | 32
Shared services | Reserved for future use | 10.1.0.64/26 | 10.1.0.64 | 10.1.0.127 | 64
Shared services | Reserved for future use | 10.1.0.128/25 | 10.1.0.128 | 10.1.0.255 | 128
Shared services | snet-adds-01 | 10.1.1.0/24 | 10.1.1.0 | 10.1.1.255 | 256
Shared services | snet-misc-01 | 10.1.2.0/24 | 10.1.2.0 | 10.1.2.255 | 256
Shared services | snet-misc-02 | 10.1.3.0/24 | 10.1.3.0 | 10.1.3.255 | 256
Shared services | Reserved for future use | 10.1.4.0/22 | 10.1.4.0 | 10.1.7.255 | 1,024
Shared services | Reserved for future use | 10.1.8.0/21 | 10.1.8.0 | 10.1.15.255 | 2,048
Shared services | Reserved for future use | 10.1.16.0/20 | 10.1.16.0 | 10.1.31.255 | 4,096
Shared services | Reserved for future use | 10.1.32.0/19 | 10.1.32.0 | 10.1.63.255 | 8,192
Shared services | Reserved for future use | 10.1.64.0/18 | 10.1.64.0 | 10.1.127.255 | 16,384
Shared services | Reserved for future use | 10.1.128.0/17 | 10.1.128.0 | 10.1.255.255 | 32,768
Application | snet-app-01 | 10.2.0.0/24 | 10.2.0.0 | 10.2.0.255 | 256
Application | snet-db-01 | 10.2.1.0/24 | 10.2.1.0 | 10.2.1.255 | 256
Application | snet-privatelink-01 | 10.2.2.0/24 | 10.2.2.0 | 10.2.2.255 | 256
Application | snet-misc-03 | 10.2.3.0/24 | 10.2.3.0 | 10.2.3.255 | 256
Application | Reserved for future use | 10.2.4.0/22 | 10.2.4.0 | 10.2.7.255 | 1,024
Application | Reserved for future use | 10.2.8.0/21 | 10.2.8.0 | 10.2.15.255 | 2,048
Application | Reserved for future use | 10.2.16.0/20 | 10.2.16.0 | 10.2.31.255 | 4,096
Application | Reserved for future use | 10.2.32.0/19 | 10.2.32.0 | 10.2.63.255 | 8,192
Application | Reserved for future use | 10.2.64.0/18 | 10.2.64.0 | 10.2.127.255 | 16,384
Application | Reserved for future use | 10.2.128.0/17 | 10.2.128.0 | 10.2.255.255 | 32,768

#### Apply sandbox configurations

Apply the configurations in the following order:

1. [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) implements a virtual network with shared services used by all the configurations.
1. [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/) implements an application virtual network with pre-configured Windows Server and Linux jumpboxes.
1. [terraform-azurerm-vm-mssql](./terraform-azurerm-vm-mssql/) (optional) implements an [IaaS](https://azure.microsoft.com/overview/what-is-iaas/) database server [virtual machine](https://learn.microsoft.com/azure/azure-glossary-cloud-terminology#vm) based on the [SQL Server virtual machines in Azure](https://learn.microsoft.com/azure/azure-sql/virtual-machines/windows/sql-server-on-azure-vm-iaas-what-is-overview#payasyougo) offering.
1. [terraform-azurerm-mssql](./terraform-azurerm-mssql/) (optional) implements a [PaaS](https://azure.microsoft.com/overview/what-is-paas/) database hosted in [Azure SQL Database](https://learn.microsoft.com/azure/azure-sql/database/sql-database-paas-overview) with a private endpoint implemented using [PrivateLink](https://learn.microsoft.com/azure/azure-sql/database/private-endpoint-overview).
1. [terraform-azurerm-mysql](./terraform-azurerm-mysql/) (optional) implements a [PaaS](https://azure.microsoft.com/overview/what-is-paas/) database hosted in [Azure Database for MySQL - Flexible Server](https://learn.microsoft.com/azure/mysql/flexible-server/overview) with a private endpoint implemented using [subnet delegation](https://learn.microsoft.com/azure/virtual-network/subnet-delegation-overview).
1. [terraform-azurerm-vwan](./terraform-azurerm-vwan/) (optional) connects the shared services virtual network and the application virtual network to remote users or a private network.

#### Destroy sandbox configurations

While a default sandbox deployment is fine for testing, it may not work with an organization's private network. The default deployment should be destroyed first before doing a custom deployment. This is accomplished by running `terraform destroy` on each configuration in the reverse order in which it was deployed:

1. [terraform-azurerm-vwan](./terraform-azurerm-vwan/)
1. [terraform-azurerm-mysql](./terraform-azurerm-mysql/)
1. [terraform-azurerm-mssql](./terraform-azurerm-mssql/)
1. [terraform-azurerm-vm-mssql](./terraform-azurerm-vm-mssql/)
1. [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/)
1. [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/). Note: Resources provisioned by `bootstrap.sh` must be deleted manually.

Alternatively, for speed, simply delete rg-sandbox-01`. You can run [cleanterraformtemp.sh](./cleanterraformtemp.sh) to clean up temporary files and directories.

```bash
# Warning: This command will delete an entire resource group and should be used with great caution.
az group delete -g rg-sandbox-01
```

### Perform custom sandbox deployment

---

A custom deployment will likely be required to connect the configurations to an organization's private network. This section provides guidance on how to customize the configurations.

#### Document private network IP address ranges (sample)

Use this section to document one or more private network IP address ranges by consulting a network professional. This is required if you want to establish a [hybrid connection](https://learn.microsoft.com/azure/architecture/solution-ideas/articles/hybrid-connectivity) between an organization's private network and the configurations. The sandbox includes two IP address ranges used in a private network. The [CIDR to IPv4 Conversion](https://ipaddressguide.com/cidr) tool may be useful for completing this section.

IP address range | CIDR | First | Last | IP address count
--- | --- | --- | --- | --:
Primary range | 10.0.0.0/8 | 10.0.0.0 | 10.255.255.255 | 16,777,216
Secondary range | 162.44.0.0/16 | 162.44.0.0 | 162.44.255.255 | 65,536

A blank table is provided here for convenience. Make a copy of this table and change the *TBD* values to your custom values.

IP address range | CIDR | First | Last | IP address count
--- | --- | --- | --- | --:
Primary range | TBD | TBD | TBD | TBD
Secondary range | TBD | TBD | TBD | TBD

#### Customize IP address ranges (sandbox)

Use this section to customize the default IP address ranges used by the configurations to support routing on an organization's private network. The aggregate range should be determined by consulting a network professional, and will likely be allocated using a range that falls within the private network IP address ranges discussed previously, and the rest of the IP address ranges must be contained within it. The [CIDR to IPv4 Conversion](https://ipaddressguide.com/cidr) tool may be useful for completing this section. Note this sandbox uses the suggested minimum address ranges from the default IP address ranges described previously.

IP address range | CIDR | First | Last | IP address count
--- | --- | --- | --- | --:
Aggregate range | 10.73.8.0/22 | 10.73.8.0 | 10.73.11.255 | 1,024
Shared services virtual network | 10.73.8.0/24  | 10.73.8.0 | 10.73.8.255 | 256
Application virtual network | 10.73.9.0/24 | 10.73.9.0 | 10.73.9.255 | 256
Virtual wan hub | 10.73.10.0/24 | 10.73.10.0 | 10.73.10.255 | 256
P2S client VPN connections | 10.73.11.0/24 | 10.73.11.0 | 10.73.11.255 | 256

A blank table is provided here for convenience. Make a copy of this table and change the *TBD* values to your custom values.

IP address range | CIDR | First | Last | IP address count
--- | --- | --- | --- | --:
Aggregate range | TBD | TBD | TBD | TBD
Shared services virtual network | TBD  | TBD | TBD | TBD
Application virtual network | TBD | TBD | TBD | TBD
Virtual wan hub | TBD | TBD | TBD | TBD
P2S client VPN connections | TBD | TBD | TBD | TBD

##### Customize subnet IP address prefixes (sandbox)

Use this section to customize the default subnet IP address prefixes used by the configurations to support routing on an organization's private network. Make a copy of this table and change these sandbox values to custom values. Each address prefix must fall within the virtual network IP address ranges discussed previously. The [CIDR to IPv4 Conversion](https://ipaddressguide.com/cidr) tool may be useful for completing this section.

Virtual network | Subnet | IP address prefix | First | Last | IP address count
--- | --- | --- | --- | --- | --:
Shared services | AzureBastionSubnet | 10.73.8.0/27 | 10.73.8.0 | 10.73.8.31 | 32
Shared services | snet-adds-01 | 10.73.8.32/27 | 10.73.8.32 | 10.73.8.63 | 32
Shared services | snet-misc-01 | 10.73.8.64/27 | 10.73.8.64 | 10.73.8.95 | 32
Shared services | snet-misc-02 | 10.73.8.96/27 | 10.73.8.96 | 10.73.8.127 | 32
Shared services | Reserved for future use | 10.73.8.128/25 | 10.73.8.128 | 10.73.8.255 | 128
Application | snet-app-01 | 10.73.9.0/27 | 10.73.9.0 | 10.73.9.31 | 32
Application | snet-db-01 | 10.73.9.32/27 | 10.73.9.32 | 10.73.9.63 | 32
Application | snet-privatelink-01 | 10.73.9.64/27 | 10.73.9.64 | 10.73.9.95 | 32
Application | snet-misc-03 | 10.73.9.96/27 | 10.73.9.96 | 10.73.9.127 | 32
Application | Reserved for future use | 10.73.9.128/25 | 10.73.9.128 | 10.73.9.255 | 128

It is recommended to reserve space for future subnets. A blank table is provided here for convenience. Make a copy of this table and change the *TBD* values to your custom values.

Virtual network | Subnet | IP address prefix | First | Last | IP address count
--- | --- | --- | --- | --- | --:
Shared services | snet-default-01 | TBD | TBD | TBD | TBD
Shared services | AzureBastionSubnet | TBD | TBD | TBD | TBD
Shared services | snet-storage-private-endpoints-01 | TBD | TBD | TBD | TBD
Application | snet-default-02 | TBD | TBD | TBD | TBD
Application | AzureBastionSubnet | TBD | TBD | TBD | TBD
Application | snet-app-01 | TBD | TBD | TBD | TBD
Application | snet-db-01 | TBD | TBD | TBD | TBD
Application | snet-privatelink-01 | TBD | TBD | TBD | TBD
Application | snet-mysql-01 | TBD | TBD | TBD | TBD

## Videos

Video | Section
--- | ---
[Overview](https://youtu.be/2TN4SEq4wzM) | [Overview](#overview)  
[Configure Client Environment (Part 1)](https://youtu.be/Q4dOoQspt90) | [Getting started \| Configure client environment \| Windows Subsystem for Linux \| Windows prerequisites](#windows-subsystem-for-linux)
[Configure Client Environment (Part 2)](https://youtu.be/YW37uG0aX8c) | [Getting started \| Configure client environment \| Windows Subsystem for Linux \| Linux prerequisites](#windows-subsystem-for-linux)
[Next Steps](https://youtu.be/EtNrzs4ZCvM) | [Next steps](#next-steps)

## Known issues

This section documents known issues with these configurations that should be addressed prior to real world usage.

* Client environment
  * If you are experiencing difficulties with WSL, see [Troubleshooting Windows Subsystem for Linux](https://learn.microsoft.com/en-us/windows/wsl/troubleshooting).
  * Some users may not be able to use [Windows subsystem for Linux](#windows-subsystem-for-linux) due to lack of administrative access to their computer or other issues. In these cases consider using [terraform-azurerm-rg-devops](./extras/terraform-azurerm-rg-devops/) and [VS Code remote development over SSH](https://code.visualstudio.com/docs/remote/ssh) as an alternative.
* Configuration management
  * *Terraform*
    * For simplicity, these configurations store [State](https://www.terraform.io/language/state) in a local file named `terraform.tfstate`. For production use, state should be managed in a secure, encrypted [Backend](https://www.terraform.io/language/state/backends) such as [azurerm](https://www.terraform.io/language/settings/backends/azurerm).
    * There is a [known issue](https://github.com/hashicorp/terraform-provider-azurerm/issues/2977) that causes Terraform plan or apply operations to fail after provisioning an Azure Files share behind a private endpoint. If this is causing plan or apply operations to fail you can either whitelist the IP address of the client environment on the storage account firewall or use [Target Resources](https://developer.hashicorp.com/terraform/tutorials/state/resource-targeting) to work around it.
  * *Windows Server*: This configuration uses [Azure Automation State Configuration (DSC)](https://learn.microsoft.com/azure/automation/automation-dsc-overview) for configuring the Windows Server virtual machines, which will be replaced by [Azure Automanage Machine Configuration](https://learn.microsoft.com/azure/governance/machine-configuration/overview). This configuration will be updated to the new implementation in a future release.
    * *configure-automation.ps1*: The performance of this script could be improved by using multi-threading to run Azure Automation operations in parallel.
* Identity, Access Management and Authentication.
  * *Authentication*: These configurations use a service principal to authenticate with Azure which requires a client secret to be shared. This is due to the requirement that sandbox users be limited to a *Contributor* Azure RBAC role assignment which is not authorized to do Azure RBAC role assignments. Production environments should consider using [managed identities](https://learn.microsoft.com/azure/active-directory/managed-identities-azure-resources/overview) instead of service principals which eliminates the need to share secrets.
    * *SQL Server Authentication*: By default this configuration uses mixed mode authentication. Production deployments should use Windows integrated authentication as per best practices.
    * *Point-to-site VPN gateway authentication*: This configuration uses self-signed certificates for simplicity. Production environments should use certificates generated from a root certificate authority.
  * *Credentials*: For simplicity, these configurations use a single set of user defined credentials when an administrator account is required to provision or configure resources. In production environments these credentials would be different and follow the principal of least privilege for better security. Some user defined credentials may cause failures due to differences in how various resources implement restricted administrator user names and password complexity requirements. Note that the default password expiration policy for Active Directory is 42 days which will require the password for `bootstrapadmin@mysandbox.local` to be changed. It is recommended that you update the related `adminpassword` secret in key vault when changing the password as this does not happen automatically.
  * *Active Directory Domain Services*: A pre-configured AD domain controller *azurerm_windows_virtual_machine.vm_adds* is provisioned.
    * *High availability*: The current design uses a single VM for AD DS which is counter to best practices as described in [Deploy AD DS in an Azure virtual network](https://learn.microsoft.com/azure/architecture/reference-architectures/identity/adds-extend-domain) which recommends a pair of VMs in an Availability Set.
    * *Data integrity*: The current design hosts the AD DS domain forest data on the OS Drive which is counter to  best practices as described in [Deploy AD DS in an Azure virtual network](https://learn.microsoft.com/azure/architecture/reference-architectures/identity/adds-extend-domain) which recommends hosting them on a separate data dr*ive with different cache settings.
  * *Role-Based Access Control (RBAC)*
    * *Least privilege*: The current design uses a single Azure RBAC role assignment to grant the *Contributor* role to the currently logged in Azure CLI user and the service principal used by Terraform. Production environments should consider leveraging best practices as described in [Azure role-based access control (Azure RBAC) best practices](https://docs.microsoft.com/azure/role-based-access-control/best-practices) which recommends using multiple role assignments to grant the least privilege required to perform a task.
    * *ARM provider registration*: As described in [issue #4440](https://github.com/hashicorp/terraform-provider-azurerm/issues/4440), some controlled environments may not permit automatic registration of ARM resource providers by Terraform. In these cases some ARM providers may need to be registered manually. See [Azure resource providers and types](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-providers-and-types) and the azurerm provider [skip_provider_registration](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs#skip_provider_registration) optional argument for more information.
* Storage
  * *Azure Storage*: For simplicity, this configuration uses the [Authorize with Shared Key](https://learn.microsoft.com/rest/api/storageservices/authorize-with-shared-key) approach for [Authorizing access to data in Azure Storage](https://learn.microsoft.com/azure/storage/common/authorize-data-access?toc=/azure/storage/blobs/toc.json). For production environments, consider using [shared access signatures](https://learn.microsoft.com/azure/storage/common/storage-sas-overview?toc=/azure/storage/blobs/toc.json) instead.
    * There is a [known issue](https://github.com/hashicorp/terraform-provider-azurerm/issues/2977) when attempting to apply Terraform plans against Azure Storage containers that sit behind a firewall such as a private endpoint. This may prevent the ability to apply changes to configurations that contain this type of dependency, such as [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/). To work around this you use [Resource Targeting](https://www.hashicorp.com/blog/resource-targeting-in-terraform) to avoid issues with storage containers.
  * *Standard SSD vs. Premium SSD*: By default, this configuration uses Standard SSD for SQL Server data and log disks instead of Premium SSD for reduced cost. Production deployments should use Premium SSD as per best practices.
* Networking
  * *azurerm_subnet.vnet_shared_01_subnets["snet-adds-01"]*: This subnet is protected by an NSG as per best practices described in described in [Deploy AD DS in an Azure virtual network](https://learn.microsoft.com/azure/architecture/reference-architectures/identity/adds-extend-domain), however the network security rules permit ingress and egress from the Virtual Network on all ports to allow for flexibility in the configurations. Production implementations of this subnet should follow the guidance in [How to configure a firewall for Active Directory domains and trusts](https://learn.microsoft.com/troubleshoot/windows-server/identity/config-firewall-for-ad-domains-and-trusts).
  * *azurerm_private_dns_zone_virtual_network_link.private_dns_zone_virtual_network_links_vnet_app_01[*] and azurerm_private_dns_zone_virtual_network_link.private_dns_zone_virtual_network_links_vnet_shared_01[*]*: Ideally private dns zones should only need to be linked to the shared services virtual network, however some provisioning processes (e.g. Azure Database for MySQL), require them to be linked to the same virtual network where the service is being provisioned. For this reason all private DNS zones are linked to all virtual networks.
  * *azurerm_point_to_site_vpn_gateway.point_to_site_vpn_gateway_01*: Connection attempts using the Azure VPN client may fail with the message `Server did not respond correctly to VPN control packets. Session state: Reset sent`. Synchronizing the time on the VPN client should resolve the issue. For Windows 11 clients go to `Settings` > `Time & Language` > `Date & Time` > `Additional settings` > `Sync now`.
  