# Contributing to AzureSandbox

Thanks for helping improve Azure Sandbox. This guide explains how to get a change merged. Maintainer-only procedures are in [For maintainers](#for-maintainers) at the end.

## TL;DR

1. Branch from **`vnext`** (fork the repo if you don't have write access). Never target `main`.
2. Run `./scripts/Invoke-CIChecks.sh` locally and fix anything it reports as `FAILED`.
3. Open a **draft** pull request against `vnext`, then mark it **Ready for review** to start CI.
4. Once CI passes and a repository owner approves, the PR is **squash-merged**.
5. The first time, sign the Microsoft CLA when the bot asks.

## Before you start

- **Code of Conduct:** this project follows the [Microsoft Open Source Code of Conduct](.github/CODE_OF_CONDUCT.md).
- **Contributor License Agreement:** most contributions require you to agree to a [CLA](https://cla.opensource.microsoft.com). A bot comments on your first PR with instructions. You only sign once for all Microsoft repositories that use it.
- **License:** contributions are accepted under the repository [license](LICENSE.md).
- **This is a public repository.** Never put secrets, subscription or tenant IDs, internal policy names, or other environment-specific details in code, issues, PRs, or commit messages.

## Questions, issues, and security reports

| You want to… | Do this |
| --- | --- |
| Ask a question or discuss an idea | Start a thread in [Discussions](https://github.com/Azure-Samples/azuresandbox/discussions). |
| Report a bug or documentation mistake | [Search existing issues](https://github.com/Azure-Samples/azuresandbox/issues?q=is%3Aissue), then [open an issue](https://github.com/Azure-Samples/azuresandbox/issues/new) and complete the [issue template](.github/ISSUE_TEMPLATE.md). |
| Propose a feature | Open an issue describing it **before** building anything substantial, so we can confirm it fits. Small changes can go straight to a PR. |
| Report a security vulnerability | **Don't open a public issue.** Follow [SECURITY.md](.github/SECURITY.md). |

## Making a change

`vnext` is the development branch where all work lands. `main` holds released code and is updated only by [release PRs](#releasing-to-main).

```bash
git switch vnext && git pull
git switch -c feature/my-change      # or work in your fork
# ...edit...
./scripts/Invoke-CIChecks.sh         # run all checks, or name some: markdown links bash
git add -A && git commit -m "Describe the change"
git push -u origin feature/my-change
gh pr create --base vnext --draft --fill
gh pr ready                          # starts CI
```

Complete the [pull request template](.github/PULL_REQUEST_TEMPLATE.md). To address review feedback, push more commits. There's no need to rebase or force-push, because the PR is squashed on merge.

### CI checks

CI runs on ready (non-draft) PRs to `vnext` and on every push to `vnext`. It's static analysis only: nothing is deployed and no credentials are used. Each workflow runs only when files it covers change. All ten checks below are required.

| Workflow | Required checks | Config | `Invoke-CIChecks.sh` name |
| --- | --- | --- | --- |
| [`ci-docs`](.github/workflows/ci-docs.yml) | `markdownlint`, `lychee (internal links)` | [`.markdownlint.jsonc`](.markdownlint.jsonc), [`lychee.toml`](lychee.toml) | `markdown`, `links` |
| [`ci-terraform`](.github/workflows/ci-terraform.yml) | `terraform fmt`, `tflint`, `terraform validate (.)`, `terraform validate (extras/configurations/rg-devops-iac)` | [`.tflint.hcl`](.tflint.hcl) | `terraform` (fmt and tflint only) |
| [`ci-powershell`](.github/workflows/ci-powershell.yml) | `PSScriptAnalyzer` | [`PSScriptAnalyzerSettings.psd1`](PSScriptAnalyzerSettings.psd1) | `powershell` |
| [`ci-bash`](.github/workflows/ci-bash.yml) | `ShellCheck` | [`.shellcheckrc`](.shellcheckrc) | `bash` |
| [`ci-actions`](.github/workflows/ci-actions.yml) | `actionlint` | [`.github/actionlint.yaml`](.github/actionlint.yaml) | `actions` |
| [`ci-secrets`](.github/workflows/ci-secrets.yml) | `gitleaks` | — | `secrets` |

The `actionlint` job also runs [`scripts/tests/Test-SandboxDeploymentSelection.sh`](scripts/tests/Test-SandboxDeploymentSelection.sh), which tests the [deployment workflow](.github/workflows/sandbox-deployment.yml)'s entry selection against sample events without GitHub or Azure access, and checks that only its `sandbox` job can request an OIDC token (`id-token: write`). It needs `jq` and Python 3 with PyYAML.

[`scripts/Invoke-CIChecks.sh`](scripts/Invoke-CIChecks.sh) runs the same tools at the same pinned versions with the same config files. Its header lists the versions and install hints. A tool that isn't installed is reported as `SKIPPED`, which means only CI will verify that check. Rule exclusions are explained inline in each config file.

For PRs from external contributors (for example, from forks), a maintainer must approve the workflow runs before CI starts.

### Architecture diagrams

Diagrams are draw.io editable SVGs (`*.drawio.svg`). The root diagram, [`images/azuresandbox.drawio.svg`](images/azuresandbox.drawio.svg), is the source of truth. Every `modules/<module>/images/` diagram is generated from it, so never hand-edit a module diagram:

1. Edit the root diagram in draw.io or the VS Code draw.io extension.
2. Run `./scripts/build-module-diagrams.py build`, then `./scripts/build-module-diagrams.py verify`.
3. Commit the root and regenerated diagrams together.

Prerequisites and the shape-to-module map are documented in the headers of [`build-module-diagrams.py`](scripts/build-module-diagrams.py) and [`render-drawio-svg.js`](scripts/render-drawio-svg.js).

## Review and merge

A PR into `vnext` can be merged when **all** of these are true:

- Every required CI check passes on the latest commit, and the branch is up to date with `vnext`.
- A repository owner approves after the latest commit, and the approver isn't the person who pushed it. Owners are requested automatically through [`CODEOWNERS`](.github/CODEOWNERS).
- All review conversations are resolved.

### Who can do what

| Role | How it's granted | Can |
| --- | --- | --- |
| Anyone | A GitHub account | Fork the repo and open PRs to `vnext`; open issues and discussions |
| Triage | Invitation from an admin | Label, assign, and close issues and PRs. No commits or merges. |
| Write | Azure-Samples organization teams | Push branches to this repo, and merge an approved PR into `vnext` once CI passes |
| Owner | The `azuresandbox-owners` team | Give the required code-owner approval, merge [release PRs](#releasing-to-main) into `main`, approve release deployments, and use [emergency bypasses](#emergency-merges) |

Nobody can push directly to `vnext` or `main`, force-push to them, delete them, or bypass merge conflicts or unresolved review conversations.

### Merge strategy

| PR | Merge method | Why |
| --- | --- | --- |
| Topic or contributor PR → `vnext` | **Squash** | Each PR lands as one commit. |
| Release PR `vnext` → `main` | **Merge commit** (never squash) | Keeps the individual `vnext` commits and branch history on `main`. |

This is a project convention. GitHub allows all three merge methods, so pick the right one when you merge.

## For maintainers

### Releasing to `main`

Only owners open and merge the `vnext` → `main` release PR:

1. Open the release PR as a draft, then mark it ready.
2. The [deployment workflow](.github/workflows/sandbox-deployment.yml) runs the static CI checks against the release head commit and its full diff from `main`.
3. The deployment waits in the `sandbox-release-gate` environment until an owner approves it. Admins can't skip this approval. To merge without a deployment, see [Emergency merges](#emergency-merges).
4. A fresh sandbox is deployed and the unit and integration tests run.
5. If everything passes, merge with a **merge commit**.

Every push, and every time the PR is marked ready again, starts a fresh run; results from an earlier commit are never reused. **Re-run failed jobs** isn't supported. To retry, convert the PR to a draft and mark it ready again, or close and reopen it. Status and evidence requirements are documented in the [rg-devops-iac deployment guide](extras/configurations/rg-devops-iac/README.md).

### Branch protection

The branches are protected by [rulesets](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) (**Settings → Rules**). Every applicable ruleset must pass, and each ruleset's bypass applies only to that ruleset. The only bypass actor is `azuresandbox-owners`, in **pull requests only** mode.

| Branch | Ruleset | Enforces | Bypass |
| --- | --- | --- | --- |
| `vnext` | `vnext-baseline` | Requires a PR, resolved conversations, and no force pushes or deletion | None |
| `vnext` | `vnext-required-checks` | The ten [CI checks](#ci-checks), with the branch up to date | Owners |
| `vnext` | `vnext-require-review` | One code-owner approval after the latest push, from someone other than the pusher | Owners |
| `main` | `main-baseline` | Requires a PR, and no force pushes or deletion | None |
| `main` | `main-release-source` | `main-source-eligibility`: the source must be this repo's `vnext` branch ([workflow](.github/workflows/main-source-policy.yml)) | Owners |
| `main` | `main-release-static-ci` | `release-static-ci` | Owners |
| `main` | `main-release-deployment` | `sandbox-deployment-gate` and `Publish release deployment status` | Owners |

Each kind of bypass has its own ruleset, so **Settings → Rules → Insights** shows which one was used. `main` also has a classic branch protection rule that restricts pushes to `azuresandbox-owners`, enforced for admins. That's how owners merge release PRs that pass every check without needing a bypass. The CLA check (`license/cla`) is managed by the Azure-Samples organization, and no ruleset here requires it.

### Deployment environments and OIDC

The [deployment workflow](.github/workflows/sandbox-deployment.yml) signs in to Azure with GitHub OIDC, through federated credentials on a deployment identity that trust this repository's two deployment environments, and on a separate runner power state identity that trusts a third environment. Because the credentials don't name a workflow file, these settings (**Settings → Environments** and **Settings → Actions**) are what restrict those identities to workflows on `main` that an owner approves or an admin starts. They're separate from the [branch protection](#branch-protection) bypasses, which control merges, not deployments:

| Setting | Required value |
| --- | --- |
| `sandbox-deployment`, `sandbox-release-gate` and `sandbox-runner-power-state` deployment branches | `main` only |
| Required reviewers | Owners, in `sandbox-deployment` and `sandbox-release-gate`. None in `sandbox-runner-power-state` |
| **Allow administrators to bypass configured protection rules** | Off in `sandbox-release-gate`, so admins can't skip release deployment approval. On in `sandbox-deployment`, so an admin can start a manual deployment without approval |
| Environment secrets | `SANDBOX_BACKEND_HCL` and `SANDBOX_TFVARS_HCL`, with `auth_mode = "oidc"`, in `sandbox-deployment` and `sandbox-release-gate`. `RUNNER_POWER_STATE_CLIENT_ID`, `AZURE_TENANT_ID` and `RUNNER_VM_ID` in `sandbox-runner-power-state` |
| OIDC subject claim template | `use_default: false` with `include_claim_keys` `repository_owner_id`, `repository_id` and `context` |

`sandbox-runner-power-state` is used by the `start_runner` and `stop_runner` jobs, which start the self-hosted runner virtual machine after a deployment is approved and deallocate it afterwards. It has no reviewers because `start_runner` waits for the deployment's own approval before it starts anything, and its identity can only read, start and deallocate that one virtual machine. Don't add it to `github_oidc_environments`, and don't use it for any other job. See [Runner power state identity](extras/configurations/rg-devops-iac/README.md#runner-power-state-identity).

Don't change the OIDC subject claim template. It changes the subject of every OIDC token the repository issues, and the federated credentials only accept this format. Check it with `gh api repos/Azure-Samples/azuresandbox/actions/oidc/customization/sub`. A new environment can't federate to the deployment identity until its name is added to `github_oidc_environments` in rg-devops-iac. See the [rg-devops-iac deployment guide](extras/configurations/rg-devops-iac/README.md#optional-deployment-identity-for-oidc-workflow-applies).

### Emergency merges

An owner can merge a PR whose CI or deployment checks haven't passed by recording the reason in the PR and selecting **Bypass rules and merge** (`gh pr merge <n> --admin`, plus `--squash` or `--merge` per the [merge strategy](#merge-strategy)). Use this only when waiting isn't practical. For example:

- A GitHub outage is blocking CI.
- A release can't be deployed because of time or cost, or it's documentation-only.
- An authorized maintenance PR to `main` doesn't come from `vnext`.
- There's only one owner, so they can't approve their own `vnext` PR. GitHub never lets authors approve their own PRs.

A bypass never creates a passing result, never approves or starts a deployment, never allows a direct push, and never overrides merge conflicts or unresolved conversations. It applies to the whole ruleset, not to specific files, so review the PR's full scope first.

### Granting access

Issues and PRs can be assigned only to users with triage access or higher, or to anyone who has commented on that item. Having commits in the repo grants no permissions. To let someone triage, invite them at the **triage** level. Then check the pending invitation's level, because an older, unaccepted invitation at a higher level isn't downgraded automatically. Access takes effect once they accept.

### CI tool versions

The tool versions pinned in the CI workflows and `Invoke-CIChecks.sh` aren't tracked by Dependabot. Each week, [`ci-tool-versions`](.github/workflows/ci-tool-versions.yml) runs [`scripts/Check-ToolVersionDrift.sh`](scripts/Check-ToolVersionDrift.sh). When any tool is behind, it opens or updates a single `tool-version-drift` issue listing every file to update. To bump a version, update every file listed, then rerun `./scripts/Invoke-CIChecks.sh`.

The Terraform CLI version isn't pinned in any workflow. [`ci-terraform`](.github/workflows/ci-terraform.yml) installs the `X.Y.Z` version from `required_version` in each configuration's `terraform.tf`, so a CLI bump only changes `terraform.tf` files. Release PRs then pass static CI without a separate update to `main`.
