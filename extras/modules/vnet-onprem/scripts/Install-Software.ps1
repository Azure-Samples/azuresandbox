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
#endregion

#region main
Write-Log "Running '$PSCommandPath' (PowerShell $($PSVersionTable.PSVersion))..."

# Resolve winget executable path
# When running as SYSTEM (e.g. via VM RunCommand), winget is not in PATH and the
# per-user AppX execution aliases (C:\Users\*\AppData\Local\Microsoft\WindowsApps\winget.exe)
# are reparse points that cannot be executed from the SYSTEM account.
# We must find the real binary inside C:\Program Files\WindowsApps.
$wingetPath = $null

Write-Log "Searching for winget.exe in Program Files\WindowsApps..."
$wingetPath = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $wingetPath) {
    Write-Log "winget not found in Program Files, trying Get-Command..."
    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

if (-not $wingetPath) {
    Exit-WithError "winget.exe not found on this system."
}

Write-Log "Found winget at '$wingetPath'."

# When running winget directly as SYSTEM (outside its MSIX activation context),
# it cannot find its framework dependency DLLs (VCLibs, UI.Xaml, etc.).
# We must add those framework package directories to PATH.
$wingetDir = Split-Path $wingetPath -Parent
$frameworkDirs = @($wingetDir)

$frameworkPatterns = @(
    "C:\Program Files\WindowsApps\Microsoft.VCLibs*_x64__8wekyb3d8bbwe",
    "C:\Program Files\WindowsApps\Microsoft.VCLibs*UWPDesktop*_x64__8wekyb3d8bbwe",
    "C:\Program Files\WindowsApps\Microsoft.UI.Xaml*_x64__8wekyb3d8bbwe"
)

foreach ($pattern in $frameworkPatterns) {
    $dir = Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    if ($dir) {
        $frameworkDirs += $dir
        Write-Log "Added framework dependency: $dir"
    }
}

$env:PATH = ($frameworkDirs -join ";") + ";$env:PATH"
Write-Log "Updated PATH with winget framework dependencies."

# Winget exit codes
$WINGET_SUCCESS              =  0
$WINGET_ALREADY_INSTALLED    = -1978335207  # 0x8A150019 UPDATE_NOT_APPLICABLE
$WINGET_MISSING_DEPENDENCY   = -1978335189  # 0x8A15002B INSTALL_MISSING_DEPENDENCY
$WINGET_PACKAGE_IN_USE       = -1978335231  # 0x8A150101 APPINSTALLER_CLI_ERROR_INSTALL_PACKAGE_IN_USE

# Install software using winget CLI.
Write-Log "Installing software using winget..."

$packages = @(
    @{ Id = "Microsoft.VisualStudioCode"; Name = "Visual Studio Code" },
    @{ Id = "Microsoft.SQLServerManagementStudio.22"; Name = "SQL Server Management Studio" },
    @{ Id = "Oracle.MySQLWorkbench"; Name = "MySQL Workbench" }
)

$failed = $false

foreach ($package in $packages) {
    Write-Log "Installing $($package.Name) (winget id: $($package.Id))..."

    $output = & $wingetPath install --id $package.Id --source winget --silent --scope machine --accept-package-agreements --accept-source-agreements 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq $WINGET_SUCCESS) {
        Write-Log "$($package.Name) installed successfully."
    }
    elseif ($exitCode -eq $WINGET_ALREADY_INSTALLED) {
        Write-Log "$($package.Name) is already installed."
    }
    elseif ($exitCode -eq $WINGET_MISSING_DEPENDENCY) {
        Write-Log "$($package.Name) installed successfully (unmanaged dependency warning ignored)."
    }
    elseif ($exitCode -eq $WINGET_PACKAGE_IN_USE) {
        Write-Log "FAILED: $($package.Name). Package in use (APPINSTALLER_CLI_ERROR_INSTALL_PACKAGE_IN_USE)."
        $failed = $true
    }
    else {
        Write-Log "FAILED: $($package.Name). Exit code: $exitCode"
        Write-Log ($output -join "`n")
        $failed = $true
    }
}

if ($failed) {
    Exit-WithError "One or more winget package installations failed. See log above."
}

Write-Log "Install-Software complete."
Exit 0
#endregion
