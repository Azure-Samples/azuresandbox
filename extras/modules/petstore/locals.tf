locals {
  registry_name = split("/", var.container_registry_id)[8]
  login_server  = "${local.registry_name}.azurecr.io"

  # The instrumented image is published to a dedicated repository, tagged with the
  # Application Insights Java agent version so that changing the agent version
  # naturally produces a new image and re-runs the build.
  image_repository = "petstore-appinsights"
  image_tag        = var.appinsights_agent_version
  image_reference  = "${local.login_server}/${local.image_repository}:${local.image_tag}"

  # Build script executed on jumplinux1 via azurerm_virtual_machine_run_command.
  # A generated preamble exports the variables consumed by the script and injects
  # the base64-encoded Dockerfile; the static script body is appended verbatim so
  # its shell '${...}' expansions are not interpreted by Terraform.
  build_image_script = join("\n", [
    "#!/bin/bash",
    "export LOGIN_SERVER='${local.login_server}'",
    "export REGISTRY_NAME='${local.registry_name}'",
    "export IMAGE_REPOSITORY='${local.image_repository}'",
    "export IMAGE_TAG='${local.image_tag}'",
    "export SOURCE_IMAGE='${var.source_container_image}'",
    "export APPINSIGHTS_VERSION='${var.appinsights_agent_version}'",
    "export DOCKERFILE_B64='${base64encode(file("${path.module}/Dockerfile"))}'",
    file("${path.module}/scripts/build-petstore-image.sh")
  ])
}
