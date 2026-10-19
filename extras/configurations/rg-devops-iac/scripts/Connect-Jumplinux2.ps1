#requires -Version 7.0
<#
.SYNOPSIS
    Connects to jumplinux2 through Azure Bastion using Microsoft Entra ID SSH sign-in, for VS Code Remote-SSH or ssh.

.DESCRIPTION
    1. Requests a short-lived (about 1 hour) Entra ID OpenSSH certificate with 'az ssh cert'.
    2. Writes (or updates) a managed 'Host jumplinux2' block in ~/.ssh/config that points at the local tunnel port.
    3. Opens 'az network bastion tunnel' to the VM resource id in the foreground, renewing the certificate in the
       background about every 50 minutes while the tunnel is up.

    Keep this terminal open while connected: it hosts the Bastion tunnel. Press Ctrl+C to close the tunnel.
    Then connect with VS Code Remote-SSH (host 'jumplinux2') or 'ssh jumplinux2' from another terminal.

    Prerequisites: Azure CLI signed in ('az login') with the 'bastion' and 'ssh' extensions, OpenSSH client
    (ssh-keygen), and the 'Virtual Machine Administrator Login' role on the VM plus Reader on the VM, its NIC and
    the Bastion host. Defaults are read from this configuration's Terraform outputs; override them with the
    parameters below when the state isn't available locally.

.EXAMPLE
    ./scripts/Connect-Jumplinux2.ps1

.EXAMPLE
    ./scripts/Connect-Jumplinux2.ps1 -BastionName <bastion> -ResourceGroupName <rg> -VmId <vm-resource-id>
#>
[CmdletBinding()]
param(
    [string]$BastionName,
    [string]$ResourceGroupName,
    [string]$VmId,
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$HostAlias = 'jumplinux2',
    [ValidateRange(1, 65535)]
    [int]$Port = 2222
)

$ErrorActionPreference = 'Stop'
$renewSeconds = 3000
$configDir = Split-Path -Parent $PSScriptRoot

#region prerequisites
foreach ($cmd in 'az', 'ssh-keygen') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "'$cmd' is required but was not found in PATH."
    }
}

az account show --only-show-errors *> $null
if ($LASTEXITCODE -ne 0) { throw "Not signed in to Azure CLI; run 'az login' first." }

foreach ($extension in 'bastion', 'ssh') {
    az extension show --name $extension --only-show-errors *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI '$extension' extension is required; run 'az extension add --name $extension'."
    }
}
#endregion

#region resolve-targets
function Get-TerraformOutputValue {
    param([string]$Name, [string]$Key)
    try {
        $json = terraform "-chdir=$configDir" output -json $Name 2> $null
        if ($LASTEXITCODE -ne 0 -or -not $json) { return '' }
        $value = ($json | ConvertFrom-Json -AsHashtable)[$Key]
        if ($value) { return [string]$value } else { return '' }
    }
    catch { return '' }
}

if (-not ($BastionName -and $ResourceGroupName -and $VmId)) {
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw 'terraform not found; pass -BastionName, -ResourceGroupName and -VmId.'
    }
    if (-not $BastionName) { $BastionName = Get-TerraformOutputValue -Name resource_names -Key bastion_host }
    if (-not $ResourceGroupName) { $ResourceGroupName = Get-TerraformOutputValue -Name resource_names -Key resource_group }
    if (-not $VmId) { $VmId = Get-TerraformOutputValue -Name resource_ids -Key virtual_machine_jumplinux2 }
}

if (-not ($BastionName -and $ResourceGroupName -and $VmId)) {
    throw "Could not read Terraform outputs from '$configDir'; pass -BastionName, -ResourceGroupName and -VmId."
}
#endregion

#region certificate
$sshDir = Join-Path $HOME '.ssh'
$keyDir = Join-Path $sshDir "az_ssh_config/$HostAlias"
$keyFile = Join-Path $keyDir 'id_rsa'
$certFile = Join-Path $keyDir 'id_rsa-cert.pub'

New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
if (-not $IsWindows) { chmod 700 $sshDir $keyDir }

# Microsoft Entra ID issues OpenSSH certificates for RSA keys only.
if (-not (Test-Path -LiteralPath $keyFile)) {
    ssh-keygen -q -t rsa -b 4096 -N '' -C "$HostAlias-entra" -f $keyFile
    if ($LASTEXITCODE -ne 0) { throw "ssh-keygen failed to create '$keyFile'." }
}

Write-Output 'Requesting Microsoft Entra ID SSH certificate...'
az ssh cert --public-key-file "$keyFile.pub" --file $certFile --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) { throw "'az ssh cert' failed." }

# The certificate principal is the Entra user name the VM expects (normally the UPN).
$certInfo = @(ssh-keygen -L -f $certFile)
$sshUser = ''
for ($i = 0; $i -lt $certInfo.Count - 1; $i++) {
    if ($certInfo[$i] -match 'Principals:') { $sshUser = $certInfo[$i + 1].Trim(); break }
}
if (-not $sshUser) { throw "Could not read the principal from '$certFile'." }
#endregion

#region ssh-config
$sshConfig = Join-Path $sshDir 'config'
$beginMarker = "# BEGIN $HostAlias (managed by connect-jumplinux2)"
$endMarker = "# END $HostAlias (managed by connect-jumplinux2)"

# OpenSSH on Windows accepts forward slashes, which avoids escaping backslashes in ssh_config.
$keyPath = $keyFile -replace '\\', '/'
$certPath = $certFile -replace '\\', '/'

$existing = if (Test-Path -LiteralPath $sshConfig) { @(Get-Content -LiteralPath $sshConfig) } else { @() }
$kept = [System.Collections.Generic.List[string]]::new()
$skip = $false
foreach ($line in $existing) {
    if ($line -eq $beginMarker) { $skip = $true; continue }
    if ($line -eq $endMarker) { $skip = $false; continue }
    if (-not $skip) { $kept.Add($line) }
}

$kept.AddRange([string[]]@(
        $beginMarker
        "Host $HostAlias"
        '  HostName 127.0.0.1'
        "  Port $Port"
        "  User $sshUser"
        "  IdentityFile `"$keyPath`""
        "  CertificateFile `"$certPath`""
        '  IdentitiesOnly yes'
        "  HostKeyAlias $HostAlias"
        $endMarker
    ))

Set-Content -LiteralPath $sshConfig -Value $kept
if (-not $IsWindows) { chmod 600 $sshConfig }
Write-Output "Updated '$sshConfig' (Host $HostAlias -> 127.0.0.1:$Port as $sshUser)."
#endregion

#region tunnel
$renewJob = Start-ThreadJob -ScriptBlock {
    while ($true) {
        Start-Sleep -Seconds $using:renewSeconds
        az ssh cert --public-key-file "$($using:keyFile).pub" --file $using:certFile --only-show-errors | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') Renewed Microsoft Entra ID SSH certificate."
        }
        else {
            Write-Warning "$(Get-Date -Format 'HH:mm:ss') Certificate renewal failed; run 'az login' and restart this script."
        }
    }
} -StreamingHost $Host

try {
    Write-Output "Opening Bastion tunnel to '$HostAlias' on 127.0.0.1:$Port. Keep this terminal open; press Ctrl+C to close."
    Write-Output "Connect with VS Code Remote-SSH (host '$HostAlias') or 'ssh $HostAlias'."
    az network bastion tunnel `
        --name $BastionName `
        --resource-group $ResourceGroupName `
        --target-resource-id $VmId `
        --resource-port 22 `
        --port $Port `
        --only-show-errors
}
finally {
    # Runs on normal exit and on Ctrl+C, so the renewal job never outlives the tunnel.
    $renewJob | Stop-Job -PassThru | Remove-Job -Force
}
#endregion
