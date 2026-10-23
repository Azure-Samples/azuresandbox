locals {
  github_runner_home = "/opt/actions-runner"
  github_runner_name = var.github_runner_name != "" ? var.github_runner_name : var.vm_jumpbox_linux_name
}

