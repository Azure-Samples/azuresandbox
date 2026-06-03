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

### Enforcement

The policy above is enforced by [branch protection](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) on `main`:

- `main` can only be updated through a pull request (no direct contributor pushes).
- Push/merge access to `main` is restricted to **@doherty100**, so only the owner can complete a `vnext` → `main` pull request.
- Force pushes and branch deletion are disabled on `main`.

Code ownership is declared in [`.github/CODEOWNERS`](.github/CODEOWNERS) (`* @doherty100`), which automatically requests the owner as a reviewer on pull requests.

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
