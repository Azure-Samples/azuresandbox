#!/bin/bash

# update-az-module.sh
#
# Ensures the latest supported (stable) version of the PowerShell 7.x Az
# module is installed.
#
# The Az module is a "meta" module: it is a small manifest that depends on
# roughly a hundred Az.* sub-modules (Az.Accounts, Az.Compute, etc.). The
# slow part of an install/update is downloading those sub-modules, so this
# script first checks what is already installed and only updates the
# sub-modules whose versions are behind. If everything is already current it
# exits quickly without changing anything.
#
# Usage:
#   ./update-az-module.sh [scope]
#     scope - PowerShell install scope: CurrentUser (default) or AllUsers.
#             AllUsers typically requires elevated privileges.
#
# Exit codes:
#   0 - success (Az module is at the latest supported version)
#   1 - failure (prerequisites missing or update/verification failed)

set -euo pipefail

# Install scope for PowerShell modules. CurrentUser avoids needing sudo.
SCOPE="${1:-CurrentUser}"

# Make sure PowerShell 7 is available before doing anything else.
if ! command -v pwsh >/dev/null 2>&1; then
  echo "Error: pwsh (PowerShell 7.x) was not found on PATH."
  echo "Install PowerShell 7 and try again."
  exit 1
fi

echo "Using PowerShell module install scope: ${SCOPE}"
echo "Checking the Az module. This can take a while the first time..."

# All of the real work is done in PowerShell because module management is a
# PowerShell task. We write the PowerShell to a temporary file and run it with
# pwsh -File, which gives reliable script execution and a clean exit code. The
# chosen scope is passed through an environment variable.
PS_SCRIPT="$(mktemp /tmp/update-az-module.XXXXXX.ps1)"

# Always remove the temporary script when this bash script exits.
trap 'rm -f "$PS_SCRIPT"' EXIT

cat > "$PS_SCRIPT" <<'POWERSHELL'
# Read the install scope passed in from the bash wrapper.
$Scope = $env:AZ_MODULE_SCOPE
if ([string]::IsNullOrWhiteSpace($Scope)) { $Scope = 'CurrentUser' }

# Stop on the first unhandled error so failures are not silently ignored.
$ErrorActionPreference = 'Stop'

# Simple timestamped console logging (no colors or special characters).
function Write-Log {
    param( [string] $Message )
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Write-Host
}

# Compare two version strings. Returns $true when $a is older than $b.
function Test-IsOlder {
    param( [string] $a, [string] $b )

    # Some gallery versions carry a prerelease suffix (e.g. 1.2.3-preview).
    # Strip it so [version] can parse the numeric portion for comparison.
    $aClean = ($a -split '-')[0]
    $bClean = ($b -split '-')[0]

    try {
        return ([version] $aClean) -lt ([version] $bClean)
    }
    catch {
        # Fall back to a plain string comparison if parsing fails.
        return ($aClean -lt $bClean)
    }
}

try {
    # --- Prerequisites -----------------------------------------------------

    # The NuGet package provider is required to talk to the PowerShell Gallery.
    $nuget = Get-PackageProvider -ListAvailable -ErrorAction SilentlyContinue |
        Where-Object Name -eq 'NuGet'

    if ($null -eq $nuget) {
        Write-Log "Installing the NuGet package provider..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope $Scope | Out-Null
    }

    # Trust the PSGallery repository so installs do not prompt for confirmation.
    $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($null -ne $repo -and $repo.InstallationPolicy -ne 'Trusted') {
        Write-Log "Setting PSGallery installation policy to Trusted..."
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    # --- Determine the latest supported Az version -------------------------

    Write-Log "Looking up the latest supported Az module version in PSGallery..."
    $latest = Find-Module -Name Az -Repository PSGallery
    Write-Log "Latest supported Az version: $($latest.Version)"

    # Build a map of sub-module name -> target version from Az's dependencies.
    # Each dependency declares either a RequiredVersion (exact) or a
    # MinimumVersion; use whichever is present as the target.
    $targets = @{}
    foreach ($dep in $latest.Dependencies) {
        if ($dep.Contains('RequiredVersion')) {
            $targets[$dep.Name] = $dep.RequiredVersion
        }
        else {
            $targets[$dep.Name] = $dep.MinimumVersion
        }
    }
    Write-Log "Az $($latest.Version) is composed of $($targets.Count) sub-modules."

    # --- Inspect what is currently installed -------------------------------

    # Highest installed version of the Az meta-module (null if not installed).
    $installedAz = Get-Module -ListAvailable -Name Az |
        Sort-Object Version -Descending |
        Select-Object -First 1

    # Highest installed version of each Az.* sub-module, keyed by name.
    $installedSub = @{}
    Get-Module -ListAvailable -Name Az.* |
        Group-Object Name |
        ForEach-Object {
            $highest = ($_.Group | Sort-Object Version -Descending | Select-Object -First 1).Version
            $installedSub[$_.Name] = $highest.ToString()
        }

    # Work out which sub-modules are missing or behind their target version.
    $toUpdate = @()
    foreach ($name in $targets.Keys) {
        $target = $targets[$name]
        if (-not $installedSub.ContainsKey($name)) {
            $toUpdate += $name
        }
        elseif (Test-IsOlder $installedSub[$name] $target) {
            $toUpdate += $name
        }
    }

    $metaCurrent = ($null -ne $installedAz) -and ($installedAz.Version.ToString() -eq $latest.Version.ToString())

    # --- Decide what to do -------------------------------------------------

    if ($metaCurrent -and $toUpdate.Count -eq 0) {
        # Nothing to do: meta-module and all sub-modules already current.
        Write-Log "Az $($latest.Version) is already installed and up to date. No changes needed."
        exit 0
    }

    if ($null -eq $installedAz) {
        # Fresh install: pull the whole Az module (this is the slow path).
        Write-Log "Az module is not installed. Performing a full install of Az $($latest.Version)..."
        Install-Module -Name Az -RequiredVersion $latest.Version -Scope $Scope -AllowClobber -Force
    }
    else {
        # Targeted update: only install the sub-modules that are behind, then
        # refresh the small meta-module manifest so its version matches.
        if ($toUpdate.Count -gt 0) {
            Write-Log "$($toUpdate.Count) sub-module(s) need updating: $($toUpdate -join ', ')"
            foreach ($name in $toUpdate) {
                $target = $targets[$name]
                Write-Log "Installing $name $target..."
                Install-Module -Name $name -RequiredVersion $target -Scope $Scope -AllowClobber -Force
            }
        }
        else {
            Write-Log "All sub-modules are current. Updating the Az meta-module only..."
        }

        if (-not $metaCurrent) {
            Write-Log "Updating the Az meta-module to $($latest.Version)..."
            Install-Module -Name Az -RequiredVersion $latest.Version -Scope $Scope -AllowClobber -Force
        }
    }

    # --- Verify ------------------------------------------------------------

    Write-Log "Verifying installed versions..."

    # Refresh the list of available modules after installing.
    $verifyAz = Get-Module -ListAvailable -Name Az |
        Sort-Object Version -Descending |
        Select-Object -First 1

    $verifySub = @{}
    Get-Module -ListAvailable -Name Az.* |
        Group-Object Name |
        ForEach-Object {
            $highest = ($_.Group | Sort-Object Version -Descending | Select-Object -First 1).Version
            $verifySub[$_.Name] = $highest.ToString()
        }

    $problems = @()

    if ($null -eq $verifyAz -or $verifyAz.Version.ToString() -ne $latest.Version.ToString()) {
        $problems += "Az meta-module is not at version $($latest.Version)."
    }

    foreach ($name in $targets.Keys) {
        $target = $targets[$name]
        if (-not $verifySub.ContainsKey($name)) {
            $problems += "$name is missing (expected $target)."
        }
        elseif (Test-IsOlder $verifySub[$name] $target) {
            $problems += "$name is $($verifySub[$name]) but expected at least $target."
        }
    }

    if ($problems.Count -gt 0) {
        Write-Log "Verification failed. The following problems were found:"
        foreach ($p in $problems) { Write-Log "  - $p" }
        exit 1
    }

    Write-Log "Success. Az $($latest.Version) and all $($targets.Count) sub-modules are installed and up to date."
    exit 0
}
catch {
    Write-Log "An error occurred: $($_.Exception.Message)"
    exit 1
}
POWERSHELL

# Run the generated PowerShell script and propagate its exit code.
AZ_MODULE_SCOPE="$SCOPE" pwsh -NoProfile -NonInteractive -File "$PS_SCRIPT"
exit $?
