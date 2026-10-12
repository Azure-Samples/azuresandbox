# GitHub Sandbox Deployment Workflow Setup

This guide documents an attended, step-by-step setup of a GitHub Actions
workflow that deploys a new Azure Sandbox on the self-hosted runner provisioned
by [GitHub Self-Hosted Runner Setup](./github-selfhosted-runner-setup.md).
The operator executes the commands and reviews each result before proceeding.
This is not a production deployment guide.

The guide will be expanded as each setup step is completed. It currently
covers scope, prerequisites, GitHub discovery, publication and approval
choices, environment protection setup, and creating a smoke-only workflow.
It also covers validation, publication to `vnext` and `main`, environment
approval, and verified self-hosted smoke execution. It does not yet contain
a Sandbox deployment job.

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

The existing test orchestrator supports JSON and JUnit results and uses these
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
Reuse that same key for subsequent operations on the Sandbox.
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

Each dispatch must explicitly distinguish a new Sandbox from an existing
Sandbox. A new Sandbox receives the initial-run-derived ID from step 22;
an existing Sandbox requires its stable deployment ID. All stages in a run
use that same ID and backend key. Selecting `apply` in a later run generates
a fresh preflight plan for that run rather than consuming an earlier run's
plan. These controls are implemented in the local workflow update, awaiting
review and publication.

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

If apply is dispatched in a separate run, first execute preflight again to
produce that run's saved plan. Do not automatically reuse a plan from an
earlier run. Keep the plan private on the same runner throughout the handoff;
do not use public artifacts for cross-stage transfer.

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
Do not include the run attempt in the deployment ID: rerunning the initial
workflow retains its run ID and targets the same Sandbox.
Record the allocated ID and originating run link in the GitHub summary before
backend initialization, so the selection is traceable even if preflight fails.

Later workflow dispatches must explicitly supply the existing deployment ID.
Reuse it and its backend key for preflight, apply, unit-test, retries, later
updates, and eventual teardown of that Sandbox. Do not substitute a later
run's ID or interpret a missing existing ID as a request for a new Sandbox.
Allocate another ID only when explicitly creating a separate Sandbox.
Creating a new state key for every workflow run loses the existing resource
tracking and can create duplicate infrastructure or name collisions.

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

For a newly allocated ID, check that its key is unused before the first
initialization. For an existing ID, verify it identifies the intended
Sandbox and use its existing state. Do not delete, rename, or migrate state
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
| `extras/configurations/rg-devops-iac/scripts/Invoke-SandboxDeployment.py` | Private configuration, backend selection, planning, saved-plan verification, apply logging, VM gate, and sanitized reporting |
| `extras/configurations/rg-devops-iac/scripts/Connect-SandboxRunner.ps1` | Explicit UAMI authentication and process-local PowerShell context for prerequisite checks and all-module tests |
| `extras/configurations/rg-devops-iac/scripts/tests/test_sandbox_deployment.py` | Isolated tests using simulated Terraform/Azure commands; no live deployment |

All new helper scripts, tests, and documentation live under
`extras/configurations/rg-devops-iac`. The existing workflow definition stays
in `.github/workflows`, as required for GitHub Actions discovery.
The helpers operate on the repository-root Sandbox configuration and invoke
its existing VM-management and test scripts; they do not apply the standalone
runner-bootstrap configuration.

Select `deployment_mode: new` and leave `deployment_id` empty for a separate
Sandbox. The default mode is `existing`, which requires an ID rather than
silently allocating new infrastructure. `run_through` defaults to `preflight`.
The source remains trusted `vnext`; dispatch the registered workflow from
`main` after publication.

The helper writes backend and input snapshots privately, uses per-attempt
Terraform metadata and Azure CLI context, and forces the default Terraform
workspace. It checks state-blob existence with the system-assigned identity
before initialization. A private deployment-level `deployment.json` binds the
stable ID to its backend and repository. Preserve this file alongside the
state: existing deployments fail closed if their runner receipt is missing.
If the runner is replaced, restore its approved private deployment records
before operating on existing Sandboxes; never delete state to bypass this check.

Preflight checks the MSI input mode, matching backend tenant/subscription,
all base-module flags, disabled extras, and Azure CLI/PowerShell authentication.
If initialized state exposes existing shared resources, it runs the existing
public-access helper before planning. Raw output remains private, including
the Terraform JSON used to produce safe plan counts.
Long commands emit generic two-minute progress messages without resource
details. Unit-test waits up to ten minutes to confirm the deployed VMs running
after the existing start helper, then invokes the orchestrator in the same
PowerShell process as the UAMI login.

Before publication, run the isolated helper tests from the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s extras/configurations/rg-devops-iac/scripts/tests \
  -p test_sandbox_deployment.py -v
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
check descriptions by default. JSON and JUnit retain their existing schemas,
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
`-VerboseResults`, which restores original check text and diagnostics in both
formats:

```powershell
./scripts/Invoke-UnitTests.ps1 -ResultsJsonPath ./test-results.json -JUnitXmlPath ./test-results.xml -VerboseResults
```

Existing calls need no additional argument. The parent forwards its setting to
children, including tests run through VM Run Command. Direct PowerShell child
calls use `-VerboseResults true`; the child's value is a validated string because
Run Command transports parameters as strings. The Linux child accepts
`--verbose-results` for direct invocation. Default child invocations remain valid.
No test assertions or pass/fail counters are changed.

General console/log diagnostics remain private; the default publication boundary
is the structured JSON/JUnit results, not arbitrary logs. Do not publish verbose
results. The runner workflow does not opt into verbose mode.
Step 26 describes publishing these default structured results as GitHub evidence.

The privacy regression test loads definitions without executing live Azure tests.
Run it from the repository root:

```bash
pwsh -NoLogo -NoProfile -File \
  ./extras/configurations/rg-devops-iac/scripts/tests/Test-UnitResultPrivacy.ps1
```

It covers all PowerShell child result helpers, static-description coverage,
sanitized and verbose JSON/JUnit, pass/fail/harness exit-code serialization,
unrecognized output, and Linux description discovery.
Actual sandbox tests still require the VM-start gate and explicit Azure
authentication described earlier.

## Step 26: Publish structured unit-test evidence

The local workflow now requests both `-ResultsJsonPath` and `-JUnitXmlPath`
through the MSI-authenticated runner wrapper, without `-VerboseResults`.
Both result files remain in the private deployment/run directory:

```text
unit-test-results.json
unit-test-results.xml
```

After either a successful or failed unit-test step, a separate evidence step
checks the generated JSON schema and XML document, then copies only these
two named files to an owner-only staging directory under `RUNNER_TEMP`.
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
If only one format was produced, publish that available file and report the
missing format as partial evidence. Invalid documents are not uploaded.
If the VM-start gate, authentication, or another prerequisite prevented results
from being generated, report evidence unavailable and skip the upload rather
than inventing test results.

Find the downloadable JSON/JUnit archive in the workflow run's **Artifacts**
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

This evidence publication is implemented locally and has not yet been exercised
on GitHub. Publish the parent/child result-privacy changes and runner helpers
to `vnext` before registering the updated workflow on `main`.

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

From the repository root, stage the reviewed tracked scope and the four new
helper/test files explicitly. Ignored HCL configuration and Terraform state
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
    extras/configurations/rg-devops-iac/scripts/Invoke-SandboxDeployment.py \
    extras/configurations/rg-devops-iac/scripts/tests/test_sandbox_deployment.py \
    extras/configurations/rg-devops-iac/scripts/tests/Test-UnitResultPrivacy.ps1
  git --no-pager diff --cached --check
  git --no-pager diff --cached --stat
  git commit \
    -m "Implement Sandbox deployment stages and sanitized test evidence" \
    -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
)
```

Then run the isolated regression tests and applicable CI gates **after the
commit**, before any push or PR creation:

```bash
(
  set -euo pipefail
  cd "$(git rev-parse --show-toplevel)"
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
    -s extras/configurations/rg-devops-iac/scripts/tests \
    -p test_sandbox_deployment.py -v
  pwsh -NoLogo -NoProfile -File \
    extras/configurations/rg-devops-iac/scripts/tests/Test-UnitResultPrivacy.ps1
  ./scripts/Invoke-CIChecks.sh bash actions powershell markdown links secrets
  git --no-pager status --short
)
```

These regression tests use isolated fixtures and mocks; they do not deploy
resources or invoke live Sandbox unit/integration tests. Stop on any failure
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

## Remaining setup stages

Subsequent steps will document:

1. Reviewing, committing, checking, and publishing the workflow and helpers.
2. Confirming the selected Sandbox settings and new/existing deployment target.
3. Dispatching preflight and reviewing its private saved-plan receipt.
4. Running the approved apply/test stages and reviewing the test-based
   success or failure report.

Do not start a Sandbox plan, apply, or test run during these discovery steps.
