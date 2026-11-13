# Validates a Windows image on the Azure VM Image Builder build VM, after customization and before the image is
# generalized and distributed. Any failed check exits with a non-zero code, which stops the build, because the image
# templates set continueDistributeOnFailure = false. Runs elevated, as SYSTEM, under the AIB PowerShell validator.
#
# Checks for every image:
#   * No Critical or Security updates are pending (using the same search criteria as the WindowsUpdate customizers).
# Image-specific checks:
#   * adds:     The AD-Domain-Services feature is NOT installed (Sysprep doesn't support the AD DS role).
#   * jumpwin:  RSAT-ADDS and RSAT-DNS-Server are installed, VS Code, SSMS and MySQL Workbench are present, and
#               Configure Automatic Updates is 4.
#   * mssqlwin: The SQL Server (MSSQLSERVER) service and binaries are present, and Configure Automatic Updates is 4.

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('adds', 'jumpwin', 'mssqlwin')]
    [string]$ImageName,

    [Parameter(Mandatory = $true)]
    [string]$UpdateSearchCriteria
)

#region functions
function Write-Log {
    param( [string] $msg)
    "$(Get-Date -Format FileDateTimeUniversal) : $msg" | Write-Host
}

$script:failed = 0

function Write-CheckResult {
    param(
        [bool]$Passed,
        [string]$Message
    )

    if ($Passed) {
        Write-Log "[PASS] $Message"
    }
    else {
        Write-Log "[FAIL] $Message"
        $script:failed++
    }
}

function Test-FeatureInstalled {
    param( [string]$Name )
    $feature = Get-WindowsFeature -Name $Name -ErrorAction SilentlyContinue
    return ($null -ne $feature -and $feature.InstallState -eq 'Installed')
}

function Test-AutomaticUpdate {
    $settings = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
    Write-CheckResult ($null -ne $settings -and $settings.NoAutoUpdate -eq 0 -and $settings.AUOptions -eq 4) `
        "Configure Automatic Updates: NoAutoUpdate = $($settings.NoAutoUpdate), AUOptions = $($settings.AUOptions) (expected 0 and 4)"
}

function Test-FilePresent {
    param(
        [string]$Name,
        [string]$Path
    )
    $file = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($file) {
        Write-CheckResult $true "$Name present at '$($file.FullName)' (version: $($file.VersionInfo.ProductVersion))"
    }
    else {
        Write-CheckResult $false "$Name not found at '$Path'"
    }
}
#endregion

#region main
Write-Log "Running '$PSCommandPath' for image '$ImageName'..."

# Pending Critical and Security updates
try {
    $searcher = (New-Object -ComObject 'Microsoft.Update.Session').CreateUpdateSearcher()
    $result = $searcher.Search($UpdateSearchCriteria)
    $titles = @($result.Updates | ForEach-Object { $_.Title })
    Write-CheckResult ($titles.Count -eq 0) "Pending Critical or Security updates: $($titles.Count) $(if ($titles.Count -gt 0) { '(' + ($titles -join '; ') + ')' })"
}
catch {
    Write-CheckResult $false "Couldn't search for pending updates: $_"
}

switch ($ImageName) {
    'adds' {
        Write-CheckResult (-not (Test-FeatureInstalled 'AD-Domain-Services')) 'Windows feature AD-Domain-Services is not installed'
    }

    'jumpwin' {
        foreach ($featureName in @('RSAT-ADDS', 'RSAT-DNS-Server')) {
            Write-CheckResult (Test-FeatureInstalled $featureName) "Windows feature $featureName is installed"
        }

        Test-FilePresent 'Visual Studio Code' 'C:\Program Files\Microsoft VS Code\Code.exe'
        Test-FilePresent 'SQL Server Management Studio' 'C:\Program Files\Microsoft SQL Server Management Studio*\Release\Common7\IDE\Ssms.exe'
        Test-FilePresent 'MySQL Workbench' 'C:\Program Files\MySQL\MySQL Workbench*\MySQL*Workbench.exe'
        Test-AutomaticUpdate
    }

    'mssqlwin' {
        $service = Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue
        Write-CheckResult ($null -ne $service) 'SQL Server (MSSQLSERVER) service is present'
        Test-FilePresent 'SQL Server database engine' 'C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\Binn\sqlservr.exe'
        Test-AutomaticUpdate
    }
}

if ($script:failed -gt 0) {
    Write-Log "Image '$ImageName' failed $($script:failed) check(s)."
    Exit 1
}

Write-Log "Image '$ImageName' passed all checks."
Exit 0
#endregion
