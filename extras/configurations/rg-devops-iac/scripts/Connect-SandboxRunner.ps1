#requires -Version 7.0

param(
    [Parameter(Mandatory = $true)]
    [string]$ProfilePath,

    [Parameter(Mandatory = $false)]
    [switch]$RunTests,

    [Parameter(Mandatory = $false)]
    [string]$ResultsJsonPath,

    [Parameter(Mandatory = $false)]
    [string]$JUnitXmlPath
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module Az.Accounts, Az.Compute, Az.Resources, Az.Sql, Az.Network, Az.PrivateDns, Az.MySql, Az.DesktopVirtualization -ErrorAction Stop
    $deploymentProfile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    Disable-AzContextAutosave -Scope Process | Out-Null
    Connect-AzAccount -Identity -AccountId $deploymentProfile.arm_client_id | Out-Null
    $context = Set-AzContext -Subscription $deploymentProfile.subscription_id -Tenant $deploymentProfile.aad_tenant_id
    if ($context.Subscription.Id -ne $deploymentProfile.subscription_id -or $context.Tenant.Id -ne $deploymentProfile.aad_tenant_id) {
        throw 'Managed identity context does not match the approved deployment.'
    }
}
catch {
    Write-Error -ErrorAction Continue $_
    exit 2
}

if ($RunTests) {
    # The orchestrator must run in this process to inherit the explicit MSI context.
    & (Join-Path $env:GITHUB_WORKSPACE 'scripts/Invoke-UnitTests.ps1') -ResultsJsonPath $ResultsJsonPath -JUnitXmlPath $JUnitXmlPath
    exit $LASTEXITCODE
}
