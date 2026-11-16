variable "deployment_identity" {
  type        = string
  description = "The deployment identity to create for Azure Sandbox applies: none, managed_identity or oidc. The root module validates the value."
}

variable "deployment_identity_github_environments" {
  type        = list(string)
  description = "The GitHub Actions environments whose jobs can sign in as the deployment identity. One federated identity credential is created per environment. Only used when var.deployment_identity is oidc."
}

variable "enable_github_runner" {
  type        = bool
  description = "Set to true to install and register the GitHub Actions self-hosted runner agent on the VM, false to skip it."
}

variable "github_repository_id" {
  type        = string
  description = "The numeric id of the GitHub repository. Only used when var.deployment_identity is oidc. When empty, it is looked up from the repository in var.github_runner_url."
}

variable "github_repository_owner_id" {
  type        = string
  description = "The numeric id of the user or organization that owns the GitHub repository. Only used when var.deployment_identity is oidc. When empty, it is looked up from the repository in var.github_runner_url."
}

variable "github_runner_labels" {
  type        = list(string)
  description = "Additional labels to apply to the GitHub Actions self-hosted runner. Only used when var.enable_github_runner is true."

  validation {
    condition     = alltrue([for label in var.github_runner_labels : can(regex("^[a-zA-Z0-9._-]{1,64}$", label))])
    error_message = "Each label must be 1-64 characters long and consist of alphanumeric characters, periods (.), underscores (_), or hyphens (-)."
  }
}

variable "github_runner_power_state_environment" {
  type        = string
  description = "The GitHub Actions environment whose jobs can sign in as the runner power state identity. Only used when var.deployment_identity is oidc."
}

variable "github_runner_token" {
  type        = string
  description = "The GitHub runner registration token used to register the self-hosted runner (expires after 1 hour). Ephemeral: delivered to the VM through a write-only Run Command protected parameter and never stored in Terraform state or the saved plan. Required only when the runner is registered (when the Run Command is created or var.github_runner_token_version changes)."
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
  description = "Increment to send a new var.github_runner_token to the VM and re-run runner registration, e.g. after a failed registration. The token is sent only when the Run Command is created or this value changes."
  default     = 1
}

variable "github_runner_url" {
  type        = string
  description = "The GitHub repository URL to register the self-hosted runner with, e.g. 'https://github.com/myorg/myrepo'. Required when var.enable_github_runner is true, or when var.deployment_identity is oidc and the repository ids are not set."
  default     = ""

  validation {
    condition     = var.github_runner_url == "" || can(regex("^https://github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_runner_url))
    error_message = "Must be empty or a GitHub repository URL, e.g. 'https://github.com/myorg/myrepo'."
  }
}

variable "github_runner_version" {
  type        = string
  description = "The version of the GitHub Actions runner agent to install, without the leading 'v'. Only used when var.enable_github_runner is true."
  default     = "2.338.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.github_runner_version))
    error_message = "Must be a semantic version in the format 'Major.Minor.Patch' (e.g., '2.338.0')."
  }
}

variable "location" {
  type        = string
  description = "The name of the Azure Region where resources will be provisioned."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the existing resource group."
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription id. The scope used to look up the role definition ids in the deployment identity's ABAC condition."
}

variable "tags" {
  type        = map(any)
  description = "The tags in map format to be used when creating new resources."
}

variable "virtual_machine_id" {
  type        = string
  description = "The id of the Linux virtual machine (jumplinux2), available only after its apt-based extensions are installed. The runner is installed on it, and the runner power state identity can start and deallocate it."
}

variable "virtual_machine_name" {
  type        = string
  description = "The name of the Linux virtual machine (jumplinux2). The runner is registered with this name."
}
