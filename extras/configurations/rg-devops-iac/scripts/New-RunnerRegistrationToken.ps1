#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Creates a GitHub Actions runner registration token for the optional self-hosted runner and sets
    TF_VAR_github_runner_token.

.DESCRIPTION
    Creates a runner registration token and sets it in the TF_VAR_github_runner_token environment
    variable of the current PowerShell session, for use when enable_github_runner = true. Not needed
    otherwise. The token is never displayed.

    Requires the GitHub CLI (gh) signed in as a repository admin. The token expires after 1 hour,
    so run terraform plan and terraform apply right away, in the same PowerShell session.

.PARAMETER RunnerUrl
    The GitHub repository URL. Defaults to github_runner_url in ../terraform.tfvars, then to the
    variable's default, the Azure Sandbox repository.

.EXAMPLE
    # From extras/configurations/rg-devops-iac
    ./scripts/New-RunnerRegistrationToken.ps1
#>

[CmdletBinding()]
param(
    [string]$RunnerUrl
)

$ErrorActionPreference = 'Stop'

$tfvars = Join-Path (Split-Path -Parent $PSScriptRoot) 'terraform.tfvars'

if (-not $RunnerUrl -and (Test-Path -Path $tfvars -PathType Leaf)) {
    $match = Select-String -Path $tfvars -Pattern '^\s*github_runner_url\s*=\s*"([^"]*)"' | Select-Object -Last 1
    if ($match) {
        $RunnerUrl = $match.Matches[0].Groups[1].Value
    }
}

# Matches the default of github_runner_url in ../variables.tf.
if (-not $RunnerUrl) {
    $RunnerUrl = 'https://github.com/Azure-Samples/azuresandbox'
}

if ($RunnerUrl -notmatch '^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') {
    throw "'$RunnerUrl' is not a GitHub repository URL, e.g. 'https://github.com/myorg/myrepo'."
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'The GitHub CLI (gh) is not installed. See https://cli.github.com.'
}

$endpoint = "repos/$($RunnerUrl.Substring('https://github.com/'.Length))/actions/runners/registration-token"

$token = gh api --method POST $endpoint --jq '.token'
if ($LASTEXITCODE -ne 0) {
    throw "Could not create a registration token for $RunnerUrl. Sign in with 'gh auth login' as a repository admin."
}

if (-not $token) {
    throw "The GitHub API returned an empty registration token for $RunnerUrl."
}

$env:TF_VAR_github_runner_token = $token
Write-Information -MessageData 'TF_VAR_github_runner_token is set. The token expires in 1 hour: run terraform plan and terraform apply in this session.' -InformationAction Continue
