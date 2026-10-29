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

function Set-SandboxContext {
    param($DeploymentProfile)
    $context = Set-AzContext -Subscription $DeploymentProfile.subscription_id -Tenant $DeploymentProfile.entra_tenant_id
    if ($context.Subscription.Id -ne $DeploymentProfile.subscription_id -or $context.Tenant.Id -ne $DeploymentProfile.entra_tenant_id) {
        throw 'Azure context does not match the approved deployment.'
    }
}

function Connect-SandboxOidc {
    param($DeploymentProfile)
    Connect-AzAccount -ServicePrincipal -ApplicationId $DeploymentProfile.client_id `
        -Tenant $DeploymentProfile.entra_tenant_id -FederatedToken (Get-SandboxGitHubIdToken) | Out-Null
    # Azure CLI, used by some tests, shares the job's AZURE_CONFIG_DIR and needs its own fresh sign-in.
    az login --service-principal --username $DeploymentProfile.client_id --tenant $DeploymentProfile.entra_tenant_id `
        --allow-no-subscriptions --output none --federated-token (Get-SandboxGitHubIdToken)
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI OIDC sign-in failed.' }
    az account set --subscription $DeploymentProfile.subscription_id
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI could not select the approved subscription.' }
    Set-SandboxContext $DeploymentProfile
    # The GitHub ID token expires 5 minutes after it's issued, and without it the session can't get a token for an
    # audience it hasn't used yet. Get every audience the runner's tests use now; cached tokens last about an hour.
    try {
        $null = Get-AzAccessToken -AsSecureString -ErrorAction Stop
        $null = Get-AzAccessToken -ResourceTypeName KeyVault -AsSecureString -ErrorAction Stop
    }
    catch { throw "Azure PowerShell could not get the access tokens the tests need: $_" }
    az account get-access-token --output none
    if ($LASTEXITCODE -ne 0) { throw 'Azure CLI could not get the access token the tests need.' }
}

# Test scripts call this once, then retry, if a token request fails because the GitHub ID token has expired.
# It only exists in OIDC mode. The profile variable has a unique name because callers' variables can shadow it.
function Update-SandboxOidcSession {
    Connect-SandboxOidc $sandboxOidcRenewalProfile
}

function Connect-SandboxAzure {
    param($DeploymentProfile)
    switch -CaseSensitive ($DeploymentProfile.auth_mode) {
        'managed_identity' {
            Connect-AzAccount -Identity -AccountId $DeploymentProfile.client_id | Out-Null
            Set-SandboxContext $DeploymentProfile
        }
        'oidc' { Connect-SandboxOidc $DeploymentProfile }
        default { throw "Unsupported auth_mode for the runner: $($DeploymentProfile.auth_mode)." }
    }
}

try {
    Import-Module Az.Accounts, Az.Compute, Az.Resources, Az.Sql, Az.Network, Az.PrivateDns, Az.MySql, Az.DesktopVirtualization -ErrorAction Stop
    $deploymentProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-SandboxAzure $deploymentProfile
    if ($deploymentProfile.auth_mode -cne 'oidc') { Remove-Item -LiteralPath Function:\Update-SandboxOidcSession }
    $sandboxOidcRenewalProfile = $deploymentProfile
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
