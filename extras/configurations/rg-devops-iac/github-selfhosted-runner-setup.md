# GitHub Self-Hosted Runner Setup

This guide documents an attended Bash deployment of the standalone
`rg-devops-iac` configuration, with its Linux VM used as a GitHub Actions
self-hosted runner for Azure Sandbox deployments. It is not a production
deployment guide.

## Steps

1. [Prepare variables and authentication](#step-1-prepare-variables-and-authentication).
2. [Enable the runner and deployment identity](#step-2-enable-the-runner-and-deployment-identity).
3. [Initialize and validate](#step-3-initialize-and-validate).
4. [Plan a fresh bootstrap deployment](#step-4-plan-a-fresh-bootstrap-deployment).
5. [Apply the reviewed bootstrap plan](#step-5-apply-the-reviewed-bootstrap-plan).
6. [Check cloud-init and the runner service](#step-6-check-cloud-init-and-the-runner-service).
7. [Verify GitHub-side runner readiness](#step-7-verify-github-side-runner-readiness).
8. [Check the runner service account's toolchain](#step-8-check-the-runner-service-accounts-toolchain).
9. [Check managed identity access to state storage](#step-9-check-managed-identity-access-to-state-storage).
10. [Check the Sandbox deployment identity](#step-10-check-the-sandbox-deployment-identity).
11. [Grant the optional Microsoft Graph permission](#step-11-grant-the-optional-microsoft-graph-permission).
12. [Clean up and hand off to Sandbox workflows](#step-12-clean-up-and-hand-off-to-sandbox-workflows).

This guide covers the standalone infrastructure bootstrap and runner-readiness
checks. Sandbox backend and workflow configuration are a separate deployment
concern; the final step records that handoff. Initialization and validation
alone do not provision or verify a runner.

## Execution boundaries

The operator executes the commands in a separate Bash terminal. Run commands
from `extras/configurations/rg-devops-iac` unless a step explicitly says
otherwise. Do not run the repository-root Sandbox configuration to bootstrap
this environment: it has independent state and a separate lifecycle.

The bootstrap normally uses local Terraform state because it creates the
storage account that will hold subsequent Sandbox deployment state. Protect
local state and saved plans as sensitive files. Later Sandbox workflows must
use the remote backend rather than local runner storage.

Stop on a deployment error. Preserve the failing command and error locally,
sanitize the details before sharing or filing a public issue, and do not retry
or change the configuration without an explicit decision.

## Public documentation hygiene

Never include credentials, actual subscription or tenant IDs, identity IDs,
organization-specific tags, deployment resource names, private addresses, or
raw state or plan contents in this guide or public GitHub content. Use
placeholders such as `<subscription-id>` and `<storage-account>`.

Do not paste secrets or unfiltered environment-variable output into the
walkthrough. Share only the requested sanitized diagnostics. Disable shell
tracing before handling secrets.

An identity with subscription `Owner` makes this runner a privileged execution
environment. Only trusted deployment workflows should use it. Do not route
untrusted pull-request code to this runner; GitHub approval alone is not a
security boundary for a persistent self-hosted runner.

## Step 1: Prepare variables and authentication

### Inspect the operator's terminal

Use the Bash terminal that will perform the deployment, not another terminal
where exports may differ. Start in `extras/configurations/rg-devops-iac`.
The existing `terraform.tfvars` file must be preserved; do not re-run bootstrap
scripts that overwrite it.

Run this diagnostic batch first. It prints variable names and set/unset status,
not credentials or deployment IDs.

```bash
set +x
terraform version
az version --query '"azure-cli"' --output tsv
git branch --show-current
git check-ignore terraform.tfvars

printf 'TF_VAR_arm_client_secret: %s\n' "${TF_VAR_arm_client_secret:+set}"
printf 'TF_VAR_github_runner_token: %s\n' "${TF_VAR_github_runner_token:+set}"

printf '\nExported Terraform/Azure variable names (values omitted):\n'
compgen -e | LC_ALL=C sort | grep -E '^(TF_VAR_|ARM_|AZURE_)' || true

printf '\nTop-level terraform.tfvars keys (values omitted):\n'
awk '/^[[:alpha:]_][[:alnum:]_]*[[:space:]]*=/ { print $1 }' terraform.tfvars

az account show \
  --query '{environment:environmentName,state:state,isDefault:isDefault}' \
  --output json
```

An empty secret-status field means the variable is unset or empty. If Azure CLI
authentication fails, stop and resolve sign-in before deployment. If
`git check-ignore` does not identify `terraform.tfvars`, do not stage that file.
Terraform's required version is defined in this configuration's `terraform.tf`;
check it against the version printed above.

### Variables to review before initialization

Review actual IDs locally and explicitly confirm the target tenant,
subscription, region, operator identity, and required tags. Do not publish
those values. The bootstrap requires these inputs:

| Setting | Purpose |
| --- | --- |
| `aad_tenant_id` | Tenant containing the bootstrap service principal. |
| `arm_client_id` | Bootstrap service principal application/client ID, not a managed identity client ID. |
| `subscription_id` | Subscription where the runner infrastructure will be created. |
| `user_object_id` | Operator's Entra user object ID for the configuration's role assignments. |
| `location` | Operator-selected Azure region with suitable VM availability and quota. |
| `tags` | Include `project`, `environment`, and `costcenter`, plus any policy-required tags. |
| `vm_jumpbox_linux_size` | Optional VM-size override; check capacity for the intended deployment workload. |

This standalone configuration has no root `additional_tags` input. Required
organizational tags belong in its `tags` map. The repository-root Sandbox
deployment has its own inputs and must be configured separately later.

For a repository-level runner, the intended additional settings are:

```hcl
enable_github_runner = true
github_runner_url    = "https://github.com/<owner>/<repository>"
github_runner_labels = ["azuresandbox"]
github_runner_token_type = "pat"
```

Replace the URL locally with the confirmed repository. Labels must match the
workflows that will target the runner. Do not append duplicate assignments if
these keys already exist.

For Sandbox deployments using managed identity, also consider:

```hcl
enable_user_assigned_identity = true
```

Confirm this choice before applying: it creates a user-assigned identity with
subscription `Owner` and attaches it to the VM. Subscription Owner privileges
are needed for the bootstrap's role assignments, or an equivalent role
combination must permit them. The subscription-owner identity can also modify
the runner infrastructure itself.

The VM's system-assigned identity remains the default for cloud-init, token
retrieval, and the remote-state backend. The user-assigned identity is selected
explicitly for later Sandbox provider authentication. Do not replace the
bootstrap's service principal client ID with that identity's client ID.

### Secret and environment handling

Keep `TF_VAR_arm_client_secret` exported in the operator's deployment terminal.
Do not put it in `terraform.tfvars` or paste its value into the walkthrough.

Runner registration also requires `TF_VAR_github_runner_token`. For a
repository-level runner, use an approved fine-grained PAT scoped to that
repository with **Administration: Read and write**, created by an authorized
repository administrator. Organization-level registration has different
permissions and must be confirmed separately.

When instructed to set the PAT, use hidden input instead of placing the
credential in shell history:

```bash
set +x
read -r -s -p 'GitHub runner PAT: ' TF_VAR_github_runner_token
printf '\n'
export TF_VAR_github_runner_token
printf 'TF_VAR_github_runner_token: %s\n' "${TF_VAR_github_runner_token:+set}"
```

The token is passed to a write-only Key Vault secret and read by the VM using
its managed identity. A registration token is a separate supported mode, but
its short lifetime can expire during provisioning; this walkthrough has not
selected that mode.

No `ARM_*` exports are required for the standalone configuration's provider
authentication: `providers.tf` explicitly uses the service principal inputs.
Inventory existing exports before deciding whether any should be cleared,
especially if this terminal previously used managed identity or another
backend. Do not copy VM-side `ARM_USE_MSI=true` into the bootstrap terminal.

If later Sandbox deployments enable `mssql` with managed identity, arrange
for a Privileged Role Administrator or Global Administrator to grant the
user-assigned identity Microsoft Graph `Group.ReadWrite.All` after creation.
Azure subscription Owner alone cannot grant that application permission.

## Step 2: Enable the runner and deployment identity

Complete [preparation](#step-1-prepare-variables-and-authentication) first.
Confirm the registration URL, token mode, and subscription-level identity
privileges with the operator before editing the configuration.

These commands select a repository-level runner, PAT registration, and a
user-assigned managed identity for subsequent Sandbox deployments. The operator
must confirm existing bootstrap IDs, region, tags, and permissions locally.
No additional `ARM_*` exports are needed for this bootstrap.

### Update terraform.tfvars

Run from `extras/configurations/rg-devops-iac`. If any of these settings already
exist, edit them in place rather than appending duplicate assignments. Preserve
the existing bootstrap inputs and tags.

The append command below is only appropriate after confirming that all five
keys are absent. Replace the placeholder URL with the approved target
repository before executing it.

```bash
chmod 600 terraform.tfvars

cat >> terraform.tfvars <<'EOF'

enable_github_runner          = true
enable_user_assigned_identity = true
github_runner_url            = "https://github.com/<owner>/<repository>"
github_runner_labels         = ["azuresandbox"]
github_runner_token_type     = "pat"
EOF

terraform fmt terraform.tfvars
```

The `arm_client_id` already in this file must remain the bootstrap service
principal's client ID. The new managed identity is created by this deployment;
its client ID is used only when configuring later Sandbox deployments.

The default VM name and runner name are `jumplinux2`; no name override is
required. The standard `self-hosted`, `Linux`, and `X64` labels are assigned by
GitHub; `azuresandbox` is the additional workload label.

### Export the runner PAT securely

Create an approved fine-grained PAT in
[GitHub personal access token settings](https://github.com/settings/personal-access-tokens).
Select the target repository's resource owner, limit repository access to the
target repository, and grant **Repository permissions > Administration >
Read and write**. The user creating the PAT needs repository administrator
access. Respect organization token policies and approval requirements; a token
awaiting approval may not be usable for registration.

Do not use an unrelated repository token or an expired token. Select an
appropriate expiration, store the token securely if needed, and do not paste
it into chat, documentation, or the tfvars file.

```bash
set +x
read -r -s -p 'GitHub runner PAT: ' TF_VAR_github_runner_token
printf '\n'
export TF_VAR_github_runner_token
printf 'TF_VAR_github_runner_token: %s\n' "${TF_VAR_github_runner_token:+set}"
```

Keep the existing `TF_VAR_arm_client_secret` exported. The two secrets serve
different purposes: the service principal authenticates the bootstrap's Azure
providers; the PAT allows the VM to request a GitHub runner registration token.
The runner does not need this PAT to authenticate ordinary workflow jobs after
registration.

### Share only safe confirmation

This diagnostic prints the five non-secret runner settings and secret-presence
flags. It does not print the bootstrap IDs, organizational tags, or credentials.

```bash
awk '/^(enable_github_runner|enable_user_assigned_identity|github_runner_url|github_runner_labels|github_runner_token_type)[[:space:]]*=/ { print }' terraform.tfvars

printf 'TF_VAR_arm_client_secret: %s\n' "${TF_VAR_arm_client_secret:+set}"
printf 'TF_VAR_github_runner_token: %s\n' "${TF_VAR_github_runner_token:+set}"
```

If the repository URL itself is confidential, replace it with a placeholder
before sharing. Both presence flags must say `set`. Do not initialize, plan,
or apply until this step has been confirmed. A set flag proves only that an
environment variable is nonempty, not that its credential or permissions are
valid.

## Step 3: Initialize and validate

Complete [runner settings](#step-2-enable-the-runner-and-deployment-identity)
first. Both secret-presence flags must report `set`, and the operator must
have confirmed bootstrap inputs and permissions. `github_runner_token_type`
is case-sensitive: use `"pat"`, not `"PAT"`.

Run these commands in the same attended Bash terminal, from
`extras/configurations/rg-devops-iac`. This is the bootstrap workstation, not
the future runner. Do not create the repository-root Sandbox backend here.

### Check for existing state and initialize

The first command reports only whether state and backend files exist; it does
not display their contents. This distinguishes an apparently fresh working
directory from one that may already manage resources. An absent local state
file alone does not prove there are no existing Azure resources or remote state.

```bash
for path in terraform.tfstate terraform.tfstate.backup backend.tf .terraform/terraform.tfstate; do
  if [ -e "$path" ]; then
    printf '%s: exists\n' "$path"
  else
    printf '%s: absent\n' "$path"
  fi
done

terraform fmt -check terraform.tfvars &&
  terraform init -input=false &&
  terraform validate
```

The `&&` chain stops at the first failing command. Initialization downloads the
modules and providers and initializes the configured backend; it does not
provision the VM. Validation checks configuration consistency, not credential
validity, Azure Policy compliance, quota, or successful runner registration.

`terraform init -input=false` intentionally does not answer backend migration
questions automatically. Do not add `-reconfigure`, `-migrate-state`, or
`-upgrade` to work around an error. Preserve an existing backend or lock file
and review any migration requirement before proceeding.

Do not initialize or inspect state while another Terraform apply is running
against this configuration. Keep the workstation's bootstrap state separate
from the later repository-root Sandbox state.

### Report the result

Share the state-file presence lines and sanitized initialization and validation
output. Expected success includes `Terraform has been successfully initialized!`
and `Success! The configuration is valid.`

Replace any actual deployment resource names, subscription or tenant IDs,
identity IDs, local host/user paths, and internal policy details with
placeholders. Never share credentials or state-file contents.

On an error, stop and report the exact command and sanitized error. Do not
retry or change configuration to bypass it. If formatting fails, report that
result rather than proceeding to initialization.

Planning and applying are separate steps. For an existing deployment, the
public-access barriers may need to be reopened before planning; confirm the
deployment's state and lifecycle before selecting those commands.

## Step 4: Plan a fresh bootstrap deployment

Complete [initialization and validation](#step-3-initialize-and-validate).
The operator must explicitly confirm this is a fresh deployment, with no
existing resources or state managed by this standalone configuration.

These commands are not the update procedure for an already-applied deployment.
Existing deployments require consideration of the public-access barriers
before planning; do not select the fresh-deployment path merely because
initialization succeeded.

### Create a saved plan

Run in the same Bash terminal from
`extras/configurations/rg-devops-iac`, with both required secrets still exported.
Do not run a plan concurrently with an apply against this state.

```bash
umask 077
terraform plan -input=false -out=main.tfplan
```

After successful plan creation, explicitly restrict and verify its permissions:

```bash
chmod 600 main.tfplan
stat -c 'Saved plan file mode: %a' main.tfplan
```

The expected mode is `600`. Do not rely solely on the umask: an existing file
can retain broader permissions.

The `.tfplan` extension is required for saved plans in this repository. The
restrictive umask protects newly created plan and state files; it does not
change permissions on files that already exist. Saved plans can contain
credentials and other sensitive data even when the terminal output redacts
them. Keep the plan local, do not upload it, and do not commit it.

The standalone configuration takes organizational tags from the confirmed
`tags` map in its own `terraform.tfvars`. Do not pass the repository-root
Sandbox's `additional_tags` argument here: that input is not defined by this
configuration.

Planning authenticates to Azure and calculates proposed changes. It does not
create the runner infrastructure or validate GitHub registration.

### Review before applying

Review the plan locally. For a fresh bootstrap, expect resource additions and
no changes or deletions to existing managed resources. Review all proposed
operations rather than relying on a predetermined resource count.

Confirm the plan includes the intended VM, runner configuration, user-assigned
managed identity, and its subscription `Owner` role assignment. Confirm that
the selected subscription, region, and tags are correct. Runner installation
and registration happen later during cloud-init; Terraform planning cannot
prove those steps will succeed.

The current configuration also creates a public IP for the VM and allows
inbound TCP port 22 from any source. Review that exposure explicitly before
applying; the runner's outbound connection to GitHub does not itself require
public inbound SSH. Restricting or removing this access requires a deliberate
configuration change and a new plan, not an untracked portal edit.

Key Vault and Storage public-access barrier operations should set
`publicNetworkAccess` to `Disabled` after their provisioning writes. The VM
uses private endpoints for subsequent access.

Some values, including rendered VM custom data and newly created resource IDs,
can remain unknown until apply. Verify that the planned cloud-init parts
include both runner configuration and the installation script, then verify
cloud-init and runner registration after provisioning. A successful plan is
not evidence that the PAT is approved or that registration will succeed.

Share only the `Plan: ... to add, ... to change, ... to destroy.` summary and
any sanitized warnings or errors. If operations are unexpected, share the
Terraform resource addresses and operation types, not actual deployment
names or IDs. Do not paste the full plan, rendered cloud-init, or credentials.

On an error, stop and preserve the exact command and sanitized error output.
Do not retry, adjust permissions, or modify configuration as a workaround
without an explicit decision.

Do not apply yet. The next step will use the reviewed saved plan. If inputs or
configuration change after planning, that saved plan is no longer the plan to
approve; it must be reconsidered before applying.

## Step 5: Apply the reviewed bootstrap plan

Complete [planning and review](#step-4-plan-a-fresh-bootstrap-deployment)
first. Resolve unexpected operations and explicitly review the
subscription-level identity privileges and public SSH exposure before
authorizing deployment.

Run from `extras/configurations/rg-devops-iac` in the operator's Bash terminal.
Only one apply may run against this configuration's state at a time. Do not
run Terraform state inspections, output commands, or another plan while the
apply is in progress.

### Apply the saved plan

```bash
terraform apply -input=false main.tfplan
```

Applying a saved plan starts deployment immediately: Terraform does not ask
for a second `yes` confirmation. Do not use plain `terraform apply`, which
would calculate a different plan instead of applying the one already reviewed.

The saved plan contains the selected variables, including this standalone
configuration's `tags` map. Do not append `-var` or `-var-file` arguments when
applying it. If configuration or inputs have changed since plan creation,
stop and review a new plan instead.

Keep the terminal open and monitor the output. Provisioning can take around
15 minutes or longer. Advancing resource creation messages or
`Still creating...` elapsed counters indicate progress; a long elapsed time
alone does not prove a hang.

Do not interrupt a progressing apply. If output stops advancing for about
10 minutes, preserve the last output and report the suspected stall before
deciding whether to abort. Do not launch a competing Terraform command to
investigate its state.

### Report completion or failure

On success, share only the summary:

```text
Apply complete! Resources: <count> added, <count> changed, <count> destroyed.
```

Do not paste unfiltered outputs: they can contain deployment-specific resource
names, addresses, subscription IDs, and identity IDs. Sanitize any warnings
before sharing.

On an error, stop. Preserve the failing command, full error locally, and
sanitized error output for the walkthrough. Do not retry the apply or change
configuration as a workaround without an explicit decision.

### What apply success does not prove

Terraform success does not establish that all VM cloud-init tasks completed
successfully or that GitHub runner registration succeeded. Runner installation
can still be progressing after Azure reports that the VM exists.

The next stage must verify cloud-init completion, the runner service, and
GitHub's runner status before dispatching deployment workflows. The later
Sandbox deployment also needs its own remote backend, authentication inputs,
module selection, tags, and workflow configuration. Do not start that
deployment merely because the bootstrap apply succeeded.

Retain bootstrap state securely: it is needed to manage this standalone
environment and is separate from the Sandbox state. Never delete it as
temporary plan-file cleanup.

## Step 6: Check cloud-init and the runner service

Proceed only after the [bootstrap apply](#step-5-apply-the-reviewed-bootstrap-plan)
completes successfully. Terraform completion does not prove that the GitHub
runner is ready.

Backporting the root Sandbox module's managed cloud-init completion wait is
tracked in [issue #805](https://github.com/Azure-Samples/azuresandbox/issues/805).
That enhancement does not replace successful-provisioning and GitHub-side
readiness checks.

Use the workstation's existing Azure CLI authentication. These checks use
[Azure VM Run Command](https://learn.microsoft.com/azure/virtual-machines/linux/run-command)
to execute read-only guest diagnostics, so they do not require downloading an
SSH private key or reopening Key Vault public access. The operator needs VM
Run Command permissions, and the Azure VM agent must be available.

### Read guest status

Run from `extras/configurations/rg-devops-iac` in the same workstation Bash
terminal. Read the VM resource ID from the completed bootstrap's outputs
without printing it or hardcoding deployment identifiers.

The resource map key below corresponds to the configuration's default VM
name. Adjust the key if that default was deliberately overridden.

```bash
set +x
set -o pipefail

VM_ID=$(terraform output -json resource_ids |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["virtual_machine_jumplinux2"])') &&
az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts 'cloud-init status --long && systemctl list-units --all --type=service --no-pager --no-legend "actions.runner.*"' \
  --query 'value[].message' \
  --output tsv
```

Run Command may take a few minutes to return. The guest command does not wait
indefinitely for cloud-init completion or install, start, restart, or
reconfigure anything. The `&&` prevents the service listing from hiding a
nonzero cloud-init status.

Inspect the returned stdout and stderr, not merely the Azure CLI exit code:
an Azure Run Command request can succeed while its guest script reports an
error.

### Interpret the output

For completed provisioning, expect `status: done` without cloud-init errors
and an `actions.runner.*.service` row reporting `loaded active running`.
An empty service list does not prove success.

`status: running` means provisioning is not yet complete; do not dispatch
deployment jobs. Report that status and wait for the walkthrough's next
instruction. If cloud-init reports errors, degraded status, or a failed
runner service, preserve the output and stop without restarting services,
rerunning cloud-init, or modifying configuration.

Share the diagnostic output after replacing any actual deployment identifiers,
host/user paths, internal policy details, or addresses with placeholders.
Do not share raw cloud-init logs, the runner credential files, `.runner`
contents, or the complete `.env` file.

The GitHub-side runner status and labels must also be verified before
workflows are dispatched. A running local service alone is not proof of
successful communication with GitHub.

## Step 7: Verify GitHub-side runner readiness

Complete the [guest-status check](#step-6-check-cloud-init-and-the-runner-service)
first. Cloud-init must report completion without errors, and the runner
service must report `loaded active running`.

### Query GitHub from the workstation

These commands require the GitHub CLI (`gh`) in the operator's Bash terminal.
They reuse the already-exported registration PAT for a read-only runner-list
request. `GH_TOKEN` is supplied only to this command, not exported persistently
or written to the runner.

The example below uses the public Azure Sandbox repository and the default
runner name. Replace the repository and name if the approved registration
target or configured runner name differs.

```bash
set +x

GH_TOKEN="$TF_VAR_github_runner_token" gh api \
  --method GET \
  --paginate \
  repos/Azure-Samples/azuresandbox/actions/runners \
  --jq '[.runners[] | select(.name == "jumplinux2") | {name, status, busy, labels: [.labels[].name]}]'
```

The query prints only runner name, connection status, busy state, and labels,
not tokens or runner IDs. Pagination prevents a runner from being overlooked
if the repository has more than one page of runners. Each page produces an
array; empty arrays from other pages are not evidence of a missing runner if
one page contains the matching record.

### Expected result

Confirm exactly one matching runner across the returned pages:

| Field | Expected value |
| --- | --- |
| `name` | The configured runner name. |
| `status` | `online`. |
| `busy` | `false` before dispatching a deployment job. |
| `labels` | Includes `self-hosted`, `Linux`, `X64`, and `azuresandbox`. |

The GitHub UI shows an online, non-busy runner as **Idle**. The API reports
connection and busy state separately.

If every page is empty, registration has not been verified. If the runner is
offline or busy, do not dispatch a new deployment. A busy runner may already
be executing a job; do not restart it or interrupt that job.

Share the filtered output. On a command or authentication error, preserve the
sanitized error and stop without rotating credentials or re-registering the
runner as an automatic workaround.

If GitHub CLI is unavailable, the same fields can be checked manually at the
approved repository's **Settings > Actions > Runners** page. This requires an
attended operator with repository runner-management access.

An online runner is not yet a fully configured Sandbox deployment workflow.
The toolchain, Azure authentication, remote-state backend, workflow inputs,
and trusted-workflow restrictions still need to be checked before dispatch.

## Step 8: Check the runner service account's toolchain

Complete [GitHub-side verification](#step-7-verify-github-side-runner-readiness)
first. Confirm the runner is online, not busy, and has the expected labels.
Do not dispatch deployment workflows yet.

### Run toolchain checks as the runner account

Use the workstation's Bash terminal. The `VM_ID` variable comes from
[step 6](#step-6-check-cloud-init-and-the-runner-service); if using a new
terminal, repeat only its output-capture command to populate that variable.

These commands use VM Run Command to run tools as the configured default
runner account, `githubrunner`, rather than merely checking that root can
access them. They do not install software or sign in to Azure.

```bash
GUEST_SCRIPT=$(cat <<'EOF'
set -eu
sudo -u githubrunner -- git --version
sudo -u githubrunner -- terraform version
sudo -u githubrunner -- az version --query '"azure-cli"' --output tsv
sudo -u githubrunner -- pwsh -NoLogo -NoProfile -Command '$ErrorActionPreference = "Stop"; $PSVersionTable.PSVersion.ToString(); Import-Module Az.Accounts -ErrorAction Stop; Get-Module -ListAvailable Az,Az.Accounts | Select-Object Name,Version'
EOF
)

az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts "$GUEST_SCRIPT" \
  --query 'value[].message' \
  --output tsv
```

Review both stdout and stderr. The guest shell stops on a failed executable,
and PowerShell reports an explicit error if `Az.Accounts` cannot be imported.

Expect Git, Terraform, Azure CLI, and PowerShell versions, plus available
`Az` and `Az.Accounts` modules. A missing `Az` rollup must be reported even if
`Az.Accounts` alone imports successfully. Terraform must satisfy the target
Sandbox revision's `terraform.tf`, not merely the bootstrap configuration's
version constraint.

These checks use the standard executable search path; they do not reproduce
every environment variable or dependency that an Actions job may configure.
Managed identity authentication, remote-state access, and workflow execution
remain separate checks.

Share the version/module output and any sanitized errors. On failure, stop;
do not install or update packages, rerun provisioning, or restart the runner
as an automatic workaround.

## Step 9: Check managed identity access to state storage

Complete the [runner toolchain check](#step-8-check-the-runner-service-accounts-toolchain).
Confirm the runner remains idle and do not dispatch workflows during these
authentication checks.

This step verifies the system-assigned identity's ability to read the state
container from the VM. It does not configure Terraform's remote backend or
validate the separate user-assigned identity used by Sandbox providers.

### Read the state container as the runner account

Run from `extras/configurations/rg-devops-iac` in the workstation's Bash
terminal. Keep the `VM_ID` captured in step 6.

```bash
STORAGE_ACCOUNT=$(terraform output -json resource_names |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["storage_account"])') &&
GUEST_SCRIPT=$(cat <<EOF
set -eu
sudo -H -u githubrunner -- az login --identity --allow-no-subscriptions --output none
sudo -H -u githubrunner -- az storage container show --account-name "$STORAGE_ACCOUNT" --name tfstate --auth-mode login --query '{container:name}' --output json --only-show-errors
EOF
) &&
az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts "$GUEST_SCRIPT" \
  --query 'value[].message' \
  --output tsv
```

If the bootstrap's `storage_container_name` was deliberately overridden,
replace `tfstate` with that confirmed container name.

The commands sign in using the VM's system-assigned identity and update only
the `githubrunner` account's local Azure CLI authentication context. The
operator's workstation login is unchanged. No service principal secret or
storage account key is passed to the VM.

`--allow-no-subscriptions` permits sign-in when the identity has only
data-plane access rather than subscription-wide management access.
`--auth-mode login` explicitly selects Microsoft Entra authorization for the
storage request; shared-key authorization is disabled on this account.

This is a read-only Azure check: it does not create or overwrite state blobs,
take a Terraform state lock, or reopen public storage access.

### Expected result

Expect a container response naming `tfstate`, with no stderr errors. Review
guest output even if Azure reports the Run Command request succeeded.

A successful read establishes managed identity authentication and data-plane
reachability from the VM. Since this configuration disables Storage public
access after provisioning, it is also an end-to-end check of the intended
private-endpoint path. It is not a test of blob writes, leases, or Terraform
backend initialization.

Share the filtered response and any sanitized errors. On failure, stop
without retrying, changing role assignments, enabling public access, or
switching identities as an automatic workaround.

The system-assigned identity is intended for the state backend; the
subscription-Owner user-assigned identity is intended for the later Sandbox
provider configuration. Keep those authentication roles distinct.

## Step 10: Check the Sandbox deployment identity

Complete the [state-storage access check](#step-9-check-managed-identity-access-to-state-storage).
The system-assigned identity is used for the state backend. This step checks
the separate user-assigned identity intended for Sandbox provider
authentication.

### Permissions already provisioned versus a separate admin grant

With `enable_user_assigned_identity = true`, the bootstrap automatically
creates `azurerm_role_assignment.user_assigned_identity_owner` at subscription
scope. No separate manual Azure RBAC grant is required for the identity's
`Owner` role. The commands below verify the live assignment rather than
granting it.

Microsoft Graph `Group.ReadWrite.All` is different: Terraform does not grant
it. If Sandbox deployments will enable `mssql`, an authorized Entra
administrator must complete `scripts/grant-graph-permissions.sh` before those
deployments. Subscription `Owner` is not Entra administrator consent.
Confirm the module scope and administrator availability before selecting that
separate grant step.

### Authenticate and inspect the subscription role

Run from `extras/configurations/rg-devops-iac` in the same workstation Bash
terminal. Keep `VM_ID` populated from step 6. The commands capture identity
IDs from the completed bootstrap's outputs without printing them.

```bash
UAI_CLIENT_ID=$(terraform output -raw user_assigned_identity_client_id) &&
UAI_PRINCIPAL_ID=$(terraform output -raw user_assigned_identity_principal_id) &&
SUBSCRIPTION_ID=$(printf '%s\n' "$VM_ID" | cut -d / -f 3) &&
GUEST_SCRIPT=$(cat <<EOF
set -eu
sudo -H -u githubrunner -- az login --identity --client-id "$UAI_CLIENT_ID" --output none
sudo -H -u githubrunner -- az account set --subscription "$SUBSCRIPTION_ID"
sudo -H -u githubrunner -- az account show --query "{subscriptionMatches:id == '$SUBSCRIPTION_ID', state:state}" --output json
sudo -H -u githubrunner -- az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[?principalId == '$UAI_PRINCIPAL_ID'].{role:roleDefinitionName}" --output json
sudo -H -u githubrunner -- az login --identity --allow-no-subscriptions --output none
printf 'Runner Azure CLI context restored to the system-assigned identity.\n'
EOF
) &&
az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts "$GUEST_SCRIPT" \
  --query 'value[].message' \
  --output tsv
```

The user-assigned identity is selected explicitly by client ID, as required
when the VM also has a system-assigned identity. Subscription scope comes
from the previously confirmed bootstrap VM resource ID.

These are read-only Azure requests. They do not create role assignments or
deploy resources. They temporarily change the runner account's local Azure
CLI context, then restore system-assigned identity authentication on success.

### Expected result

Expect `subscriptionMatches: true`, `state: "Enabled"`, a role entry for
`Owner`, and the final context-restoration message.

Review stdout and stderr. If authentication or role inspection fails, the
guest command stops and may not reach context restoration. Report the
sanitized error and stop; do not attempt an automatic retry or permission
change.

Successful Azure authentication and subscription `Owner` do not establish
Microsoft Graph application permissions. If the later Sandbox deployment
enables `mssql`, arrange the separately documented `Group.ReadWrite.All`
grant by a Privileged Role Administrator or Global Administrator.

This check does not perform a Terraform Sandbox plan or validate all provider
operations. The later Sandbox configuration must use this identity's client
ID as `arm_client_id` with `arm_auth_mode = "msi"`. Do not change the
standalone bootstrap's service principal inputs.

## Step 11: Grant the optional Microsoft Graph permission

This step is required when the later Sandbox deployment enables `mssql` with
managed identity provider authentication. Skip it if that module will remain
disabled. Complete the [deployment identity check](#step-10-check-the-sandbox-deployment-identity)
first.

### Administrator gate

Before running the command, the operator must explicitly confirm:

- Sandbox deployments will enable `mssql`.
- The workstation Azure CLI is signed in to the correct tenant as an Entra
  **Privileged Role Administrator** or **Global Administrator**.
- That role is active. If activated through PIM after sign-in, sign in again
  so the current session reflects the role activation.

Subscription `Owner` is not sufficient. Do not run the grant on the VM using
its managed identity, or assume the bootstrap service principal can grant
application permissions.

If another administrator must perform the grant, arrange a private handoff
of the managed identity principal ID and the existing script. Do not publish
the actual identity ID.

### Run the existing grant script

Run on the **workstation**, from `extras/configurations/rg-devops-iac`, using
the confirmed administrator's Azure CLI session:

```bash
./scripts/grant-graph-permissions.sh
```

The script reads `user_assigned_identity_principal_id` from the completed
bootstrap outputs. It resolves Microsoft Graph's service principal and
`Group.ReadWrite.All` application role, inspects existing assignments, and
creates the assignment only if it is missing.

This command changes directory permissions: it grants a broad application
permission to read and write groups in the tenant. It is not merely an
authentication check or an Azure RBAC assignment. Limit access to the runner
and its trusted deployment workflows accordingly.

Managed identities have no application registration to configure through the
usual app-registration API permissions interface; this script creates the
application role assignment on the managed identity service principal.

### Report the result safely

Expected output includes either:

```text
Group.ReadWrite.All: granted.
Microsoft Graph permission grant complete.
```

or:

```text
Group.ReadWrite.All: already granted.
Microsoft Graph permission grant complete.
```

The script also prints the actual managed identity name and principal ID.
Keep those locally; share only the permission-status and completion lines.
If it fails, share the sanitized error, preserve the full output locally, and
stop without retrying, broadening permissions, or switching credentials as
an automatic workaround.

A successful grant does not configure the Sandbox backend or a deployment
workflow. Those remain separate from this standalone infrastructure bootstrap.

## Step 12: Clean up and hand off to Sandbox workflows

After completing the preceding checks, the standalone runner infrastructure
is provisioned and its prerequisites are verified:

- Cloud-init completed without reported errors.
- The runner service is active and GitHub reports the expected runner online,
  idle, and labeled for Azure Sandbox.
- The runner account can use the required deployment toolchain.
- The system-assigned identity can read the state container from the VM.
- The user-assigned identity authenticates to the intended subscription and
  has subscription `Owner`.
- If `mssql` will be enabled, an authorized administrator completed the
  Microsoft Graph `Group.ReadWrite.All` grant.

This does not mean an Azure Sandbox has been deployed or that a deployment
workflow, Terraform backend initialization, blob writes, or state leases have
been tested.

### Remove the applied plan and clear the registration token export

Run in the workstation's Bash terminal from
`extras/configurations/rg-devops-iac`, after confirming apply succeeded and
there is no operation in progress:

```bash
rm -- main.tfplan
unset TF_VAR_github_runner_token
```

The saved plan is no longer needed and can contain sensitive input values.
Removing this named file does not remove Terraform state or Azure resources.

The registered runner does not use the PAT for ordinary jobs. Unsetting the
workstation export does not revoke the PAT or delete its Key Vault secret.
Retain it securely according to the approved lifecycle and rotation policy
if future VM provisioning may need it. Re-export a valid registration
credential before a future bootstrap plan/apply with the runner enabled.

Preserve `terraform.tfstate`, any state backup, `terraform.tfvars`, and the
provider lock file. Keep bootstrap state secure and separate from Sandbox
state; do not run broad cleanup scripts or delete the bootstrap resource
group as plan cleanup.

### Separate Sandbox workflow configuration

A deployment workflow needs its own human-confirmed configuration:

| Concern | Required setup |
| --- | --- |
| Runner selection | Match `self-hosted`, `Linux`, `X64`, and `azuresandbox`; labels are routing, not an authorization boundary. |
| Source revision | Explicitly select the intended Sandbox revision. |
| Provider authentication | Set `arm_auth_mode = "msi"` and use the user-assigned identity client ID as `arm_client_id`. Do not copy the bootstrap service principal settings. |
| State backend | Use the provisioned storage account and container with Azure AD/managed identity authorization, normally the system-assigned identity. |
| State key | Confirm a unique, stable key for the intended Sandbox; do not mix it with bootstrap state. |
| Job workspace | Generate environment-specific inputs and backend configuration securely in each checkout; ignored local files are not automatically available to Actions jobs. Preserve an existing backend rather than overwriting it. |
| Deployment inputs | Confirm tenant/subscription, region, operator object ID, module selection, organizational tags, and test scope before planning or applying. |
| Concurrency | Serialize operations against each Sandbox state, including interactive operations. |
| Workflow trust | Restrict privileged execution to trusted workflows and code; do not run untrusted pull-request code on this runner. |

See [Terraform State for CD Workflows](./modules/vm-jumpbox-linux/README.md#terraform-state-for-cd-workflows)
for the backend shape and the [root Sandbox documentation](../../../README.md)
for the separate configuration.

The bootstrap's `tags` map and the Sandbox's `additional_tags` mechanism are
different. Do not carry tags into a Sandbox deployment by assumption: capture
them explicitly for that deployment and include them consistently in its
plan/apply inputs.

Subscription `Owner` does not substitute for Storage data-plane roles. Avoid
unintentionally making the backend select the user-assigned identity through
a shared `ARM_CLIENT_ID` export when its storage authorization was configured
for the system-assigned identity.
