#!/usr/bin/env pwsh

#region functions
function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Host
}
function Exit-WithError {
    param( [string]$msg )
    Write-Log "There was an exception during the process, please review..."
    Write-Log $msg
    Exit 2
}

# Modules installed from a temporary repository record that repository in PSGetModuleInfo.xml. Once it
# is unregistered, Update-Module / Update-PSResource / Get-InstalledPSResource fail on those modules.
# The packages are identical to the ones PSGallery serves, so point the metadata back at PSGallery.
function Convert-AzModuleSourceToPSGallery {
    param( [string] $RepositoryName )

    $modulesPath = '/usr/local/share/powershell/Modules'
    foreach ($module in Get-Module -ListAvailable -Name 'Az', 'Az.*' | Where-Object { $_.ModuleBase.StartsWith($modulesPath) }) {
        $infoPath = Join-Path $module.ModuleBase 'PSGetModuleInfo.xml'
        if (-not (Test-Path $infoPath)) { continue }

        $xml = Get-Content -Path $infoPath -Raw
        if ($xml -notmatch "<S N=""Repository"">$([regex]::Escape($RepositoryName))</S>") { continue }

        $xml = $xml -replace '(<S N="Repository">)[^<]*(</S>)', '${1}PSGallery${2}'
        $xml = $xml -replace '(<S N="RepositorySourceLocation">)[^<]*(</S>)', '${1}https://www.powershellgallery.com/api/v2${2}'
        Set-Content -Path $infoPath -Value $xml -NoNewline
    }
}

# The PowerShell Gallery CDN throttles each download to ~100 KB/s, so installing the Az rollup
# from PSGallery takes 60+ minutes (see issue #801). Instead, install from the Az offline bundle
# published on the Azure/azure-powershell GitHub release (all Az nupkgs in one tarball), and fall
# back to Microsoft Artifact Registry (MAR) if that fails.
function Install-AzFromGitHubRelease {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Azure/azure-powershell/releases/latest' -Headers @{ 'User-Agent' = 'azuresandbox' }
    $asset = $release.assets | Where-Object name -Match '^Az-Cmdlets-.*\.tar\.gz$' | Select-Object -First 1
    if ($null -eq $asset) {
        throw "No Az-Cmdlets-*.tar.gz asset found in Azure/azure-powershell release '$($release.tag_name)'."
    }

    $sourcePath = Join-Path ([System.IO.Path]::GetTempPath()) "az-$([guid]::NewGuid())"
    $repoName = "AzOfflineBundle-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $sourcePath | Out-Null

    try {
        Write-Log "Downloading '$($asset.name)' from release '$($release.tag_name)'..."
        $tarball = Join-Path $sourcePath $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tarball
        tar -xzf $tarball -C $sourcePath
        if ($LASTEXITCODE -ne 0) { throw "Failed to extract '$tarball'." }

        # PSResourceGet does not resolve the Az rollup's dependencies from a local file repository,
        # so every package in the bundle is installed explicitly.
        $names = Get-ChildItem -Path $sourcePath -Filter '*.nupkg' |
            ForEach-Object { $_.BaseName -replace '^(.+?)\.\d+\.\d+\.\d+(\.\d+)?(-[0-9A-Za-z.-]+)?$', '$1' }
        if ($names.Count -eq 0) { throw "No .nupkg files found in '$($asset.name)'." }

        Register-PSResourceRepository -Name $repoName -Uri $sourcePath -Trusted
        Write-Log "Installing $($names.Count) Az packages from offline bundle..."
        Install-PSResource -Name $names -Repository $repoName -Scope AllUsers -TrustRepository -SkipDependencyCheck -AcceptLicense -Quiet -ErrorAction Stop

        $missing = $names | Where-Object { -not (Get-Module -ListAvailable -Name $_) }
        if ($missing) { throw "Packages missing after install: $($missing -join ', ')" }

        Convert-AzModuleSourceToPSGallery -RepositoryName $repoName
    }
    finally {
        Unregister-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue
        Remove-Item -Path $sourcePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-AzFromMar {
    $repoName = 'MAR'
    $registered = $false
    if (-not (Get-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue)) {
        Register-PSResourceRepository -Name $repoName -Uri 'https://mcr.microsoft.com' -ApiVersion ContainerRegistry -Trusted
        $registered = $true
    }

    try {
        Install-PSResource -Name Az -Repository $repoName -Scope AllUsers -TrustRepository -AcceptLicense -Quiet -ErrorAction Stop
        Convert-AzModuleSourceToPSGallery -RepositoryName $repoName
    }
    finally {
        if ($registered) { Unregister-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue }
    }
}
#endregion

#region main
# Install PowerShell prerequisites
$nugetPackage = Get-PackageProvider | Where-Object Name -eq 'NuGet'

if ($null -eq $nugetPackage) {
    Write-Log "Installing NuGet PowerShell package provider..."

    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force 
    }
    catch {
        Exit-WithError $_
    }
}

$nugetPackage = Get-PackageProvider | Where-Object Name -eq 'NuGet'
Write-Log "NuGet Powershell Package Provider version $($nugetPackage.Version.Major).$($nugetPackage.Version.Minor).$($nugetPackage.Version.Build).$($nugetPackage.Version.Revision) is already installed..."

$repo = Get-PSRepository -Name PSGallery
if ( $repo.InstallationPolicy -eq 'Trusted' ) {
    Write-Log "PSGallery installation policy is already set to 'Trusted'..."
}
else {
    Write-Log "Setting PSGallery installation policy to 'Trusted'..."

    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted    
    }
    catch {
        Exit-WithError $_
    }
}

$azModule = Get-Module -ListAvailable -Name Az*
if ($null -eq $azModule ) {
    Write-Log "Installing PowerShell Az module..."

    try {
        Install-AzFromGitHubRelease
    }
    catch {
        Write-Log "Installing Az from GitHub release failed, falling back to Microsoft Artifact Registry: $_"

        try {
            Install-AzFromMar
        }
        catch {
            Exit-WithError $_
        }
    }
}
else {
    Write-Log "PowerShell Az module is already installed..."
}

$azAutomationModule = Get-Module -ListAvailable -Name Az.Automation
Write-Log "PowerShell Az.Automation version $($azAutomationModule.Version) is installed..."

Exit 0
#endregion
