# GitHub Sandbox Deployment Workflow Setup

This guide documents an attended, step-by-step setup of a GitHub Actions
workflow that deploys a new Azure Sandbox on the self-hosted runner provisioned
by [GitHub Self-Hosted Runner Setup](./github-selfhosted-runner-setup.md).
The operator executes the commands and reviews each result before proceeding.
This is not a production deployment guide.

This guide records setup, publication, protected approval, and the first
successful full Sandbox deployment with JSON/JUnit evidence.
Earlier steps retain historical setup decisions and commands.
The latest policy in step 43 provisions new Sandboxes only, rejecting existing
state on every attempt. Steps 40 through 44 record changes developed locally
after the first deployment. Step 45 describes their coordinated publication:
verify both trusted source and registration before another dispatch.
Step 51 describes the subsequent Bash + PowerShell port and removal of the
retained helper test suite. Step 52 records authorization for coordinated
publication and a fresh full acceptance run. The second deployment used the
Python implementation; its test failure was correctly reported.
Step 73 changes the unit-test stage to JSON-only output and consumption.
Earlier JUnit artifact observations describe historical runs, not the current
output contract.
Step 93 makes release static CI a prerequisite for deployment approval and
moves both branches from classic branch protection to rulesets. Step 94
introduces the `azuresandbox-owners` team, splits the release checks into
separate rulesets, and restores a classic push restriction on `main`. Earlier
descriptions of branch protection are historical, not current policy.
Step 95 adds a manual `source_branch` choice so a run can deploy `main` as
well as `vnext`; earlier references to a fixed `vnext` manual checkout are
historical.

## Deployment scope and success criteria

The intended workflow is manually triggered, not triggered by untrusted
pull-request code or every push. It deploys an explicitly selected Sandbox
revision; the walkthrough uses `vnext`.

All base modules are enabled:

| Module | Enablement |
| --- | --- |
| `vnet_shared` | Always enabled by the root configuration. |
| `vnet_app` | `enable_module_vnet_app = true`. |
| `vm_jumpbox_linux` | `enable_module_vm_jumpbox_linux = true`. |
| `vm_mssql_win` | `enable_module_vm_mssql_win = true`. |
| `mssql` | `enable_module_mssql = true`. |
| `mysql` | `enable_module_mysql = true`. |
| `vwan` | `enable_module_vwan = true`. |

Extra modules under `extras/modules` remain disabled, including `avd`,
`petstore`, and `vnet_onprem`. Do not interpret "all base modules" as enabling
every optional module in the repository.

The operator selected the existing all-modules test behavior:
`scripts/Invoke-UnitTests.ps1` runs unit tests and applicable integration tests
automatically when `-Module` is omitted. Do not add `-Integration` to an
all-modules invocation.

The workflow has three sequential stages: `preflight`, `apply`, and
`unit-test`. Report each stage's result separately. The apply stage succeeds
when its saved Terraform plan applies successfully; it does not include VM
startup or testing. A later test failure does not change that apply result.

Full deployment-and-test success requires successful apply followed by
successful unit-test execution. The workflow must distinguish test failures
from test harness or infrastructure errors; it must not report full success
when tests were skipped because an earlier stage failed.

The existing test orchestrator supports JSON results and uses these
exit codes:

| Exit code | Meaning |
| --- | --- |
| `0` | Tests passed. |
| `1` | One or more tests failed. |
| `2` | Test harness error; tests may not have run or may be incomplete. |

Result handling must preserve the real test exit code. Avoid `continue-on-error`
or output pipelines that turn failure into a successful job. Public reporting
should use sanitized status and counts, not unfiltered resource details.

## Authentication, inputs, and state boundaries

This deployment workflow uses managed identities, not user-managed
authentication secrets. Store the complete backend and input HCL files as
GitHub **environment secrets**, accessed through `secrets`. This protects
configuration containing identity IDs and all required tags; it does not
introduce an Azure password, PAT, or storage key.
Secret values cannot be read back through the GitHub UI or API after saving.
GitHub masks recognized secret values in logs, but partial or reformatted
configuration values may remain visible. Do not print the files or rely on
masking to sanitize raw Terraform output.
Keep actual deployment values out of committed files and public documentation.

The operator must explicitly confirm the deployment target and test scope
before planning or applying. The walkthrough selects the same tenant,
subscription, region, and operator object ID as the standalone bootstrap,
with separate, human-supplied Sandbox tags.

Use the runner's user-assigned identity for Sandbox provider authentication:
`arm_auth_mode = "msi"` and its client ID as `arm_client_id`. The root
configuration supports this without a service principal password. Keep
Azure CLI and Azure PowerShell authentication aligned with this identity for
deployment management operations and tests.

For the root Sandbox `terraform.tfvars`, add the authentication mode and
replace the SPN client ID with the user-assigned identity's **client ID**:

```hcl
arm_auth_mode = "msi"
arm_client_id = "<user-assigned-managed-identity-client-id>"
```

Use the client ID, not the identity's principal/object ID. Keep the confirmed
tenant, subscription, region, and operator `user_object_id` unchanged.
The root providers select MSI through `arm_auth_mode`; setting `ARM_USE_MSI`
alone does not replace this input.

Retrieve the identity client ID privately from the standalone bootstrap
directory, after confirming no bootstrap apply is running:

```bash
terraform output -raw user_assigned_identity_client_id
printf '\n'
```

Do not paste the output into chat or public documentation. The root MSI
configuration does not require an SPN secret, and its workflow should not
receive `TF_VAR_arm_client_secret`. The standalone `rg-devops-iac` bootstrap
still uses SPN authentication; preserve its separate `arm_client_id`, input
file, and operator-session secret.

Run the root MSI configuration on the Azure runner to which this identity
is attached, not from the workstation merely because its input file was
edited. Terraform automatically loads `terraform.tfvars`, not the misspelled
`terraform.tfvrs`; the latter is also not covered by the existing tfvars
ignore rule.

Use the system-assigned identity for the remote-state backend in the
bootstrap storage account's `tfstate` container. Use a unique, stable state
blob key for each independent Sandbox, as described in step 22, and verify
that a newly allocated key does not already belong to another deployment.
All stages within its provisioning run use that key. Later maintenance or
teardown must preserve that same state, but is manual and outside this workflow.
Do not deploy with workstation-local or runner-local Sandbox state.

Immediately after checking out the Sandbox source, create `backend.tf` in
the runner checkout's repository root, before any `terraform init`.
Generate it from confirmed backend settings rather than committing deployment
identifiers. Fail explicitly if backend configuration cannot be created or
initialized; never fall back to local state. Do not overwrite an existing
backend file or alter a workstation checkout's unrelated backend.

Environment-specific tags are required in this walkthrough. The operator
includes their confirmed values in the `tags` map in the approved root
`terraform.tfvars`. Never infer or reuse values from an earlier deployment.
The runner has no separate tag configuration variable or
`-var='additional_tags=...'` argument. That mechanism belongs to interactive
deployments and is outside this runner workflow.

Preserve any workstation-root `terraform.tfvars`, backend configuration, and
state from other deployments. The workflow needs its own securely generated
inputs and backend configuration in the Actions checkout; ignored local files
are not automatically copied to a runner job.

The preceding runner guide verifies subscription `Owner`, state-container
read access, and the optional Microsoft Graph `Group.ReadWrite.All` grant
needed for `mssql`. It does not verify every backend operation or all
deployment prerequisites.

The subscription `Owner` assignment belongs to the **user-assigned identity**,
not the VM's system-assigned identity. The bootstrap creates it automatically
when `enable_user_assigned_identity = true`; see the runner guide's
[deployment identity check](./github-selfhosted-runner-setup.md#step-10-check-the-sandbox-deployment-identity).
The system-assigned identity instead has storage data-plane access for the
backend. Verify the live deployment-identity assignment before a real
deployment; do not grant the system-assigned identity subscription `Owner`
as a workaround or infer RBAC verification from the smoke toolchain check.

The attended read-only RBAC check in this walkthrough returned `Owner` for
the provisioned user-assigned identity at the bootstrap subscription scope.
No new role assignment was needed. This does not verify backend writes or
the identity selection in the future deployment job.

## Workflow safety and publication

Only trusted code may execute on this privileged runner. Serialize all
operations against the same Sandbox state and do not cancel a healthy apply
to start a newer run. Do not start another interactive apply or inspect state
while a workflow apply is in progress.

Immediately before tests, start the Sandbox VMs using
`scripts/manage-vms.sh start` and confirm the relevant VMs are actually
running. The script issues asynchronous starts for some VMs; command success
alone does not satisfy this gate.

Do not publish actual subscription/tenant/identity IDs, organizational tags,
deployment resource names, private addresses, credentials, or raw state/plan
contents in this document, commits, issues, or PR descriptions. Use
placeholders. Keep saved plans and generated configuration out of public
artifacts.

Stop on a deployment or setup error, preserve the command and full error
locally, and report sanitized details. Do not retry, modify permissions, or
work around a failure automatically.

Before each push that triggers repository CI or creation of a PR targeting
`vnext`, run the relevant checks through `scripts/Invoke-CIChecks.sh` after
committing. A failed check blocks publication. Topic PRs target `vnext`; the
`vnext` to `main` release path uses a regular merge commit.

## Step 1: Discover GitHub workflow availability and permissions

Run in the existing workstation Bash terminal from
`extras/configurations/rg-devops-iac`. These are read-only checks. They do not
create an environment, set secrets, publish commits, or start a workflow.

The GitHub CLI must be authenticated using an authorized operator's account.
The registration PAT from runner setup is not needed for ordinary runner jobs,
and unsetting it in the preceding guide does not authenticate `gh` itself.
Do not substitute an unrelated or insufficiently scoped token.

```bash
set +x

git branch --show-current

gh api --method GET repos/Azure-Samples/azuresandbox \
  --jq '{default_branch, can_push: .permissions.push, can_administer: .permissions.admin}' &&
gh api --method GET --paginate \
  repos/Azure-Samples/azuresandbox/actions/workflows \
  --jq '[.workflows[] | {name, path, state}]'
```

Share this filtered output. If authentication fails or repository permissions
are insufficient, stop and resolve the setup gate before modifying GitHub.
Permission booleans alone do not prove that branch protection permits a
direct push; publication must follow repository branch/PR rules.

### Default-branch requirement

GitHub requires a `workflow_dispatch` workflow to exist on the repository's
default branch before it can be manually dispatched. Adding a new workflow
only to `vnext` is not sufficient if the default branch is `main`.
Once registered, a workflow can be dispatched for another branch with
`gh workflow run ... --ref ...`.

See [Manually running a workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
Confirm the default branch and existing workflows first, then explicitly
decide the publication path before building or dispatching the deployment
workflow. Do not bypass branch protection or change the repository's default
branch to avoid this requirement.

## Step 2: Choose publication and approval gates

The deployment environment name for this walkthrough is `sandbox-deployment`.
The operator selected the workflow-only publication exception and operator
approval, with the currently authenticated GitHub account as the reviewer
and self-approval allowed. Environment creation and configuration are still
pending. Review the choices below when adapting this guide for another setup.

First publish a smoke-only manually triggered workflow to verify real Actions
execution on the runner without provisioning a Sandbox or running the
unit/integration test orchestrator. Add the deployment and test stages only
after that smoke run succeeds and deployment inputs are confirmed.

### Publication choices

The workflow's GitHub registration and the Terraform source revision are
separate. A workflow published on `main` can be manually dispatched on `main`
and explicitly check out the approved `vnext` revision for deployment.
Publishing the workflow on `main` does not require deploying Terraform from
`main`.

| Path | Effect | Tradeoff |
| --- | --- | --- |
| Normal release | Merge a topic PR into `vnext`, then a regular-merge release PR from `vnext` into `main`. | Preserves the normal branch lineage, but releases all pending `vnext` changes, not just the workflow. |
| Workflow-only exception | Merge the topic PR into `vnext`, then create a separate, narrowly scoped PR based on `main` containing the new workflow registration change. | Allows testing the approved `vnext` source without releasing unrelated changes; requires explicit authorization for a PR targeting `main`. |
| Defer registration | Prepare and review the workflow on `vnext`, leaving publication to a later release. | Makes no exception and no immediate release, but cannot manually dispatch the new workflow yet. |

Use the normal release path if the pending `vnext` changes are ready for
release. Otherwise, the workflow-only exception limits the scope of immediate
publication. Neither path authorizes direct pushes to `main`, changing the
default branch, or merging unrelated changes without review.

### Approval choices

An environment approval is a pause before the privileged deployment job
starts and receives its environment configuration. It is separate from PR
review and separate from clicking **Run workflow**.

| Gate | Operator experience | Protection |
| --- | --- | --- |
| Operator approval | An authorized environment reviewer approves the pending run; self-approval is allowed if that reviewer triggered it. | Adds an explicit last check without requiring another person. |
| Separate reviewer | Another configured reviewer must approve; self-approval is blocked. | Provides a second-person check, but requires that person to be available. |
| Dispatch only | The manually dispatched run starts without an additional environment approval. | Relies on dispatch authorization and branch restrictions; fewer human checkpoints. |

For an attended personal sandbox exercise, operator approval is a practical
additional checkpoint. For shared privileged infrastructure, a separate
reviewer provides stronger oversight. Only configure a gate whose reviewer
can actually approve the run.

All options still require trusted workflow/source revisions, a restricted
environment deployment branch, and concurrency controls. Environment approval
does not isolate the VM's managed identities from other jobs that execute on
the same runner.

No GitHub environment changes or publication commands should run until these
decisions are confirmed.

## Step 3: Inspect the selected GitHub environment

Before creating or configuring `sandbox-deployment`, check whether it already
exists. Do not overwrite an existing environment's protection rules, reviewers,
or secrets without reviewing them and authorizing the changes.

Run from the workstation's existing Bash terminal:

```bash
gh api --method GET --paginate \
  repos/Azure-Samples/azuresandbox/environments \
  --jq '[.environments[] | select(.name == "sandbox-deployment") | {name, protection_rules: [(.protection_rules // [])[] | {type, prevent_self_review, reviewer_count: ((.reviewers // []) | length)}], deployment_branch_policy}]'
```

This is a read-only query. It filters to the selected environment and reports
reviewer counts rather than account names or IDs. Each page produces an
array. If all arrays are empty, the environment does not exist; if a page
contains the environment, review its existing settings before proceeding.

Share the filtered output. On an authentication or permission error, stop
and report the sanitized error. Do not create the environment or configure
secrets yet.

The intended environment configuration will restrict deployment workflow
runs to `main` and require the selected operator's approval, with
self-approval allowed. The workflow on `main` will explicitly check out the
trusted `vnext` source; this does not require allowing deployment workflow
runs from arbitrary branches.

## Step 4: Create the protected deployment environment

Proceed only after step 3 confirms `sandbox-deployment` is absent. These
commands create it with the selected operator's GitHub account as its sole
required reviewer, self-approval allowed, no wait timer, and a custom
deployment branch policy allowing only the `main` branch.

Run from the same workstation Bash terminal:

```bash
set +x
set -o pipefail

REVIEWER_ID=$(gh api --method GET user --jq '.id') &&
printf '{"wait_timer":0,"prevent_self_review":false,"reviewers":[{"type":"User","id":%s}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n' "$REVIEWER_ID" |
  gh api --method PUT \
    repos/Azure-Samples/azuresandbox/environments/sandbox-deployment \
    --input - \
    --jq '{name}' &&
gh api --method POST \
  repos/Azure-Samples/azuresandbox/environments/sandbox-deployment/deployment-branch-policies \
  -f name=main \
  -f type=branch \
  --jq '{name, type}' &&
gh api --method GET \
  repos/Azure-Samples/azuresandbox/environments/sandbox-deployment \
  --jq '{name, protection_rules: [(.protection_rules // [])[] | {type, prevent_self_review, reviewer_count: ((.reviewers // []) | length)}], deployment_branch_policy}'
```

The authenticated operator's reviewer ID is captured without printing it.
These commands change GitHub environment settings but create no Azure
resources and start no workflow. The `&&` chain and `pipefail` stop subsequent
commands after a failure.

Expected output includes the environment name, a branch policy with
`name: "main"` and `type: "branch"`, and a `required_reviewers` rule with
`reviewer_count: 1` and `prevent_self_review: false`. The deployment branch
policy should report `protected_branches: false` and
`custom_branch_policies: true`; the separate name rule selects `main`.

The branch policy applies to the workflow run's branch, not the source ref
checked out by a workflow step. The approved workflow runs on `main` and
explicitly checks out `vnext`.

Additional custom deployment protection rules may be offered by GitHub Apps
already installed on the repository. This walkthrough does not enable them.
These are external approval/rejection gates before an environment job starts,
not post-deployment unit tests or Azure identity permissions. Only enable a
rule if organizational policy requires it and its owner confirms the supported
approval behavior and configuration. Availability in the UI alone does not
prove the app implements a suitable gate. Leaving an optional environment
rule unchecked does not uninstall its GitHub App.

See [Configuring custom deployment protection rules](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/configure-custom-protection-rules).
A rule whose service does not respond can leave the job waiting until GitHub's
timeout, which can be up to 30 days. Keep the selected reviewer and branch
protections; do not remove an organization-required rule as a workaround.

Share the filtered output. If creation succeeds but a later command fails,
the environment may be partially configured. Stop and preserve the sanitized
error; do not repeat the creation command or adjust protections as an
automatic workaround. Do not add secrets or dispatch a workflow yet.

The API references are
[Create or update an environment](https://docs.github.com/en/rest/deployments/environments#create-or-update-an-environment)
and [Create a deployment branch policy](https://docs.github.com/en/rest/deployments/branch-policies#create-a-deployment-branch-policy).

## Step 5: Create the smoke-only workflow on a topic branch

Proceed after step 4 confirms the environment's reviewer and `main` branch
protections. Work on a topic branch based on `vnext`, preserving the existing
documentation changes. Do not commit or push yet.

The commands below create `.github/workflows/sandbox-deployment.yml` and
`.github/actionlint.yaml` at the repository root. The lint configuration
declares the custom runner label without disabling any checks.

Run from `extras/configurations/rg-devops-iac`:

```bash
git switch -c feat/sandbox-workflow vnext &&
(
  set -e
  set -o noclobber

  cat > ../../../.github/workflows/sandbox-deployment.yml <<'YAML'
name: Azure Sandbox deployment

on:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: azure-sandbox-deployment
  cancel-in-progress: false

defaults:
  run:
    shell: bash

jobs:
  smoke:
    name: Self-hosted runner smoke test
    runs-on: [self-hosted, linux, x64, azuresandbox]
    environment: sandbox-deployment
    timeout-minutes: 180
    steps:
      - name: Check out the approved Sandbox source
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: vnext
          persist-credentials: false

      - name: Check runner and toolchain
        id: smoke
        run: |
          set -euo pipefail
          if [[ "$RUNNER_NAME" != "jumplinux2" ]]; then
            echo "::error::The job did not run on the expected runner."
            exit 1
          fi
          if [[ "${ARM_USE_MSI:-}" != "true" || -z "${ARM_TENANT_ID:-}" ]]; then
            echo "::error::The runner managed identity environment is incomplete."
            exit 1
          fi
          git --version
          terraform version
          az version --query '"azure-cli"' --output tsv
          # PowerShell must expand these variables, not Bash.
          # shellcheck disable=SC2016
          pwsh -NoLogo -NoProfile -Command '$ErrorActionPreference = "Stop"; $PSVersionTable.PSVersion.ToString(); Import-Module Az -ErrorAction Stop; Get-Module Az,Az.Accounts | Select-Object Name,Version'
          printf 'All smoke checks passed.\n'

      - name: Report smoke result
        if: ${{ always() }}
        env:
          SMOKE_OUTCOME: ${{ steps.smoke.outcome }}
        run: |
          case "$SMOKE_OUTCOME" in
            success) result=PASS ;;
            failure) result=FAIL ;;
            *) result="NOT RUN ($SMOKE_OUTCOME)" ;;
          esac
          {
            printf '## Self-hosted runner smoke test\n\n'
            printf 'Result: **%s**\n\n' "$result"
            printf 'No Azure resources were deployed and no Sandbox unit/integration tests were run.\n'
          } >> "$GITHUB_STEP_SUMMARY"
YAML

  cat > ../../../.github/actionlint.yaml <<'YAML'
self-hosted-runner:
  labels:
    - azuresandbox
YAML
) &&
git status --short
```

The subshell uses `noclobber` to prevent overwriting either existing file.
If the topic branch or a file already exists, stop and report that result
rather than resetting, deleting, or overwriting it.

The runner labels are matched case-insensitively by GitHub. The default
runner name check corresponds to the preceding runner guide; adapt it if the
approved runner has a different configured name.

The workflow has only a manual trigger, references the protected environment,
uses read-only repository token permissions, and explicitly checks out the
trusted `vnext` source. It verifies the runner's managed identity environment
without printing tenant values, imports the installed Az modules, and reports
smoke success, failure, or non-execution separately.

The inline PowerShell command intentionally uses Bash single quotes so that
PowerShell, not Bash, expands its variables. The preceding ShellCheck directive
suppresses SC2016 only for that command. Do not change it to Bash double quotes.

The environment's `main` policy means this topic-branch workflow cannot yet
run its protected job. The publication stage must register the workflow on
`main` before dispatch. The narrowly scoped `main` exception will include the
workflow and its required custom-runner lint configuration, not unrelated
pending `vnext` changes.

This smoke test does not log in to Azure, initialize Terraform, deploy a
Sandbox, or invoke its unit/integration tests. Keep that distinction visible
in the summary until deployment stages are added.

### Runtime budgets

The initial workflow uses `timeout-minutes: 180` so the intended deployment
budget is present from the start. It still executes only smoke checks at this
stage, which should take a few minutes.

Retain the three-hour budget when adding the full deployment/test job. This
provides an hour of headroom for an approximately two-hour run, including
preflight, planning, provisioning all base modules, VM startup, tests, and
reporting. The environment approval happens before job execution.

When adding the full job, review its step-level and Terraform resource
timeouts too; a larger job budget does not override a shorter inner timeout.
Avoid automatic cancellation of an advancing apply. If a run times out,
preserve the evidence and inspect the outcome only after the apply has
stopped; do not automatically retry against potentially partial state.

Share the branch-switch and file-status output, not any local credentials or
state. Review and validation come next; do not commit, push, open a PR, or
dispatch yet.

## Step 6: Validate the local workflow and documentation

Review the actual files created in step 5, not merely the terminal's pasted
command text. Confirm the workflow is still smoke-only, uses the protected
environment and approved source, and has the intended three-hour job budget.

Run this batch from `extras/configurations/rg-devops-iac`:

```bash
(
  cd ../../.. &&
  ./scripts/Invoke-CIChecks.sh actions markdown links secrets &&
  git diff --check &&
  git status --short
)
```

The subshell runs checks from the repository root without changing the
operator's terminal directory. These are static checks; they do not run the
smoke workflow or provision a Sandbox.

The selected checks cover Actions workflow validation, Markdown, internal
links, and secret scanning. Secret scanning is included because it is a
repository-wide PR gate. Do not stage local tfvars, state, plans, SSH keys,
or generated deployment settings.

Share the check summary, warnings, any `SKIPPED` tool messages, and final
file status. `FAILED` blocks publication. `SKIPPED` is not a failure, but
means the missing local tool's gate still needs verification by GitHub CI.

Do not commit or push yet. After review, publication instructions will stage
only the intended files, create the local commit, and run the relevant checks
again after committing and before pushing or opening a PR. Do not treat this
preliminary run as a replacement for that mandatory publication gate.

## Step 7: Commit the reviewed files and repeat the publication checks

Proceed only after step 6 reports no failures and its file status contains
only the intended changes. In this walkthrough, Markdown and internal links
passed, Actions and secret scans were skipped because the local tools were
missing, and Node 22 differed from CI's Node 20. Skipped gates must be verified
by GitHub CI before merging.

Run from `extras/configurations/rg-devops-iac`:

```bash
(
  cd ../../.. &&
  git add -- \
    .github/actionlint.yaml \
    .github/workflows/sandbox-deployment.yml \
    extras/configurations/rg-devops-iac/README.md \
    extras/configurations/rg-devops-iac/github-selfhosted-runner-setup.md \
    extras/configurations/rg-devops-iac/github-sandbox-workflow-setup.md &&
  git diff --cached --check &&
  git diff --cached --stat &&
  git commit \
    -m "Add self-hosted Sandbox smoke workflow and setup guides" \
    -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" &&
  ./scripts/Invoke-CIChecks.sh actions markdown links secrets &&
  git status --short
)
```

The explicit paths avoid staging ignored state, tfvars, saved plans, or other
unrelated files. Do not run the commit command if unrelated changes have
already been staged; review and separate them first.

This creates a local commit only. The check runner executes after committing,
as required before publication. Share the commit summary, check summary,
skipped/warning messages, and final status. Stop on failure; do not amend the
commit, push, or open the PR as an automatic workaround.

Do not proceed to step 8 until the results have been reviewed. If files
change afterward, review and commit those changes and run the applicable
checks again before publication.

## Step 8: Publish the topic branch and open the vnext PR

Proceed only after step 7 is accepted and the intended changes are committed.
This publishes the topic branch and opens a PR targeting `vnext`; it does not
merge the PR, publish the workflow on `main`, or dispatch a deployment.

Run from `extras/configurations/rg-devops-iac`:

```bash
(
  cd ../../.. &&
  ./scripts/Invoke-CIChecks.sh actions markdown links secrets &&
  git push --set-upstream origin feat/sandbox-workflow &&
  ./scripts/Invoke-CIChecks.sh actions markdown links secrets &&
  gh pr create \
    --repo Azure-Samples/azuresandbox \
    --base vnext \
    --head feat/sandbox-workflow \
    --title "Add self-hosted Sandbox smoke workflow and setup guides" \
    --body "$(cat <<'EOF'
## Summary

- Add a manually triggered, environment-protected self-hosted runner smoke workflow.
- Declare the custom runner label for actionlint.
- Document runner provisioning and the step-by-step Sandbox workflow setup.

The workflow currently checks the runner environment and installed toolchain only.
It does not deploy Azure resources or run Sandbox unit/integration tests.
A narrowly scoped follow-up PR to the default branch is required for manual dispatch.

## Validation

- Local Markdown and internal-link checks passed.
- Local Actions and secret scans were skipped because actionlint and gitleaks were unavailable; GitHub CI must verify these gates.
- Local Node 22 differs from the Node 20 used by documentation CI.
EOF
)"
)
```

Checks run before both publication actions, and a failure stops the command
chain. If the local tool availability or check outcomes differ from those
recorded above, update the PR validation wording to match the actual results.

Share the check summaries and PR URL. Wait for hosted CI and resolve the
required review gate as described in step 9 before merging. Do not bypass
failed or pending checks or change repository protection settings. The
workflow's environment allows only `main` runs, so this `vnext` PR is not
itself a deployment trigger.

## Step 9: Verify hosted CI and obtain required PR review

Use the PR number returned in step 8. Discover it from the current topic
branch and inspect its checks and merge readiness:

```bash
PR_NUMBER=$(gh pr view \
  --repo Azure-Samples/azuresandbox \
  --json number --jq '.number') &&
gh pr checks "$PR_NUMBER" \
  --repo Azure-Samples/azuresandbox \
  --watch --interval 10 &&
gh pr view "$PR_NUMBER" \
  --repo Azure-Samples/azuresandbox \
  --json baseRefName,headRefOid,mergeable,mergeStateStatus,reviewDecision,isDraft
```

Immediately after a push, the checks command may still show the preceding
commit's results before GitHub registers new runs. Verify the Actions run
belongs to the current commit before interpreting an apparent lint failure:

```bash
gh run list \
  --repo Azure-Samples/azuresandbox \
  --workflow ci-actions.yml \
  --branch feat/sandbox-workflow \
  --commit "$(git rev-parse HEAD)" \
  --limit 3 \
  --json databaseId,headSha,status,conclusion,url
```

A passing CI result and `mergeable: MERGEABLE` do not override required
review. If `reviewDecision` is `REVIEW_REQUIRED`, obtain approval from eligible
reviewers before merging. GitHub does not allow the PR author to approve
their own PR. The deployment environment's self-approval setting is a
separate control and does not satisfy branch review requirements.

Keep repository protection settings unchanged. If no eligible independent
reviewer is available, stop and obtain explicit operator authorization
before using an existing review-bypass permission for that PR. This exception
merges without independent review; it is not self-approval and must never
bypass failed or pending checks. Authorization for one PR does not authorize
any later PR.

Publish any remaining guide changes before requesting final review or using
an authorized exception, since new commits may invalidate earlier approvals.
Recheck the final PR head, checks, and merge readiness before proceeding.
For an authorized exception, use the existing portal bypass option and select
**Squash and merge** for the topic PR into `vnext`; do not add or modify bypass
rules. If the portal shows any other unmet requirement besides the explicitly
authorized review exception, stop and resolve it first. Do not dispatch yet:
the workflow still needs the separate default-branch registration PR.

## Step 10: Inspect the default branch before workflow registration

Proceed only after the topic PR is confirmed merged into `vnext`. The next PR
targets `main` and contains only `.github/workflows/sandbox-deployment.yml`
and its required `.github/actionlint.yaml` configuration. Do not merge or
cherry-pick the whole topic commit, since it also contains documentation.

Use a separate Git worktree for this registration PR to preserve the original
checkout's local deployment configuration, ignored state, and ongoing guide
updates. First refresh the branch references and inspect the relevant files
and existing worktrees. Run from `extras/configurations/rg-devops-iac`:

```bash
(
  cd ../../.. &&
  git fetch origin main vnext &&
  printf '\nRelevant files already on main:\n' &&
  git ls-tree -r --name-only origin/main -- \
    .github/workflows/sandbox-deployment.yml \
    .github/actionlint.yaml \
    scripts/Invoke-CIChecks.sh &&
  printf '\nRegistration-file differences:\n' &&
  git diff --name-status origin/main origin/vnext -- \
    .github/workflows/sandbox-deployment.yml \
    .github/actionlint.yaml &&
  printf '\nExisting worktrees:\n' &&
  git worktree list
)
```

These commands do not create a branch or worktree, change deployment settings,
or touch Terraform state. Share the output before preparing the registration
branch. Preserve any existing lint configuration on `main` rather than
replacing it blindly.

This publication exception authorizes a narrowly scoped PR targeting `main`,
not a direct push or a release of unrelated `vnext` changes. Any review-bypass
exception previously authorized for the topic PR does not apply to the new PR.
Do not dispatch the workflow until default-branch registration is complete.

## Step 11: Prepare the workflow-only main branch in a separate worktree

Proceed after step 10 confirms the two registration files are absent from
`main` and the local check runner is present. This walkthrough copies them
from the verified topic PR merge commit. When adapting the guide, replace
that public commit with your own verified merge commit.

Ensure actionlint 1.7.12 and ShellCheck are available on the client `PATH`.
Run from the original `extras/configurations/rg-devops-iac` directory:

```bash
(
  cd ../../.. &&
  REGISTRATION_WORKTREE="$(pwd)-workflow-registration" &&
  APPROVED_COMMIT=a6a85a84c01fa73587a8fc82804151f513f41925 &&
  git worktree add \
    -b feat/register-sandbox-workflow \
    "$REGISTRATION_WORKTREE" origin/main &&
  cd "$REGISTRATION_WORKTREE" &&
  git restore --source="$APPROVED_COMMIT" -- \
    .github/workflows/sandbox-deployment.yml \
    .github/actionlint.yaml &&
  git add -- \
    .github/workflows/sandbox-deployment.yml \
    .github/actionlint.yaml &&
  git diff --cached --check &&
  git diff --cached --exit-code "$APPROVED_COMMIT" -- \
    .github/workflows/sandbox-deployment.yml \
    .github/actionlint.yaml &&
  ./scripts/Invoke-CIChecks.sh actions secrets &&
  git diff --cached --stat &&
  git status --short
)
```

The sibling worktree starts from `origin/main`; only the two named files
are copied and staged. The comparison verifies they exactly match the approved
source. The subshell leaves the operator's terminal in its original directory.
Do not copy local tfvars, backend configuration, state, plans, or credentials
into the new worktree. Leave the original checkout's pending guide updates
untouched.

The current `ci-actions` automatic triggers target `vnext`, not `main`.
Require the local Actions check to report `PASSED`, not `SKIPPED`, and plan
separate hosted verification for the registration branch. Do not assume the
earlier topic PR checks validate this different `main`-based tree.

Share the check summary, staged diff summary, and file status. Expect exactly
two added files. If the branch or worktree path already exists, stop and report
the error rather than deleting or overwriting it. Do not commit, push, open
the registration PR, or dispatch the smoke workflow yet.

## Step 12: Commit and publish the narrow main registration PR

Proceed only after step 11 reports two staged additions, an exact source
comparison, and a passing Actions check. This publication is a PR to `main`,
not a direct push or a `vnext` release. Ensure the pinned actionlint binary
remains available on the client `PATH`.

Run from the original `extras/configurations/rg-devops-iac` directory:

```bash
(
  REGISTRATION_WORKTREE="$(git rev-parse --show-toplevel)-workflow-registration" &&
  cd "$REGISTRATION_WORKTREE" &&
  git diff --cached --check &&
  git diff --cached --stat &&
  git commit \
    -m "Register manual Sandbox smoke workflow on main" \
    -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" &&
  ./scripts/Invoke-CIChecks.sh actions secrets &&
  git push --set-upstream origin feat/register-sandbox-workflow &&
  ./scripts/Invoke-CIChecks.sh actions secrets &&
  gh pr create \
    --repo Azure-Samples/azuresandbox \
    --base main \
    --head feat/register-sandbox-workflow \
    --title "Register manual Sandbox smoke workflow on main" \
    --body "$(cat <<'EOF'
## Summary

- Register the manually dispatched, environment-protected Sandbox smoke workflow on the default branch.
- Copy only the workflow and its custom-runner lint configuration from the verified topic PR merge.
- Continue checking out the trusted vnext source without releasing unrelated vnext changes.

This workflow checks the self-hosted runner and installed toolchain only.
It does not deploy Azure resources or run Sandbox unit/integration tests.

## Validation

- Local actionlint 1.7.12 passed on the main-based registration tree.
- Local secret scanning was skipped because gitleaks was unavailable.
- Hosted Actions and secret checks will be manually dispatched for this branch; automatic CI targets vnext.
EOF
)"
)
```

The checks run after committing and before each publication action. Stop on
failure. If check outcomes differ, correct the PR validation wording before
creating the PR. No guide, Terraform configuration, state, or credential files
should be included in the registration commit.

Share the commit and check summaries and the new PR URL. Both `ci-actions.yml`
and `ci-secrets.yml` support manual dispatch on the registration branch; the
next step will use those hosted checks to cover the `main` PR's automatic-CI
gap. These static workflows use GitHub-hosted runners, not the Sandbox runner.
Do not merge, use a review bypass, or dispatch the Sandbox smoke workflow yet.
Any review exception for this new PR requires its own explicit authorization.

## Step 13: Dispatch hosted static checks for the main registration branch

Proceed after the registration PR is open and confirmed to contain only the
two approved files. Verify its published description and head commit, then
dispatch the existing hosted lint and secret-scanning workflows on that branch.
These workflows run on GitHub-hosted runners and do not deploy a Sandbox or
use the protected self-hosted smoke job.

For this walkthrough, the verified registration commit is
`2a3c42165ef37df4aae177660777c9c3e9edccb6`. When adapting the guide, use your own
verified registration commit:

```bash
gh workflow run ci-actions.yml \
  --repo Azure-Samples/azuresandbox \
  --ref feat/register-sandbox-workflow &&
gh workflow run ci-secrets.yml \
  --repo Azure-Samples/azuresandbox \
  --ref feat/register-sandbox-workflow &&
gh run list \
  --repo Azure-Samples/azuresandbox \
  --branch feat/register-sandbox-workflow \
  --commit 2a3c42165ef37df4aae177660777c9c3e9edccb6 \
  --event workflow_dispatch \
  --limit 5 \
  --json workflowName,databaseId,headSha,status,conclusion
```

Share the dispatch output and run list. The runs may not appear immediately;
an empty list is not a CI failure. Query their status again rather than
dispatching duplicate runs.

Before merging, wait for both identified runs and inspect their jobs, not just
their overall conclusions. Require the `actionlint` job and the `gitleaks`
job to complete successfully on the verified registration commit. A skipped
`actionlint` job does not validate the registration files. Also inspect the
PR's remaining checks and review requirements. Stop and report any failure.
Do not merge or dispatch the Sandbox smoke workflow yet.

## Step 14: Wait for hosted checks and inspect registration PR readiness

Use the two run IDs returned by step 13, even if one has not yet appeared in
the run list. Do not redispatch them. The IDs below are the public runs from
this walkthrough; substitute your own when adapting it:

```bash
gh run watch 37998497406 \
  --repo Azure-Samples/azuresandbox --exit-status --interval 10 &&
gh run view 37998497406 \
  --repo Azure-Samples/azuresandbox \
  --json headSha,conclusion,jobs \
  --jq '{headSha, conclusion, jobs: [.jobs[] | {name, conclusion}]}' &&
gh run watch 37998501453 \
  --repo Azure-Samples/azuresandbox --exit-status --interval 10 &&
gh run view 37998501453 \
  --repo Azure-Samples/azuresandbox \
  --json headSha,conclusion,jobs \
  --jq '{headSha, conclusion, jobs: [.jobs[] | {name, conclusion}]}' &&
gh pr checks 808 \
  --repo Azure-Samples/azuresandbox --watch --interval 10 &&
gh pr view 808 \
  --repo Azure-Samples/azuresandbox \
  --json baseRefName,headRefOid,mergeable,mergeStateStatus,reviewDecision,isDraft
```

Both run heads must match the registration PR head. Require successful
`actionlint` and `gitleaks` jobs, not skipped jobs, as well as resolution of
any other applicable PR checks. Share the job summaries and PR readiness.
If required independent review cannot be obtained, ask the operator for a
separate, PR-specific exception under the procedure in step 9. Do not infer
that the earlier topic PR's exception applies to this `main` PR.

Do not merge or dispatch the Sandbox smoke workflow in this batch.

## Step 15: Merge the clean registration PR and verify workflow registration

Proceed only after both hosted jobs pass on the exact registration PR head
and its remaining checks pass. In this walkthrough, the `main` PR reports
`mergeStateStatus: CLEAN`, `mergeable: MERGEABLE`, and no required review.
Use a normal merge without an administrator bypass.

Record the manually dispatched CI evidence on the PR because these runs may
not appear in its automatic check list. Then squash-merge this narrow topic
PR, matching the verified head to prevent merging an unexpected later commit.
This is not the `vnext` to `main` release PR, which uses a regular merge commit.
Substitute your own PR number, commit, and run links when adapting:

```bash
gh pr comment 808 \
  --repo Azure-Samples/azuresandbox \
  --body "Hosted validation passed on registration commit 2a3c42165ef37df4aae177660777c9c3e9edccb6. The actionlint job passed in https://github.com/Azure-Samples/azuresandbox/actions/runs/37998497406 and the gitleaks job passed in https://github.com/Azure-Samples/azuresandbox/actions/runs/37998501453. Neither validation job was skipped." &&
gh pr merge 808 \
  --repo Azure-Samples/azuresandbox \
  --squash \
  --match-head-commit 2a3c42165ef37df4aae177660777c9c3e9edccb6 &&
gh pr view 808 \
  --repo Azure-Samples/azuresandbox \
  --json state,mergedAt,baseRefName,mergeCommit &&
gh api --method GET --paginate \
  repos/Azure-Samples/azuresandbox/actions/workflows \
  --jq '[.workflows[] | select(.path == ".github/workflows/sandbox-deployment.yml") | {name, id, path, state}]'
```

Expect the PR to be merged into `main` and the workflow to appear as `active`.
An empty workflow list immediately after merging can mean registration is
still propagating; report it without attempting another merge or dispatch.
Do not change the workflow's triggers or protection settings to work around it.

Share the output before dispatching. Registration alone does not execute
the smoke job, deploy resources, or run Sandbox tests. Leave the worktrees
and original deployment files in place for the next steps.

## Step 16: Dispatch and approve the first self-hosted smoke run

Proceed only after the registration PR is merged into `main` and the workflow
is listed as `active`. The registered workflow still performs smoke checks
only: it does not initialize Terraform, deploy resources, or run Sandbox tests.

Run from the operator's existing terminal:

```bash
gh workflow run sandbox-deployment.yml \
  --repo Azure-Samples/azuresandbox \
  --ref main
```

Dispatch on `main`, not `vnext`, to satisfy the environment's branch policy.
The workflow explicitly checks out the trusted `vnext` source afterward.
Keep the returned run ID and URL; do not dispatch another run if approval is
pending.

Approve from the workflow run page, not the PR page or repository environment
settings. Sign in to the GitHub account configured as the required environment
reviewer (the account used when creating the environment in step 4):

1. Open the run URL returned by the dispatch command.
2. Select **Summary** in the run's left sidebar if another view is open.
   Verify the branch is `main` and the job is **Self-hosted runner smoke test**.
3. Find the notification that the run is waiting for review and click
   **Review deployments**.
4. In the dialog, select the checkbox for `sandbox-deployment`.
5. Leave the optional comment blank or describe the smoke-only approval,
   then click **Approve and deploy**.
6. Confirm the waiting-for-review notification disappears. The job should
   then queue for the runner or start running.

This is the configured environment approval, not a PR review or rules bypass.
The selected environment permits the operator to approve their own dispatch.
Do not select **Start all waiting jobs** or
**I understand the consequences, start deploying**; those controls bypass
environment protection rather than submit the normal reviewer approval.

If **Review deployments** is not visible, refresh the run's **Summary** page
and verify the browser is signed in as the configured reviewer. Do not change
environment protection settings; report what the portal shows if the expected
approval controls remain unavailable.

See GitHub's [deployment review instructions](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments).

Share the dispatch output and whether approval was accepted. The next step
will inspect the run, its runner assignment, logs, and smoke summary. A passing
smoke run verifies runner/toolchain readiness only; it is not evidence of a
successful Sandbox deployment or passing unit/integration tests.

## Step 17: Verify actual self-hosted execution and smoke results

After approving the environment in step 16, wait for the returned run ID and
inspect the job's actual runner and step results. The run below is the public
smoke run from this walkthrough; substitute your own run ID when adapting:

```bash
gh run watch 37999044625 \
  --repo Azure-Samples/azuresandbox --exit-status --interval 10 &&
gh run view 37999044625 \
  --repo Azure-Samples/azuresandbox \
  --json headBranch,headSha,status,conclusion,url &&
gh api --method GET --paginate \
  repos/Azure-Samples/azuresandbox/actions/runs/37999044625/jobs \
  --jq '[.jobs[] | {name, status, conclusion, runner_name, steps: [.steps[] | {name, conclusion}]}]' &&
gh run view 37999044625 \
  --repo Azure-Samples/azuresandbox --log
```

Require the workflow run to use `main` and the verified registration merge
commit. The job must execute on the expected configured runner, and its
checkout, toolchain check, and report steps must succeed. Review the portal's
job summary too: it should report smoke `PASS` and explicitly state that no
Azure resources were deployed or Sandbox unit/integration tests run.

Share the status, runner/step results, and logs. If the run is still waiting
for environment approval, complete that approval before starting the watch
command; do not dispatch again. Stop and capture failed logs if any command or
job fails. Do not automatically rerun, change runner settings, or treat a
skipped smoke check as success.

A verified smoke pass completes runner execution validation, not the full
deployment goal. Sandbox runtime inputs, required tags, state-key freshness,
provider/backend authentication, VM readiness, and test-based result handling
still need their own setup before any real plan, apply, or test run.

### Verified smoke result

The [first smoke run](https://github.com/Azure-Samples/azuresandbox/actions/runs/37999044625)
completed successfully on October 9, 2026. Its job ran on the configured
self-hosted runner in 1 minute 17 seconds; every job step succeeded.
The workflow ran from `main` commit
`a8bd991d1b065ef1c45f1072cc0692d3877bd49a` and checked out `vnext` commit
`a6a85a84c01fa73587a8fc82804151f513f41925`.

The logs confirmed Git 2.43.0, Terraform 1.16.5, Azure CLI 2.91.0,
PowerShell 7.6.6, Az 16.4.0, and Az.Accounts 5.5.3. The runner's managed
identity environment checks passed, and the report step received
`SMOKE_OUTCOME: success` and wrote the smoke `PASS` summary.

No Azure resources were deployed and no Sandbox unit/integration tests ran.
The smoke check did not authenticate the deployment identity to Azure or
exercise backend writes. Keep those separate from the verified toolchain
and runner execution result.

## Step 18: Prepare the full deployment workflow topic branch

Proceed only after the smoke result is verified. The next implementation
will add the all-base-module deployment and all-modules unit/integration
test behavior, not change the verified runner infrastructure.

Create a new topic branch from refreshed `vnext` in the original checkout.
Carry the accumulated local guide updates onto it; do not discard them or
copy deployment state into the registration worktree. Run from the original
`extras/configurations/rg-devops-iac` directory:

```bash
(
  cd ../../.. &&
  git status --short &&
  git fetch origin main vnext &&
  git switch -c feat/sandbox-deployment origin/vnext &&
  git status --short
)
```

Expect the new branch and the pending guide and README modifications. Git will refuse
the switch if it would overwrite conflicting local changes; report any
error rather than forcing the switch or resetting files. The subshell
leaves the terminal directory unchanged.

Share the branch-switch output and file status. This does not plan, apply,
or run tests. The next setup stage will capture the remaining human-supplied
runtime settings and required tags privately before implementation or
dispatch of the real deployment workflow.

## Step 19: Configure remote state first in the runner checkout

The JSON capture commands in this step record the initial attended setup.
The operator subsequently selected complete HCL files in step 20. For the
current procedure, use that HCL upload step rather than repeating the JSON
capture commands below. Backend creation still comes first after checkout.

The first Terraform configuration step after cloning/checking out the Sandbox
source must create `backend.tf` in that checkout's repository root.
This belongs in the deployment workflow and must happen on every new checkout,
not as a one-time manual edit that the next checkout cleanup would remove.

Use this execution order:

1. Check out the approved Sandbox source.
2. Create the root `backend.tf` from the confirmed private backend settings.
3. Write the complete approved `terraform.tfvars`, including its `tags` map.
4. Run `terraform init` against the configured Azure backend.
5. Validate, plan, apply the saved plan, start and verify VMs, and run tests.

The backend uses Azure AD authentication with the runner's system-assigned
managed identity, the bootstrap storage account's `tfstate` container, and
the previously selected `azuresandbox.tfstate` key. Provider authentication
remains separate: the user-assigned identity supplies deployment permissions.
Do not select that user-assigned identity for the backend through a shared
`ARM_CLIENT_ID` environment variable.

Capture and confirm the backend tenant, subscription, and storage account
privately before implementing this step. Verify the state key is unused for
this new Sandbox before the first initialization. Do not invent account names
or reuse another environment's state.

Do not create or overwrite `backend.tf` in the operator's workstation checkout
for this workflow exercise. Preserve its existing state and configuration.
The deployment workflow is not implemented yet, so no backend file has been
created and no initialization should be run at this stage.

### Capture the backend settings privately

Use the actual tenant and subscription from the standalone bootstrap's
`terraform.tfvars`, not IDs from a throw-away root sample. The storage account
is read from that bootstrap's recorded outputs. Run in the original
`extras/configurations/rg-devops-iac` directory only when no bootstrap apply
is running:

```bash
(
  set +x
  set -euo pipefail

  read -r -s -p 'Actual bootstrap tenant ID: ' BACKEND_TENANT_ID
  printf '\n'
  read -r -s -p 'Actual bootstrap subscription ID: ' BACKEND_SUBSCRIPTION_ID
  printf '\n'
  BACKEND_STORAGE_ACCOUNT=$(terraform output -json resource_names |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["storage_account"])')
  export BACKEND_TENANT_ID BACKEND_SUBSCRIPTION_ID BACKEND_STORAGE_ACCOUNT

  SANDBOX_BACKEND_JSON=$(python3 - <<'PY'
import json
import os
import re
import sys

guid = r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"
for name in ("BACKEND_TENANT_ID", "BACKEND_SUBSCRIPTION_ID"):
    if not re.fullmatch(guid, os.environ[name]):
        sys.exit(f"{name} must be a GUID; value omitted.")
if not re.fullmatch(r"[a-z0-9]{3,24}", os.environ["BACKEND_STORAGE_ACCOUNT"]):
    sys.exit("Bootstrap storage account name is invalid; value omitted.")
print(json.dumps({
    "tenant_id": os.environ["BACKEND_TENANT_ID"],
    "subscription_id": os.environ["BACKEND_SUBSCRIPTION_ID"],
    "storage_account_name": os.environ["BACKEND_STORAGE_ACCOUNT"],
    "container_name": "tfstate",
    "key": "azuresandbox.tfstate",
    "use_azuread_auth": True,
    "use_msi": True,
}))
PY
)

  printf '%s' "$SANDBOX_BACKEND_JSON" |
    gh variable set SANDBOX_BACKEND_JSON \
      --repo Azure-Samples/azuresandbox --env sandbox-deployment
  gh variable list \
    --repo Azure-Samples/azuresandbox --env sandbox-deployment \
    --json name \
    --jq '[.[] | select(.name == "SANDBOX_BACKEND_JSON")]'
)
```

The container and state key are the values already selected for this
walkthrough. The payload intentionally has no `client_id`: backend access
uses the system-assigned identity, not the provider's user-assigned identity.
The initial `vars.SANDBOX_BACKEND_JSON` configuration variable captured these
settings without an authentication secret. Step 20 supersedes this payload
with complete HCL file contents, subsequently selected for environment-secret
storage as described in that step.

Share only the variable-set confirmation and variable-name list. The prompts do
not echo IDs, and neither the payload nor storage account name is printed.
This reads bootstrap output metadata and creates a non-secret GitHub
environment configuration variable; it does not create a local backend file, initialize
Terraform, verify blob freshness, or deploy resources. State-key freshness
must still be verified from the runner before the first initialization.

Alternatively, the operator may provide the five backend fields directly.
Prepare the equivalent JSON payload in an owner-readable-only file outside
the Git checkout, without adding the values to this document. If
`SANDBOX_BACKEND_JSON` already exists, obtain explicit confirmation before
replacing its configuration. To inspect the variable in the portal, open the
repository's **Settings**,
select **Environments**, open `sandbox-deployment`, and find
`SANDBOX_BACKEND_JSON` under **Environment variables**. Its edit control
shows the saved configuration value, unlike an environment secret.

Upload the confirmed private payload through standard input:

```bash
(
  set +x
  set -euo pipefail

  BACKEND_FILE="<private-backend-json-file>"
  gh variable set SANDBOX_BACKEND_JSON \
    --repo Azure-Samples/azuresandbox --env sandbox-deployment \
    < "$BACKEND_FILE"
  gh api \
    repos/Azure-Samples/azuresandbox/environments/sandbox-deployment/variables/SANDBOX_BACKEND_JSON \
    --jq '.value' |
    python3 -c '
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    expected = json.load(source)
if json.load(sys.stdin) != expected:
    sys.exit("Backend variable mismatch; values omitted. Stop here.")
print("Backend configuration variable verified; values omitted.")
' "$BACKEND_FILE"
  rm -- "$BACKEND_FILE"
)
```

Replace the placeholder with the exact prepared file path. Remove only that
file after successful upload and verification; do not print its contents
or put it in the repository. This updates non-secret environment configuration,
not Terraform state, backend resources, or runner permissions.

If an earlier setup created a same-named environment secret, it is a separate
entry. Do not use it as a fallback or assume it updates the variable.
Leave it unchanged until the variable is verified and cleanup is explicitly
authorized. This initial capture used `vars.SANDBOX_BACKEND_JSON`, not
`secrets.SANDBOX_BACKEND_JSON`. Step 20 documents the subsequent HCL upload
and the approved migration to `secrets.SANDBOX_BACKEND_HCL`.

The attended upload created the environment configuration variable and
verified its decoded JSON against the operator-confirmed local payload.
The temporary payload file was then removed. The old secret was not changed,
and no Sandbox backend file, initialization, or deployment was performed.

After verifying the replacement variable and obtaining explicit operator
authorization, remove only the obsolete environment secret:

```bash
gh secret delete SANDBOX_BACKEND_JSON \
  --repo Azure-Samples/azuresandbox --env sandbox-deployment &&
gh secret list \
  --repo Azure-Samples/azuresandbox --env sandbox-deployment \
  --json name \
  --jq '[.[] | select(.name == "SANDBOX_BACKEND_JSON")]' &&
gh variable list \
  --repo Azure-Samples/azuresandbox --env sandbox-deployment \
  --json name \
  --jq '[.[] | select(.name == "SANDBOX_BACKEND_JSON")]'
```

Expect an empty secret result (`[]`) and a variable result containing
`SANDBOX_BACKEND_JSON`. Deleting the secret does not delete the same-named
configuration variable, change Azure permissions, or affect runner
registration. Do not delete other secrets as part of this cleanup.

The attended cleanup confirmed that the obsolete environment secret is
absent and the same-named configuration variable remains present.

## Step 20: Store complete HCL configuration

The operator selected complete HCL files instead of JSON payloads. The
workflow will write `backend.tf` first after checkout, then write
`terraform.tfvars`, without converting either file into another syntax.
The previous JSON backend capture is a historical setup step, not the
configuration format selected for the deployment job.

The operator initially uploaded these files as environment configuration
variables, then selected migration to environment secrets to protect their
contents. The workflow will use `secrets.SANDBOX_BACKEND_HCL` and
`secrets.SANDBOX_TFVARS_HCL` after the migration is confirmed:

| Environment secret | Contents and purpose |
|---|---|
| `SANDBOX_BACKEND_HCL` | Complete `terraform { backend "azurerm" { ... } }` file |
| `SANDBOX_TFVARS_HCL` | Complete approved repository-root `terraform.tfvars`, including all required tags |

All base and organizational tags are baked into the input file's `tags` map.
The runner does not support a separate additional-tag variable or command-line
override. Keep the interactive deployment mechanism unchanged; it is not part
of this workflow. The original input file remains unchanged.

The attended checks confirmed MSI mode, the provisioned user-assigned
identity's client ID, and the selected base-module flags in the root input
file. Its tenant, subscription, region, and operator object ID also match
the previously confirmed bootstrap settings. These checks do not prove
policy compliance, blob freshness, or a successful deployment.

The complete backend HCL was prepared privately from the already verified
backend settings. This is a one-time migration of existing configuration;
the deployment workflow will not perform a JSON/HCL round trip.
The backend uses the system-assigned identity and has no `client_id`.
The operator subsequently updated `SANDBOX_BACKEND_HCL` to omit the fixed
`key` attribute, leaving the container and other backend settings unchanged.
Step 22 defines the required deployment-specific key supplied at initialization.

### Sanitized backend file example

Store the complete following `backend.tf` structure in `SANDBOX_BACKEND_HCL`,
replacing the sanitized placeholders with your deployment's actual values:

```hcl
terraform {
  backend "azurerm" {
    use_azuread_auth     = true
    use_msi              = true
    tenant_id            = "<tenant>"
    subscription_id      = "<subscription>"
    storage_account_name = "<state-storage-account>"
    container_name       = "tfstate"
  }
}
```

The example contains no authentication credentials. It omits `client_id` so
the backend uses the runner's system-assigned managed identity, and omits
`key` because the workflow supplies the deployment-specific state blob key
during initialization. `container_name` identifies the shared container,
not an individual deployment's state blob. Do not commit the populated file.

### Sanitized input file example

Store the complete following `terraform.tfvars` structure in
`SANDBOX_TFVARS_HCL`, replacing sanitized placeholders with your approved
deployment values:

```hcl
aad_tenant_id   = "<tenant>"
arm_auth_mode   = "msi"
arm_client_id   = "<user-assigned-identity-client-id>"
location        = "southcentralus"
subscription_id = "<subscription>"
user_object_id  = "<user-object-id>"

tags = {
  project              = "sand"
  costcenter           = "mycostcenter"
  environment          = "dev"
  "<organization-tag>" = "<organization-tag-value>"
}

# Enable modules here

enable_module_vnet_app         = true
enable_module_vm_jumpbox_linux = true
enable_module_vm_mssql_win     = true
enable_module_mssql            = true
enable_module_mysql            = true
enable_module_vwan             = true

# Enable extra modules here

# enable_module_petstore         = true
# enable_module_avd              = true
# enable_module_vnet_onprem      = true
```

Use the same tenant and subscription as the backend example.
`arm_client_id` selects the runner's user-assigned managed identity for
Terraform providers; it is not an authentication secret or the backend's
identity selection. Replace the generic organizational tag name and value
with the required, human-approved tags in this same `tags` map.
The sample enables all optional base modules and leaves extra modules
commented out and disabled. Do not commit the populated input file.

### Historical configuration-variable upload

The following upload was completed before environment-secret storage was
selected. Do not repeat it for the secret migration below.

From `extras/configurations/rg-devops-iac`, upload the files and compare the
stored HCL with each source without printing values:

```bash
(
  set +x
  set -euo pipefail
  PRIVATE_DIR="<private-configuration-directory>"

  for NAME in SANDBOX_BACKEND_HCL SANDBOX_TFVARS_HCL; do
    case "$NAME" in
      SANDBOX_BACKEND_HCL) FILE="$PRIVATE_DIR/sandbox-backend.tf" ;;
      SANDBOX_TFVARS_HCL) FILE="../../../terraform.tfvars" ;;
    esac
    gh variable set "$NAME" \
      --repo Azure-Samples/azuresandbox --env sandbox-deployment \
      < "$FILE"
    gh api \
      "repos/Azure-Samples/azuresandbox/environments/sandbox-deployment/variables/$NAME" |
      python3 -c '
import json
from pathlib import Path
import sys
expected = Path(sys.argv[1]).read_bytes().decode("utf-8")
actual = json.load(sys.stdin)["value"]
if actual.strip() != expected.strip():
    sys.exit("Stored HCL mismatch; values omitted. Stop here.")
print(f"{sys.argv[2]}: HCL configuration verified; values omitted.")
' "$FILE" "$NAME"
  done
)
```

Replace the private-directory placeholder with the prepared files' exact
location. Only insignificant outer whitespace is ignored when comparing
the stored text. Python decodes the GitHub API's JSON response envelope;
it does not parse or convert the HCL configuration.

If either target variable already exists, obtain explicit authorization before
replacing it.

The attended upload verified both complete HCL files against their approved
sources. The operator subsequently removed the obsolete JSON backend variable
and the separate tag variable. A name-only check confirmed that only
`SANDBOX_BACKEND_HCL` and `SANDBOX_TFVARS_HCL` remain for runner configuration.
The temporary backend and tag-argument files were removed; the original
repository-root `terraform.tfvars` was not changed.

These variables are readable configuration, not secret storage, and are not
automatically masked in logs. Do not include authentication credentials or
confidential data. Share only upload and verification confirmations.
Do not print actual HCL in public logs or commit the environment-specific
files. This step does not initialize Terraform or deploy resources.

### Migrate the complete HCL files to environment secrets

In GitHub, open **Settings > Environments > sandbox-deployment**.

1. Copy the complete value of the existing `SANDBOX_BACKEND_HCL` environment
   variable privately, then create an **environment secret** with that same
   name and exact HCL contents.
2. Repeat for `SANDBOX_TFVARS_HCL`, preserving all approved inputs and tags.
3. Confirm both secret names without printing their values:

```bash
gh secret list \
  --repo Azure-Samples/azuresandbox \
  --env sandbox-deployment \
  --json name \
  --jq '.[].name'
```

The listing confirms the entries exist, not that their contents match.
Copy from the previously verified variables without editing the HCL.
Do not paste configuration into chat, commit it, or print it in public logs.
Keep the variables temporarily until both secrets have been created and
confirmed; then remove only those two obsolete variable entries.
Secrets and variables are separate entries even when their names match.

The workflow will read the secrets directly through the `secrets` context;
no REST retrieval token or additional authentication credential is needed.
After checkout, write `backend.tf` first and `terraform.tfvars` second with
owner-only permissions, without a JSON conversion. Continue keeping raw
Terraform output private because masking the original HCL does not guarantee
redaction of individual values emitted elsewhere.

The attended name-only check confirmed that both environment secrets exist.
Their contents cannot be read back through the GitHub API; this check does
not verify HCL equality. The attended cleanup deleted both obsolete variables,
and the final variable-name listing was empty. The operator also confirmed
removing the fixed state key from the backend secret. No workflow implementation
or Terraform operation has run as part of this migration.

After confirming both secrets exist, remove only their same-named variable
entries and list the remaining variable names:

```bash
(
  set -euo pipefail
  gh variable delete SANDBOX_BACKEND_HCL \
    --repo Azure-Samples/azuresandbox --env sandbox-deployment
  gh variable delete SANDBOX_TFVARS_HCL \
    --repo Azure-Samples/azuresandbox --env sandbox-deployment
  gh variable list \
    --repo Azure-Samples/azuresandbox --env sandbox-deployment \
    --json name --jq '.[].name'
)
```

These commands delete configuration variables, not the environment secrets,
Terraform state, or Azure resources.

## Step 21: Define preflight, apply, and unit-test stages

The operator selected three sequential stages, retaining `preflight` as the
default manual selection:

| Stage | Responsibility | Successful completion |
|---|---|---|
| `preflight` | Initialize, validate, and generate a private saved plan. | All checks and Terraform commands succeed. |
| `apply` | Apply the saved plan produced by that run's preflight. | `terraform apply` exits successfully. |
| `unit-test` | Start and verify VMs, then run all-module unit/integration tests. | The VM gate and test orchestrator succeed. |

The operator confirmed a **Run through stage** selector for manual dispatch,
defaulting to `preflight`:

| Selection | Stages executed |
|---|---|
| `preflight` | Preflight only |
| `apply` | Preflight, then apply |
| `unit-test` | Preflight, then apply, then unit-test |

Under the latest policy, every dispatch requests a new independent
Sandbox and receives its run-derived ID from step 22. All stages within that
run use the same ID and backend key. Selecting `apply` or `unit-test` in a later
dispatch provisions another Sandbox; it does not continue a preflight-only
deployment or update existing infrastructure. Existing-target selection from
the original implementation is removed as described in step 43.

### Preflight

Preflight must exercise Terraform, not merely repeat the toolchain smoke test.
After the environment approval, it must:

1. Check out the approved Sandbox source and write the complete `backend.tf`
   first, then the approved `terraform.tfvars`, including all required tags.
2. Verify the required toolchain, managed identities, backend access, and
   intended state target. Stop if the target belongs to another deployment.
3. Run `terraform init -input=false` against the configured remote backend,
   explicitly selecting the stable deployment-specific key from step 22.
4. Run `terraform validate -no-color` and fail the job on an error.
5. Run `terraform plan -input=false -no-color -out=<private-runner-path>/sandbox.tfplan`
   and fail the job on an error. The plan uses the approved input file,
   including its complete `tags` map.

Create the plan's parent directory on the runner with owner-only permissions
(`0700`) and run Terraform with `umask 077`, so the saved `.tfplan` is
owner-readable and writable only (`0600`). Keep the plan and raw plan output
inside that private directory; do not print raw output in public logs,
upload it as a GitHub artifact, or commit it. Public reporting may show
sanitized status and change counts, not resource details or plan contents.
Treat the saved plan as sensitive even when Terraform masks values in its
console output.

#### Saved-plan location and reporting

A successful preflight produces a saved `.tfplan` and a receipt identifying
it. Keep both on the runner in a per-run directory outside the checkout and
`RUNNER_TEMP`, so checkout cleanup and job-end temporary-file cleanup do not
remove the plan before apply. Use this runner-local layout:

```text
$HOME/.local/state/azuresandbox/deployments/<deployment-id>/runs/<run-id>-<run-attempt>/
  sandbox.tfplan
  preflight.log
  plan-receipt.json
```

The directory uses `0700` permissions; all three files use `0600`.
`preflight.log` retains command results and raw diagnostics privately.
Write a successful receipt only after planning succeeds and the saved file
exists. Record its local path, SHA-256 digest, UTC creation time, checked-out
Sandbox source commit, deployment ID, originating workflow run ID/URL,
effective backend key, current workflow run ID/attempt, and sanitized change
counts.
Keep configuration fingerprints in the private receipt to bind the plan to
the backend and inputs without publishing their contents.

Publish the safe receipt metadata in the GitHub Actions job summary using
`GITHUB_STEP_SUMMARY`: preflight result, runner-relative plan path, plan
SHA-256, source commit, creation time, non-identifying deployment ID and
state key, originating workflow run link, current run ID/attempt, and change
counts.
Do not publish raw logs, state, configuration, resource names, or the plan
file itself. This provides a GitHub audit record without uploading the plan
as an artifact.

The job's protected `sandbox-deployment` environment also creates a GitHub
deployment record. Its `environment.url` points at the workflow run so the
environment's deployment history links to the job summary. The implementation
uses one job with separate stage steps, keeping the plan on the same runner
and enforcing one 180-minute execution budget. The deployment record reports
the overall job outcome; the summary reports each stage separately.
A successful preflight-only job means preflight succeeded, not that
infrastructure was applied or tests passed.

Before applying, check that the receipt identifies the expected source and
configuration and that the local plan's digest matches the recorded digest.
A digest is a consistency check, not a replacement for access controls.
Retain the private files through the apply handoff. Cleanup must not delete
a plan that is still awaiting apply; a retention policy remains to be agreed.

Preflight does not apply infrastructure changes, start VMs, or run Sandbox
unit/integration tests. It is **not strictly read-only**:
initialization downloads modules/providers, writes local Terraform metadata,
and may create a backend state blob or acquire a state lock. Planning reads
and refreshes resource data and acquires the state lock; Azure provider
configuration can also register resource providers. Serialize preflight with
deployment operations and do not run it during an interactive apply.
An empty state blob created by a successful preflight must not be mistaken
for another deployed Sandbox on the subsequent apply run.

A successful preflight confirms initialization, configuration validity, and
successful planning, not complete Azure provisioning permissions, policy
compliance, or test success.

### Apply

Run only after preflight succeeds, and apply its exact private saved
`.tfplan`. Apply does not generate a replacement plan, start VMs, or run tests.
It is complete when `terraform apply` exits successfully.

Apply consumes preflight's exact saved plan within the same run.
A separate dispatch creates a different Sandbox; it cannot consume an earlier
run's plan or continue its deployment. Keep the plan private on the same runner
throughout the handoff; do not use public artifacts for cross-stage transfer.

#### Apply log and reporting

Every attempted apply produces a runner-local `apply.log`, whether Terraform
succeeds or fails. Keep it beside that run's plan and receipt:

```text
$HOME/.local/state/azuresandbox/deployments/<deployment-id>/runs/<run-id>-<run-attempt>/apply.log
```

Create the log with `0600` permissions before invoking Terraform, then
capture both stdout and stderr, including progress and full diagnostics.
Record the command, verified plan digest, UTC start/end times, and actual
Terraform exit code. Each run attempt has its own directory; do not overwrite
an earlier attempt's log.

Preserve the exit code independently of log capture so a successful logger
cannot turn a failed apply into stage success. Failure to create or write the
log must be surfaced explicitly, not ignored. On cancellation, timeout, or
runner loss, retain whatever output was captured and report the attempt as
interrupted or incomplete if its final Terraform exit code is unavailable;
do not invent a completed outcome.

Retain successful and failed apply logs locally. Do not upload raw logs as
GitHub artifacts or print them in public job output. Publish only a sanitized
GitHub job summary with the apply result, exit code when available, timestamps,
run ID/attempt, plan digest, and runner-relative log path. Link that summary
from the environment deployment record as described for preflight.
A failed apply prevents unit-test from running; a successful apply is reported
separately from the subsequent test result.

### Unit-test

Run only after apply succeeds. First execute `scripts/manage-vms.sh start`
and confirm all relevant VMs report `VM running`; asynchronous start requests
alone are insufficient. Then run `scripts/Invoke-UnitTests.ps1` without
`-Module` or `-Integration`, preserving the selected all-module unit and
applicable integration test scope.

Preserve the orchestrator's exit code and distinguish failed tests from
harness errors. If this stage fails, report `apply` as successful,
`unit-test` as failed, and the full pipeline as failed. If apply fails, do
not run unit-test or label it successful. Keep the overall 180-minute budget.

The configuration-storage decision is resolved: use the two complete HCL
environment secrets from step 20. Both secret entries are confirmed present
and the obsolete variables have been removed. The three-stage workflow is
implemented locally but not yet published or exercised against Azure.
Use the `secrets` context directly; runner-private configuration sources,
REST retrieval, and runtime-masked reusable-workflow parameters are not needed.
Keep configuration and raw Terraform diagnostics out of public logs.
No preflight initialization, validation, planning, or deployment has been performed.

## Step 22: Isolate multiple deployments on one runner

A fresh checkout does not clean the rest of a self-hosted runner. Also,
`actions/checkout` may reuse a clone; configure and verify checkout cleanup
rather than assuming every job starts with a new filesystem.

### Deployment identity and remote state

For direct GitHub traceability, allocate the deployment ID once from the
initial workflow run ID when the operator explicitly requests a new Sandbox:

```text
Deployment ID: sandbox-<initial-workflow-run-id>
State key:     sandboxes/sandbox-<initial-workflow-run-id>/terraform.tfstate
Originating run:
https://github.com/Azure-Samples/azuresandbox/actions/runs/<initial-workflow-run-id>
```

GitHub supplies the initial ID through `github.run_id` / `GITHUB_RUN_ID`.
Do not include the run attempt in the deployment ID: a workflow rerun retains
its run ID. Under the new-only policy it must fail before initialization if
that key already exists, even if its state is empty or the previous apply failed.
Record the allocated ID and originating run link in the GitHub summary before
backend initialization, so the selection is traceable even if preflight fails.

Later dispatches allocate separate Sandboxes, not updates to previous ones.
There is no existing-ID input. Keep every earlier Sandbox's state intact.
Any manual maintenance or teardown must use its original ID/key; never use
another dispatch's new key for those operations. Automatic recovery of
partially deployed Sandboxes is not supported.

Include the stable deployment ID and requested operation in workflow run names
and stage summaries. Record both the originating and current run links in
private receipts and GitHub summaries, allowing later operations to be traced
back to the initial run without confusing their individual execution results.

The Sandbox deployment ID is distinct from GitHub's environment-associated
deployment-record ID. Environment jobs create their own deployment records;
those records report stage outcomes and link to their workflow runs, but do
not replace the stable Sandbox ID or automatically group all its future runs.
The originating run link identifies the initial workflow execution, not proof
that its apply succeeded.

Select the effective key explicitly during initialization:

```bash
terraform init -input=false "-backend-config=key=$TF_STATE_KEY"
```

`TF_STATE_KEY` must come from the confirmed deployment ID, not a guessed
default. Stop before initialization if that selection is missing. The backend
secret deliberately omits `key`; do not restore a fixed shared-state fallback.
Initialization with `-input=false` requires the missing key to be supplied,
and clean per-run Terraform metadata prevents inheritance of an earlier
backend selection. Terraform backend blocks do not interpolate normal input
variables.

For the run-derived ID, check that its key is unused before initialization
on every attempt. An existing blob causes an explicit failure, not recovery,
even if a private receipt matches. Do not delete, rename, or migrate state
to make a new deployment appear empty. Keep the standalone bootstrap state
separate and unchanged.

Bind the deployment ID and effective backend key to the private plan receipt
and include their non-identifying values in the GitHub summary. Apply and
unit-test must target that same deployment. A unique key isolates Terraform
state; it does not by itself guarantee distinct Azure resource names,
non-overlapping networks, sufficient quotas, or affordable aggregate cost.
Retain each state blob while its resources exist so they can be updated or
destroyed deliberately.

### Runner filesystem isolation and cleanup

| Location | Required handling |
|---|---|
| Checkout | Clean stale generated files before writing that run's backend and inputs. Never remove another active run's workspace. |
| Terraform metadata | Keep `.terraform` within the cleaned checkout, or use a distinct `TF_DATA_DIR` per run. Never reuse cached backend metadata for a different deployment. |
| Plans, logs, and receipts | Use the deployment/run-specific private directory from step 21. Do not overwrite earlier attempts or delete a plan awaiting apply. |
| Configuration and temporary files | Snapshot the approved configuration per run with owner-only access; remove only that run's temporary files after they are no longer needed. |
| Azure CLI context | Use a per-run `AZURE_CONFIG_DIR` and authenticate the required managed identity explicitly; do not inherit another deployment's subscription/context. |
| Azure PowerShell context | Disable context autosave for the process and authenticate explicitly in the process that runs tests; do not wipe shared `~/.Azure` data. |
| Provider/module caches | Retain intentional download caches where safe; do not treat them as authoritative deployment state or backend configuration. |

Cleanup must target known run-specific paths, not broadly delete the runner's
home, shared authentication directories, or other deployments' files.
Completed run logs and obsolete temporary files need an explicit retention
policy; no retention duration has been selected yet. Do not automatically
delete remote state as part of filesystem cleanup.

Deployment-specific initialization is implemented locally but has not run.
The backend secret no longer contains a fixed key, but existing state blobs
have not been modified, renamed, or deleted.

## Step 23: Check runner availability after starting the VM

After starting the runner VM, confirm that its service has reconnected to
GitHub before dispatching another workflow. List only status and label metadata:

```bash
gh api \
  repos/Azure-Samples/azuresandbox/actions/runners \
  --jq '.runners[] | select(any(.labels[]; .name == "azuresandbox")) | {status, busy, labels: [.labels[].name]}'
```

The intended runner should report `status: "online"` and `busy: false`,
with the `azuresandbox` label. An empty result does not confirm availability.
The listing does not verify Azure authentication or provisioning permissions.

The attended check confirmed the runner is online and idle, with the
`self-hosted`, `Linux`, `X64`, and `azuresandbox` labels.

The published workflow is still smoke-only. Do not dispatch it expecting
Terraform preflight, apply, or tests. Once runner availability is confirmed,
implement and publish the three-stage workflow before its first preflight run.

## Step 24: Review the three-stage workflow update

The local topic branch now contains the workflow and its runner helpers:

| File | Purpose |
|---|---|
| `.github/workflows/sandbox-deployment.yml` | Protected manual dispatch, stage selection, serialized execution, and overall 180-minute timeout |
| `extras/configurations/rg-devops-iac/scripts/Invoke-SandboxDeployment.sh` | Restrictive Linux umask, PowerShell entrypoint, and private native-command redirection |
| `extras/configurations/rg-devops-iac/scripts/Invoke-SandboxDeployment.ps1` | Private configuration, backend selection, planning, saved-plan verification, apply logging, VM gate, and sanitized reporting |
| `extras/configurations/rg-devops-iac/scripts/SandboxProgress.ps1` | Shared bounded, allowlisted apply/test progress filtering |
| `extras/configurations/rg-devops-iac/scripts/Connect-SandboxRunner.ps1` | Explicit UAMI authentication and process-local PowerShell context for prerequisite checks and all-module tests |

All new helper scripts and documentation live under
`extras/configurations/rg-devops-iac`. The existing workflow definition stays
in `.github/workflows`, as required for GitHub Actions discovery.
The helpers operate on the repository-root Sandbox configuration and invoke
its existing VM-management and test scripts; they do not apply the standalone
runner-bootstrap configuration.

Every dispatch requests a new independent Sandbox; there are no
`deployment_mode` or `deployment_id` inputs in the updated workflow.
`run_through` defaults to `preflight`.
The source remains trusted `vnext`; dispatch the registered workflow from
`main` after publication.

The helper writes backend and input snapshots privately, uses per-attempt
Terraform metadata and Azure CLI context, and forces the default Terraform
workspace. It checks state-blob existence with the system-assigned identity
before initialization. A private deployment-level `deployment.json` binds the
stable ID to its backend and repository. Preserve this file alongside the
state for audit and manual maintenance; it does not authorize reuse of existing
state by this workflow. Never delete state to bypass the new-only check.

Preflight checks the MSI input mode, matching backend tenant/subscription,
all base-module flags, disabled extras, and Azure CLI/PowerShell authentication.
It does not invoke the public-access helper used for updating existing Sandboxes.
Raw output remains private, including
the Terraform JSON used to produce safe plan counts.
Long commands emit two-minute progress messages with bounded, allowlisted
apply/test previews as described in steps 40 and 41.
Unit-test waits up to ten minutes to confirm the deployed VMs running
after the existing start helper, then invokes the orchestrator in the same
PowerShell process as the UAMI login.

Before publication, run the applicable existing CI checks from the repository
root. The operator removed the retained helper fixtures and regression harnesses;
do not recreate them or add Pester as part of this port.

```bash
./scripts/Invoke-CIChecks.sh bash powershell actions markdown links secrets
```

Review and publish the topic update to `vnext` first, including both helpers.
Then publish the narrow workflow update to `main` so manual dispatch uses the
new definition. Keep environment approval and the required review process;
the earlier one-time smoke PR bypass does not authorize another bypass.
After each commit and before each push/PR creation, run the applicable local
CI checks (`actions bash powershell markdown links secrets`) without failures.
Do not dispatch the updated workflow before its helpers are available on
`vnext`. No deployment has been executed as part of implementation.

## Step 25: Use sanitized unit-test results by default

The parent orchestrator and its PowerShell/Linux child tests now emit sanitized
check descriptions by default. JSON retains its existing schema,
statuses, counts, timing, and exit-code semantics. Runtime identifiers, resource
names, addresses, usernames, and exception text are excluded from the default
machine-readable results.

Children have explicit static descriptions alongside the original diagnostic
messages. The parent accepts only descriptions declared by the selected child
script; unrecognized runtime text is replaced with an explicit withheld-details
label and a warning. Exception continuations and harness errors are not copied
into public results. This avoids relying on regex replacements to identify every
possible environment-specific value.

For private troubleshooting, the parent accepts the optional switch
`-VerboseResults`, which restores original check text and diagnostics in JSON:

```powershell
./scripts/Invoke-UnitTests.ps1 -ResultsJsonPath ./test-results.json -VerboseResults
```

Existing calls need no additional argument. The parent forwards its setting to
children, including tests run through VM Run Command. Direct PowerShell child
calls use `-VerboseResults true`; the child's value is a validated string because
Run Command transports parameters as strings. The Linux child accepts
`--verbose-results` for direct invocation. Default child invocations remain valid.
No test assertions or pass/fail counters are changed.

General console/log diagnostics remain private; the default publication boundary
is the structured JSON results, not arbitrary logs. Do not publish verbose
results. The runner workflow does not opt into verbose mode.
Step 26 describes publishing these default structured results as GitHub evidence.

The original implementation used isolated privacy fixtures to check these
boundaries. Those helper test sources have since been removed at the operator's
request. Existing deployed-module unit/integration tests remain unchanged;
validation now uses existing CI gates and real executions as described in step 51.
Actual sandbox tests still require the VM-start gate and explicit Azure
authentication described earlier.

## Step 26: Publish structured unit-test evidence

The local workflow now requests only `-ResultsJsonPath`
through the MSI-authenticated runner wrapper, without `-VerboseResults`.
The result file remains in the private deployment/run directory:

```text
unit-test-results.json
```

In the updated workflow, unit-test finalization checks the generated
JSON schema after either successful or failed tests, then copies only this
named file to an owner-only staging directory under `RUNNER_TEMP`.
The upload action receives explicit file paths, not a deployment-directory
wildcard. Plans, state, backend/input files, receipts, profiles, and raw logs
are never included.

The workflow uses the commit-pinned `actions/upload-artifact` release to publish
one artifact named:

```text
unit-test-evidence-<deployment-id>-<run-id>-<run-attempt>
```

Evidence upload runs after test failures without changing the test step's
outcome or exit code. Apply and unit-test results remain separate in the
summary; successful publication cannot turn failed tests into a successful
pipeline. Upload failures are surfaced explicitly.
Preparation failures fail the unit-test step if testing succeeded, or preserve
its existing nonzero exit code if testing failed. Details remain in its private
log, and no upload is approved when validation or staging fails.
Invalid JSON is not uploaded. XML files are neither required nor consumed.
If the VM-start gate, authentication, or another prerequisite prevented results
from being generated, report evidence unavailable and skip the upload rather
than inventing test results.

Find the downloadable JSON archive in the workflow run's **Artifacts**
section or follow **Download sanitized unit-test evidence** in its job summary.
The protected environment's deployment-history link leads to that same run.
The files are downloadable evidence, not an inline JSON viewer or a separate
attachment stored on the environment deployment record.
Access requires signing into GitHub with repository read access; for this
public repository, treat artifact contents as public-safe.

No PAT or new Azure credential is required for artifact upload; the action
uses GitHub-provided workflow runtime authentication, independently of Azure MSI.
GitHub's configured repository artifact-retention policy applies.
The download link expires when its artifact expires or the artifact/run is
deleted. Private runner copies remain subject to the separate retention policy
that has not yet been selected.

The original evidence publication passed on GitHub as recorded in step 42.
Moving preparation into unit-test finalization is a later
simplification described in step 44.

## Step 27: Prepare publication before the first full run

The operator confirmed a **new independent Sandbox** for the first complete
`preflight -> apply -> unit-test` run, using the previously approved HCL secrets,
all base modules, disabled extras, and all-module unit/integration tests.
This may create additional billable resources alongside existing Sandboxes.
Its ID will be allocated from the initial workflow run; no state key or ID
has been allocated yet.

The implementation is local and uncommitted. The registered `main` workflow
was checked and still contains only the earlier smoke job. Do not dispatch
it expecting the three-stage pipeline.
First publish all helpers and parent/child privacy changes to `vnext`,
then publish the narrow workflow-definition update to `main`.
Both publication steps require normal review and clean applicable local
CI checks after committing and before pushing or creating a PR.

From the current checkout, inspect branch freshness and the pending scope
without printing HCL secrets or Terraform state:

```bash
cd "$(git rev-parse --show-toplevel)"
git fetch origin
git branch --show-current
git --no-pager diff --stat
git --no-pager status --short
git rev-list --left-right --count origin/vnext...HEAD
```

Review this output before staging or changing branch history.
The divergence counts show commits unique to `origin/vnext` first and to the
current branch second; nonzero remote divergence must be handled deliberately
without discarding the pending changes.
This step does not commit, push, open a PR, or deploy resources.

The attended check confirmed the topic branch had no commits ahead of or
behind `origin/vnext` (`0 0`). The pending tracked changes matched the workflow,
standalone documentation, and parent/child result-privacy scope; the new runner
helpers and regression tests were untracked. No branch-history adjustment was
needed at that point.

## Step 28: Commit and check the implementation locally

This step records the original publication procedure. For the current port,
do not stage or commit anything until the operator reviews it.
After approval, stage the reviewed tracked scope and new helper files explicitly
from the repository root. Ignored HCL configuration and Terraform state
must not be staged; do not use `git add -f`.

```bash
(
  set -euo pipefail
  cd "$(git rev-parse --show-toplevel)"
  git add -u -- \
    .github/workflows/sandbox-deployment.yml \
    extras/configurations/rg-devops-iac \
    modules extras/modules scripts
  git add -- \
    extras/configurations/rg-devops-iac/scripts/Connect-SandboxRunner.ps1 \
    extras/configurations/rg-devops-iac/scripts/Invoke-SandboxDeployment.sh \
    extras/configurations/rg-devops-iac/scripts/Invoke-SandboxDeployment.ps1 \
    extras/configurations/rg-devops-iac/scripts/SandboxProgress.ps1 \
    extras/configurations/rg-devops-iac/scripts/Watch-SandboxRunner.sh \
    extras/configurations/rg-devops-iac/scripts/Watch-SandboxRunner.ps1
  git --no-pager diff --cached --check
  git --no-pager diff --cached --stat
  git commit \
    -m "Implement Sandbox deployment stages and sanitized test evidence" \
    -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
)
```

Then run the applicable existing CI gates **after the
commit**, before any push or PR creation:

```bash
(
  set -euo pipefail
  cd "$(git rev-parse --show-toplevel)"
  ./scripts/Invoke-CIChecks.sh bash actions powershell markdown links secrets
  git --no-pager status --short
)
```

These CI checks do not deploy resources or invoke live Sandbox unit/integration
tests. Stop on any failure
and review the output before publishing. A `SKIPPED` gate is not a failure,
but record which checks were unavailable locally; the hosted gate remains
necessary. Review actual error output as well as the final CI summary.
This step commits locally only; it does not push or create a PR.

### If PowerShell analysis includes ancillary dependency files

The attended run passed both isolated regression suites: 22 Python tests
and privacy checks covering 22 child scripts and 667 static descriptions.
Bash, Markdown, and internal links passed. Actionlint and gitleaks were
unavailable locally. The PowerShell gate failed on two `make.ps1` warnings;
the operator confirmed that file is ancillary and not part of the repository.

The local PowerShell gate recursively analyzes the working directory, whereas
hosted CI starts with a clean checkout. Do not change analyzer rules, edit
downloaded dependencies, or remove Terraform's initialized directories to
silence these findings. Instead, run the unchanged CI command against a
temporary clean worktree of the committed source. This excludes local
untracked and ignored dependencies without excluding committed scripts.

After committing any documentation updates, run from the repository root:

```bash
(
  set -euo pipefail
  repo_root="$(git rev-parse --show-toplevel)"
  check_dir="$(mktemp -d "${TMPDIR:-/tmp}/azuresandbox-ci.XXXXXXXX")"
  git worktree add --detach "$check_dir/checkout" HEAD
  trap 'git -C "$repo_root" worktree remove "$check_dir/checkout"; rmdir "$check_dir"' EXIT
  cd "$check_dir/checkout"
  ./scripts/Invoke-CIChecks.sh bash actions powershell markdown links secrets
)
```

The temporary worktree is removed on exit; the original checkout, ignored
configuration, Terraform dependencies, and state remain untouched.
Any `FAILED` gate in this clean run still blocks publication.
Unavailable actionlint or gitleaks gates must be reported as `SKIPPED`,
not represented as locally verified.

## Step 29: Publish the implementation to vnext

The operator published `feat/sandbox-deployment` and opened
[PR #810](https://github.com/Azure-Samples/azuresandbox/pull/810) against `vnext`.
Clean committed-source local CI passed Bash, PowerShell, Markdown, and internal
links. Actionlint and gitleaks were unavailable locally; both passed hosted CI.
The PR reported 14 successful checks, two skipped Terraform lint checks, and
no failed or pending checks.

Required review was the remaining blocker. The operator explicitly authorized
a one-time review bypass for **this PR only**, then squash-merged the exact
checked head `7d90b1144bc7f104391c14044f1985d20950f542`.
GitHub confirmed the merge into `vnext` at
`60e7e058c2a309d7e15c46f3e2f5d5556597dcc3`.
This authorization does not apply to subsequent PRs.
The merge publishes the implementation; it does not run a Sandbox deployment.

## Step 30: Inspect the narrow main workflow update

Before creating a new registration branch, inspect current `main` and existing
worktrees. The approved source below is the verified merge from step 29,
not an unreviewed moving branch tip. Run from the repository root:

```bash
(
  set -euo pipefail
  git fetch origin main vnext
  printf '\nRelevant files on main:\n'
  git ls-tree -r --name-only origin/main -- \
    .github/workflows/sandbox-deployment.yml \
    .github/actionlint.yaml \
    scripts/Invoke-CIChecks.sh
  printf '\nRegistration-file differences:\n'
  git diff --name-status origin/main \
    60e7e058c2a309d7e15c46f3e2f5d5556597dcc3 -- \
    .github/workflows/sandbox-deployment.yml \
    .github/actionlint.yaml
  printf '\nExisting worktrees:\n'
  git worktree list
)
```

Review this output before preparing the branch. Preserve any existing lint
configuration and worktrees rather than overwriting them. Only necessary
workflow-registration changes belong in the `main` PR; do not release all of
`vnext` or cherry-pick the whole implementation commit.
Use a separate worktree to preserve the original checkout's private deployment
files and ongoing documentation updates. Those guide updates will be published
separately to `vnext`, not included in the narrow `main` update.
Do not dispatch until the updated default-branch workflow is registered.

The attended inspection confirmed that `main` already contains the workflow,
custom-runner actionlint configuration, and local CI runner. Only the workflow
differs from the approved implementation. An earlier registration worktree
still exists; preserve it and use a different branch and worktree below.

## Step 31: Commit the workflow-only main update

Run from the original repository root. This creates a separate worktree from
`origin/main`, copies only the approved workflow, verifies the staged scope
and exact source match, commits it, and runs applicable CI afterward:

```bash
(
  set -euo pipefail
  registration_worktree="$(git rev-parse --show-toplevel)-sandbox-pipeline-registration"
  approved_commit=60e7e058c2a309d7e15c46f3e2f5d5556597dcc3
  git worktree add -b feat/register-sandbox-pipeline \
    "$registration_worktree" origin/main
  cd "$registration_worktree"
  git restore --source="$approved_commit" -- \
    .github/workflows/sandbox-deployment.yml
  git add -- .github/workflows/sandbox-deployment.yml
  test "$(git diff --cached --name-only)" = ".github/workflows/sandbox-deployment.yml"
  git diff --cached --check
  git diff --cached --exit-code "$approved_commit" -- \
    .github/workflows/sandbox-deployment.yml
  git --no-pager diff --cached --stat
  git commit \
    -m "Register three-stage Sandbox deployment workflow on main" \
    -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ./scripts/Invoke-CIChecks.sh actions secrets
  git --no-pager status --short
)
```

Expect exactly one changed file in the commit. The subshell leaves the
operator's terminal in the original checkout. Existing worktrees, deployment
configuration, state, and pending guide updates remain untouched.
If the new path or branch already exists, stop rather than overwriting it.
Any failed check blocks publication; report unavailable tools as skipped.

Do not push or create the PR until this output has been reviewed.
Automatic lint/secrets CI targets `vnext`, so the `main` registration branch
will additionally require manually dispatched hosted static checks on its
exact committed source before merging. The #810 review bypass does not apply
to this new PR. No Sandbox workflow is dispatched by these commands.

The attended preparation produced commit `89200c6`, containing exactly one
changed workflow file matching the approved source. Both local Actions and
secret-scanning gates were skipped because their tools were unavailable.
The check runner reported no failures and the registration worktree was clean.
These skipped gates are not evidence of successful static analysis.

## Step 32: Publish the narrow main PR

From the original checkout, enter the separate registration worktree inside
a subshell. Repeat the applicable local checks before each publication action:

```bash
(
  set -euo pipefail
  registration_worktree="$(git rev-parse --show-toplevel)-sandbox-pipeline-registration"
  cd "$registration_worktree"
  ./scripts/Invoke-CIChecks.sh actions secrets
  git push --set-upstream origin feat/register-sandbox-pipeline
  ./scripts/Invoke-CIChecks.sh actions secrets
  gh pr create \
    --repo Azure-Samples/azuresandbox \
    --base main \
    --head feat/register-sandbox-pipeline \
    --title "Register three-stage Sandbox deployment workflow on main" \
    --body '## Summary
- Update only the manual Sandbox deployment workflow from the approved #810 merge.
- Keep protected-environment approval and trusted vnext source checkout.
- Register preflight, apply, unit-test, and sanitized test-evidence publication without releasing unrelated vnext changes.

## Validation
- The only changed file exactly matches the approved implementation.
- Local Actions and secret-scanning gates were skipped because their tools were unavailable.
- Hosted Actions and secret checks must be manually dispatched on this registration branch before merging.
- No Sandbox deployment has been dispatched.'
)
```

Stop if a check or publication command fails. Share the new PR URL before
merging or dispatching anything. Publishing this PR does not run Terraform.
The next step must verify actual hosted actionlint and gitleaks jobs on the
registration commit; passing checks on #810 are not a substitute.
Any required review or bypass authorization must be resolved for this PR
independently.

The operator published the registration branch and opened
[PR #811](https://github.com/Azure-Samples/azuresandbox/pull/811) against `main`.
Both pre-publication local checks reported no failures, with Actions and
secret scanning skipped.

## Step 33: Verify the published registration PR

Inspect the published head, base, file scope, and review requirements:

```bash
gh pr view 811 \
  --repo Azure-Samples/azuresandbox \
  --json baseRefName,headRefName,headRefOid,files,mergeable,mergeStateStatus,reviewDecision,isDraft
```

Expect base `main`, head `feat/register-sandbox-pipeline`, commit beginning
`89200c6`, and only `.github/workflows/sandbox-deployment.yml` in the file list.
Review this output before dispatching hosted CI.
Automatic `ci-actions` and `ci-secrets` triggers target `vnext`, not `main`;
the subsequent manual dispatches must use the registration branch, not
`vnext`. Inspect actual job outcomes and require both actionlint and gitleaks
to run successfully on the verified head. No review-bypass authorization
has been granted for #811.

The published PR inspection confirmed `main` as base, exactly one workflow
file, and head `89200c69bf93d1617a163c105631b9b1967db678`.
GitHub reported `CLEAN`, `MERGEABLE`, and no required review decision.
This does not replace verification of the hosted static checks.

## Step 34: Dispatch hosted checks on the registration commit

Run only these static-analysis workflows on the registration branch:

```bash
gh workflow run ci-actions.yml \
  --repo Azure-Samples/azuresandbox \
  --ref feat/register-sandbox-pipeline &&
gh workflow run ci-secrets.yml \
  --repo Azure-Samples/azuresandbox \
  --ref feat/register-sandbox-pipeline &&
gh run list \
  --repo Azure-Samples/azuresandbox \
  --branch feat/register-sandbox-pipeline \
  --commit 89200c69bf93d1617a163c105631b9b1967db678 \
  --event workflow_dispatch \
  --limit 5 \
  --json workflowName,databaseId,headSha,status,conclusion
```

These workflows use GitHub-hosted runners and do not deploy Azure resources,
run live Sandbox tests, or consume the protected deployment environment.
The list is bound to the verified PR head. If a run has not appeared yet,
query the list again later instead of dispatching duplicates.
Record the returned run IDs and inspect their jobs before merging.
Require the actual `actionlint` and `gitleaks` jobs to succeed; a skipped
actionlint job or a merely successful dispatch is not sufficient.
Do not dispatch `sandbox-deployment.yml` in this step.

The operator verified both hosted runs on the exact registration head:

| Check | Run | Actual analysis job |
|---|---|---|
| Actions | [38306902897](https://github.com/Azure-Samples/azuresandbox/actions/runs/38306902897) | `actionlint`: completed successfully |
| Secrets | [38306906653](https://github.com/Azure-Samples/azuresandbox/actions/runs/38306906653) | `gitleaks`: completed successfully |

Both runs reported source `89200c69bf93d1617a163c105631b9b1967db678`.
Neither analysis job was skipped.

## Step 35: Merge the checked registration PR

Recheck the PR checks, then merge the exact verified head without an admin
bypass. This is a narrow topic-branch registration update, not a full
`vnext`-to-`main` release:

```bash
gh pr checks 811 --repo Azure-Samples/azuresandbox &&
gh pr merge 811 \
  --repo Azure-Samples/azuresandbox \
  --squash \
  --match-head-commit 89200c69bf93d1617a163c105631b9b1967db678 \
  --subject "Register three-stage Sandbox deployment workflow on main" \
  --body 'Register the approved manual deployment workflow while retaining protected-environment approval and trusted vnext checkout.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>' &&
gh pr view 811 \
  --repo Azure-Samples/azuresandbox \
  --json state,mergedAt,mergeCommit,url
```

If required review or another branch rule blocks the normal merge, stop
and report it rather than adding `--admin`. No review bypass has been
authorized for #811. If the head changed, the pinned merge must fail; do not
substitute an unverified head.
Share the merge confirmation before dispatching a deployment.
Merging this manually triggered workflow does not itself create Azure resources.

GitHub confirmed #811 merged normally into `main` at
`cdbe5517b9cf18c8f0ec9d9f396cc7ff199dbdc9`.
The PR check list showed only the successful CLA check; the separately
dispatched hosted static runs above supplied the actionlint/gitleaks evidence.
No deployment has been dispatched by these publication steps.

## Step 36: Recheck registration and runner availability

Before dispatching the approved new-Sandbox full run, check the registered
workflow, its source blob, current trusted-source tip, runner availability,
and environment secret names:

```bash
(
  set -euo pipefail
  gh api repos/Azure-Samples/azuresandbox/actions/workflows/sandbox-deployment.yml \
    --jq '{name,state,path}'
  gh api 'repos/Azure-Samples/azuresandbox/contents/.github/workflows/sandbox-deployment.yml?ref=main' \
    --jq '{path,sha}'
  printf '\nExpected workflow blob:\n'
  git rev-parse \
    60e7e058c2a309d7e15c46f3e2f5d5556597dcc3:.github/workflows/sandbox-deployment.yml
  printf '\nCurrent trusted source commit:\n'
  gh api repos/Azure-Samples/azuresandbox/git/ref/heads/vnext \
    --jq '.object.sha'
  gh api repos/Azure-Samples/azuresandbox/actions/runners \
    --jq '.runners[] | select(any(.labels[]; .name == "azuresandbox")) | {status,busy,labels:[.labels[].name]}'
  gh secret list \
    --repo Azure-Samples/azuresandbox \
    --env sandbox-deployment \
    --json name --jq '.[].name'
)
```

Expect an active workflow, matching workflow blob hashes, trusted source
`60e7e058c2a309d7e15c46f3e2f5d5556597dcc3`, an online idle runner with the required
labels, and both `SANDBOX_BACKEND_HCL` and `SANDBOX_TFVARS_HCL` secret names.
If trusted source advanced, inspect and approve the new source before deploying;
do not silently treat it as the already checked commit.
The name-only secret check does not read or validate secret contents.
The operator already approved those complete HCL inputs and the new independent
Sandbox/full-test scope. No new configuration values are inferred here.
Share the readiness output before dispatching.

The attended readiness check passed: the workflow was active; its blob
`5a426f9b732728743c9e6762292d7f411f49cec8` matched the approved definition;
`vnext` remained at `60e7e058c2a309d7e15c46f3e2f5d5556597dcc3`;
the runner was online and idle with the required labels; and both HCL
environment secrets existed.

## Step 37: Dispatch the approved full new-Sandbox run

The command below records the original verified dispatch, before the local
new-only simplification. For the simplified workflow after publication, use
the command in step 43, without the removed selector inputs.

The operator already approved a new independent Sandbox using the confirmed
HCL inputs, all base modules, disabled extras, and all-module unit/integration
tests. Dispatch once on `main`, explicitly leaving the existing ID empty:

```bash
gh workflow run sandbox-deployment.yml \
  --repo Azure-Samples/azuresandbox \
  --ref main \
  -f run_through=unit-test \
  -f deployment_mode=new \
  -f deployment_id=''
```

Record the returned run URL/ID and share it before environment approval.
If needed, identify the run without creating another dispatch:

```bash
gh run list \
  --repo Azure-Samples/azuresandbox \
  --workflow sandbox-deployment.yml \
  --branch main \
  --event workflow_dispatch \
  --limit 3 \
  --json databaseId,displayTitle,status,conclusion,url
```

The stable deployment ID is `sandbox-<this-initial-run-id>` and its state key
is `sandboxes/sandbox-<this-initial-run-id>/terraform.tfstate`.
Do not supply an existing Sandbox ID or fall back to a shared backend key.
Dispatch creates the workflow run; the protected environment requires approval
before its job starts.

Approving this `unit-test` selection authorizes the full sequence:
preflight, then automatic apply of its exact saved plan, then all-module
unit/integration tests. There is no separate approval between stages.
This creates additional billable Azure resources; a successful preflight
alone is not evidence that apply or tests succeeded.
Do not run interactive Terraform operations against this target in parallel.
Do not dispatch again or retry a failed deployment without an explicit decision.

The operator dispatched the requested run once:
[38307770905](https://github.com/Azure-Samples/azuresandbox/actions/runs/38307770905).
Its intended stable Sandbox ID is `sandbox-38307770905`; its backend target is
`sandboxes/sandbox-38307770905/terraform.tfstate`.
This records the selected target, not confirmation that state or resources
have already been created.

## Step 38: Verify and approve the protected full run

Inspect the exact run before approving:

```bash
gh run view 38307770905 \
  --repo Azure-Samples/azuresandbox \
  --json displayTitle,event,headBranch,headSha,status,conclusion,url,jobs \
  --jq '{displayTitle,event,headBranch,headSha,status,conclusion,url,jobs:[.jobs[]|{name,status,conclusion}]}'
```

Expect title `Sandbox sandbox-38307770905 / unit-test`, event
`workflow_dispatch`, branch `main`, and workflow source
`cdbe5517b9cf18c8f0ec9d9f396cc7ff199dbdc9`.
The runtime checkout will separately use the trusted `vnext` source; its actual
SHA is recorded by preflight.
If metadata does not match, stop before approving and report the difference.

Open that exact run URL in the GitHub portal as the configured environment
reviewer. Select **Review deployments**, select `sandbox-deployment`, and
choose **Approve and deploy**. This is the existing environment-review gate,
not an admin bypass or a change to protection rules. Self-approval is allowed
by the previously confirmed environment configuration.

Approval permits all three stages to proceed automatically. Confirm approval
and share the metadata output before moving to monitoring.
If the approval control is absent or an error appears, report that state
rather than changing environment protections, rerunning, or dispatching again.

The attended metadata check matched the intended run and showed it waiting
for environment approval. No deployment stage had started.

## Step 39: Set up independent read-only monitoring before approval

At the operator's request, the assistant installed an independent collector on
the runner VM using Azure VM **Run Command**, before environment approval.
The VM resource ID was obtained from this standalone configuration's
`resource_ids["virtual_machine_jumplinux2"]` output, not inferred from names or
copied into public documentation.

The current port's collector source is maintained here:

* `scripts/Watch-SandboxRunner.sh`
* `scripts/Watch-SandboxRunner.ps1`
* `scripts/SandboxProgress.ps1` (shared progress filter)

When installing the reviewed port, copy all three files into the same
owner-only directory. Start it through the Bash launcher so the restrictive
umask applies to files created by PowerShell. For example, its systemd
`ExecStart` can invoke:

```bash
bash /path/to/private-monitor/Watch-SandboxRunner.sh \
  -RunId <run-id> -Attempt 1 \
  -OutputDirectory /var/lib/azuresandbox-monitor/<run-id>-1
```

The collector installed for the first deployment used the original Python
implementation and completed normally. Local edits do not replace an installed
collector or alter the active Actions job.

The collector runs as a detached systemd service named
`azuresandbox-monitor-<run-id>-<attempt>`, independent of the Actions job and the
client connection. Every 120 seconds it records a sanitized snapshot and
private history under `/var/lib/azuresandbox-monitor/<run-id>-<attempt>/`.
The directory is owner-only, with a restrictive umask for its files.
It stops on a recorded stage failure or completed unit-test stage, and has
a maximum lifetime of six hours.

Monitoring reads the runner service state, process names/counts, and this run's
private stage logs/status receipts. It extracts only logical Terraform resource
addresses, operation names, and elapsed heartbeat counters; resource IDs and
arbitrary diagnostics are not returned as progress text.
It does not read backend configuration, tfvars, plans, or Terraform state.
After setup, no Terraform CLI command is needed for monitoring.
It never starts, retries, repairs, or cancels deployment operations.

The verified initial snapshot reported an active runner service, one listener,
no worker or Terraform process, and `awaiting-job`/`waiting` health.
VM Run Command returned `MONITOR_READY` and confirmed the service was active.
The assistant's client-side timed reads retrieve these snapshots through
Run Command for approximately two-minute progress updates.
Approval remains an attended portal action by the operator.
Public updates must use only the sanitized snapshot, not raw private logs.

Health follows log advancement, not total resource provisioning time:
advancing output is healthy; four quiet minutes warrant a possible-stall
warning; ten quiet minutes warrant a suspected-hang warning and a human
decision. Slow gateway creation with advancing heartbeats is not a hang.
Monitoring failures must be reported separately from deployment failure.

## Step 40: Add sanitized apply progress to future Actions runs

While the first apply was running, the operator requested a local-only change
to enrich its two-minute Actions heartbeat with a filtered log tail.
The local deployment helper now prints up to four distinct logical resource
progress lines after the existing elapsed-time/health message.
Only newly written, complete lines are considered, with at most the newest
64 KiB read per heartbeat. Repeated heartbeats for one resource collapse to
its latest operation/counter.

Illustrative public output:

```text
apply: 76 min elapsed; log advancing.
  module.vwan[0].azurerm_point_to_site_vpn_gateway.this: Still creating... [19m50s elapsed]
```

The port's `scripts/SandboxProgress.ps1` shares the allowlisted parser with the local
independent monitor. It accepts known Terraform resource types, logical labels,
numeric module/resource indexes, and operation/elapsed-time text. It excludes
resource-ID suffixes, quoted instance keys, arbitrary messages, hostnames,
and error details. It is not a raw `tail` or blanket log sanitizer.
If there is no new output, the helper retains the existing no-new-output
warning and does not replay old progress as fresh.

Preflight and unit-test logging, subprocess exit semantics, raw private logs,
and the two-minute interval remain unchanged.
A preview-read error is reported explicitly with diagnostics kept private;
it does not interrupt the apply or change its exit result.
The change and directly related regression coverage are local and uncommitted,
not pushed or deployed. The current workflow and installed monitor continue
using their original checked-out/copied code; this enhancement applies to
future runs after publication.

## Step 41: Add sanitized unit-test progress to future Actions runs

After apply completed successfully and the first unit-test stage began, the
operator requested an equivalent local-only enhancement for test heartbeats.
The helper now uses the same bounded, new-lines-only preview for `unit-test`,
with a test-specific allowlist instead of Terraform operation parsing.

Illustrative public output:

```text
unit-test: 4 min elapsed; log advancing.
  Module: vnet-shared
  vnet-shared: Passed=30 Failed=0 Total=30
  Integration: SSH connectivity
```

Only known static module names, friendly allowlisted integration labels,
numeric suite/overall summaries, and the final `RESULT: PASS`/`FAIL` marker
are exposed. When individual result lines arrive before a suite summary,
the preview shows counts labeled **recent result lines** for the current
preview window, not canonical cumulative test totals.
It does not expose check descriptions, VM targets, FQDNs, addresses,
usernames, exception continuations, or arbitrary diagnostics, even if verbose
details appear in the private log.

The preview remains limited to four lines and does not replay old output as
fresh. JSON artifacts remain the authoritative detailed result evidence.
Preview-read failures produce an explicit sanitized warning, retain private
diagnostics, and preserve the test subprocess's original exit code.
This code and its regression coverage are local and uncommitted; the
already-running test stage uses the original published helper unchanged.

## Step 42: Verify the first full deployment and evidence

[Run 38307770905](https://github.com/Azure-Samples/azuresandbox/actions/runs/38307770905)
completed successfully on 2026-10-12. All three stages, evidence preparation,
artifact upload, and final reporting succeeded. Private stage receipts confirmed:

| Stage | Exit code | Duration |
|---|---|---|
| Preflight | 0 | 1m36s |
| Apply | 0 | 88m00s |
| Unit-test | 0 | 17m05s |

The receipt binds deployment `sandbox-38307770905`, run `38307770905`,
attempt `1`, and runtime source
`60e7e058c2a309d7e15c46f3e2f5d5556597dcc3`.
The workflow definition used commit
`cdbe5517b9cf18c8f0ec9d9f396cc7ff199dbdc9` on `main`.
Manual operations on this same Sandbox must reuse its stable ID and state key;
the new-only workflow cannot modify it.

### Published result evidence

The verified artifact is
[unit-test-evidence-sandbox-38307770905-38307770905-1](https://github.com/Azure-Samples/azuresandbox/actions/runs/38307770905/artifacts/11778925440).
The assistant downloaded it and confirmed it contains exactly:

* `unit-test-results.json`: schema version `1`, exit code `0`.
* `unit-test-results.xml`: valid JUnit `testsuites` document.

The JSON reports **109 passed checks, zero failed checks**, 13 passed suites,
and 10 skipped suites. All eight base-module suites and five applicable
integration suites passed. The skipped suites correspond only to the
intentionally disabled Petstore, AVD, and on-premises extras and their related
integrations.
JUnit reports 119 cases, zero failures/errors, and 10 skipped cases;
the ten additional cases represent skipped suites rather than extra executed
checks.

Open the run's **Summary > Artifacts** to download the evidence through the
GitHub portal, subject to repository access and configured retention.
For a CLI download, choose a new empty destination and run:

```bash
gh run download 38307770905 \
  --repo Azure-Samples/azuresandbox \
  --name unit-test-evidence-sandbox-38307770905-38307770905-1 \
  --dir /path/to/empty/evidence-directory
```

No plans, state, HCL configuration, or raw private logs are in this artifact.
The detailed evidence remains separate from stage success messages.

### Monitor and local change status

The independent collector recorded exit code zero for every stage and stopped
normally. Its final snapshot showed an active runner listener, no job worker,
no Terraform or PowerShell process, and `completed` health.
No further client polling was scheduled after completion.
The runner remains available for later approved jobs; no infrastructure was
torn down.

The richer apply/unit-test heartbeat enhancements requested during this run,
the monitoring sources/tests, and the ongoing guide updates remain local and
uncommitted. They did not alter this verified run and are not yet published
to `vnext`. Publication requires a separate reviewed change and the applicable
post-commit pre-push CI checks.

## Step 43: Restrict automation to new Sandboxes only

The operator confirmed this change is **local only** and selected strict
new-only behavior: refuse any existing state blob on every attempt.
The local workflow removes `deployment_mode` and `deployment_id`; the helper
always derives `sandbox-<workflow-run-id>` and its unique state key.
Only `run_through` remains as a manual input.

After this change is published to `vnext` and the registered workflow is updated
on `main`, a full dispatch will be:

```bash
gh workflow run sandbox-deployment.yml \
  --repo Azure-Samples/azuresandbox \
  --ref main \
  -f run_through=unit-test
```

The protected approval remains necessary before execution. Preflight refuses
an existing blob before `terraform init`, regardless of the attempt number
or matching private receipt. A rerun may proceed only if the previous attempt
never created state. A preflight-only run that created even an empty state blob
cannot later be continued through a rerun; choose the desired terminal stage
on the initial dispatch, or start another independent Sandbox with a fresh run.

Existing-Sandbox selection, cross-run target reuse, state-based retry recovery,
and preflight public-access re-enablement have been removed. A stale caller
requesting an existing target is explicitly rejected, not silently interpreted
as a billable new deployment.
Per-attempt private files, plan/receipt verification, sanitized progress,
single test execution, evidence publication, and stage reporting remain intact.

This change does not delete or alter any deployed resources, remote state,
private receipts, or published artifacts. All previous Sandboxes remain tracked
by their original state; manual maintenance or teardown is outside automation.
The published workflow and source remain unchanged until a separately approved
publication.

## Step 44: Simplify post-test processing

The operator requested removing the separate preparation step locally.
Unit-test now runs the orchestrator once, then validates and stages its existing
JSON results before recording the final stage status. Finalization also
runs after test or prerequisite failures: valid failed-test evidence is retained,
and missing results are explicitly reported without fabrication.

Only two post-test steps remain:

* **Publish** uploads the explicit validated paths emitted by Unit-test, even
  when Unit-test failed. It skips upload if preparation produced no approved files.
* **Report** runs after earlier success or failure, summarizes the existing
  receipts and results, and links the uploaded artifact without rerunning tests.

Preparation errors are logged privately and surfaced with a sanitized message.
They cannot turn failed tests into success or replace an existing test failure
code. If testing succeeded but preparation failed, Unit-test fails.
Plans, state, configuration, and raw logs remain excluded from the upload.

This change is local and uncommitted; no deployed workflow or Azure resource has
changed. Before another dispatch after publication, update both the trusted
helper on `vnext` and the registered workflow on `main`: the old workflow still
invokes the removed standalone preparation command.

## Step 45: Publish the updated workflow before a second deployment

The operator authorized committing the accumulated changes and preparing
`vnext` and `main`. This publication includes sanitized apply/test previews,
new-only state checks, integrated evidence finalization, monitoring sources
and tests, the first-run evidence record, and the **Repository workspace** label.
GitHub automatically names its cleanup step **Post Repository workspace**;
both are provided by the standard checkout action, not custom deployment stages.

Use a clean topic branch based on current `vnext` for the implementation PR.
The original topic branch was previously squash-merged, so replay only the
new change rather than reintroducing its old commits. Preserve private
configuration, state, and existing worktrees.
For subsequent publication, run the applicable existing local CI gates after
committing and before every push or PR creation. Hosted checks must pass on
the exact PR head, and required review must be satisfied.
Earlier one-time review bypasses do not authorize bypassing this PR.

After the implementation is approved and squash-merged into `vnext`, prepare
a separate registration topic branch from current `main`. Copy only
`.github/workflows/sandbox-deployment.yml` from that approved merge.
Verify the one-file scope and exact blob match; do not release unrelated
`vnext` changes. Run local Actions/secret checks before publishing and manually
dispatch the hosted Actions/secret checks on that registration branch.
Require the actual analysis jobs to pass on the exact committed head before
the normal squash merge.

Do not dispatch the Sandbox workflow during the transition: the old registered
workflow invokes the removed preparation command, while the updated helper
prepares evidence inside Unit-test.
After both merges, verify the active registration, matching workflow blobs on
`vnext` and `main`, the approved trusted-source commit, an online idle runner,
and both protected HCL secret names.

Publication alone does not authorize a new billable deployment or modify
existing resources. Reconfirm the protected HCL inputs, module/tag scope,
full-test selection, and fresh independent Sandbox before dispatching.
Then use the simplified command in step 43 and approve that exact new run
through the existing environment protection gate.

## Step 46: Confirm inputs and readiness for the second deployment

The operator reconfirmed the existing protected HCL inputs, correct identities
and backend, complete required tags, all base modules with extras disabled,
and all-module unit/integration testing. The requested deployment is another
independent, billable Sandbox; the first deployment and its state remain intact.
No secret contents were read or changed during this confirmation.

Implementation PR #826 merged into `vnext` at
`4e837eb295f771dfe5ac139bba12e78b3288394e` with an explicitly authorized,
one-time review bypass for that PR only. Registration PR #827 merged normally
into `main` at `559447d62f4756eb92ba3a720d804e3499db44b6`.
The workflow blob on both branches is
`7fbb75b0f42fd5f286455b2a44ab4a376d8bb08c`.
Hosted checks passed; local secret scanning was unavailable.

The runner was offline at publication readiness. The operator reported starting
it, so recheck that it is online and idle before dispatch. From the operator's
Bash terminal, inspect the trusted source, registered definition, runner,
protected secret names, and recent deployment runs:

```bash
(
  set -euo pipefail
  gh api repos/Azure-Samples/azuresandbox/git/ref/heads/vnext \
    --jq '{ref,sha:.object.sha}'
  gh api repos/Azure-Samples/azuresandbox/git/ref/heads/main \
    --jq '{ref,sha:.object.sha}'
  gh api repos/Azure-Samples/azuresandbox/actions/workflows/sandbox-deployment.yml \
    --jq '{name,state,path}'
  gh api 'repos/Azure-Samples/azuresandbox/contents/.github/workflows/sandbox-deployment.yml?ref=main' \
    --jq '{path,sha}'
  gh api repos/Azure-Samples/azuresandbox/actions/runners \
    --jq '.runners[] | select(any(.labels[]; .name == "azuresandbox")) | {status,busy,labels:[.labels[].name]}'
  gh secret list \
    --repo Azure-Samples/azuresandbox \
    --env sandbox-deployment \
    --json name --jq '.[].name'
  gh run list \
    --repo Azure-Samples/azuresandbox \
    --workflow sandbox-deployment.yml \
    --limit 5 \
    --json databaseId,displayTitle,status,conclusion
)
```

Review the output before dispatch. Expect the exact commits/blob above,
an active workflow, an online idle runner with all required labels,
both HCL secret names, and no queued, waiting, or in-progress deployment.
If the trusted source changed, approve the new revision before continuing.
This inspection does not dispatch a workflow or start Terraform.

The operator's readiness output matched the approved source and registered
workflow commits and blob. The workflow was active, the runner online and idle
with all required labels, and both protected HCL secret names present.
The recent deployment runs were completed successfully; none was active.

## Step 47: Dispatch the second full new-Sandbox run

After the confirmed inputs and readiness check, dispatch once from the
operator's Bash terminal:

```bash
gh workflow run sandbox-deployment.yml \
  --repo Azure-Samples/azuresandbox \
  --ref main \
  -f run_through=unit-test
```

Do not supply the removed `deployment_mode` or `deployment_id` inputs.
Record and share the returned run URL before approving the protected environment.
Do not repeat the dispatch to check progress: another dispatch allocates
another independent Sandbox.
The new run derives `sandbox-<run-id>` and
`sandboxes/sandbox-<run-id>/terraform.tfstate`, leaving the first deployment
unchanged. Environment approval permits preflight, saved-plan apply, and
all-module unit/integration tests to proceed without another interstage prompt.

The operator dispatched the second run once:
[38334479593](https://github.com/Azure-Samples/azuresandbox/actions/runs/38334479593).
Its allocated deployment ID is `sandbox-38334479593`, and the state key is
`sandboxes/sandbox-38334479593/terraform.tfstate`.
Dispatch confirms selection of the target, not successful creation of state
or resources.

## Step 48: Verify the second run before approval

Inspect the exact run from the operator's Bash terminal:

```bash
gh run view 38334479593 \
  --repo Azure-Samples/azuresandbox \
  --json displayTitle,event,headBranch,headSha,status,conclusion,url,jobs \
  --jq '{displayTitle,event,headBranch,headSha,status,conclusion,url,jobs:[.jobs[]|{name,status,conclusion}]}'
```

Expect title `Sandbox sandbox-38334479593 / unit-test`, event
`workflow_dispatch`, branch `main`, definition commit
`559447d62f4756eb92ba3a720d804e3499db44b6`, and a job waiting for environment
approval. The trusted runtime source is separately checked out from `vnext`;
preflight records its actual revision.
Review this output before approving. A successful dispatch alone does not
confirm these settings or authorize bypassing the protection gate.

The operator's metadata output matched the expected title, event, branch,
and definition commit. The run and its deployment job were waiting for
environment approval; no deployment stage had started.

## Step 49: Approve the second full deployment

Open [run 38334479593](https://github.com/Azure-Samples/azuresandbox/actions/runs/38334479593)
as the configured environment reviewer. Select **Review deployments**, select
`sandbox-deployment`, and choose **Approve and deploy**.
This uses the existing environment protection gate, not an admin bypass.

Approval authorizes preflight, apply of its exact saved plan, and all-module
unit/integration tests for the confirmed new Sandbox. There is no separate
approval between stages. The first Sandbox and its state remain unchanged.
Do not run concurrent interactive Terraform commands against the new target.

After approving, inspect this same run rather than dispatching another:

```bash
gh run view 38334479593 \
  --repo Azure-Samples/azuresandbox \
  --json status,conclusion,jobs \
  --jq '{status,conclusion,jobs:[.jobs[]|{name,status,conclusion,steps:[.steps[]|{name,status,conclusion}]}]}'
```

The updated step list should show **Repository workspace**, **Preflight**,
**Apply**, **Unit-test**, **Publish sanitized unit-test evidence**, and
**Report stage results**, without a separate evidence-preparation step.
Two-minute apply/test previews begin only when the corresponding subprocess
has been running long enough for its heartbeat.

The operator approved the run. Its first execution snapshot showed
**Repository workspace** completed successfully and **Preflight** in progress.
The pending steps matched the updated layout, including Publish and Report
without a standalone preparation step, followed by **Post Repository workspace**.

## Step 50: Observe the second deployment without redispatching

Follow the existing run from the operator's Bash terminal:

```bash
gh run watch 38334479593 \
  --repo Azure-Samples/azuresandbox \
  --interval 120 \
  --exit-status
```

This refreshes GitHub step status every two minutes; it does not stream the
private Terraform log. To inspect the changed progress previews, keep the
run open in GitHub and expand **Apply**, then **Unit-test** when it starts.
Long-running subprocesses emit their sanitized previews at the two-minute
heartbeat. Short commands may finish without emitting a preview.

The terminal watch reports completion and exits nonzero for an unsuccessful
run. Stopping this local watch does not cancel the deployment.
If deployment fails, preserve and report the failure; do not retry, dispatch
another run, or alter configuration to work around it.
After completion, review stage outcomes, the artifact link, and JSON
results separately; a successful checkout or apply does not prove tests passed.

## Step 51: Port the deployment helpers to Bash + PowerShell

The operator requested a local, uncommitted port and removal of the helper
test sources and their empty `scripts/tests` directory. That directory held
Python unittest fixtures and a PowerShell privacy harness, not Pester tests.
It has been removed without replacement. The repository's existing Sandbox
unit/integration scripts and the workflow's all-module test phase remain intact.

The Bash entrypoints set `umask 077` before starting PowerShell 7.3 or newer.
The private-file permission APIs require its .NET 7 runtime or newer.
`Invoke-SandboxDeployment.ps1` owns the stage logic and uses .NET argument lists
and an explicitly filtered child environment. Its internal Bash command mode
redirects native stdout/stderr straight to private files, without pipe buffering
or shell evaluation of command text. The shared PowerShell filter retains
bounded previews, static allowlists, fresh complete lines, and a four-line limit.

The port retains new-only state rejection, backend/provider identity separation,
private per-attempt records, saved-plan/configuration hashes, two-minute command
heartbeats, the VM-start gate, one test invocation, failed-test evidence
finalization, explicit artifact paths, and always-run reporting.
The independent monitor keeps its systemd lifecycle and private JSON snapshot
format. It does not inspect Terraform state or change infrastructure.

No Python dependency remains in the deployment/monitor helpers.
Existing bootstrap JWT decoding and unrelated diagram-generation tooling are
outside this port and remain unchanged.

### Validation and publication boundaries

Use the existing Bash, PowerShell, Actions, Markdown, internal-link, and secret
checks. PowerShell analysis must include the new files before staging; an
unstaged file is not yet available in a committed-source worktree.
Do not change shared analyzer rules or delete initialized Terraform dependencies
to hide local-only findings. Inspect applicable changed scripts directly while
the port is uncommitted; after review/commit, run the unchanged umbrella checks
from a clean committed-source worktree if necessary.

No helper test suite, mock framework, or Pester dependency is retained.
Non-deploying real command executions can check argument forwarding, private
redirection, exit codes, progress filtering, and reporting. End-to-end acceptance
requires a separately approved fresh Sandbox run after publication; static CI
alone does not prove deployment parity.

Review the local diff before any staging, commit, push, or PR creation.
Until separately authorized, keep the published Python workflow/source and
the active deployment untouched. After review, publish the helpers to `vnext`
and register the matching workflow on `main` before dispatching the port.
Do not mix a Bash/PowerShell registration with a Python-only trusted checkout,
or the old Python registration with a checkout that has removed its entrypoint.

## Step 52: Publish the port and prepare a fresh full acceptance run

The operator reported that the second run completed with a
`vm_jumpbox_linux` integration-test failure. The workflow correctly marked
Unit-test as failed and published the failed result in its structured artifact.
That test failure will be investigated separately; it does not establish
end-to-end parity of the new helpers.

The operator deleted that Sandbox's resource group and authorized publication
of the port. Deleting a resource group does not necessarily delete its remote
state blob. Leave previous state and runner records untouched: a new dispatch
derives an independent Sandbox ID and state key.

The operator reconfirmed both protected HCL configurations, their identities,
backend, subscription, tenant, and required tags. The approved scope is all
base modules, disabled extras, and full deployed-module unit/integration tests.
The operator also approved another independent, billable Sandbox.

Publish the implementation through a PR to `vnext`, with the applicable local
CI gates clean before every push and PR creation. Then register only the
matching workflow through a separate PR to `main`; do not release unrelated
`vnext` changes. Honor branch protections and obtain separate authorization
for any review bypass. Do not dispatch during the transition.

Before dispatch, verify that the workflow blobs on `main` and `vnext` match,
the trusted `vnext` source contains all five Bash/PowerShell helper files,
the registered workflow is active, the approved runner is online and idle,
both protected secret names exist, and no deployment is active. Query secret
names only, never their values.

After publication and readiness confirmation, the operator manually runs:

```bash
gh workflow run sandbox-deployment.yml \
  --repo Azure-Samples/azuresandbox \
  --ref main \
  -f run_through=unit-test
```

Record the exact run URL returned by this command. Inspect that run's definition
SHA, title, and pending protected-environment approval before approving it.
Approval covers preflight, its saved-plan apply, and the full test suite.
Do not rerun a previous dispatch or delete its state to reuse it.

After approval, follow the exact returned run ID:

```bash
gh run watch <new-run-id> \
  --repo Azure-Samples/azuresandbox \
  --interval 120 \
  --exit-status
```

Review all stage outcomes and the JSON artifact. Explicitly distinguish
a reproducible Sandbox test failure from a helper/runtime failure. A correct
failed stage with matching failed-test evidence validates failure propagation,
not a fully passing deployment. Raw Terraform and orchestrator diagnostics
remain private on the runner. Stop and report infrastructure/helper errors
without automatically retrying or modifying the deployment.

## Step 53: Verify the Bash + PowerShell acceptance dispatch

The operator manually dispatched the full run from `main`:
[run 38411237820](https://github.com/Azure-Samples/azuresandbox/actions/runs/38411237820).
Its derived Sandbox ID is `sandbox-38411237820`; its independent state key is
`sandboxes/sandbox-38411237820/terraform.tfstate`.

Before approving the protected environment, inspect this exact run:

```bash
gh run view 38411237820 \
  --repo Azure-Samples/azuresandbox \
  --json displayTitle,event,headBranch,headSha,status,conclusion,url,jobs \
  --jq '{displayTitle,event,headBranch,headSha,status,conclusion,url,jobs:[.jobs[]|{name,status,conclusion}]}'
```

Expect `workflow_dispatch`, `headBranch: main`, the title
`Sandbox sandbox-38411237820 / unit-test`, and definition revision
`fb9c6aa9cea3ab5e385aaa47b0b10e9e3b73e05b`.
This is the workflow definition SHA, not the trusted `vnext` source SHA checked
out by Repository workspace. The source revision is recorded separately in the
saved-plan receipt and stage summary.

The job should remain waiting for protected-environment approval. These are
expected values, not a confirmed execution result. Review the returned snapshot
before approving; do not redispatch or approve a different run.

The operator's returned snapshot confirmed the expected title, event, branch,
and definition SHA. Both the run and its deployment job were `waiting`, with
no conclusion or completed deployment claimed.

## Step 54: Approve the port acceptance run

Open [run 38411237820](https://github.com/Azure-Samples/azuresandbox/actions/runs/38411237820),
choose **Review deployments**, select `sandbox-deployment`, and choose
**Approve and deploy**. Use the existing protected-environment approval, not an
admin bypass.

This authorizes preflight, its saved-plan apply, and full deployed-module
unit/integration testing for the confirmed new Sandbox. It does not authorize
updating or recovering a previous Sandbox. Do not run interactive Terraform
commands against this target while its apply is in flight.

After approval, inspect the same run:

```bash
gh run view 38411237820 \
  --repo Azure-Samples/azuresandbox \
  --json status,conclusion,jobs \
  --jq '{status,conclusion,jobs:[.jobs[]|{name,status,conclusion,steps:[.steps[]|{name,status,conclusion}]}]}'
```

Inspect Repository workspace and Preflight first. A completed checkout alone
does not establish preflight, apply, or test success. Preserve any failure
without automatically retrying or modifying the deployment.

## Step 55: Observe the port acceptance run

The operator's next snapshot showed the run and deployment job `queued`, with
no steps and no conclusion. Execution had not started; this snapshot is not a
failure or proof of deployment success.

Follow this exact run from the operator's Bash terminal:

```bash
gh run watch 38411237820 \
  --repo Azure-Samples/azuresandbox \
  --interval 120 \
  --exit-status
```

The command refreshes GitHub job/step status every two minutes and exits nonzero
if the run fails. Stopping the local watch does not cancel the workflow.
In GitHub, expand Apply and Unit-test to observe the helpers' sanitized
two-minute previews; raw logs remain private. Short commands can complete
without a preview. Keep an advancing Terraform creation heartbeat distinct
from a stalled process, even when a resource legitimately takes a long time.

If queuing persists for several minutes, inspect the approved runner's current
online/busy status before treating the delay as a deployment error. Do not
redispatch, cancel, or modify infrastructure merely because the run is queued.

## Step 56: Stop after the acceptance run's Apply failure

The operator's watch reported run `38411237820` completed with failure.
Read-only inspection of its public job evidence confirmed:

| Stage | Result |
|---|---|
| Repository workspace | Success |
| Preflight | Success, 1m18s |
| Apply | Failure, exit 1, 77m48s |
| Unit-test | Skipped |
| Publish sanitized unit-test evidence | Skipped |
| Report stage results | Success |
| Post Repository workspace | Success |

The job took 1h19m14s. Apply ran from 14:15:02 to 15:32:50 UTC on
2026-10-13. The actual trusted source checkout was
`6ca6859a3e91ea0e0ba3a6b62cb43cb400dd54b1`; the workflow definition SHA remained
`fb9c6aa9cea3ab5e385aaa47b0b10e9e3b73e05b`.

The failing workflow command was:

```bash
bash extras/configurations/rg-devops-iac/scripts/Invoke-SandboxDeployment.sh apply
```

Its available public error annotations were:

```text
apply failed (exit 1); review its private runner log.
Process completed with exit code 1.
```

The underlying native command/error remains in the private Apply log and has
not been retrieved. Do not infer a failing resource, a Terraform error, or a
port regression from these annotations or elapsed time alone.

The failure was recorded in
[issue #831](https://github.com/Azure-Samples/azuresandbox/issues/831),
with sanitized revision, scope, timing, and stage evidence. Full sanitized
native diagnostics and actual runtime/provider versions remain pending.
No automatic diagnosis, retry, state inspection, configuration change, or
new dispatch was performed. Stop until the operator explicitly authorizes
investigation or resumption. End-to-end acceptance of the port remains incomplete.

The operator subsequently requested closing issue #831 and addressing the
failure in the attended session. The issue was closed as `not planned`, not
as fixed. This does not establish a passing apply or acceptance result.

## Step 57: Exclude an unrelated alert deployment failure

The operator clarified that the previously supplied Azure Copilot alert
deployment failure was not part of this deployment. Disregard that finding
when investigating run `38411237820`; it is not evidence for the Apply failure
and does not justify changing provider registration for this acceptance run.

The workflow's Apply failure remains unexplained pending its private error
log. No provider registration, retry, or infrastructure change was performed.

## Step 58: Record the reported P2S gateway operation conflict

The operator supplied the activity-log event identified as the actual
deployment failure. Its non-identifying technical fields were:

| Field | Value |
|---|---|
| Operation | `Microsoft.Network/p2sVpnGateways/write` |
| Resource type | `Microsoft.Network/p2sVpnGateways` |
| Status | `Failed` |
| Event time | 2026-10-13 15:32:07 UTC |
| Outer error | `ResourceOperationFailure` |
| Detailed error | `UpdateGatewayInProgress` |

The detailed error message was:

```text
There is already another operation in progress for updating the gateway.
Please try any update/delete operation after some time.
```

Azure reported a conflicting in-progress gateway update. The event occurred
approximately 43 seconds before the workflow reported Apply failure, which
aligns with the failure window. It is not a resource-provider registration
error or a Terraform state-lock error.

The event does not identify the other operation or its initiator. Do not
infer concurrent workflow applies, a policy action, a helper regression, or
a specific recovery method without additional evidence. The matching private
Terraform error remains to be collected.

Identity claims, caller/application identifiers, subscription/tenant IDs,
correlation/event identifiers, and deployment-specific resource paths are
intentionally excluded. No gateway update, deletion, retry, or workflow
redispatch was performed.

## Step 59: Accept the run as an Apply-failure handling case

The operator assessed the gateway operation conflict as transient and accepted
run `38411237820` as a test case for transient failure during Apply.
This is the operator's classification, not proof that the underlying conflict
has cleared or that a subsequent apply would succeed.

The observed workflow behavior met this failure-path expectation: Preflight
passed, Apply surfaced exit code 1 and failed the job, Unit-test and test
artifact publication were skipped, and reporting and checkout cleanup completed.
No test success was fabricated and no automatic retry hid the failure.

This validates the observed Apply-failure propagation and stage gating. It
does not establish successful infrastructure deployment, completion of the
public-access barriers, or full unit/integration acceptance of the port.
Partial infrastructure may remain after the failed apply. No retry, cleanup,
new dispatch, or code change is authorized by this classification alone.

## Step 60: Await the operator's next full deployment

The operator reported deleting the failed Sandbox and chose to continue
acceptance with another full, independently dispatched deployment. The operator
already has the commands and will invoke and approve the workflow manually,
then provide its outcome.

No new run ID or execution result has been supplied. Do not record a dispatch,
successful cleanup verification, passing deployment, or passing tests yet.
Keep the accepted transient Apply-failure case separate from the next run's
full-success acceptance evidence. No assistant-initiated dispatch or
configuration change was performed.

## Step 61: Inspect the apparent SQL-module test stall

The operator requested read-only troubleshooting through VM Run Command on
the self-hosted runner after the portal reported no new unit-test log output.
The active run was
[38438999153](https://github.com/Azure-Samples/azuresandbox/actions/runs/38438999153).
Preflight and Apply succeeded; Unit-test began at 19:06:43 UTC on 2026-10-13.

Runner snapshots at 19:31:58 and 19:33:22 UTC showed an active runner service,
a live supervisor and test process, and unchanged native/orchestrator logs
last modified at 19:12:13 UTC. The native test process's stdout and stderr
were redirected directly to the private stage log, not an undrained pipe.
The latest module was `vm-mssql-win`; no final test receipt or result files
existed at those snapshots.

The final lifecycle messages showed SQL VM deallocation followed by startup,
without the subsequent SQL-readiness message. In the existing orchestrator,
that places the wait at `Start-AzVM` inside `Invoke-VMStopDeallocateStart`,
before readiness probes or the SQL module's guest test Run Command.
Both the orchestrator and managed-identity connection wrapper were unchanged
between the published Python and Bash/PowerShell implementations.

Read-only Azure inspection showed:

| Evidence | Observation |
|---|---|
| SQL VM deallocation | Succeeded at 19:11:52 UTC |
| SQL VM start | Started and accepted at 19:12:13 UTC; no terminal event in the returned activity-log window |
| SQL VM power state | Running |
| SQL VM provisioning state | Updating |
| Guest-agent status | Not present in the returned instance view |

These findings localize the delay to an unfinished Azure VM startup operation;
they do not establish why Azure has not completed it. There was no evidence
of a port-induced stdout/stderr deadlock. Lack of progress for over 20 minutes
was surfaced as a suspected stall, not reported as healthy test progress.

No processes were killed, tests rerun, VMs restarted, or Terraform state read.
No guest Run Command was issued to the SQL VM. Deployment-specific identities,
resource names, and resource paths are omitted from this record. Recovery or
cancellation requires the operator's decision.

## Step 62: Track the startup-test issue without changing the workflow

The operator classified the stall as a `vm_mssql_win` unit-test issue, requested
a separate issue, and instructed that the workflow remain unchanged.
[Issue #832](https://github.com/Azure-Samples/azuresandbox/issues/832)
records the existing startup-cycle test's long, opaque lifecycle wait and lack
of a test-level wall-clock bound. No workflow fix or cancellation was performed.

After the operator reported the SQL VM showing Running in the portal, a
read-only API snapshot confirmed provisioning changed from Updating to
Succeeded at 19:37:34 UTC. Power state remained Running; the guest agent
reported Not Ready, with its status blob not yet populated.

A runner snapshot at 19:38:54 UTC confirmed both logs advanced at 19:37:36 UTC
to the SQL startup-readiness phase. The `Start-AzVM` wait cleared without
intervention after approximately 25 minutes. It was no longer the blocking
call at that snapshot. No final unit-test receipt existed.

The issue was updated with this progress rather than treating the earlier
snapshot as a persistent hang. SQL readiness and full acceptance remain
pending. No VM recovery, process termination, test rerun, or workflow change
was performed.

## Step 63: Verify supervisor cadence separately from test progress

The operator reported a portal gap from the 28-minute to the 44-minute
unit-test heartbeat. This was investigated independently; a blocked native
test call should not prevent the separate supervisor's two-minute updates.

Read-only runner diagnostics showed successful console-batch uploads at
19:34:53, 19:36:53, 19:38:53, 19:40:53, 19:42:53, 19:44:53, 19:46:53,
19:48:52, and 19:50:52 UTC on 2026-10-13, each with success rate `1/1`.
Uploads continued every two minutes through 19:58:52 UTC.

A 150-second sample from 19:57:21 to 19:59:51 UTC recorded 68 additional
supervisor-written bytes across two write calls. The native test log remained
unchanged, last modified at 19:37:36 UTC. These observations support continued
heartbeat generation and successful runner-side console delivery during the
quiet test. They do not establish a 16-minute supervisor pause; the apparent
portal gap concerns live display/delivery downstream of those uploads.

Separately, Azure activity-log evidence showed the first SQL-readiness guest
Run Command started and accepted at 19:38:07 UTC, without a terminal event in
the returned window. The SQL VM again reported Updating and guest agent
Not Ready in the 19:47 snapshot. This explains the current quiet test phase
without explaining the underlying guest-agent delay.

Issue #832 was updated with both distinctions. No workflow or VM changes,
process termination, test rerun, or additional SQL guest command were performed.

## Step 64: Confirm whole-job timeout and post-run state

The operator supplied the final watch output for run `38438999153`, including:

```text
The job has exceeded the maximum execution time of 3h0m0s
The operation was canceled.
```

GitHub reported the run and job `cancelled`, not a normally completed test
failure. The configured `timeout-minutes: 180` applies to the entire deployment
job, including checkout, Preflight, Apply, and Unit-test. It is not a separate
180-minute allowance for testing.

| Event | Time or outcome |
|---|---|
| Job began | 2026-10-13 17:29:38 UTC |
| Preflight | Success |
| Apply | Success; completed at 19:06:43 UTC |
| Unit-test | Cancelled at 20:30:20 UTC, after about 83m37s |
| Job ended | 20:30:23 UTC; total 3h0m45s including cancellation/cleanup |
| Test artifact publication | Skipped; no uploaded artifacts |
| Reporting and checkout cleanup | Success |

The operator reported manually stopping the SQL VM. Read-only activity logs
showed deallocation starting at 20:21:30 and succeeding at 20:22:49 UTC.
Subsequent test Run Commands failed with `OperationNotAllowed`, stating that
the VM must be running. The test later advanced through readiness attempts and
into integration tests; it had not completed before the job deadline.

A later operator start succeeded at 20:37:59 UTC; the last VM snapshot before
cleanup showed Running, provisioning Succeeded, and guest agent Ready.
The operator then reported deleting the Sandbox resource group. No further
inspection of that group was performed. Independently stored Terraform state
is not assumed deleted and was not modified.

A runner snapshot at 20:41:36 UTC confirmed no remaining PowerShell/Terraform
processes from the workflow. The runner was online and idle. Successful
Preflight and Apply receipts remained, but no final Unit-test receipt or
JSON/JUnit result files existed. The private native stage log and workspace
orchestrator log retained partial test evidence through 20:30:06 UTC.
Do not fabricate a completed result or treat partial summaries as full acceptance.

The observed whole-job timeout, cancellation, reporting, and process cleanup
worked as the configured safety boundary. Completed unit/integration acceptance
and structured test-result publication were not exercised successfully by this
run. Issue #832 tracks the test-level bounded-wait concern; no workflow or
unit-test implementation changes were made.

## Step 65: Record the next full acceptance dispatch

The operator manually dispatched another full run from `main` using
`run_through=unit-test`:
[run 38465302741](https://github.com/Azure-Samples/azuresandbox/actions/runs/38465302741).
The workflow implementation was unchanged. The derived Sandbox ID is
`sandbox-38465302741`, with independent state key
`sandboxes/sandbox-38465302741/terraform.tfstate`.

Inspect this exact run before protected-environment approval:

```bash
gh run view 38465302741 \
  --repo Azure-Samples/azuresandbox \
  --json displayTitle,event,headBranch,headSha,status,conclusion,url,jobs \
  --jq '{displayTitle,event,headBranch,headSha,status,conclusion,url,jobs:[.jobs[]|{name,status,conclusion}]}'
```

Compare its workflow definition revision with the published registration
`fb9c6aa9cea3ab5e385aaa47b0b10e9e3b73e05b`, and verify the full-test title,
`workflow_dispatch` event, and `main` branch before approving. The runner-side
execution observations below do not establish a passing acceptance outcome.

## Step 66: Distinguish stale preparation status from runner execution

The operator reported that run `38465302741` appeared stuck preparing its
workspace. GitHub's API showed an online, busy runner and an in-progress job,
but returned an empty step list.

With the operator's authorization, read-only VM Run Command diagnostics inspected
the runner's worker log, without reading Terraform state or modifying the
deployment. The worker log showed:

* Workspace checkout completed, and Preflight began at `20:46:07 UTC`.
* Preflight completed, and Apply began at `20:47:29 UTC`.
* Console-batch uploads succeeded at approximately two-minute intervals through
  `20:55:32 UTC`.

These observations establish that execution had advanced beyond preparation
despite the stale GitHub display. They do not establish an Apply or Unit-test
result, or identify the cause of the delayed GitHub status.

A second read-only snapshot at `20:56:57 UTC` confirmed an active Terraform
process for the current run and advancing native Apply heartbeats for Azure
Firewall and Bastion. Disk space was not exhausted: approximately `9.5 GiB`
remained available, with `5%` of filesystem inodes used. No lingering
PowerShell or Terraform process from the previous run appeared in the process
snapshot. Apply was progressing; no completed deployment or test result had
yet been observed.

The operator subsequently deleted the previous cancelled workflow run from
GitHub. The new run had already entered Apply before that deletion, so deleting
the earlier run was not needed to start it. Deleting a workflow run removes its
GitHub history and associated logs and artifacts; it does not clean up Azure
resources or Terraform backend state. Do not use workflow-run deletion as a
runner recovery mechanism.

The operator also reported missing stage status in both `gh run watch` and the
portal. Fresh requests to GitHub's individual-job and run-job APIs both returned
`steps: []`, so this was not merely a browser-refresh problem. At `20:59:28 UTC`,
the runner log showed that its timeline-update queue had started and its initial
job timeline update had completed, with no matching warning or error records.
Console uploads continued to succeed through `20:57:32 UTC`. Successful console
uploads do not establish successful publication or processing of step-status
updates. GitHub Status reported Actions operational with no active incidents,
but that does not exclude a run-specific problem. The missing step timeline's
root cause remained undetermined; no workflow or runner recovery changes were
made.

## Step 67: Record operator cancellation and runner restart

The operator cancelled run `38465302741`, reported deleting its Sandbox resource
group, and restarted the self-hosted runner. GitHub subsequently confirmed that
the run and job had completed with conclusion `cancelled`, and the runner was
online and idle.

A read-only runner process snapshot at `21:05:48 UTC` showed the runner listener,
with no Terraform or PowerShell processes. This confirmed that no previous
deployment process remained active before another dispatch. The restart's
effect on step-status reporting was not yet established.

Resource-group deletion does not remove the independently stored backend state.
Use a new manual dispatch for the next fresh Sandbox; do not rerun the cancelled
run against its existing state key. This cancelled attempt did not establish a
passing Apply or Unit-test outcome.

## Step 68: Record the fresh dispatch after runner restart

The operator manually dispatched
[run 38468152894](https://github.com/Azure-Samples/azuresandbox/actions/runs/38468152894)
from `main` with `run_through=unit-test`. GitHub confirmed the expected title
`Sandbox sandbox-38468152894 / unit-test`, the `workflow_dispatch` event, and
workflow definition revision `fb9c6aa9cea3ab5e385aaa47b0b10e9e3b73e05b`.
The independent state key is
`sandboxes/sandbox-38468152894/terraform.tfstate`.

The operator confirmed protected-environment approval for this dispatch.

At `21:10:43 UTC`, the operator reported that stage-status updates were again
missing from both the portal and `gh run watch`, and elected to leave the run
running. The restart had not restored visible stage reporting at that point.
This observation alone does not establish the runner's actual deployment stage
or whether execution is advancing.

The first API snapshot showed an in-progress job with an empty step list.
That early snapshot alone does not establish whether the restart resolved the
previous run's missing step-status updates. No runner-side inspection or
completed stage result was available for this new run.

Watch the new dispatch:

```bash
gh run watch 38468152894 \
  --repo Azure-Samples/azuresandbox \
  --interval 120 \
  --exit-status
```

## Step 69: Enable independent monitoring for the current run

With stage reporting still unavailable, the operator requested independent
monitoring and approximately two-minute updates for run `38468152894`.
The existing reviewed Bash/PowerShell collector was copied from the runner's
checkout into an owner-only directory outside the Actions workspace and started
as `azuresandbox-monitor-38468152894-1.service`.

The collector records sanitized snapshots every 120 seconds under
`/var/lib/azuresandbox-monitor/38468152894-1/`, independently of GitHub's live
status display. It reads private stage receipts, log metadata, allowlisted
progress lines, and process counts; it does not inspect Terraform state or
modify the deployment. It stops on a recorded stage failure or completed
Unit-test stage, with a six-hour maximum lifetime.

The initial snapshot at `21:13:51 UTC` confirmed that the collector was active,
Preflight had passed, and Apply was healthy at approximately four minutes
elapsed. Terraform was creating Azure Firewall and Bastion, and the Key Vault
private endpoint had completed. No completed Apply or Unit-test result had
yet been observed.

The operator subsequently reported the portal message, "Job is about to start
running on the runner: <runner>." That message contradicted the verified
runner-side snapshot, which already showed Preflight complete and Apply
executing. This confirms misleading GitHub status for this run, but does not
establish a platform-wide service incident or identify the underlying cause.

## Step 70: Record successful Apply and the start of Unit-test

The independent collector's `22:45:52 UTC` snapshot confirmed successful
Preflight and Apply receipts (`exit_code = 0`) for run `38468152894`. The
Unit-test stage was executing at approximately two minutes elapsed, with
no active Terraform process.

The first visible test summary was `vnet-shared: Passed=9 Failed=0 Total=9`,
followed by `Module: vnet-app`. The collector reported advancing output and
healthy execution. Apply succeeded, but full unit/integration acceptance
remained pending.

## Step 71: Confirm SQL VM unit checks passed and integration tests advanced

By `22:57:52 UTC`, Unit-test was approximately 14 minutes into execution and
integration testing had advanced through SQL connectivity to Azure SQL
connectivity. Read-only extraction of allowlisted module-summary fields from
the native test log confirmed:

| Module | Passed | Failed | Total |
| --- | --- | --- | --- |
| `vm-mssql-win` | 25 | 0 | 25 |
| `mssql` | 6 | 0 | 6 |
| `mysql` | 6 | 0 | 6 |
| `vwan` | 6 | 0 | 6 |

The prolonged SQL VM startup/readiness stall from the preceding attempt had
not prevented completion of this run's SQL VM unit checks. This does not
establish that the unbounded-wait concern in #832 is fixed. Full integration
results and the final workflow outcome remained pending.

## Step 72: Record passing tests but failed evidence validation

The collector's final snapshot at `23:01:52 UTC` showed
`Overall: Passed=109 Failed=0 Total=109` and `RESULT: PASS`. P2S VPN integration
checks passed `12/12`. The native test process returned exit code `0`, but the
Unit-test deployment helper subsequently returned exit code `1`.

Read-only capture of the final private log established the helper error:

```text
Invalid JUnit XML; evidence was not published.
```

The stack identified `Stop-SandboxStage` at line 18,
`Export-SandboxEvidence` at line 348, and its caller at line 488 of
`scripts/Invoke-SandboxDeployment.ps1`. The XML was not inspected and no
automatic diagnosis, repair, or retry was attempted; this error alone does not
establish whether the generated XML or the validator is defective.

GitHub confirmed the final workflow conclusion `failure`: Preflight and Apply
passed, Unit-test failed, sanitized evidence publication was skipped, and
reporting and checkout cleanup passed. The artifacts API returned no artifacts.
The final API response included the completed step list despite the missing
live step status during observation.

The sanitized failure was filed as #833. All unit/integration checks passed,
but full workflow acceptance remains incomplete because evidence validation
failed. Apply took approximately `94m27s`; Unit-test approximately `17m01s`.

The collector stopped normally after recording the failure receipt. Its final
process snapshot showed no Terraform, PowerShell test, or runner-worker
processes, with the runner listener still active. Monitoring history remains
in the owner-only per-run directory for follow-up; no deployment resources or
Terraform state were modified by monitoring.

## Step 73: Remove JUnit output and use JSON-only unit-test evidence

At the operator's request, #833 was closed as not planned while the failure
was addressed on the current branch. Local reproduction showed that
PowerShell's XML adapter resolved the root's `name` attribute instead of its
element name, causing valid generated JUnit XML to be rejected.

The operator then selected JSON-only output instead of retaining XML support.
The root orchestrator and MSI wrapper no longer accept `-JUnitXmlPath` or
generate XML. The deployment helper requests, requires, validates, and stages
only `unit-test-results.json`; the workflow uploads only its explicit
`json_path`. Existing XML files are ignored, and artifact reporting labels
the evidence as JSON.

The framework's JUnit writer and XML-only string sanitizer are removed rather
than retained behind an unused option. No JUnit helper sources, replacement
test fixtures, or JUnit-specific validation are retained.

JSON schema version `1`, sanitization, test counts, and exit-code semantics
remain unchanged. Missing JSON is reported as unavailable; invalid JSON is
rejected rather than published. Successful tests still require their requested
JSON result file. No raw logs, state, configuration, or directory wildcards
are added to artifact publication.

At this step, these changes were local to the current branch. They had not
been published or exercised in a new Azure deployment.

## Step 74: Coordinate JSON-only publication before another deployment test

The operator authorized publication of the JSON-only changes, including
one-time merge overrides if needed for this publication. This does not
authorize unrelated protection changes, bypassing failed checks, or
automatically dispatching or approving another deployment.

Publish the source changes through `feat/sandbox-json-only` into `vnext`,
then publish only `.github/workflows/sandbox-deployment.yml` through
`feat/register-sandbox-json-only` into `main`. Keep the operator's checkout
and pre-existing worktrees intact. Run the applicable local CI checks after
committing and before every push or PR creation, and require successful
applicable hosted checks before merging. Verify that the workflow blobs on
`main` and `vnext` match after both merges.

The remaining deployment test is attended and operator-triggered. A new
dispatch must use a fresh run-derived state key; do not rerun an old attempt.
After publication is verified:

```bash
gh workflow run sandbox-deployment.yml \
  --repo Azure-Samples/azuresandbox \
  --ref main \
  -f run_through=unit-test
```

Approve the protected environment for that new run, then watch its returned
run ID. Full acceptance requires successful Preflight, Apply, Unit-test, JSON
artifact publication, and final reporting. Passing test counts alone are not
sufficient if evidence validation or upload fails.

## Step 75: Verify coordinated JSON-only publication

Source PR #834 merged into `vnext` as
`adba2c1a9b355d7590b1f0da631ff50ed49f6853`. All applicable PR checks passed
on its exact topic head before the operator-authorized one-time independent
review override was used. No protection settings were changed or failed
checks bypassed.

Workflow-only PR #835 merged normally into `main` as
`757784f976358c3b4a71db1b7be65545047af00e`, after hosted actionlint and
gitleaks passed on its exact topic head. The published workflow blob on both
branches is `0f2cc2f6329480e8af5f3a76a313938105f6123d`.

All six post-merge `vnext` CI workflows completed successfully. Local gitleaks
was unavailable and reported SKIPPED; hosted secret scanning passed.
The operator's checkout stayed on `feat/sandbox-deployment`, committed and
clean, with a source tree matching published `vnext`. Only the two worktrees
created for this publication were removed; older worktrees were preserved.
No deployment was dispatched or approved by the assistant.

## Step 76: Record the first JSON-only acceptance dispatch

The operator manually dispatched
[run 38486222399](https://github.com/Azure-Samples/azuresandbox/actions/runs/38486222399)
from `main` with `run_through=unit-test`. GitHub confirmed the expected title
`Sandbox sandbox-38486222399 / unit-test`, the `workflow_dispatch` event, and
workflow definition revision `757784f976358c3b4a71db1b7be65545047af00e`.
The independent state key is
`sandboxes/sandbox-38486222399/terraform.tfstate`.

The initial snapshot showed the job waiting for protected-environment approval.
The expected trusted source is the published `vnext` revision recorded above;
its actual checked-out revision must be verified once checkout executes.
No completed stage or acceptance outcome has yet been observed for this run.

At `23:48:21 UTC`, the operator confirmed protected-environment approval and
reported that workflow status messages were now flowing. This is consistent
with a transient reporting problem affecting the earlier runs; it does not
establish a confirmed GitHub service incident or its underlying cause.

After approving the protected environment, watch this exact dispatch:

```bash
gh run watch 38486222399 \
  --repo Azure-Samples/azuresandbox \
  --interval 120 \
  --exit-status
```

## Step 77: Capture the JSON-only acceptance run's Apply failure

The operator reported an Apply failure approximately 35 minutes into execution
and requested read-only capture of the runner's Apply log, explicitly directing
that no issue be filed. GitHub confirmed run `38486222399` completed with
conclusion `failure`: Preflight passed, Apply failed, Unit-test and artifact
publication were skipped, and reporting and checkout cleanup passed.

The captured private Apply-log tail showed these failures:

| Resource | Sanitized diagnostic |
| --- | --- |
| `module.vnet_app[0].azurerm_virtual_machine_extension.configure_azure_files` | `VMExtensionProvisioningError`, Custom Script Extension code `71`: the message mentioned managed-identity permissions but reported HTTP `404 Not Found` and "The specified blob does not exist." |
| `module.vnet_app[0].azurerm_storage_blob.remote_scripts["orchestrator"]` | Checking `Invoke-AzureFilesConfiguration.ps1` failed because `<storage-account>.blob.core.windows.net` could not be resolved: `no such host`. |
| `module.vnet_app[0].azurerm_storage_blob.remote_scripts["worker"]` | Uploading `Set-AzureFilesConfiguration.ps1` failed with `HTTP response was nil; connection may have been reset`. |

The affected resource declarations are `modules/vnet-app/compute.tf:113`
and `modules/vnet-app/storage.tf:92`. Apply finished with exit code `1` at
`00:24:22 UTC`. The observed upload failures and missing-blob response concern
Azure Files script publication/access; the outer managed-identity wording
alone does not establish an RBAC defect. No root cause was confirmed, no
configuration was changed, and no retry or issue creation was attempted.
The new JSON-only test/evidence path was not exercised because Unit-test
did not run.

## Step 78: Record the transient-failure assessment and related issues

The operator subsequently requested issue creation, assessed the failure as
transient, and stated that the failed Sandbox would be deleted before another
deployment. The sanitized recurrence was filed as #836, linking these verified
closed issues:

* #771 is the closest match: the same `vnet_app` script-blob DNS failure and
  Azure Files extension code `71`/missing-blob `404`. It was closed as not
  reproducible after a fresh deployment completed those resources and passed
  `109/109` checks; the original DNS cause was not diagnosed.
* #167 records a related storage-endpoint `no such host` error during Azure
  Files directory creation, attributed in its closing comment to client DNS.
  Its operation and environment differ from this run.

The operator's transient assessment is recorded separately from a confirmed
root cause. No automatic repair, retry, resource deletion, or reopening of
historical issues was performed by the assistant.

## Step 79: Record the next fresh JSON-only acceptance dispatch

The operator manually dispatched
[run 38491545341](https://github.com/Azure-Samples/azuresandbox/actions/runs/38491545341)
from `main` with `run_through=unit-test`. GitHub confirmed the expected title
`Sandbox sandbox-38491545341 / unit-test`, the `workflow_dispatch` event, and
workflow definition revision `757784f976358c3b4a71db1b7be65545047af00e`.
The independent state key is
`sandboxes/sandbox-38491545341/terraform.tfstate`.

The first snapshot showed the job waiting for protected-environment approval.
No execution outcome has yet been observed. After approval, watch this exact
run:

```bash
gh run watch 38491545341 \
  --repo Azure-Samples/azuresandbox \
  --interval 120 \
  --exit-status
```

## Step 80: Capture runner shutdown during the next Apply

The operator reported another Apply failure and requested private runner-log
inspection without issue creation. GitHub confirmed run `38491545341`
completed with conclusion `failure`, but the Apply step itself was
`cancelled`, not a normally completed Terraform error.

Apply started at `00:43:42 UTC`. Public logs showed advancing resource creation
at `00:45:44 UTC`, followed by:

```text
00:47:14 UTC: The runner has received a shutdown signal.
00:47:27 UTC: The operation was canceled.
```

Runner cleanup logged termination of the PowerShell supervisor, Terraform,
and provider processes. Unit-test, artifact publication, stage reporting,
and post-checkout cleanup were skipped.

The requested private-log read could not execute: VM Run Command returned
`OperationNotAllowed`, requiring the VM to be running. Read-only Azure instance
view confirmed that the execution VM was deallocated, and GitHub reported the
runner offline and idle. The captured public log contains no Terraform resource
error explaining this interruption; the initiator of the shutdown remains
unknown.

The private Apply log remains uninspected until the runner is available.
No VM start, deployment retry, Terraform state inspection, or issue creation
was attempted.

At `00:51:24 UTC`, the operator identified an environment-specific
cost-optimization policy as the cause of the runner shutdown and stated that
they would manually restart the runner and create a new dispatch. This cause
is operator-confirmed, not independently verified through Azure activity logs.
No policy identifiers or internal details are recorded here.

Before dispatching again, confirm the runner is online and idle. Use a new
dispatch rather than rerunning the interrupted attempt against its existing
state key. The interrupted Apply may have left partial Sandbox resources;
restarting the runner or creating a new run does not clean them up.

## Step 81: Record the fresh dispatch after the policy-related shutdown

The operator manually dispatched
[run 38492739205](https://github.com/Azure-Samples/azuresandbox/actions/runs/38492739205)
from `main` with `run_through=unit-test`. GitHub confirmed the expected title
`Sandbox sandbox-38492739205 / unit-test`, the `workflow_dispatch` event, and
workflow definition revision `757784f976358c3b4a71db1b7be65545047af00e`.
The independent state key is
`sandboxes/sandbox-38492739205/terraform.tfstate`.

The initial snapshot showed the job waiting for protected-environment approval.
No stage result has yet been observed for this run. After approval, watch
this exact dispatch:

```bash
gh run watch 38492739205 \
  --repo Azure-Samples/azuresandbox \
  --interval 120 \
  --exit-status
```

## Step 82: Verify whether main accepts only vnext release PRs

The operator requested read-only verification of repository policies. Live
branch-protection and effective-rules APIs showed no enforced PR source-branch
restriction on `main`:

* Classic protection restricts which actor can push/merge, not which PR head
  branch is allowed.
* Pull-request protection is configured with zero required approvals.
* No required status checks were returned for `main`, and administrator
  enforcement is disabled.
* The effective ruleset list for `main` was empty. The active
  `vnext-require-review` ruleset targets only `refs/heads/vnext`.
* The live `main` workflow inventory contained no PR source-eligibility gate.

PR #835 is a concrete example: it merged normally from
`feat/register-sandbox-json-only` into `main`, without the one-time override
used for the separate source PR.

Enforcing the intended release policy requires a required, fail-closed check
for PRs targeting `main` that accepts only a same-repository `vnext` head.
Skipping the deployment job for other source branches is not sufficient
because skipped jobs can satisfy required checks. Administrator bypass
behavior must also be deliberately selected. No repository settings or
workflow code were changed during this verification.

## Step 83: Implement the main release-source policy and owner exception

The operator authorized a metadata-only GitHub Actions workflow and GitHub
settings changes, while the manually dispatched deployment remained running.
PR #837 registered `.github/workflows/main-source-policy.yml` on `main` and
updated `CONTRIBUTING.md`. Local workflow, Markdown, and internal-link checks
passed. Local secret scanning was unavailable; hosted secret scanning and the
other applicable hosted checks passed before the bootstrap PR merged.

The new `main-release-source` ruleset is active only on `refs/heads/main`.
It requires a PR and the `main-source-eligibility` status from the GitHub
Actions integration. The trusted workflow runs on a GitHub-hosted runner,
does not check out PR code, and publishes the status on the exact PR head SHA:
same-repository `vnext` passes; other branches and fork sources fail.

The new `azuresandbox-main-bypass` team has one member, the repository owner,
and maintain access to this repository. Its bypass on this ruleset is
**For pull requests only**, not **Always**. Maintenance exceptions require
an explicit bypass with justification recorded in the PR; this does not
waive unrelated protections or create a passing source result.

Temporary verification PR #838 from `vnext` received a successful source
status and a clean merge state. Temporary topic PR #839 received a failed
source status and a blocked merge state. Both were closed without merging.
The API confirmed the owner's PR-only bypass permission; no exception merge
was performed merely to test that permission.

Classic `main` protection, the existing `vnext` review ruleset, and the
`vnext` source revision were unchanged. The deployment workflow file and
running deployment were untouched. This implements source eligibility only,
not the future Azure deployment/CD gate.

## Step 84: Prepare the release environment and publish the PR-entry path

The operator authorized a separate `sandbox-release-gate` environment with
owner approval, self-review permitted, and a `main` deployment branch policy.
The operator supplied `SANDBOX_BACKEND_HCL` and `SANDBOX_TFVARS_HCL` directly
in GitHub; verification inspected secret names only, never secret values.
The existing `sandbox-deployment` environment remains the manual path.

Active Actions event policies now explicitly allow `pull_request_target`
only for `.github/workflows/main-source-policy.yml`, and
`pull_request_target` plus `workflow_dispatch` only for
`.github/workflows/sandbox-deployment.yml`. Neither policy is a repository-wide
event allowance.

The first release-gate increment was published through runtime PR #841 to
`vnext` and workflow-registration PR #840 to `main`:

* Runtime commit: `e61b1ac061826927b25f7edd9e48d49b75b649a2`.
* Workflow registration commit: `f272929e29b9f62bb3a8f2bc46f59207fb3c1b7b`.
* Matching workflow blob: `a6017d9c5f3f30e0b17da28aa70c8b8418f0993f`.

A GitHub-hosted metadata-only selection job accepts ready same-repository
`vnext` PRs targeting `main`. Opening/reopening a ready PR, marking it ready,
updating its head, or changing its base to `main` requests a deployment.
Drafts and ordinary title/description edits do not deploy. Other source
branches and forks fail before self-hosted scheduling.

Eligible PR deployments require approval in `sandbox-release-gate`, check out
the exact captured PR head SHA, and always run through unit/integration
testing and JSON publication. Manual dispatch retains `sandbox-deployment`,
the `vnext` checkout, and the stage selector. The helper verifies PR metadata,
full stage selection, and the checked-out SHA before writing configuration.

The existing `azure-sandbox-deployment` concurrency group now belongs to the
deployment job rather than the whole workflow. Hosted validation does not
occupy its pending slot; active-run cancellation remains disabled.

The actual selection script passed 21 isolated cases and the actual helper
guard passed 15 isolated cases without Azure or Terraform execution. Local
workflow, PowerShell, Markdown, and internal-link gates passed; local secret
scanning was unavailable, and applicable hosted checks passed before merging.
No helper test files were retained. The runtime PR used the existing
maintainer self-merge path; workflow registration used the authorized PR-only
main maintenance exception with its source check still correctly failed.

The required `main` check remains source eligibility only. No required
deployment result, retry identifiers, or cleanup automation was added.
No release PR was opened, deployment dispatched, environment approval granted,
or Azure/runner/state operation performed during publication. The existing
manual run remained in progress on its original workflow revision. Live
release-PR deployment acceptance is still a separate, attended step.

## Step 85: Publish fail-closed deployment status without closing PRs

The operator authorized item 2: explicit PR-head deployment status publication,
while retaining protected-environment approval and serialized applies.
Runtime PR #843 and workflow-registration PR #844 published the increment:

* Runtime commit: `c0160c82e9bebda6f6b272ec2a90ef0c1c699727`.
* Workflow registration commit: `a5fad4a29a8c0f96e415f7ae74bde2b141e56226`.
* Matching workflow blob: `b4bbc4c50c86d42c2124f1e58af3ec77921588b4`.

After hosted eligibility validation, a separate GitHub-hosted publisher marks
`sandbox-deployment-gate` pending on the exact candidate SHA before environment
approval. A PR deployment cannot start unless that publication succeeds.
Manual dispatch explicitly skips the pending-status dependency and retains
its original environment and stage selection.

A hosted final reporter requires successful deployment-job completion,
Preflight, Apply, Unit-test, artifact upload, stage reporting, and valid passing
JSON evidence. The JSON must have native exit code zero, `result = "pass"`,
positive passing counts, zero failed tests/suites, and consistent nonnegative
integer totals. Existing optional-suite skip semantics are unchanged.
Failed, skipped, cancelled, missing, or malformed results cannot produce a
new successful deployment status. Hard cancellation or unavailable final
reporting may leave the previously published pending status unresolved.

The two status publishers alone have status-write permissions. They share a
per-SHA concurrency lock and use attempt-specific run URLs as ownership
markers; an older reporter cannot replace a newer attempt's pending result.
Metadata-only selection does not occupy that lock. Workflow code neither
closes nor merges PRs, so failures leave the release PR open for correction.

The actual selector/publisher scripts passed 46 isolated cases and the evidence
exporter passed 17, without Azure or Terraform execution. Applicable local and
hosted static gates passed before merge; local secret scanning was unavailable
and hosted scanning passed. No helper test files were retained. Publication
used the existing maintainer self-merge path for `vnext` and the authorized
PR-only main maintenance exception. The registration topic was correctly
rejected by the source/entry validators, and its self-hosted job was skipped.

The `main` ruleset still requires source eligibility only. Deployment
enforcement is a separate step after live release-path acceptance; require the
hosted final-reporter check alongside the SHA status so a failure to publish
pending cannot make an older same-SHA success sufficient. No retry/state-ID
or cleanup automation was added, and no release PR, deployment dispatch,
environment approval, or Azure/runner/state operation was performed.

## Step 86: Confirm successful JSON-only manual deployment acceptance

During publication verification, the original manual run
`38492739205` was observed completed successfully on its original workflow
revision `757784f976358c3b4a71db1b7be65545047af00e`. GitHub reported successful
Preflight, Apply, Unit-test, and sanitized evidence publication.

The run published one artifact. Read-only artifact validation confirmed its
ZIP contains only `unit-test-results.json`, with schema version 1,
`result = "pass"`, native exit code zero, and totals:

* Passed: 109.
* Failed: 0.
* Total: 109.
* Failed suites: 0.
* Skipped suites: 10, retained under the existing native discovery behavior.

Only structural metadata and numeric totals were inspected/reported; raw
diagnostics were not printed and no artifact file was persisted locally.
This completes the manual JSON-only end-to-end acceptance milestone.
It does not exercise the newly added PR-status publishers, which still need
an explicitly approved release-PR acceptance run before enforcement.

## Step 87: Confirm successful release-PR deployment acceptance

Maintenance PR #847 was merged into `vnext`. Release PR #848 was then opened
as a draft from `vnext` to `main`, using the repository template, with candidate
SHA `b12279415b156d6a46f33f607ed4bcaabc1da964`.

Draft-event run `38591391869` completed successfully. Hosted entry validation
passed; pending-status publication, the self-hosted deployment job, and final
status publication were all skipped. Applicable hosted static checks and
`main-source-eligibility` passed.

After the operator marked the PR ready for review, run `38591955844` published
`sandbox-deployment-gate = pending` on that exact candidate SHA before requesting
approval for `sandbox-release-gate`. The pending status linked to this run's
attempt-specific URL. The operator confirmed capacity for a fresh sandbox and
runner availability before approving the deployment.

The operator monitored the run from a separate terminal:

```bash
gh run watch 38591955844 \
  --repo Azure-Samples/azuresandbox \
  --interval 120 \
  --exit-status
```

The run completed successfully. Entry validation, pending-status publication,
Preflight, Apply, Unit-test, sanitized evidence publication, stage reporting,
and the hosted final reporter all passed. The self-hosted job took 1 hour,
48 minutes, 37 seconds.

Read-only verification confirmed that the PR head remained unchanged and that
`sandbox-deployment-gate = success` on the candidate SHA linked to
run `38591955844`, attempt 1. The hosted `Publish release deployment status`
check also succeeded on that SHA, with GitHub Actions integration ID `15368`.

The run published one artifact,
`unit-test-evidence-sandbox-38591955844-38591955844-1`.
In-memory ZIP validation confirmed it contains only `unit-test-results.json`,
with schema version 1, `result = "pass"`, native exit code zero, and totals:

* Passed: 109.
* Failed: 0.
* Total: 109.
* Suites: 23.
* Failed suites: 0.
* Skipped suites: 10, retained under the existing native discovery behavior.

No raw diagnostics were printed, no artifact file was persisted locally, and
no Terraform state was inspected. PR #848 remained open and unmerged.

This completes successful-path release-PR acceptance, including the draft skip,
pending-before-approval behavior, and final status on the exact candidate SHA.
No deliberate failure or cancellation run was performed. The active `main`
ruleset still required only `main-source-eligibility` at verification;
mandatory deployment enforcement remains a separate authorized settings step.
Azure cleanup remains manual, and runner-local cleanup remains deferred.

## Step 88: Require deployment status and final reporting before release merge

After successful-path acceptance, the operator authorized adding both
deployment checks to the active `main-release-source` ruleset. The required
checks are now:

* `main-source-eligibility`.
* `sandbox-deployment-gate`.
* `Publish release deployment status`.

All three are bound to GitHub Actions integration ID `15368`. The final
reporter's successful native check was verified on the exact candidate SHA
before adding the requirement. Requiring it alongside the explicit SHA status
also covers a failed pending-status publication that leaves an older same-SHA
status unchanged.

The settings update preserved the `main` branch scope, active enforcement,
existing PR requirement, non-strict required-check policy, and sole
owner-team PR-only maintenance bypass. Read-back verification confirmed the
complete requested ruleset without changing any other settings.

PR #848 remained open, unmerged, and reported a clean merge state. No additional
deployment, environment approval, Azure cleanup, or runner cleanup was started.
Ordinary release merges now require the deployment checks; failed checks do not
close the PR. The explicit owner-only maintenance exception remains available.

## Step 89: Add the deployed resource group to future run summaries

The operator requested the actual resource group name in the deployment-job
summary to distinguish active Sandboxes. The operator explicitly approved
publishing this single name as an exception to deployment-name sanitization.
Other resource names, IDs, raw Terraform outputs, and diagnostics remain private.

The change was prepared locally on `feat/sandbox-summary-resource-group`,
based on the validated `vnext` candidate. After a successful apply, the helper
queries only the existing `resource_names` output:

```bash
terraform output -json resource_names
```

It validates the `resource_group` entry and stores that name in a private
per-run record for the final summary. It does not infer the name from tags,
read Terraform state while apply is running, or publish the entire output map.
Unit-test failure does not hide a name already captured after successful apply.
Without verified post-apply output, the summary explicitly reports the name as
unavailable. Invalid or missing output fails the capture rather than inventing
a name.

Isolated checks exercised the actual apply, validation, and reporting functions
without executing Terraform or Azure commands. PowerShell analysis and Markdown
checks passed. No test harness files were retained.

At this step the implementation and related README update remained local and
uncommitted in a separate worktree. Neither `vnext` nor PR #848 was changed,
and no additional deployment was triggered. Completed run summaries, including
run `38591955844`, are not rewritten by this change.

## Step 90: Merge the accepted release while preserving branch lineage

After all three required release checks passed, the operator merged PR #848
from `vnext` to `main` using a regular merge commit:

* Merge commit: `180b468333ed5c7dbcceb409fec93e54057af8a8`.
* Previous `main` parent: `a5fad4a29a8c0f96e415f7ae74bde2b141e56226`.
* Accepted `vnext` parent: `b12279415b156d6a46f33f607ed4bcaabc1da964`.

Read-only GitHub verification confirmed the PR was merged and that the merge
commit has both parents, preserving the release branch lineage rather than
squashing it.

The accepted deployment runtime and dependency maintenance are now on `main`.
The subsequent resource-group summary enhancement from step 89 remains local,
uncommitted, and unpublished; it was not part of this release. The ongoing
walkthrough updates also remain local and uncommitted. No additional deployment
or cleanup was performed during merge verification.

## Step 91: Verify the published release tag

The operator published
[v5.14.2](https://github.com/Azure-Samples/azuresandbox/releases/tag/v5.14.2)
as a non-draft, non-prerelease release targeting `main`.

Read-only verification confirmed the tag points directly to merge commit
`180b468333ed5c7dbcceb409fec93e54057af8a8`, the accepted release from PR #848.
The local resource-group summary enhancement and uncommitted walkthrough
updates are not included in this release.

## Step 92: Consolidate remaining changes and retire publication branches

The operator requested that all remaining session changes be published to
`vnext` and that only local `main` and `vnext` branches remain afterward.
The full uncommitted walkthrough was first copied to the fresh summary-change
branch and verified byte-for-byte before any cleanup.

Main-to-vnext synchronization PR #849 passed applicable local and hosted checks
and merged with a regular merge commit,
`4b786a4f2e022527a2eaf3cc73b0f73f2e189e94`. This preserves the release ancestry
and brings the main-source policy and contribution guidance into `vnext`
without changing the accepted deployment runtime.

The remaining topic publication includes the preserved walkthrough,
the resource-group summary enhancement, and documentation of the now-required
release checks. Publish these changes through a checked topic PR targeting
`vnext`, using the normal squash-merge path. This does not create a release PR,
authorize another deployment, or modify the published v5.14.2 tag.

After the topic PR is merged, verify that its files are present on `vnext`
before removing the original uncommitted copies. Then fast-forward local
`main` and `vnext`, switch the primary checkout to `vnext`, and remove only the
verified obsolete publication branches and clean auxiliary worktrees.
Keep ignored configuration, credentials, Terraform state, and Azure resources
untouched. Azure cleanup and runner-local retention cleanup remain separate.

## Step 93: Require static CI before release deployment approval

Issue #854 found that a ready `vnext` → `main` release PR could request
deployment approval before its static CI had finished. The fix makes static CI
an explicit prerequisite and aligns both branches with these operator flows:

| Target | Normal path |
| --- | --- |
| `vnext` | Draft PR → mark ready for review → static CI runs → once it passes, the PR can be merged. |
| `main` | Draft `vnext` → `main` PR → mark ready for review → static CI runs → deployment queued awaiting approval → owner approves → deploy and unit/integration tests → once they pass, the PR can be merged. |

Workflow changes:

* The six `ci-*.yml` workflows skip all jobs on draft PRs and start a fresh
  run on `ready_for_review`. Post-merge CI on `vnext` is unchanged.
* Each is also a reusable workflow (`workflow_call`) with `head_sha` and
  `base_sha` inputs. In that release mode it checks out the exact head SHA
  without persisted credentials, diffs the full release against its merge base
  with `main`, keys concurrency on the PR number and head SHA, and ends with a
  no-logic `release report` job that passes back its raw job results. Native
  PR, push, and manual runs behave as before.
* `sandbox-deployment.yml` publishes `release-static-ci` and
  `sandbox-deployment-gate` as pending, calls the six workflows from the
  trusted `main` revision, and runs a hosted `Release static CI` job that
  applies one `pass` / `not-applicable` / `fail` rule to every workflow's
  results and rechecks the live PR. "Re-run failed jobs" is not supported;
  a fresh run (draft then ready, or close and reopen) is the retry path.
  Only after it publishes `release-static-ci = success` can the deployment job
  request approval. After approval, the deployment job repeats the live and
  status-ownership check before checking out candidate code.
* Manual dispatch keeps its existing behavior and does not run or wait for
  static CI.

Branch protection for both branches moved from classic branch protection rules
to rulesets, and both classic rules were deleted after the replacement
rulesets were active and verified. Rules that must never be bypassed (PR
required, conversation resolution on `vnext`, force-push and deletion blocks)
are in baseline rulesets with no bypass. The required CI checks on `vnext`,
the review requirement on `vnext`, the owner-only update restriction on
`main`, and the release checks on `main` each allow the owner's team to
bypass **for pull requests only**. See
[CONTRIBUTING.md](../../../CONTRIBUTING.md#branch-protection) for the ruleset table
and the emergency-merge rules. After hosted verification, `release-static-ci`
is added to the `main-release-source` ruleset.

Validation used temporary, session-only logic tests of the actual workflow
scripts (the verdict rule, full-diff staging, the static CI aggregate,
and the post-approval guard) with stubbed GitHub API responses. No test
sources were committed. Hosted acceptance on a real release PR, confirming
that static CI runs and passes before any deployment approval request
appears, is recorded on issue #854.

## Step 94: Define repository owners and separate bypass types

After Step 93, every merge to `main` counted as a bypass, even a release PR
whose checks all passed. A ruleset can't list who is allowed to update a
branch, so the owner-only update restriction applied to the owner too. The
owner also wanted contributions to require an owner's review, and each type
of bypass to be identifiable in the merge history.

Settings changes:

* A new `azuresandbox-owners` team (maintain role) replaces the two bypass
  teams. It is the only bypass actor on every ruleset, the code owner for the
  whole repository, and the required reviewer for the `sandbox-release-gate`
  environment. Adding an owner means adding them to this team.
* `vnext-require-review` now requires the approval to come from a code owner,
  after the PR's latest commit, from someone other than the person who pushed
  it. Any account with write access can merge an approved PR once CI passes.
* `main-release-source` now requires only `main-source-eligibility`. New
  `main-release-static-ci` and `main-release-deployment` rulesets require
  `release-static-ci`, and `sandbox-deployment-gate` plus
  `Publish release deployment status`, respectively.
* The `main-restrict-updates` ruleset is replaced by a classic branch
  protection rule on `main` whose only setting restricts pushes to the
  `azuresandbox-owners` team, enforced for administrators. Owners now merge a
  release PR that passes every check without a bypass.

Each bypass now appears under its own ruleset in Settings → Rules → Insights:
review, CI, release source, release static CI, or deployment. While there's
only one owner, an owner's own `vnext` PR still needs a review-only bypass,
because GitHub doesn't let authors approve their own PRs. See
[CONTRIBUTING.md](../../../CONTRIBUTING.md#who-can-do-what)
for the resulting contribution and merge rules.

## Step 95: Choose the manual deployment source branch

Manual runs always deployed the `vnext` tip, so there was no way to deploy a
new Sandbox from released `main` code. Issue #853 adds a `source_branch`
choice to `workflow_dispatch`, with `vnext` (the default) and `main` as the
only options.

Workflow changes:

* The workflow still runs only in the trusted `main` context. The input
  chooses the source code to deploy, not the workflow revision.
* The hosted `Validate deployment entry` job reads the input only through an
  environment variable. It rejects anything other than `vnext` or `main`
  (other branches, tags, SHAs, fork references, or an empty value) before any
  checkout or environment-secret access.
* The deployment job checks out `refs/heads/<branch>` from this repository,
  so a tag can't shadow the branch. Every stage choice (`preflight`, `apply`,
  and `unit-test`) works with either source, and runs keep the
  `sandbox-deployment` environment, its secrets, and its approvals.
* The run name (`Sandbox sandbox-<run id> / <stage> / <branch>`) and the
  selection job's summary show the selected source. The stage results still
  record the exact deployed commit.
* Release PR runs ignore the input. They still deploy the PR's exact head SHA
  through `sandbox-release-gate`, and manual runs never publish or satisfy
  `release-static-ci` or `sandbox-deployment-gate`.

[`scripts/tests/Test-SandboxDeploymentSelection.sh`](../../../scripts/tests/Test-SandboxDeploymentSelection.sh)
runs the selection step against sample events with no GitHub or Azure
access. It covers both sources for every stage, invalid sources and stages,
and the unchanged release PR path. The `actionlint` job in `ci-actions` and
`./scripts/Invoke-CIChecks.sh actions` both run it.

The change reaches `vnext` through a normal topic PR. Because manual runs use
the workflow file on `main`, a narrow maintenance PR then copies only
`.github/workflows/sandbox-deployment.yml` to `main`, as in steps 10 through
15. An owner merges it with a bypass because the source isn't `vnext`. A
`main` to `vnext` sync PR follows. The test script and documentation reach
`main` with the next normal release.
