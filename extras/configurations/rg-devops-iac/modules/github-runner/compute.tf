#region resources

# Optional: installs and registers the GitHub Actions self-hosted runner.
# Runs after cloud-init and the VM extensions, so the base VM is identical with or without the runner.
# The token goes through write-only sensitive_body, so it never lands in state, the plan, custom data or Key Vault.
# It is sent only on create or when var.github_runner_token_version changes.
# Other updates re-run the script without it, and the script leaves a registered runner as-is.
resource "azapi_resource" "github_runner" {
  count = var.enable_github_runner ? 1 : 0

  type      = "Microsoft.Compute/virtualMachines/runCommands@2025-04-01"
  name      = "${module.naming.names["virtual_machine_extension"].name}-${var.virtual_machine_name}-ConfigureGitHubRunner"
  parent_id = var.virtual_machine_id # Available only after the VM's last apt-based extension, so installing the runner dependencies doesn't contend for the apt locks.
  location  = var.location

  body = {
    properties = {
      source = {
        script = file("${path.module}/scripts/configure-github-runner.sh")
      }
      parameters = [
        { name = "RUNNER_URL", value = var.github_runner_url },
        { name = "RUNNER_NAME", value = var.virtual_machine_name },
        { name = "RUNNER_LABELS", value = join(",", var.github_runner_labels) },
        { name = "RUNNER_VERSION", value = var.github_runner_version },
        { name = "RUNNER_HOME", value = local.github_runner_home },
        { name = "AAD_TENANT_ID", value = data.azurerm_client_config.current.tenant_id },
        # The vwan tunnel wrapper and its installer belong to the root repo's unit-testing scripts. They're
        # read from there so rg-devops-iac never keeps its own copy.
        { name = "VWAN_TUNNEL_B64", value = filebase64("${path.module}/../../../../../scripts/vwan-tunnel.sh") },
        { name = "VWAN_TUNNEL_INSTALLER_B64", value = filebase64("${path.module}/../../../../../scripts/install-vwan-tunnel.sh") }
      ]
      asyncExecution                  = false
      treatFailureAsDeploymentFailure = true
      timeoutInSeconds                = 3600
    }
  }

  sensitive_body = {
    properties = {
      protectedParameters = [
        { name = "RUNNER_TOKEN", value = var.github_runner_token }
      ]
    }
  }

  # Sends sensitive_body only on create or when var.github_runner_token_version changes. See that variable.
  sensitive_body_version = {
    "properties.protectedParameters" = tostring(var.github_runner_token_version)
  }

  timeouts {
    create = "90m"
    update = "90m"
  }

  lifecycle {
    precondition {
      condition     = var.github_runner_url != ""
      error_message = "var.github_runner_url must be set when var.enable_github_runner is true."
    }
  }
}
#endregion
