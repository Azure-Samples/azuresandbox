variable "deployment_identity" {
  type        = string
  description = "The deployment identity to create for Azure Sandbox applies. Use none for no identity; managed_identity for an identity attached to the Linux virtual machine, with standing roles on the subscription (auth_mode = \"managed_identity\"); or oidc for an identity that GitHub Actions workflows sign in as, with time-bound roles the operator grants before each run (auth_mode = \"oidc\")."
  default     = "none"

  validation {
    condition     = contains(["none", "managed_identity", "oidc"], var.deployment_identity)
    error_message = "deployment_identity must be one of: none, managed_identity or oidc."
  }
}

variable "enable_github_runner" {
  type        = bool
  description = "Set to true to install and register the GitHub Actions self-hosted runner agent on the Linux virtual machine, false to skip it."
  default     = false
}

variable "entra_tenant_id" {
  type        = string
  description = "The Microsoft Entra tenant id."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.entra_tenant_id))
    error_message = "Must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "github_oidc_environments" {
  type        = list(string)
  description = "The GitHub Actions environments whose jobs can sign in as the deployment identity. One federated identity credential is created per environment. Only used when var.deployment_identity is oidc."
  default     = ["sandbox-deployment", "sandbox-release-gate"]

  validation {
    condition     = length(var.github_oidc_environments) > 0 && length(var.github_oidc_environments) <= 20 && alltrue([for environment in var.github_oidc_environments : can(regex("^[A-Za-z0-9._-]{1,255}$", environment))])
    error_message = "Must contain 1-20 environment names made of alphanumeric characters, periods (.), underscores (_), or hyphens (-)."
  }
}

variable "github_repository_id" {
  type        = string
  description = "The numeric id of the GitHub repository, e.g. from 'gh api repos/OWNER/NAME --jq .id'. Only used when var.deployment_identity is oidc. When empty, it is looked up from the repository in var.github_runner_url, which works only for public repositories."
  default     = ""

  validation {
    condition     = var.github_repository_id == "" || can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "Must be empty or a numeric GitHub repository id."
  }
}

variable "github_repository_owner_id" {
  type        = string
  description = "The numeric id of the user or organization that owns the GitHub repository, e.g. from 'gh api repos/OWNER/NAME --jq .owner.id'. Only used when var.deployment_identity is oidc. When empty, it is looked up from the repository in var.github_runner_url, which works only for public repositories."
  default     = ""

  validation {
    condition     = var.github_repository_owner_id == "" || can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "Must be empty or a numeric GitHub user or organization id."
  }
}

variable "github_runner_labels" {
  type        = list(string)
  description = "Additional labels to apply to the GitHub Actions self-hosted runner. Only used when var.enable_github_runner is true."
  default     = ["azuresandbox"]

  validation {
    condition     = alltrue([for label in var.github_runner_labels : can(regex("^[a-zA-Z0-9._-]{1,64}$", label))])
    error_message = "Each label must be 1-64 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-)."
  }
}

variable "github_runner_power_state_environment" {
  type        = string
  description = "The GitHub Actions environment whose jobs can sign in as the runner power state identity, which starts and deallocates the Linux virtual machine for workflow runs. Must not be one of var.github_oidc_environments. Only used when var.deployment_identity is oidc."
  default     = "sandbox-runner-power-state"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,255}$", var.github_runner_power_state_environment))
    error_message = "Must be an environment name made of alphanumeric characters, periods (.), underscores (_), or hyphens (-)."
  }

  validation {
    condition     = !contains([for environment in var.github_oidc_environments : lower(environment)], lower(var.github_runner_power_state_environment))
    error_message = "Must not be one of github_oidc_environments, so the runner power state identity and the deployment identity never accept the same subject."
  }
}

variable "github_runner_token" {
  type        = string
  description = "The GitHub runner registration token used to register the self-hosted runner (expires after 1 hour), e.g. from 'scripts/new-runner-registration-token.sh'. Set using the environment variable 'TF_VAR_github_runner_token' for both 'terraform plan' and 'terraform apply'. Ephemeral: never stored in Terraform state or the saved plan. Required only when the runner is registered (on first deployment or when var.github_runner_token_version changes)."
  sensitive   = true
  ephemeral   = true
  default     = ""
}

# Controls when the ephemeral github_runner_token is sent to the VM. Terraform can't store an ephemeral value
# to detect changes, so the Run Command's write-only sensitive_body_version tracks this number instead: the
# token is sent when the Run Command is created (including when the VM is replaced, which then needs a fresh
# token) and whenever this value changes, and is omitted otherwise. Leave it at 1 in normal use. Increment it
# only to retry a failed registration with a new token, e.g. after the token expired before the Run Command ran.
variable "github_runner_token_version" {
  type        = number
  description = "Increment to send a new var.github_runner_token to the VM and re-run runner registration, e.g. after a failed registration. Only used when var.enable_github_runner is true."
  default     = 1
}

variable "github_runner_url" {
  type        = string
  description = "The GitHub repository URL to register the self-hosted runner with. Defaults to the Azure Sandbox repository. Used when var.enable_github_runner is true, or when var.deployment_identity is oidc and the repository ids are not set."
  default     = "https://github.com/Azure-Samples/azuresandbox"

  validation {
    condition     = var.github_runner_url == "" || can(regex("^https://github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_runner_url))
    error_message = "Must be empty or a GitHub repository URL, e.g. 'https://github.com/myorg/myrepo'."
  }

  validation {
    condition     = var.deployment_identity != "oidc" || (var.github_repository_id != "" && var.github_repository_owner_id != "") || var.github_runner_url != ""
    error_message = "Must be set when deployment_identity is oidc, unless github_repository_id and github_repository_owner_id are both set."
  }
}

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.location))
    error_message = "Must be a valid Azure region name. It should only contain lowercase letters, numbers, and dashes."
  }
}

variable "log_analytics_workspace_retention_days" {
  type        = string
  description = "The retention period in days for the Log Analytics workspace."
  default     = "30"

  validation {
    condition     = can(regex("^(30|31|60|90|120|180|270|365|550|730)$", var.log_analytics_workspace_retention_days))
    error_message = "Must be one of the valid retention periods: 30, 31, 60, 90, 120, 180, 270, 365, 550, or 730 days."
  }
}

variable "storage_access_tier" {
  type        = string
  description = "The access tier for the new storage account."
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool", "Archive"], var.storage_access_tier)
    error_message = "storage_access_tier must be one of: Hot, Cool, or Archive (case-sensitive, as per Azure Blob Storage access tiers)."
  }
}

variable "storage_container_name" {
  type        = string
  description = "The name of the storage container for Terraform state."
  default     = "tfstate"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,61}[a-z0-9]$", var.storage_container_name))
    error_message = "Must conform to Azure storage container naming standards: it can only contain lowercase alphanumeric characters and hyphens (-), must start and end with an alphanumeric character, and must be between 3 and 63 characters long."
  }
}

variable "storage_replication_type" {
  type        = string
  description = "The type of replication for the new storage account."
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, or RAGZRS (case-sensitive, as per Azure Storage replication types)."
  }
}

variable "subnet_address_prefix" {
  type        = string
  description = "The address prefix for the devops subnet."
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_address_prefix, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "subnet_bastion_address_prefix" {
  type        = string
  description = "The address prefix for the AzureBastionSubnet. The Standard SKU Bastion host requires a /26 or larger prefix."
  default     = "10.0.0.0/26"

  validation {
    condition     = can(cidrhost(var.subnet_bastion_address_prefix, 0)) && try(tonumber(split("/", var.subnet_bastion_address_prefix)[1]) <= 26, false)
    error_message = "Must be valid IPv4 CIDR with a prefix length of /26 or larger (e.g. /26, /25)."
  }
}

variable "subnet_devops_name" {
  type        = string
  description = "The name of the devops subnet, which hosts the Linux virtual machine."
  default     = "snet-devops-01"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.subnet_devops_name))
    error_message = "Must conform to Azure subnet naming standards: it can only contain alphanumeric characters and hyphens (-), must start and end with an alphanumeric character, and must be between 1 and 64 characters long."
  }
}

variable "subnet_privatelink_address_prefix" {
  type        = string
  description = "The address prefix for the private link subnet, which hosts the private endpoints."
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_privatelink_address_prefix, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "subnet_privatelink_name" {
  type        = string
  description = "The name of the private link subnet."
  default     = "snet-privatelink-03"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.subnet_privatelink_name))
    error_message = "Must conform to Azure subnet naming standards: it can only contain alphanumeric characters and hyphens (-), must start and end with an alphanumeric character, and must be between 1 and 64 characters long."
  }
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id used to provision resources."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Must be a valid GUID in the format 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'."
  }
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."
  default     = { costcenter = "mycostcenter", environment = "dev", project = "devops" }

  validation {
    condition = alltrue([
      for key, value in var.tags :
      can(regex("^[a-zA-Z0-9._-]{1,512}$", key)) &&
      can(regex("^[a-zA-Z0-9._ -]{0,256}$", value))
    ])
    error_message = "Each tag key must be 1-512 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-). Each tag value must be 0-256 characters long and consist of alphanumeric characters, periods (.), underscores (_), spaces, or hyphens (-)."
  }
}

variable "vm_jumpbox_linux_size" {
  type        = string
  description = "The size of the Linux virtual machine."
  default     = "Standard_D2ls_v6"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.vm_jumpbox_linux_size))
    error_message = "The 'vm_jumpbox_linux_size' must conform to Azure virtual machine size naming conventions: it can only contain alphanumeric characters and underscores (_). Examples include 'Standard_DS1_v2' or 'Standard_B2ms'."
  }
}

variable "vnet_address_space" {
  type        = string
  description = "The address space in CIDR notation for the virtual network."
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "Must be valid IPv4 CIDR."
  }
}

variable "vnet_name" {
  type        = string
  description = "The suffix appended to the generated virtual network name."
  default     = "devops"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,64}$", var.vnet_name))
    error_message = "Must conform to Azure virtual network naming standards: it can only contain alphanumeric characters and hyphens (-), must start and end with an alphanumeric character, and must be between 1 and 64 characters long."
  }
}
