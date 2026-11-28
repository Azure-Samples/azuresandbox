locals {
  # Numeric ids of the GitHub repository and its owner, used in the OIDC subjects below.
  # Each id comes from its variable (var.github_repository_id, var.github_repository_owner_id) when set.
  # If either is empty, the missing id is looked up from the GitHub API on each plan, using the repository in var.github_runner_url.
  # The lookup is anonymous, so it works only for public repositories; set both variables for a private repository.
  github_repository_lookup   = var.deployment_identity == "oidc" && (var.github_repository_id == "" || var.github_repository_owner_id == "")
  github_repository          = local.github_repository_lookup ? jsondecode(data.http.github_repository[0].response_body) : null
  github_repository_id       = var.github_repository_id != "" ? var.github_repository_id : try(tostring(local.github_repository.id), "")
  github_repository_owner_id = var.github_repository_owner_id != "" ? var.github_repository_owner_id : try(tostring(local.github_repository.owner.id), "")

  # A GitHub OIDC subject identifies which repository and environment a GitHub Actions job runs in.
  # Each subject becomes a federated identity credential so matching jobs can sign in to Azure without a stored secret.
  # The repository must use the subject claim template {"use_default":false,"include_claim_keys":["repository_owner_id","repository_id","context"]}.
  # The template can be set on the repository itself or inherited from its organization.
  # For a job in an environment, "context" is "environment:<name>", so each subject is this prefix followed by the environment name.
  github_oidc_subject_prefix = "repository_owner_id:${local.github_repository_owner_id}:repository_id:${local.github_repository_id}:environment:"

  # The oidc deployment identity accepts one subject for each environment in var.deployment_identity_github_environments.
  github_oidc_subjects = var.deployment_identity == "oidc" ? {
    for environment in var.deployment_identity_github_environments : environment => "${local.github_oidc_subject_prefix}${environment}"
  } : {}

  # The runner power state identity accepts one subject, for var.github_runner_power_state_environment.
  github_runner_power_state_subject = var.deployment_identity == "oidc" ? "${local.github_oidc_subject_prefix}${var.github_runner_power_state_environment}" : null

  github_runner_home = "/opt/actions-runner"
}
