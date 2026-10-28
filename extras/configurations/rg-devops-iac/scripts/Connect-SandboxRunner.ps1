#requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$ProfilePath,

    [Parameter(Mandatory = $false)]
    [switch]$RunTests,

    [Parameter(Mandatory = $false)]
    [string]$ResultsJsonPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SandboxOidc.ps1')

function Connect-SandboxAzure {
    param($DeploymentProfile)
    switch -CaseSensitive ($DeploymentProfile.auth_mode) {
        'managed_identity' {
            Connect-AzAccount -Identity -AccountId $DeploymentProfile.client_id | Out-Null
        }
        'oidc' {
            Connect-AzAccount -ServicePrincipal -ApplicationId $DeploymentProfile.client_id `
                -Tenant $DeploymentProfile.entra_tenant_id -FederatedToken (Get-SandboxGitHubIdToken) | Out-Null
            # Azure CLI, used by some tests, shares the job's AZURE_CONFIG_DIR and needs its own fresh sign-in.
            az login --service-principal --username $DeploymentProfile.client_id --tenant $DeploymentProfile.entra_tenant_id `
                --allow-no-subscriptions --output none --federated-token (Get-SandboxGitHubIdToken)
            if ($LASTEXITCODE -ne 0) { throw 'Azure CLI OIDC sign-in failed.' }
            az account set --subscription $DeploymentProfile.subscription_id
            if ($LASTEXITCODE -ne 0) { throw 'Azure CLI could not select the approved subscription.' }
        }
        default { throw "Unsupported auth_mode for the runner: $($DeploymentProfile.auth_mode)." }
    }
    $context = Set-AzContext -Subscription $DeploymentProfile.subscription_id -Tenant $DeploymentProfile.entra_tenant_id
    if ($context.Subscription.Id -ne $DeploymentProfile.subscription_id -or $context.Tenant.Id -ne $DeploymentProfile.entra_tenant_id) {
        throw 'Azure context does not match the approved deployment.'
    }
}

try {
    Import-Module Az.Accounts, Az.Compute, Az.Resources, Az.Sql, Az.Network, Az.PrivateDns, Az.MySql, Az.DesktopVirtualization -ErrorAction Stop
    $deploymentProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-SandboxAzure $deploymentProfile
}
catch {
    Write-Error -ErrorAction Continue $_
    exit 2
}

if ($RunTests) {
    # Full detail stays in the private results file; Invoke-SandboxDeployment.ps1 redacts the published copy.
    $testArguments = @{ ResultsJsonPath = $ResultsJsonPath; VerboseResults = $true }
    # The orchestrator must run in this process to inherit the explicit Azure context.
    & (Join-Path $env:GITHUB_WORKSPACE 'scripts/Invoke-UnitTests.ps1') @testArguments
    exit $LASTEXITCODE
}
