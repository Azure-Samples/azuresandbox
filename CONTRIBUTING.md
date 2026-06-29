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
| `vnext` | Active development / integration branch. All day-to-day work lands here. | Any collaborator with write access | Pull requests (or direct pushes by maintainers) |
| `main` | Stable, released code. | Repository owner **@doherty100** only | Pull request merging `vnext` → `main` |

### Workflow

1. **Target `vnext` for all contributions.** Open every pull request — features, bug fixes, and documentation — against the `vnext` branch. Do not open pull requests directly against `main`.
2. **Integration happens on `vnext`.** Reviews, status checks (including the CLA bot), and testing occur here.
3. **Promotion to `main` is restricted.** Only the repository owner (**@doherty100**) opens and merges the `vnext` → `main` pull request that promotes accumulated changes to the stable branch. No other collaborator can merge into `main`.

### Merge strategy

**TL;DR:** Squash-merge topic/contributor PRs into `vnext`; use a regular merge commit (no squash) for the `vnext` → `main` release PR.

- **Topic/contributor PRs → `vnext`:** **squash merge**, so each PR lands as one tidy commit on `vnext`.
- **`vnext` → `main` (release promotion):** **regular merge commit (do not squash)**, so the individual `vnext` commits and the branch lineage are preserved on `main`. Squashing this promotion flattens all the work into a single commit and loses that history.

### Merging into `vnext` (merge queue)

`vnext` uses a **merge queue**, so you no longer use the "Squash and merge" button or merge a PR directly — you queue it and the queue squash-merges it for you once it is up to date and green. Simple workflow, starting from edits in your working tree:

```bash
# 1. Put your edits on a branch (uncommitted changes come with you).
git checkout -b feature/my-change
git add -A
git commit -m "describe my change"
git push -u origin feature/my-change

# 2. Open the PR against vnext.
gh pr create --base vnext --fill

# 3. After checks pass and the PR has 1 approval, queue it:
gh pr merge --squash --auto

# 4. The queue updates your branch, re-runs checks, and squash-merges it.
#    Then sync your local vnext:
git checkout vnext && git pull
```

You do **not** need to manually click "Update branch" when your PR falls behind — the merge queue rebases it on the latest `vnext` automatically. Expect a short delay (rather than an instant merge) while the queue builds and tests your PR.

### Enforcement

The policy above is enforced by [branch protection](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) on `main`:

- `main` can only be updated through a pull request (no direct contributor pushes).
- Push/merge access to `main` is restricted to **@doherty100**, so only the owner can complete a `vnext` → `main` pull request.
- Force pushes and branch deletion are disabled on `main`.

Code ownership is declared in [`.github/CODEOWNERS`](.github/CODEOWNERS) (`* @doherty100`), which automatically requests the owner as a reviewer on pull requests.

## Collaborator Access and Issue Assignment

**TL;DR — to assign someone an issue/PR, they need `triage` access (or higher); a past commit alone is not enough.**

- Issues/PRs can only be assigned to users with **write, triage, or admin** access — or anyone who has commented on that item.
- A prior commit / *Contributors* listing grants **no** permission; a `read`-only user won't appear in the assignee picker.
- Use **`triage`** for reviewers/triagers: it allows issue/PR management and assignment but **no commits or merges to any branch** (including `main`).
- Granting access (owner/admin only): invite the user at the `triage` level, then **verify the pending invitation's level** — an older unaccepted invitation at a higher level (e.g. `write`) is not auto-downgraded and must be patched down.
- The user must **accept the invitation** before access takes effect and they become assignable.

## Continuous Integration

Pull requests targeting `vnext` (and pushes to `vnext`) automatically run lightweight static-analysis checks via GitHub Actions. These do **not** deploy anything to Azure and require no credentials. The workflows live in [`.github/workflows/`](.github/workflows):

| Workflow | Checks | Configuration |
| --- | --- | --- |
| `ci-docs` | `markdownlint-cli2` (Markdown style) and `lychee` (internal/relative link checker, offline) | [`.markdownlint.jsonc`](.markdownlint.jsonc), [`.markdownlint-cli2.jsonc`](.markdownlint-cli2.jsonc) |
| `ci-terraform` | `terraform fmt -check -recursive` and `tflint --recursive` | [`.tflint.hcl`](.tflint.hcl) |
| `ci-powershell` | `PSScriptAnalyzer` over all PowerShell scripts | [`PSScriptAnalyzerSettings.psd1`](PSScriptAnalyzerSettings.psd1) |
| `ci-bash` | `ShellCheck` over all `*.sh` scripts (fails on warning + error severity) | [`.shellcheckrc`](.shellcheckrc) |

To reproduce the checks locally before opening a PR:

```bash
# Docs
npx --yes markdownlint-cli2@0.22.1
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
