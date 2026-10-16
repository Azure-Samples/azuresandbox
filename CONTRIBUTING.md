# Contributing to #AzureSandbox

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

- [Code of Conduct](#code-of-conduct)
- [Issues and Bugs](#found-an-issue)
- [Feature Requests](#want-a-feature)
- [Branching and Merge Policy](#branching-and-merge-policy)
- [Collaborator Access and Issue Assignment](#collaborator-access-and-issue-assignment)
- [Continuous Integration](#continuous-integration)
- [Submission Guidelines](#submission-guidelines)

## Code of Conduct

Help us keep this project open and inclusive. Please read and follow our [Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

## Found an Issue?

If you find a bug in the source code or a mistake in the documentation, you can help us by
[submitting an issue](#submitting-an-issue) to the GitHub Repository. Even better, you can
[submit a Pull Request](#submitting-a-pull-request-pr) with a fix.

## Want a Feature?

You can *request* a new feature by [submitting an issue](#submitting-an-issue) to the GitHub
Repository. If you would like to *implement* a new feature, please submit an issue with
a proposal for your work first, to be sure that we can use it.

- **Small Features** can be crafted and directly [submitted as a Pull Request](#submitting-a-pull-request-pr).

## Branching and Merge Policy

This repository uses a two-branch model to keep `main` stable and releasable at all times.

| Branch | Purpose | Who can update it | How it is updated |
| --- | --- | --- | --- |
| `vnext` | Active development / integration branch. All day-to-day work lands here. | Any collaborator with write access, after a repository owner approves the PR | Pull requests only (direct pushes are blocked) |
| `main` | Stable, released code. | Repository owners (the `azuresandbox-owners` team) only | Pull request merging `vnext` → `main`, or an explicitly authorized maintenance exception |

### Workflow

1. **Target `vnext` for all contributions.** Open every pull request — features, bug fixes, and documentation — against the `vnext` branch. Direct PRs to `main` are reserved for explicitly authorized maintenance exceptions described below.
2. **Integration happens on `vnext`.** Reviews, status checks (including the CLA bot), and testing occur here.
3. **Promotion to `main` is restricted.** Only repository owners (members of the **`azuresandbox-owners`** team) open and merge the `vnext` → `main` pull request that promotes accumulated changes to the stable branch. No other collaborator can merge into `main`.

### Merge strategy

**TL;DR:** Squash-merge topic/contributor PRs into `vnext`; use a regular merge commit (no squash) for the `vnext` → `main` release PR.

- **Topic/contributor PRs → `vnext`:** **squash merge**, so each PR lands as one tidy commit on `vnext`.
- **`vnext` → `main` (release promotion):** **regular merge commit (do not squash)**, so the individual `vnext` commits and the branch lineage are preserved on `main`. Squashing this promotion flattens all the work into a single commit and loses that history.

### Pull request flow

Open every PR as a **draft** while you work. Draft PRs run no CI checks; marking a PR **Ready for review** starts them.

| Target | Normal path |
| --- | --- |
| `vnext` | Open a draft PR → mark it ready for review → the [static CI checks](#continuous-integration) run → once they pass and the review and conversation requirements are met, the PR can be merged. |
| `main` | The owner opens a draft `vnext` → `main` release PR → marks it ready for review → the release workflow runs the same static CI checks against the release's exact head commit and its full diff from `main` → once they pass, the deployment is queued awaiting approval → the owner approves → a fresh sandbox is deployed and the existing unit and integration tests run → if they pass, the PR can be merged. |

No Azure deployment starts before approval. Pushing a new commit to a ready PR, or marking a draft ready again, starts a fresh run; results from an earlier commit or run are never reused. CI also runs on `vnext` after every merge, to check the combined code. On a release PR, **Re-run failed jobs** is not supported: if static CI or the deployment fails (for example, during a GitHub outage), mark the PR as a draft and then ready again, or close and reopen it, to start a fresh run.

### Who can contribute and who can merge

- **Anyone with a GitHub account** can contribute: fork the repository and open a PR against `vnext`. GitHub may ask a maintainer to approve workflow runs for a first-time contributor. Every PR must pass CI and be approved by a repository owner, who is requested automatically through [`.github/CODEOWNERS`](.github/CODEOWNERS). Commits pushed after that approval need a fresh approval. A contributor without write access can't merge their own PR; someone with write access merges it once it's approved.
- **Accounts with write access** (granted through the Azure-Samples organization) can also create branches directly in this repository instead of forking. Once an owner has approved a PR's latest commit and CI has passed, they can merge it into `vnext`. They can't push directly to `vnext` or `main`, can't merge into `main`, and can't bypass any check.
- **Repository owners** (members of the `azuresandbox-owners` team) are the only accounts that can merge into `main`, and only release PRs from `vnext` are eligible. Owners also have a [PR-only bypass](#emergency-merges) for failed CI or deployment checks, for maintenance PRs to `main`, and, while there's only one owner, for approving their own `vnext` PRs (GitHub never lets authors approve their own PRs). The reason for every bypass is recorded in the PR.
- **Nobody** can push directly to `vnext` or `main`, force-push to them, delete them, or bypass merge conflicts or unresolved conversations.

### Merging into `vnext`

Push a branch and open a draft PR against `vnext`:

```bash
# Put your edits on a branch (uncommitted changes come with you).
git checkout -b feature/my-change
git add -A
git commit -m "describe my change"
git push -u origin feature/my-change

# Open the PR against vnext as a draft, then mark it ready when done.
gh pr create --base vnext --fill --draft
gh pr ready
```

A PR into `vnext` can be merged once:

- every required CI check passes on the PR's latest commit, and the branch is up to date with `vnext`;
- it has **one approval from a repository owner**, given after its latest commit, from someone other than the person who pushed that commit (owners are requested automatically through [`.github/CODEOWNERS`](.github/CODEOWNERS)); and
- all review conversations are resolved.

Then squash-merge it, consistent with the [merge strategy](#merge-strategy) above:

```bash
gh pr merge <pr-number> --squash
git checkout vnext && git pull
```

GitHub never lets authors approve their own PRs. While there's only one owner, an owner merges their own PR without an approval by selecting **Bypass rules and merge** (`gh pr merge <pr-number> --squash --admin`), after the required checks pass. That bypass applies only to the `vnext-require-review` ruleset and is logged separately from a CI bypass. Once a second owner exists, owners review each other's PRs instead.

### Enforcement

Both branches are protected by [rulesets](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) (Settings → Rules). Every applicable ruleset must pass, and each ruleset's bypass list applies only to that ruleset. Rules that must never be bypassed are in rulesets with no bypass list. Every bypass is **For pull requests only**, so nobody can push directly to either branch. The only bypass actor is the `azuresandbox-owners` team.

`main` also has a classic branch protection rule (Settings → Branches) whose only setting is **Restrict who can push**, limited to the `azuresandbox-owners` team and enforced for administrators. Rulesets can't list who is allowed to update a branch, so this classic rule lets owners merge release PRs that pass every check without using a bypass.

| Branch | Ruleset | Rules | Bypass |
| --- | --- | --- | --- |
| `vnext` | `vnext-baseline` | Require a PR, require conversation resolution, block force pushes and deletion | None |
| `vnext` | `vnext-required-checks` | Require the ten static CI checks from GitHub Actions, with the branch up to date | `azuresandbox-owners`, PRs only |
| `vnext` | `vnext-require-review` | Require one approval from a code owner, given after the latest commit by someone other than its pusher | `azuresandbox-owners`, PRs only |
| `main` | `main-baseline` | Require a PR, block force pushes and deletion | None |
| `main` | `main-release-source` | Require `main-source-eligibility` | `azuresandbox-owners`, PRs only |
| `main` | `main-release-static-ci` | Require `release-static-ci` | `azuresandbox-owners`, PRs only |
| `main` | `main-release-deployment` | Require `sandbox-deployment-gate` and `Publish release deployment status` | `azuresandbox-owners`, PRs only |

Each kind of bypass is in its own ruleset, so the merge's entry in **Settings → Rules → Insights** shows which kind was used: review, CI, release source, release static CI, or deployment.

The [source-policy workflow](.github/workflows/main-source-policy.yml) publishes
`main-source-eligibility`. It runs trusted default-branch code on a
GitHub-hosted runner without checking out or executing PR code, and reports
success on the exact PR head SHA only when the source is this repository's
`vnext` branch; other sources, including a fork's `vnext`, fail. This is a
source-policy check, not an Azure deployment gate.

The [deployment workflow](.github/workflows/sandbox-deployment.yml) publishes
`release-static-ci` after the static CI checks pass on the release head, then
`sandbox-deployment-gate` and `Publish release deployment status` after the
approved deployment and tests. Deployment or test failures block ordinary
merging without closing the PR. See the
[deployment workflow guide](extras/configurations/rg-devops-iac/README.md) for
the exact-SHA status and evidence requirements.

The Microsoft CLA check (`license/cla`) is managed by the Azure-Samples
organization, not this repository. No ruleset or workflow here depends on it.

#### Emergency merges

For urgent situations where waiting isn't practical, a repository owner can
merge an existing PR to either branch when its CI checks or, on `main`, its
deployment haven't passed. Examples include a GitHub outage that delays CI, a
deployment that isn't possible because of time or cost constraints, or an
authorized workflow-registration or maintenance PR to `main` that is not from
`vnext`. Record the reason in the PR, then select **Bypass rules and merge**.

- The bypassed checks keep their real pending or failed state; a bypass never
  creates a passing result, approves or starts a deployment, or allows a direct
  push.
- A bypass never resolves merge conflicts or unresolved conversations, which
  have no bypass.
- GitHub's bypass applies to the whole selected ruleset, not to a list of
  files, so review the PR's full scope before using it.

Code ownership is declared in [`.github/CODEOWNERS`](.github/CODEOWNERS) (`* @Azure-Samples/azuresandbox-owners`), which automatically requests the owners as reviewers on pull requests. The same team approves release deployments in the `sandbox-release-gate` environment.

## Collaborator Access and Issue Assignment

**TL;DR — to assign someone an issue/PR, they need `triage` access (or higher); a past commit alone is not enough.**

- Issues/PRs can only be assigned to users with **write, triage, or admin** access — or anyone who has commented on that item.
- A prior commit / *Contributors* listing grants **no** permission; a `read`-only user won't appear in the assignee picker.
- Use **`triage`** for reviewers/triagers: it allows issue/PR management and assignment but **no commits or merges to any branch** (including `main`).
- Granting access (owner/admin only): invite the user at the `triage` level, then **verify the pending invitation's level** — an older unaccepted invitation at a higher level (e.g. `write`) is not auto-downgraded and must be patched down.
- The user must **accept the invitation** before access takes effect and they become assignable.

## Continuous Integration

Ready (non-draft) pull requests targeting `vnext`, and pushes to `vnext`, automatically run lightweight static-analysis checks via GitHub Actions. These do **not** deploy anything to Azure and require no credentials. The same six workflows also run inside the release deployment workflow for a ready `vnext` → `main` PR, against the release's exact head commit and its full diff from `main`, before any deployment can be approved. The workflows live in [`.github/workflows/`](.github/workflows):

| Workflow | Checks | Configuration |
| --- | --- | --- |
| `ci-docs` | `markdownlint-cli2` (Markdown style) and `lychee` (internal/relative link checker, offline) | [`.markdownlint.jsonc`](.markdownlint.jsonc), [`.markdownlint-cli2.jsonc`](.markdownlint-cli2.jsonc) |
| `ci-terraform` | `terraform fmt -check -recursive`, `tflint --recursive`, and `terraform validate` for both root configurations | [`.tflint.hcl`](.tflint.hcl) |
| `ci-powershell` | `PSScriptAnalyzer` over all PowerShell scripts | [`PSScriptAnalyzerSettings.psd1`](PSScriptAnalyzerSettings.psd1) |
| `ci-bash` | `ShellCheck` over all `*.sh` scripts (fails on warning + error severity) | [`.shellcheckrc`](.shellcheckrc) |
| `ci-actions` | `actionlint` over the GitHub Actions workflows | — |
| `ci-secrets` | `gitleaks` secret scan of the working tree (always runs) | — |

To reproduce the checks locally before opening a PR:

```bash
# Docs
npx --yes markdownlint-cli2@0.23.3
lychee --offline --no-progress './**/*.md'

# Terraform
terraform fmt -check -recursive -diff
tflint --init && tflint --recursive

# PowerShell (PowerShell 7.x with the PSScriptAnalyzer module)
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -Severity Error,Warning"

# Bash (requires ShellCheck on PATH:
#   sudo apt-get install -y shellcheck  |  brew install shellcheck  |
#   download a release from https://github.com/koalaman/shellcheck/releases)
./scripts/Invoke-ShellCheck.sh
```

The PSScriptAnalyzer settings file excludes a small set of rules that conflict with intentional patterns in this deployment-automation codebase (for example, `Write-Host` console output, the project's own `Write-Log` helper, and plaintext-to-`SecureString` conversion required for unattended VM configuration). Each exclusion is documented inline in `PSScriptAnalyzerSettings.psd1`.

`ci-bash` runs ShellCheck at `--severity=warning` (the warning + error gate, mirroring the PowerShell CI). `scripts/Invoke-ShellCheck.sh` runs the identical command locally and shares the repo-root `.shellcheckrc`, so local results match CI exactly. A single documented `# shellcheck disable=SC2024` is applied in `modules/vm-jumpbox-linux/scripts/configure-vm-jumpbox-linux.sh`, where `sudo <cmd> >> $log_file` intentionally elevates only the command while appending to the user-owned log; the justification is recorded inline at the top of that script.

### Automated CI tool-version drift detection

Each CI linter/scanner is pinned to a specific tool version — ShellCheck, actionlint, and gitleaks as direct binary downloads (env-var version + SHA256), PSScriptAnalyzer via `Install-Module -RequiredVersion`, markdownlint-cli2 via `npx …@<ver>`, and Terraform CLI / tflint / the tflint `azurerm` ruleset via setup-action inputs and `.tflint.hcl`. Dependabot only tracks the `terraform` and `github-actions` ecosystems (see [`.github/dependabot.yml`](.github/dependabot.yml)), so it cannot see any of these pins. The scheduled [`ci-tool-versions`](.github/workflows/ci-tool-versions.yml) workflow fills that gap: weekly it runs [`scripts/Check-ToolVersionDrift.sh`](scripts/Check-ToolVersionDrift.sh), which compares every pin against its upstream latest stable release and, when anything is behind, opens (or updates) a **single** tracking issue — labelled `tool-version-drift` — listing each drifted tool's current pin, latest version, and every file that must be updated (the workflow, the mirrored copy in `scripts/Invoke-CIChecks.sh`, plus `.tflint.hcl` for the ruleset and `terraform.tf` for the Terraform CLI). The issue is closed automatically once all pins are back in sync. Run the detector locally at any time with `./scripts/Check-ToolVersionDrift.sh`. When bumping a tool, update every file the report lists and re-run `./scripts/Invoke-CIChecks.sh` before pushing so the pins stay consistent.

## Architecture diagrams

Every module has an architecture diagram under `modules/<module>/images/`, and the whole sandbox has a root diagram at [`images/azuresandbox.drawio.svg`](images/azuresandbox.drawio.svg). They are draw.io **editable SVG** files (`*.drawio.svg`), which store the diagram twice: the editable mxGraph model in the root `<svg content="...">` attribute, and the rendered SVG body that browsers and GitHub display. Editing only one half leaves the file displaying the wrong topology, so always edit them in draw.io (or the VS Code draw.io extension), which keeps both halves in sync.

The root diagram is the **single source of truth** for the shared visual language — connector labels, colour coding, frame naming, and the vnet/subnet layout. The module diagrams are generated from it rather than maintained by hand, so refinements made once to the root propagate everywhere:

```bash
./scripts/build-module-diagrams.py list     # show the root diagram's cells and their owning module
./scripts/build-module-diagrams.py build    # regenerate every module diagram from the root diagram
./scripts/build-module-diagrams.py verify   # integrity-check the generated files
```

For each module the script copies the root diagram, retitles it, and deletes the shapes that belong neither to a required module nor to the module being drawn. Shape geometry is deliberately left alone — deleted shapes simply leave whitespace — so the diagrams stay visually comparable. Which shapes belong to which module is recorded in a commented cell-id map at the top of the script; `list` reports any shape that is missing from it, which is what to run first after adding a shape to the root diagram.

**Workflow:** edit `images/azuresandbox.drawio.svg` in draw.io, run `build`, then run `verify` (it checks that no connector points at a deleted shape and that the embedded model and the rendered picture still agree). Rendering is delegated to draw.io's own engine running headless via [`scripts/render-drawio-svg.js`](scripts/render-drawio-svg.js), which needs Node.js, puppeteer, and network access to `app.diagrams.net`; see that script's header for setup. Commit the regenerated diagrams together with the root diagram change.

## Submission Guidelines

### Submitting an Issue

Before you submit an issue, search the archive, maybe your question was already answered.

If your issue appears to be a bug, and hasn't been reported, open a new issue.
Help us to maximize the effort we can spend fixing issues and adding new
features, by not reporting duplicate issues.  Providing the following information will increase the
chances of your issue being dealt with quickly:

- **Overview of the Issue** - if an error is being thrown a non-minified stack trace helps
- **Version** - what version is affected (e.g. 0.1.2)
- **Motivation for or Use Case** - explain what are you trying to do and why the current behavior is a bug for you
- **Browsers and Operating System** - is this a problem with all browsers?
- **Reproduce the Error** - provide a live example or a unambiguous set of steps
- **Related Issues** - has a similar issue been reported before?
- **Suggest a Fix** - if you can't fix the bug yourself, perhaps you can point to what might be
  causing the problem (line of code or commit)

You can file new issues by providing the above information at the corresponding repository's issues link: [#AzureSandbox](https://github.com/Azure-Samples/azuresandbox/issues/new).

### Submitting a Pull Request (PR)

Before you submit your Pull Request (PR) consider the following guidelines:

- Search the repository [#AzureSandbox](https://github.com/Azure-Samples/azuresandbox/pulls) for an open or closed PR
  that relates to your submission. You don't want to duplicate effort.

- Make your changes in a new git branch or fork, based on `vnext`:

- Commit your changes using a descriptive commit message
- Push your branch or fork to GitHub:
- In GitHub, create a pull request **with `vnext` as the base branch** (not `main`)
- If we suggest changes then:
  - Make the required updates.
  - Rebase your branch and force push to your GitHub repository (this will update your Pull Request):

    ```shell
    git rebase vnext -i
    git push -f
    ```

That's it! Thank you for your contribution!
