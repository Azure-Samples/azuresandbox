# GitHub Sandbox Deployment Workflow Setup

This guide documents an attended, step-by-step setup of a GitHub Actions
workflow that deploys a new Azure Sandbox on the self-hosted runner provisioned
by [GitHub Self-Hosted Runner Setup](./github-selfhosted-runner-setup.md).
The operator executes the commands and reviews each result before proceeding.
This is not a production deployment guide.

The guide will be expanded as each setup step is completed. It currently
covers scope, prerequisites, GitHub discovery, publication and approval
choices, environment protection setup, and creating a smoke-only workflow.
It also covers local validation and preparing the topic PR. It does not yet
contain a Sandbox deployment job.

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

Success requires successful deployment followed by successful test execution.
The workflow must distinguish test failures from test harness or infrastructure
errors; it must not report success when tests were skipped because an earlier
step failed.

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

The operator must explicitly confirm the deployment target and test scope
before planning or applying. The walkthrough selects the same tenant,
subscription, region, and operator object ID as the standalone bootstrap,
with separate, human-supplied Sandbox tags.

Use the runner's user-assigned identity for Sandbox provider authentication:
`arm_auth_mode = "msi"` and its client ID as `arm_client_id`. The root
configuration supports this without a service principal password. Keep
Azure CLI and Azure PowerShell authentication aligned with this identity for
deployment management operations and tests.

Use the system-assigned identity for the remote-state backend in the
bootstrap storage account's `tfstate` container. Confirm a stable state blob
key for this new Sandbox, such as `azuresandbox.tfstate`, and verify that it
does not already contain another deployment's state before the first run.
Do not deploy with workstation-local or runner-local Sandbox state.

Environment-specific tags are required in this walkthrough. The operator
will supply their actual values privately in the terminal. Never infer or
reuse those values from an earlier deployment. Include the confirmed
`additional_tags` map in every newly generated Sandbox plan; applying its
saved plan uses the values already captured there.

Preserve any workstation-root `terraform.tfvars`, backend configuration, and
state from other deployments. The workflow needs its own securely generated
inputs and backend configuration in the Actions checkout; ignored local files
are not automatically copied to a runner job.

The preceding runner guide verifies subscription `Owner`, state-container
read access, and the optional Microsoft Graph `Group.ReadWrite.All` grant
needed for `mssql`. It does not verify every backend operation or all
deployment prerequisites.

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

Share the check summaries and PR URL. Wait for hosted CI and required review
before merging. Do not bypass failed checks, branch protection, or review
requirements. The workflow's environment allows only `main` runs, so this
`vnext` PR is not itself a deployment trigger.

## Remaining setup stages

Subsequent steps will document:

1. Reviewing and merging the topic PR, publishing the narrow default-branch
   registration PR, and verifying the smoke run.
2. Capturing human-supplied Sandbox settings and required tags privately.
3. Checking the selected state key and runner deployment/test prerequisites.
4. Creating the manually triggered workflow and its result handling.
5. Reviewing, committing, checking, and publishing the workflow.
6. Dispatching one deployment, monitoring it, and reviewing the test-based
   success or failure report.

Do not start a Sandbox plan, apply, or test run during these discovery steps.
