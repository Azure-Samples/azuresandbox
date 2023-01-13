# #AzureSandbox

![diagram](./diagram.drawio.svg)

## Contents

* [Overview](#overview)
* [Sandbox index](#sandbox-index)
* [Prerequisites](#prerequisites)
* [Getting started](#getting-started)
* [Next steps](#next-steps)
* [Known issues](#known-issues)

## Overview

This repository contains a collection of inter-dependent [cloud computing](https://azure.microsoft.com/en-us/overview/what-is-cloud-computing) configurations for implementing common [Microsoft Azure](https://azure.microsoft.com/en-us/overview/what-is-azure/) services on a single [subscription](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#subscription). Collectively these configurations provide a flexible and cost effective sandbox environment useful for experimenting with various Azure services and capabilities. Depending upon your Azure offer type and region, a fully provisioned #AzureSandbox environment costs approximately $50 USD / day. These costs can be further reduced by stopping / deallocating virtual machines when not in use, or by skipping optional configurations that you do not plan to use.

*Disclaimer:* #AzureSandbox is not intended for production use. While some best practices are used, others are intentionally not used in favor of simplicity and cost. See [Known issues](#known-issues) for more information.

\#AzureSandbox is implemented using popular open source tools that are supported on Windows, macOS and Linux including:

* [git](https://git-scm.com/) for source control.
* [Bash](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) for scripting.
* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/what-is-azure-cli?view=azure-cli-latest) is a command line interface for Azure.
* [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/overview?view=powershell-7.1)
  * [PowerShell Core](https://docs.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-71?view=powershell-7.1)
  * [PowerShell 5.1](https://docs.microsoft.com/en-us/powershell/scripting/overview?view=powershell-5.1) for Windows Server configuration.
* [Terraform](https://www.terraform.io/intro/index.html#what-is-terraform-) v1.3.6 for [Infrastructure as Code](https://en.wikipedia.org/wiki/Infrastructure_as_code) (IaC).
  * [Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) (azuerrm) v3.37.0
  * [cloud-init Provider](https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs) (cloudinit) v2.2.0
  * [Random Provider](https://registry.terraform.io/providers/hashicorp/random/latest/docs) (random) v3.4.3

This repo was created by [Roger Doherty](https://www.linkedin.com/in/roger-doherty-805635b/).

## Sandbox index

\#AzureSandbox features a modular design and can be deployed as a whole or incrementally depending upon your requirements.

* [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) includes the following:
  * A [resource group](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#resource-group) which contains all the sandbox resources.
  * A [key vault](https://docs.microsoft.com/en-us/azure/key-vault/general/overview) for managing secrets.
  * A [log analytics workspace](https://docs.microsoft.com/en-us/azure/azure-monitor/data-platform#collect-monitoring-data) for log data and metrics.
  * A [storage account](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#storage-account) for blob storage.
  * An [automation account](https://docs.microsoft.com/en-us/azure/automation/automation-intro) for configuration management.
  * A [virtual network](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vnet) for hosting [virtual machines](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm).
  * A [bastion](https://docs.microsoft.com/en-us/azure/bastion/bastion-overview) for secure RDP and SSH access to virtual machines.
  * A Windows Server [virtual machine](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) running [Active Directory Domain Services](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview) with a pre-configured domain and DNS server.
* [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/) includes the following:
  * A [virtual network](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vnet) for hosting [virtual machines](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) and private endpoints implemented using [PrivateLink](https://docs.microsoft.com/en-us/azure/private-link/private-link-overview) and [subnet delegation](https://docs.microsoft.com/en-us/azure/virtual-network/subnet-delegation-overview). [Virtual network peering](https://docs.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview) with [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) is automatically configured.
  * A Windows Server [virtual machine](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
  * A Linux [virtual machine](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) for use as a jumpbox.
  * A [PaaS](https://azure.microsoft.com/en-us/overview/what-is-paas/) SMB file share hosted in [Azure Files](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-introduction) with a private endpoint implemented using [PrivateLink](https://docs.microsoft.com/en-us/azure/storage/common/storage-private-endpoints).
* [terraform-azurerm-vm-mssql](./terraform-azurerm-vm-mssql/) includes the following:
  * An [IaaS](https://azure.microsoft.com/en-us/overview/what-is-iaas/) database server [virtual machine](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) based on the [SQL Server virtual machines in Azure](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-server-on-azure-vm-iaas-what-is-overview#payasyougo) offering.
* [terraform-azurerm-msssql](./terraform-azurerm-mssql/) includes the following:
  * A [PaaS](https://azure.microsoft.com/en-us/overview/what-is-paas/) database hosted in [Azure SQL Database](https://docs.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview) with a private endpoint implemented using [PrivateLink](https://docs.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview).
* [terraform-azurerm-mysql](./terraform-azurerm-mysql/) includes the following:
  * A [PaaS](https://azure.microsoft.com/en-us/overview/what-is-paas/) database hosted in [Azure Database for MySQL - Flexible Server](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/overview) with a private endpoint implemented using [subnet delegation](https://docs.microsoft.com/en-us/azure/virtual-network/subnet-delegation-overview).
* [terraform-azurerm-vwan](./terraform-azurerm-vwan/) includes the following:
  * A [virtual wan](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources).
  * A [virtual wan hub](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources) with pre-configured [hub virtual network connections](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#resources) with [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/) and [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/). The hub is also pre-configured for [User VPN (point-to-site) connections](https://docs.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#uservpn).
* Miscellaneous samples
  * [az-graph](./az-graph/)
    * Common [Azure Resource Graph](https://docs.microsoft.com/en-us/azure/governance/resource-graph/overview) queries used for real world cloud estate discovery projects
    * Utility script for executing resource graph queries and exporting results
    * Utility script for provisioning shared resource graph queries

## Prerequisites

The following prerequisites are required in order to get started. Note that once these prerequisite are in place, a [Contributor](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#contributor) Azure RBAC role assignment is sufficient to use the configurations.

* Identify the [Azure Active Directory](https://docs.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-whatis) (AAD) tenant to be used for identity and access management, or create a new AAD tenant using [Quickstart: Set up a tenant](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-create-new-tenant).
* Identify a single Azure [subscription](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#subscription) or create a new Azure subscription. See [Azure Offer Details](https://azure.microsoft.com/en-us/support/legal/offer-details/) and [Associate or add an Azure subscription to your Azure Active Directory tenant](https://docs.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-subscriptions-associated-directory) for more information.
* Identify the owner of the Azure subscription to be used for \#AzureSandbox. This user should have an [Owner](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#owner) Azure RBAC role assignment on the subscription. See [Steps to assign an Azure role](https://docs.microsoft.com/en-us/azure/role-based-access-control/role-assignments-steps) for more information.
* Ask the subscription owner to create a [Contributor](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#contributor) Azure RBAC role assignment for each sandbox user. See [Steps to assign an Azure role](https://docs.microsoft.com/en-us/azure/role-based-access-control/role-assignments-steps) for more information.
* Verify the subscription owner has privileges to create a Service principal name on the AAD tenant. See [Check Azure AD permissions](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#check-azure-ad-permissions) for more information.
* Ask the subscription owner to [Create a service principal](https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli) (SPN) for sandbox users by running the following Azure CLI command in [Azure Cloud Shell](https://docs.microsoft.com/en-us/azure/cloud-shell/quickstart).

  ```lang-bash
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

* Some organizations may institute [Azure policy](https://docs.microsoft.com/en-us/azure/governance/policy/overview) which may cause some sandbox deployments to fail. This can be addressed by using custom settings which pass the policy checks, or by disabling the policies on the Azure subscription being used for the configurations.
* Some Azure subscriptions may have low quota limits for specific Azure resources which may cause sandbox deployments to fail. See [Resolve errors for resource quotas](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/error-resource-quota) for more information. Consult the following table to determine if quota increases are required to deploy the configurations using default settings:

Resource |  Quota required per deployment | Command
--- | :-: | ---
Public IP Addresses | ~2 | *az network list-usages*
Standard BS Family vCPUs | ~5 | *az vm list-usage*
Standard Sku Public IP Addresses | ~2 | *az network list-usages*
Static Public IP Addresses  | ~2 | *az network list-usages*

*Note:* This list is not comprehensive. Quotas vary by Azure subscription offer type and environment. More than one quota may need to be increased for a single resource type, such as [public ip addresses](https://docs.microsoft.com/en-us/azure/virtual-network/public-ip-addresses).

## Getting started

Before you begin, familiarity with the following topics will be helpful when working with \#AzureSandbox:

* Familiarize yourself with Terraform [Input Variables](https://www.terraform.io/docs/configuration/variables.html)  
* Familiarize yourself with Terraform [Output Values](https://www.terraform.io/docs/configuration/outputs.html) also referred to as *Output Variables*
* See [Authenticating to Azure using a Service Principal and a Client Secret](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret) to understand the type of authentication used by Terraform in \#AzureSandbox
* Familiarize yourself with [Recommended naming and tagging conventions](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)
* Familiarize yourself with [Naming rules and restrictions for Azure resources](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules)

### Configure client environment

---

Each sandbox user must select and configure a client environment in advance. A variety of options are available and are detailed in this section.

#### Cloud shell

Azure [cloud shell](https://aka.ms/cloudshell) is a free pre-configured cloud hosted container with a full complement of [tools](https://docs.microsoft.com/en-us/azure/cloud-shell/features#tools) needed to use \#AzureSandbox. This option will be preferred for users who do not wish to install any software and don't mind a web based command line user experience. Review the following content to get started:

* [Bash in Azure Cloud Shell](https://docs.microsoft.com/en-us/azure/cloud-shell/quickstart)
* [Persist files in Azure Cloud Shell](https://docs.microsoft.com/en-us/azure/cloud-shell/persisting-shell-storage)
* [Using the Azure Cloud Shell editor](https://docs.microsoft.com/en-us/azure/cloud-shell/using-cloud-shell-editor)

*Warning:* Cloud shell containers are ephemeral. Anything not saved in `~/clouddrive` will not be retained when your cloud shell session ends. Also, cloud shell sessions expire. This can interrupt a long running process.

#### Windows 11 with WSL

Windows 11 users can use [WSL](https://learn.microsoft.com/en-us/windows/wsl/about) which supports a [variety of Linux distributions](https://docs.microsoft.com/en-us/windows/wsl/install-win10#install-your-linux-distribution-of-choice). Here is a sample configuration preferred by the author:

* Windows 11 prerequisites
  * [Install Linux on Windows with WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
  * [Ubuntu 20.04 LTS (Focal Fossa)](https://www.microsoft.com/store/productId/9N6SVWS3RX71)
  * [Visual Studio Code on Windows](https://code.visualstudio.com/docs/setup/windows)
  * [SQL Server Management Studio](https://docs.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-ver15)
  * [Azure Data Studio](https://docs.microsoft.com/en-us/sql/azure-data-studio/download-azure-data-studio?view=sql-server-ver16)
  * [MySQL Workbench](https://www.mysql.com/products/workbench/)
  * [Azure VPN Client](https://www.microsoft.com/store/productId/9NP355QT2SQB)
* WSL prerequisites
  * [Install the Azure CLI on Linux | apt (Ubuntu, Debian)](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
  * [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform)
    * Refer to the *Linux* tab then choose the *Ubuntu/Debian* tab.
    * Note: Skip the [Quick start tutorial](https://learn.hashicorp.com/tutorials/terraform/install-cli#quick-start-tutorial).
  * [Installing PowerShell on Linux | Ubuntu 20.04](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7.1#ubuntu-2004)
    * After installation, run [configure-powershell.ps1](./configure-powershell.ps1) to install [Azure PowerShell](https://docs.microsoft.com/en-us/powershell/azure/what-is-azure-powershell):

      From bash:

      ```bash
      sudo pwsh
      ```

      From PowerShell Core:

      ```powershell
      ./configure-powershell.ps1
      ```
  
  * Install [pip3](https://pip.pypa.io/en/stable/) Python library package manager.
  
    ```bash
    sudo apt install python3-pip
    ```
  
  * Install [PyJWT](https://pyjwt.readthedocs.io/en/latest/) Python library. This is used to determine the id of the security principal for the currently signed in Azure CLI user.

    ```bash
    pip3 install --upgrade pyjwt
    ```

  * VS Code extensions for WSL
    * [Remote - WSL](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-wsl)
    * [Terraform](https://marketplace.visualstudio.com/items?itemName=mauve.terraform)
    * [PowerShell](https://marketplace.visualstudio.com/items?itemName=ms-vscode.PowerShell)

#### Linux / macOS

Linux and macOS users can deploy the configurations natively by installing the following tools:

* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/what-is-azure-cli?view=azure-cli-latest)
  * Debian or Ubuntu: [Install Azure CLI with apt](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest)
  * RHEL, Fedora or CentOS: [Install Azure CLI with yum](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-yum?view=azure-cli-latest)
  * openSUSE or SLES: [Install Azure CLI with zypper](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-zypper?view=azure-cli-latest)
  * [Install Azure CLI on macOS](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-macos?view=azure-cli-latest)
  * [Install Azure CLI on Linux manually](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-linux?view=azure-cli-latest)
* [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli#install-terraform)
  * Refer to the *Linux* tab then choose the corresponding tab for your distro if installing on Linux.
  * Refer to the *Homebrew on OS X* if installing on macOS.
  * Note: Skip the [Quick start tutorial](https://learn.hashicorp.com/tutorials/terraform/install-cli#quick-start-tutorial).
* [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/overview?view=powershell-7.1)
  * [Installing PowerShell on Linux](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7.1)
  * [Installing PowerShell on macOS](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-macos?view=powershell-7.1)
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

Now that the client environment has been configured, here's how to clone a copy of this repo and start working with the latest release of code.

```lang-bash
git clone https://github.com/doherty100/azuresandbox
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

This section documents the default subnet IP address prefixes used in the configurations. Subnets enable you to segment the virtual network into one or more sub-networks and allocate a portion of the virtual network's address space to each subnet. You can then connect network resources to a specific subnet, and control ingress and egress using [network security qroups](https://docs.microsoft.com/en-us/azure/virtual-network/security-overview).

Virtual network | Subnet | IP address prefix | First | Last | IP address count
--- | --- | --- | --- | --- | --:
Shared services | AzureBastionSubnet | 10.1.0.0/27 | 10.1.0.0 | 10.1.0.31 | 32
Shared services | Reserved for future use | 10.1.0.32/27 | 10.1.0.32 | 10.1.0.63 | 32
Shared services | Reserved for future use | 10.1.0.64/26 | 10.1.0.64 | 10.1.0.127 | 64
Shared services | Reserved for future use | 10.1.0.128/25 | 10.1.0.128 | 10.1.0.255 | 128
Shared services | snet-adds-01 | 10.1.1.0/24 | 10.1.1.0 | 10.1.1.255 | 256
Shared services | Reserved for future use | 10.1.2.0/24 | 10.1.2.0 | 10.1.2.255 | 256
Shared services | Reserved for future use | 10.1.3.0/24 | 10.1.3.0 | 10.1.3.255 | 256
Shared services | Reserved for future use | 10.1.4.0/22 | 10.1.4.0 | 10.1.7.255 | 1,024
Shared services | Reserved for future use | 10.1.8.0/21 | 10.1.8.0 | 10.1.15.255 | 2,048
Shared services | Reserved for future use | 10.1.16.0/20 | 10.1.16.0 | 10.1.31.255 | 4,096
Shared services | Reserved for future use | 10.1.32.0/19 | 10.1.32.0 | 10.1.63.255 | 8,192
Shared services | Reserved for future use | 10.1.64.0/18 | 10.1.64.0 | 10.1.127.255 | 16,384
Shared services | Reserved for future use | 10.1.128.0/17 | 10.1.128.0 | 10.1.255.255 | 32,768
Application | snet-app-01 | 10.2.0.0/24 | 10.2.0.0 | 10.2.0.255 | 256
Application | snet-db-01 | 10.2.1.0/24 | 10.2.1.0 | 10.2.1.255 | 256
Application | snet-privatelink-01 | 10.2.2.0/24 | 10.2.2.0 | 10.2.2.255 | 256
Application | snet-mysql-01 | 10.2.3.0/24 | 10.2.3.0 | 10.2.3.255 | 256
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
1. [terraform-azurerm-vm-mssql](./terraform-azurerm-vm-mssql/) (optional) implements an [IaaS](https://azure.microsoft.com/en-us/overview/what-is-iaas/) database server [virtual machine](https://docs.microsoft.com/en-us/azure/azure-glossary-cloud-terminology#vm) based on the [SQL Server virtual machines in Azure](https://docs.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-server-on-azure-vm-iaas-what-is-overview#payasyougo) offering.
1. [terraform-azurerm-mssql](./terraform-azurerm-mssql/) (optional) implements a [PaaS](https://azure.microsoft.com/en-us/overview/what-is-paas/) database hosted in [Azure SQL Database](https://docs.microsoft.com/en-us/azure/azure-sql/database/sql-database-paas-overview) with a private endpoint implemented using [PrivateLink](https://docs.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview).
1. [terraform-azurerm-mysql](./terraform-azurerm-mysql/) (optional) implements a [PaaS](https://azure.microsoft.com/en-us/overview/what-is-paas/) database hosted in [Azure Database for MySQL - Flexible Server](https://docs.microsoft.com/en-us/azure/mysql/flexible-server/overview) with a private endpoint implemented using [subnet delegation](https://docs.microsoft.com/en-us/azure/virtual-network/subnet-delegation-overview).
1. [terraform-azurerm-vwan](./terraform-azurerm-vwan/) (optional) connects the shared services virtual network and the application virtual network to remote users or a private network.

#### Destroy sandbox configurations

While a default sandbox deployment is fine for testing, it may not work with an organization's private network. The default deployment should be destroyed first before doing a custom deployment. This is accomplished by running `terraform destroy` on each configuration in the reverse order in which it was deployed:

1. [terraform-azurerm-vwan](./terraform-azurerm-vwan/)
1. [terraform-azurerm-mysql](./terraform-azurerm-mysql/)
1. [terraform-azurerm-mssql](./terraform-azurerm-mssql/)
1. [terraform-azurerm-vm-mssql](./terraform-azurerm-vm-mssql/)
1. [terraform-azurerm-vnet-app](./terraform-azurerm-vnet-app/)
1. [terraform-azurerm-vnet-shared](./terraform-azurerm-vnet-shared/). Note: Resources provisioned by `bootstrap.sh` must be deleted manually.

Alternatively, for speed, simply run `az group delete -g rg-sandbox-01`. You can run [cleanterraformtemp.sh](./cleanterraformtemp.sh) to clean up temporary files and directories.

### Perform custom sandbox deployment

---

A custom deployment will likely be required to connect the configurations to an organization's private network. This section provides guidance on how to customize the configurations.

#### Document private network IP address ranges (sample)

Use this section to document one or more private network IP address ranges by consulting a network professional. This is required if you want to establish a [hybrid connection](https://docs.microsoft.com/en-us/azure/architecture/solution-ideas/articles/hybrid-connectivity) between an organization's private network and the configurations. The sandbox includes two IP address ranges used in a private network. The [CIDR to IPv4 Conversion](https://ipaddressguide.com/cidr) tool may be useful for completing this section.

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
Shared services | Reserved for future use | 10.73.8.64/26 | 10.73.8.64 | 10.73.8.127 | 64
Shared services | Reserved for future use | 10.73.8.128/25 | 10.73.8.128 | 10.73.8.255 | 128
Application | snet-app-01 | 10.73.9.0/27 | 10.73.9.0 | 10.73.9.31 | 32
Application | snet-db-01 | 10.73.9.32/27 | 10.73.9.32 | 10.73.9.63 | 32
Application | snet-privatelink-01 | 10.73.9.64/27 | 10.73.9.64 | 10.73.9.95 | 32
Application | snet-mysql-01 | 10.73.9.96/27 | 10.73.9.96 | 10.73.9.127 | 32
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

## Known issues

This section documents known issues with these configurations that should be addressed prior to real world usage.

* Configuration management
  * *Terraform*: For simplicity, these configurations store [State](https://www.terraform.io/language/state) in a local file named `terraform.tfstate`. For production use, state should be managed in a secure, encrypted [Backend](https://www.terraform.io/language/state/backends) such as [azurerm](https://www.terraform.io/language/settings/backends/azurerm).
  * *Windows Server*: This configuration uses [Azure Automation State Configuration (DSC)](https://docs.microsoft.com/en-us/azure/automation/automation-dsc-overview) for configuring the Windows Server virtual machines, which will be replaced by [Azure Automanage Machine Configuration](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/overview). This configuration will be updated to the new implementation in a future releawe.
    * *configure-automation.ps1*: The performance of this script could be improved by using multi-threading to run Azure Automation operations in parallel.
    * There is a [known issue](https://github.com/dsccommunity/SqlServerDsc/issues/1816) with SQL Server 2022 on Windows Server 2022 which increases deployment time due to initial failures applying configurations.
  * *Linux*: This configuration uses [cloud-init](https://cloudinit.readthedocs.io/) for configuring [Ubuntu 20.04 LTS (Focal Fossa)](http://www.releases.ubuntu.com/20.04/) virtual machines.
    * *azurerm_linux_virtual_machine.vm_jumpbox_linux*: ARM tags are currently used to pass some configuration data to cloud-init. This dependency on ARM tags could make the configuration more fragile if users manually manipulate ARM tags or they are overwritten by Azure Policy.
* Identity, Access Management and Authentication.
  * *Authentication*: These configurations use a service principal to authenticate with Azure which requires a client secret to be shared. This is due to the requirement that sandbox users be limited to a *Contributor* Azure RBAC role assignment which is not authorized to do Azure RBAC role assignments. Production environments should consider using [managed identities](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview) instead of service principals which eliminates the need to share secrets.
    * *SQL Server Authentication*: By default this configuration uses mixed mode authentication. Production deployments should use Windows integrated authentication as per best practices.
    * *Point-to-site VPN gateway authentication*: This configuration uses self-signed certificates for simplicity. Production environments should use certificates generated from a root certificate authority.
  * *Credentials*: For simplicity, these configurations use a single set of user defined credentials when an administrator account is required to provision or configure resources. In production environments these credentials would be different and follow the principal of least privilege for better security. Some user defined credentials may cause failures due to differences in how various resources implement restricted administrator user names and password complexity requirements.
  * *Active Directory Domain Services*: A pre-configured AD domain controller *azurerm_windows_virtual_machine.vm_adds* is provisioned.
    * *High availability*: The current design uses a single VM for AD DS which is counter to best practices as described in [Deploy AD DS in an Azure virtual network](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/identity/adds-extend-domain) which recommends a pair of VMs in an Availability Set.
    * *Data integrity*: The current design hosts the AD DS domain forest data on the OS Drive which is counter to  best practices as described in [Deploy AD DS in an Azure virtual network](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/identity/adds-extend-domain) which recommends hosting them on a separate data dr*ive with different cache settings.
* Storage
  * *Azure Storage*: For simplicity, this configuration uses the [Authorize with Shared Key](https://docs.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key) approach for [Authorizing access to data in Azure Storage](https://docs.microsoft.com/en-us/azure/storage/common/authorize-data-access?toc=/azure/storage/blobs/toc.json). For production environments, consider using [shared access signatures](https://docs.microsoft.com/en-us/azure/storage/common/storage-sas-overview?toc=/azure/storage/blobs/toc.json) instead.
  * *Standard SSD vs. Premium SSD*: By default, this configuration uses Standard SSD for SQL Server data and log disks instead of Premium SSD for reduced cost. Production deployments should use Premium SSD as per best practices.
* Networking
  * *azurerm_subnet.vnet_shared_01_subnets["snet-adds-01"]*: This subnet is protected by an NSG as per best practices described in described in [Deploy AD DS in an Azure virtual network](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/identity/adds-extend-domain), however the network security rules permit ingress and egress from the Virtual Network on all ports to allow for flexibility in the configurations. Production implementations of this subnet should follow the guidance in [How to configure a firewall for Active Directory domains and trusts](https://docs.microsoft.com/en-us/troubleshoot/windows-server/identity/config-firewall-for-ad-domains-and-trusts).
  * *azurerm_private_dns_zone_virtual_network_link.private_dns_zone_virtual_network_links_vnet_app_01[*] and azurerm_private_dns_zone_virtual_network_link.private_dns_zone_virtual_network_links_vnet_shared_01[*]*: Ideally private dns zones should only need to be linked to the shared services virtual network, however some provisioning processes (e.g. Azure Database for MySQL), require them to be linked to the same virtual network where the service is being provisioned. For this reason all private DNS zones are linked to all virtual networks.
