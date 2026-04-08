# Prerequisites:
#   - PowerShell 7.x (pwsh)
#   - Authenticated Azure session (Connect-AzAccount)
#   - Terraform CLI in PATH with initialized state in the repo root
#   - openvpn installed and in PATH: install via 'sudo apt-get install -y openvpn' (Debian/Ubuntu)
#     or 'winget install OpenVPNTechnologies.OpenVPN' (Windows)
#   - sudo access (Linux/macOS) for openvpn tunnel creation
#   - dig (Linux/macOS): install via 'sudo apt-get install -y dnsutils' (Debian/Ubuntu)
#     or 'sudo yum install -y bind-utils' (RHEL/CentOS). Used for DNS resolution against
#     the sandbox DNS server. On Windows, Resolve-DnsName is used instead.

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $true)]
    [string]$VirtualWanName,

    [Parameter(Mandatory = $true)]
    [string]$VirtualHubName,

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $false)]
    [string]$StorageShareName,

    [Parameter(Mandatory = $false)]
    [string]$MssqlServerFqdn,

    [Parameter(Mandatory = $false)]
    [string]$MssqlDatabaseName,

    [Parameter(Mandatory = $false)]
    [string]$MysqlServerFqdn,

    [Parameter(Mandatory = $false)]
    [string]$MysqlDatabaseName
)

#region functions
function Write-Log {
    param([string]$msg)
    Write-Output "$(Get-Date -Format FileDateTimeUniversal) : $msg"
}

function Write-TestResult {
    param(
        [string]$module,
        [string]$status,
        [string]$msg
    )
    Write-Log ("[MODULE:$module] [$status] $msg")
}

function Test-TcpPort {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMs = 10000
    )

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcp.BeginConnect($HostName, $Port, $null, $null)
        $waited = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)

        if ($waited -and $tcp.Connected) {
            $tcp.Close()
            return $true
        }

        $tcp.Close()
        return $false
    }
    catch {
        return $false
    }
}

function Resolve-DnsViaServer {
    param(
        [string]$Name,
        [string]$DnsServer,
        [string]$PreferSubnet
    )

    if ($IsWindows) {
        $result = Resolve-DnsName -Name $Name -Server $DnsServer -Type A -ErrorAction Stop
        $ips = ($result | Where-Object { $_.QueryType -eq 'A' }).IPAddress
    }
    else {
        $result = & dig "@$DnsServer" $Name +short 2>&1
        $ips = @($result -split "`n" | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' })
    }

    if (-not $ips -or $ips.Count -eq 0) { return $null }

    # If a preferred subnet is specified, prefer IPs matching it
    if ($PreferSubnet) {
        $preferred = $ips | Where-Object { $_ -like $PreferSubnet }
        if ($preferred) { return ($preferred | Select-Object -First 1) }
    }

    return ($ips | Select-Object -First 1)
}

function Get-TunInterfaceIp {
    # Get the IP address assigned to the tun/tap VPN interface
    if ($IsLinux -or $IsMacOS) {
        # Search all tun interfaces (tun0, tun1, etc.)
        $ifOutput = & ip -4 addr show 2>&1 | Out-String
        if ($ifOutput -match 'tun\d+.*?inet\s+(\d+\.\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
        # Also try matching the VPN client address range (10.4.x.x)
        if ($ifOutput -match 'inet\s+(10\.4\.\d+\.\d+)') {
            return $Matches[1]
        }
        return $null
    }
    else {
        # On Windows, OpenVPN creates a TAP adapter
        $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -match '^10\.4\.' }
        if ($adapters) {
            return $adapters[0].IPAddress
        }
        return $null
    }
}

function Test-RouteExists {
    param([string]$Prefix)

    if ($IsLinux -or $IsMacOS) {
        $routes = & ip route 2>&1
        return ($routes -match [regex]::Escape($Prefix))
    }
    else {
        $route = Get-NetRoute -DestinationPrefix $Prefix -ErrorAction SilentlyContinue
        return ($null -ne $route)
    }
}
#endregion

#region main
$WarningPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$moduleName = 'integration'
$dnsServer = '10.1.1.4'

# Verify dig is available on Linux/macOS (prerequisite for DNS resolution against the sandbox DNS server)
if (-not $IsWindows) {
    if (-not (Get-Command dig -ErrorAction SilentlyContinue)) {
        Write-TestResult $moduleName 'FAIL' "P2S VPN: dig command not found in PATH. Install dnsutils (Debian/Ubuntu: sudo apt-get install -y dnsutils) or bind-utils (RHEL/CentOS: sudo yum install -y bind-utils)."
        Write-TestResult $moduleName 'SUMMARY' "Passed: 0 Failed: 1 Total: 1"
        exit 1
    }
}

Write-Log "Starting integration test: P2S VPN connectivity via OpenVPN..."
Write-Log "Parameters: ResourceGroupName='$ResourceGroupName' VirtualWanName='$VirtualWanName' VirtualHubName='$VirtualHubName'"

$passed = 0
$failed = 0

# Verify sudo access (required for openvpn on Linux)
if ($IsLinux -or $IsMacOS) {
    Write-Log 'Validating sudo access...'
    # Check if passwordless sudo is available (CI/CD agents)
    & sudo -n true 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'Passwordless sudo available.'
    }
    else {
        # Fall back to interactive prompt if running in a terminal
        if ([System.Environment]::UserInteractive -or (Test-Path /dev/tty)) {
            Write-Log 'Passwordless sudo not available, requesting credentials...'
            & sudo -v 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-TestResult $moduleName 'FAIL' 'P2S VPN: sudo access required but authentication failed.'
                Write-TestResult $moduleName 'SUMMARY' "Passed: 0 Failed: 1 Total: 1"
                exit 1
            }
        }
        else {
            Write-TestResult $moduleName 'FAIL' 'P2S VPN: sudo access required but not available (non-interactive, no passwordless sudo). Configure NOPASSWD in sudoers for this user.'
            Write-TestResult $moduleName 'SUMMARY' "Passed: 0 Failed: 1 Total: 1"
            exit 1
        }
    }
}

# Verify openvpn is installed
if (-not (Get-Command openvpn -ErrorAction SilentlyContinue)) {
    Write-TestResult $moduleName 'FAIL' 'P2S VPN: openvpn command not found in PATH. Install OpenVPN and retry.'
    $failed++
    $total = $passed + $failed
    Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
    exit 1
}

# Create temp directory for VPN artifacts
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "vwan-integration-test-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$caCertPath = Join-Path $tempDir 'ca.pem'
$clientCertPath = Join-Path $tempDir 'client.crt'
$clientKeyPath = Join-Path $tempDir 'client.key'
$ovpnConfigPath = Join-Path $tempDir 'vpn.ovpn'
$ovpnLogPath = Join-Path $tempDir 'openvpn.log'
$ovpnPidPath = Join-Path $tempDir 'openvpn.pid'

$vpnStarted = $false

try {
    # ========================================
    # Phase 0: VPN Tunnel Setup
    # ========================================
    Write-Log 'Phase 0: Establishing P2S VPN tunnel...'

    # Step 1: Export certificates
    Write-Log 'Retrieving certificates from terraform outputs and Key Vault...'

    $repoRoot = Split-Path $PSScriptRoot -Parent

    Push-Location $repoRoot
    $rootCertPem = terraform output -raw root_cert_pem 2>&1
    $rootCertExitCode = $LASTEXITCODE
    $clientCertPem = terraform output -raw client_cert_pem 2>&1
    $clientCertExitCode = $LASTEXITCODE
    Pop-Location

    if ($rootCertExitCode -ne 0) {
        Write-TestResult $moduleName 'FAIL' "P2S VPN: Failed to read root_cert_pem from terraform output: $rootCertPem"
        $failed++
        throw 'Terraform output root_cert_pem not available'
    }

    if ($clientCertExitCode -ne 0) {
        Write-TestResult $moduleName 'FAIL' "P2S VPN: Failed to read client_cert_pem from terraform output: $clientCertPem"
        $failed++
        throw 'Terraform output client_cert_pem not available'
    }

    # Temporarily enable public access on Key Vault to retrieve the client private key
    Write-Log "Enabling public network access on Key Vault '$KeyVaultName'..."
    az keyvault update --name $KeyVaultName --resource-group $ResourceGroupName --public-network-access Enabled --only-show-errors | Out-Null
    try {
        $clientKeyPem = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'p2svpn-client-private-key-pem' -AsPlainText -ErrorAction Stop)
    }
    finally {
        Write-Log "Disabling public network access on Key Vault '$KeyVaultName'..."
        az keyvault update --name $KeyVaultName --resource-group $ResourceGroupName --public-network-access Disabled --only-show-errors | Out-Null
    }

    # Write cert files (join array output with newlines — PowerShell captures multi-line output as string arrays)
    Set-Content -Path $caCertPath -Value ($rootCertPem -join "`n") -NoNewline
    Set-Content -Path $clientCertPath -Value ($clientCertPem -join "`n") -NoNewline
    Set-Content -Path $clientKeyPath -Value ($clientKeyPem -join "`n") -NoNewline

    # Restrict permissions on private key
    if ($IsLinux -or $IsMacOS) {
        & chmod 600 $clientKeyPath
    }

    Write-Log 'Certificates exported successfully.'

    # Step 2: Get VPN server hostname from P2S VPN gateway
    Write-Log 'Retrieving VPN gateway configuration...'

    $p2sGateway = Get-AzP2sVpnGateway -ResourceGroupName $ResourceGroupName -ErrorAction Stop |
        Where-Object { $_.VirtualHub.Id -match $VirtualHubName } |
        Select-Object -First 1

    if (-not $p2sGateway) {
        Write-TestResult $moduleName 'FAIL' "P2S VPN: No P2S VPN gateway found for hub '$VirtualHubName'"
        $failed++
        throw 'P2S VPN gateway not found'
    }

    # Generate VPN profile to get the server hostname
    $profileResponse = Get-AzP2sVpnGatewayVpnProfile -ResourceGroupName $ResourceGroupName -Name $p2sGateway.Name -AuthenticationMethod 'EAPTLS' -ErrorAction Stop
    $profileUrl = $profileResponse.ProfileUrl

    if (-not $profileUrl) {
        Write-TestResult $moduleName 'FAIL' 'P2S VPN: Failed to generate VPN profile URL'
        $failed++
        throw 'VPN profile generation failed'
    }

    # Download and extract the VPN profile to get the server hostname
    $profileZipPath = Join-Path $tempDir 'vpnprofile.zip'
    $profileExtractPath = Join-Path $tempDir 'vpnprofile'
    Invoke-WebRequest -Uri $profileUrl -OutFile $profileZipPath -ErrorAction Stop
    Expand-Archive -Path $profileZipPath -DestinationPath $profileExtractPath -Force

    # Parse the OpenVPN config from the downloaded profile
    $genericOvpnPath = Join-Path $profileExtractPath 'OpenVPN' 'vpnconfig.ovpn'

    if (-not (Test-Path $genericOvpnPath)) {
        # Try alternate path structure
        $genericOvpnPath = Get-ChildItem -Path $profileExtractPath -Recurse -Filter '*.ovpn' | Select-Object -First 1 -ExpandProperty FullName
    }

    if ($genericOvpnPath -and (Test-Path $genericOvpnPath)) {
        # Use the Azure-provided OpenVPN config as a base, then replace cert/key references
        $ovpnContent = Get-Content -Path $genericOvpnPath -Raw

        # Remove inline cert/key blocks if present (we'll use file references instead)
        $ovpnContent = $ovpnContent -replace '(?s)<ca>.*?</ca>', ''
        $ovpnContent = $ovpnContent -replace '(?s)<cert>.*?</cert>', ''
        $ovpnContent = $ovpnContent -replace '(?s)<key>.*?</key>', ''

        # Remove the 'log' directive from the Azure config (we pass --log on the command line)
        $ovpnContent = $ovpnContent -replace '(?m)^log\s+.*$', ''

        # Enable disable-dco for OpenVPN 2.6+ (DCO kernel module may not be available)
        $ovpnContent = $ovpnContent -replace '(?m)^#disable-dco\s*$', 'disable-dco'

        # Append cert file references
        # Use system CA bundle for server cert verification (Azure VPN gateway uses Microsoft public CA),
        # and client cert/key for mutual TLS authentication
        $systemCaBundle = if ($IsLinux) { '/etc/ssl/certs/ca-certificates.crt' } elseif ($IsMacOS) { '/etc/ssl/cert.pem' } else { $caCertPath }
        $ovpnContent = $ovpnContent.TrimEnd() + "`nca $systemCaBundle`ncert $clientCertPath`nkey $clientKeyPath`n"
    }
    else {
        # Fallback: parse the AzureVPN XML config for the server hostname
        $azureVpnConfigPath = Get-ChildItem -Path $profileExtractPath -Recurse -Filter 'azurevpnconfig.xml' | Select-Object -First 1 -ExpandProperty FullName

        if (-not $azureVpnConfigPath) {
            Write-TestResult $moduleName 'FAIL' 'P2S VPN: Could not find VPN config in downloaded profile'
            $failed++
            throw 'VPN config not found in profile'
        }

        [xml]$vpnConfig = Get-Content -Path $azureVpnConfigPath
        $vpnServerHostname = $vpnConfig.AzVpnProfile.ServerAddress

        if (-not $vpnServerHostname) {
            Write-TestResult $moduleName 'FAIL' 'P2S VPN: Could not parse server address from VPN profile'
            $failed++
            throw 'Server address not found in VPN config'
        }

        # Construct OpenVPN config
        $systemCaBundle = if ($IsLinux) { '/etc/ssl/certs/ca-certificates.crt' } elseif ($IsMacOS) { '/etc/ssl/cert.pem' } else { $caCertPath }
        $ovpnContent = @"
client
dev tun
proto tcp
remote $vpnServerHostname 443
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verb 3
ca $systemCaBundle
cert $clientCertPath
key $clientKeyPath
"@
    }

    Set-Content -Path $ovpnConfigPath -Value $ovpnContent -NoNewline
    # Save a copy for manual debugging
    Copy-Item -Path $ovpnConfigPath -Destination '/tmp/debug-vpn.ovpn' -Force
    Copy-Item -Path $caCertPath -Destination '/tmp/debug-ca.pem' -Force
    Copy-Item -Path $clientCertPath -Destination '/tmp/debug-client.crt' -Force
    Copy-Item -Path $clientKeyPath -Destination '/tmp/debug-client.key' -Force
    $debugOvpn = (Get-Content '/tmp/debug-vpn.ovpn' -Raw) -replace [regex]::Escape($caCertPath), '/tmp/debug-ca.pem' -replace [regex]::Escape($clientCertPath), '/tmp/debug-client.crt' -replace [regex]::Escape($clientKeyPath), '/tmp/debug-client.key'
    Set-Content -Path '/tmp/debug-vpn.ovpn' -Value $debugOvpn -NoNewline
    Write-Log 'OpenVPN config file generated.'

    # Step 3: Start OpenVPN tunnel
    Write-Log 'Starting OpenVPN tunnel...'

    $ovpnStderrPath = Join-Path $tempDir 'openvpn-stderr.log'

    if ($IsLinux -or $IsMacOS) {
        # Run openvpn in background, capturing stderr separately for diagnostics
        & sudo bash -c "openvpn --config '$ovpnConfigPath' --log '$ovpnLogPath' --writepid '$ovpnPidPath' 2>'$ovpnStderrPath' </dev/null &"
        $ovpnExitCode = $LASTEXITCODE
    }
    else {
        Start-Process -FilePath 'openvpn' -ArgumentList "--config `"$ovpnConfigPath`" --log `"$ovpnLogPath`" --service-pipe" -WindowStyle Hidden
        $ovpnExitCode = 0
        # On Windows, OpenVPN runs in the foreground by default in service mode; we'll use Start-Process
    }

    if ($ovpnExitCode -ne 0) {
        $stderrContent = if (Test-Path $ovpnStderrPath) { Get-Content -Path $ovpnStderrPath -Raw -ErrorAction SilentlyContinue } else { '' }
        Write-TestResult $moduleName 'FAIL' "P2S VPN: OpenVPN failed to start (exit code $ovpnExitCode). Stderr: $stderrContent"
        $failed++
        throw 'OpenVPN failed to start'
    }

    $vpnStarted = $true

    # Wait briefly then verify the daemon is running and log file exists
    Start-Sleep -Seconds 5
    if (-not (Test-Path $ovpnLogPath)) {
        # Check if openvpn process is running at all
        $ovpnRunning = if ($IsLinux -or $IsMacOS) { & pgrep -x openvpn 2>/dev/null } else { $null }
        $stderrContent = if (Test-Path $ovpnStderrPath) {
            & sudo cat $ovpnStderrPath 2>/dev/null
        } else { '' }
        $diagMsg = "OpenVPN log file not created at '$ovpnLogPath'."
        if (-not $ovpnRunning) {
            $diagMsg += ' OpenVPN process is not running — it likely exited immediately after starting.'
        } else {
            $diagMsg += " OpenVPN process is running (PID: $ovpnRunning) but log file missing."
        }
        if ($stderrContent) { $diagMsg += " Stderr: $stderrContent" }
        # Also dump the config for debugging
        $configContent = Get-Content -Path $ovpnConfigPath -Raw -ErrorAction SilentlyContinue
        Write-Log "OpenVPN config contents:`n$configContent"
        Write-TestResult $moduleName 'FAIL' "P2S VPN: $diagMsg"
        $failed++
        throw 'OpenVPN log file not created'
    }

    # Poll for tunnel establishment
    $maxWaitSeconds = 120
    $pollInterval = 5
    $elapsed = 0
    $tunnelEstablished = $false

    while ($elapsed -lt $maxWaitSeconds) {
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval

        if (Test-Path $ovpnLogPath) {
            $logContent = if ($IsLinux -or $IsMacOS) {
                & sudo cat $ovpnLogPath 2>/dev/null
            } else {
                Get-Content -Path $ovpnLogPath -Raw -ErrorAction SilentlyContinue
            }
            if ($logContent -match 'Initialization Sequence Completed') {
                $tunnelEstablished = $true
                Write-Log "VPN tunnel established after $elapsed seconds."
                break
            }

            if ($logContent -match 'AUTH_FAILED|TLS Error|Connection refused') {
                Write-Log "OpenVPN error detected in log after $elapsed seconds."
                break
            }
        }

        if ($elapsed % 30 -eq 0) {
            Write-Log "Waiting for VPN tunnel... ($elapsed/$maxWaitSeconds seconds)"
        }
    }

    if (-not $tunnelEstablished) {
        $logTail = ''
        if (Test-Path $ovpnLogPath) {
            $logTail = if ($IsLinux -or $IsMacOS) {
                & sudo tail -n 20 $ovpnLogPath 2>/dev/null | Out-String
            } else {
                Get-Content -Path $ovpnLogPath -Tail 20 -ErrorAction SilentlyContinue | Out-String
            }
        }
        Write-TestResult $moduleName 'FAIL' "P2S VPN: Tunnel did not establish within $maxWaitSeconds seconds. Log tail:`n$logTail"
        $failed++
        throw 'VPN tunnel establishment timed out'
    }

    # Allow a few seconds for routes to propagate
    Start-Sleep -Seconds 5

    # ========================================
    # Test 1: VPN tunnel established with correct client IP
    # ========================================
    Write-Log 'Test 1: VPN tunnel established with correct client IP...'
    try {
        $vpnIp = Get-TunInterfaceIp

        if ($vpnIp -and $vpnIp -match '^10\.4\.') {
            Write-TestResult $moduleName 'PASS' "P2S VPN: Tunnel established with client IP $vpnIp (in 10.4.0.0/16)"
            $passed++
        }
        elseif ($vpnIp) {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: Client IP $vpnIp is not in expected range 10.4.0.0/16"
            $failed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' 'P2S VPN: Could not determine VPN client IP address'
            $failed++
        }

        # Check routes
        $routeIssues = @()
        foreach ($prefix in @('10.1.0.0/16', '10.2.0.0/16', '10.3.0.0/16')) {
            if (-not (Test-RouteExists $prefix)) {
                $routeIssues += $prefix
            }
        }

        if ($routeIssues.Count -eq 0) {
            Write-TestResult $moduleName 'PASS' 'P2S VPN: Routes to 10.1.0.0/16, 10.2.0.0/16, 10.3.0.0/16 are present'
            $passed++
        }
        else {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: Missing routes: $($routeIssues -join ', ')"
            $failed++
        }
    }
    catch {
        Write-TestResult $moduleName 'FAIL' "P2S VPN: Test 1 exception: $_"
        $failed++
    }

    # ========================================
    # Test 2: DNS resolution - jumpwin1 (IaaS)
    # Required module: vnet_app
    # ========================================
    # Read resource_names to check module deployment
    Push-Location $repoRoot
    $resourceNamesJson = terraform output -json resource_names 2>&1
    Pop-Location
    $resourceNames = $resourceNamesJson | ConvertFrom-Json -AsHashtable

    $jumpwin1Deployed = [bool]$resourceNames['virtual_machine_jumpwin1']
    $jumplinux1Deployed = [bool]$resourceNames['virtual_machine_jumplinux1']
    $storageDeployed = [bool]$resourceNames['storage_account']

    if ($jumpwin1Deployed) {
        Write-Log 'Test 2: DNS resolution - jumpwin1...'
        try {
            $ip = Resolve-DnsViaServer -Name 'jumpwin1.mysandbox.local' -DnsServer $dnsServer -PreferSubnet '10.2.*'
            if ($ip -and $ip -match '^10\.2\.') {
                Write-TestResult $moduleName 'PASS' "P2S VPN: jumpwin1.mysandbox.local resolved to $ip (in 10.2.0.0/16)"
                $passed++
            }
            elseif ($ip) {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: jumpwin1.mysandbox.local resolved to $ip (expected 10.2.x.x)"
                $failed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' 'P2S VPN: jumpwin1.mysandbox.local DNS resolution returned no result'
                $failed++
            }
        }
        catch {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: jumpwin1.mysandbox.local DNS resolution failed: $_"
            $failed++
        }
    }
    else {
        Write-Log 'Test 2: SKIPPED - vnet_app module not deployed (virtual_machine_jumpwin1 not in resource_names)'
    }

    # ========================================
    # Test 3: DNS resolution - jumplinux1 (IaaS)
    # Required module: vm_jumpbox_linux
    # ========================================
    if ($jumplinux1Deployed) {
        Write-Log 'Test 3: DNS resolution - jumplinux1...'
        try {
            $ip = Resolve-DnsViaServer -Name 'jumplinux1.mysandbox.local' -DnsServer $dnsServer -PreferSubnet '10.2.*'
            if ($ip -and $ip -match '^10\.2\.') {
                Write-TestResult $moduleName 'PASS' "P2S VPN: jumplinux1.mysandbox.local resolved to $ip (in 10.2.0.0/16)"
                $passed++
            }
            elseif ($ip) {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: jumplinux1.mysandbox.local resolved to $ip (expected 10.2.x.x)"
                $failed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' 'P2S VPN: jumplinux1.mysandbox.local DNS resolution returned no result'
                $failed++
            }
        }
        catch {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: jumplinux1.mysandbox.local DNS resolution failed: $_"
            $failed++
        }
    }
    else {
        Write-Log 'Test 3: SKIPPED - vm_jumpbox_linux module not deployed (virtual_machine_jumplinux1 not in resource_names)'
    }

    # ========================================
    # Test 4: RDP (port 3389) connectivity to jumpwin1 (IaaS)
    # Required module: vnet_app
    # ========================================
    if ($jumpwin1Deployed) {
        Write-Log 'Test 4: RDP (port 3389) connectivity to jumpwin1...'
        try {
            $jumpwin1Ip = Resolve-DnsViaServer -Name 'jumpwin1.mysandbox.local' -DnsServer $dnsServer -PreferSubnet '10.2.*'
            if (-not $jumpwin1Ip) {
                Write-TestResult $moduleName 'FAIL' 'P2S VPN: jumpwin1.mysandbox.local DNS resolution failed for TCP test'
                $failed++
            }
            else {
                $rdpReachable = Test-TcpPort -HostName $jumpwin1Ip -Port 3389
                if ($rdpReachable) {
                    Write-TestResult $moduleName 'PASS' "P2S VPN: TCP connection to jumpwin1.mysandbox.local:3389 succeeded (via $jumpwin1Ip)"
                    $passed++
                }
                else {
                    Write-TestResult $moduleName 'FAIL' "P2S VPN: TCP connection to jumpwin1.mysandbox.local:3389 failed (tried $jumpwin1Ip)"
                    $failed++
                }
            }
        }
        catch {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: RDP connectivity test failed: $_"
            $failed++
        }
    }
    else {
        Write-Log 'Test 4: SKIPPED - vnet_app module not deployed (virtual_machine_jumpwin1 not in resource_names)'
    }

    # ========================================
    # Test 5: SSH (port 22) connectivity to jumplinux1 (IaaS)
    # Required module: vm_jumpbox_linux
    # ========================================
    if ($jumplinux1Deployed) {
        Write-Log 'Test 5: SSH (port 22) connectivity to jumplinux1...'
        try {
            $jumplinux1Ip = Resolve-DnsViaServer -Name 'jumplinux1.mysandbox.local' -DnsServer $dnsServer -PreferSubnet '10.2.*'
            if (-not $jumplinux1Ip) {
                Write-TestResult $moduleName 'FAIL' 'P2S VPN: jumplinux1.mysandbox.local DNS resolution failed for TCP test'
                $failed++
            }
            else {
                $sshReachable = Test-TcpPort -HostName $jumplinux1Ip -Port 22
                if ($sshReachable) {
                    Write-TestResult $moduleName 'PASS' "P2S VPN: TCP connection to jumplinux1.mysandbox.local:22 succeeded (via $jumplinux1Ip)"
                    $passed++
                }
                else {
                    Write-TestResult $moduleName 'FAIL' "P2S VPN: TCP connection to jumplinux1.mysandbox.local:22 failed (tried $jumplinux1Ip)"
                    $failed++
                }
            }
        }
        catch {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: SSH connectivity test failed: $_"
            $failed++
        }
    }
    else {
        Write-Log 'Test 5: SKIPPED - vm_jumpbox_linux module not deployed (virtual_machine_jumplinux1 not in resource_names)'
    }

    # ========================================
    # Test 6: SMB (port 445) connectivity to Azure Files (PaaS)
    # Required module: vnet_app
    # ========================================
    if ($storageDeployed -and $StorageAccountName) {
        Write-Log 'Test 6: SMB (port 445) connectivity to Azure Files...'
        $storageFqdn = "$StorageAccountName.file.core.windows.net"
        try {
            # DNS resolution
            $ip = Resolve-DnsViaServer -Name $storageFqdn -DnsServer $dnsServer
            if ($ip -and $ip -match '^10\.2\.') {
                Write-TestResult $moduleName 'PASS' "P2S VPN: $storageFqdn resolved to private IP $ip"
                $passed++
            }
            elseif ($ip) {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: $storageFqdn resolved to $ip (expected 10.2.x.x privatelink IP)"
                $failed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: $storageFqdn DNS resolution returned no result"
                $failed++
            }

            # TCP connectivity (use resolved IP to bypass .NET system DNS)
            $smbTarget = if ($ip) { $ip } else { $storageFqdn }
            $smbReachable = Test-TcpPort -HostName $smbTarget -Port 445
            if ($smbReachable) {
                Write-TestResult $moduleName 'PASS' "P2S VPN: TCP connection to ${storageFqdn}:445 succeeded"
                $passed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: TCP connection to ${storageFqdn}:445 failed"
                $failed++
            }
        }
        catch {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: SMB connectivity test failed: $_"
            $failed++
        }
    }
    else {
        Write-Log 'Test 6: SKIPPED - vnet_app module not deployed (storage_account not in resource_names)'
    }

    # ========================================
    # Test 7: TDS (port 1433) connectivity to Azure SQL Database (PaaS)
    # Required module: mssql
    # ========================================
    if ($MssqlServerFqdn) {
        Write-Log 'Test 7: TDS (port 1433) connectivity to Azure SQL Database...'
        try {
            # DNS resolution
            $ip = Resolve-DnsViaServer -Name $MssqlServerFqdn -DnsServer $dnsServer
            if ($ip -and $ip -match '^10\.') {
                Write-TestResult $moduleName 'PASS' "P2S VPN: $MssqlServerFqdn resolved to private IP $ip"
                $passed++
            }
            elseif ($ip) {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: $MssqlServerFqdn resolved to $ip (expected private IP)"
                $failed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: $MssqlServerFqdn DNS resolution returned no result"
                $failed++
            }

            # TCP connectivity (use resolved IP to bypass .NET system DNS)
            $tdsTarget = if ($ip) { $ip } else { $MssqlServerFqdn }
            $tdsReachable = Test-TcpPort -HostName $tdsTarget -Port 1433
            if ($tdsReachable) {
                Write-TestResult $moduleName 'PASS' "P2S VPN: TCP connection to ${MssqlServerFqdn}:1433 succeeded"
                $passed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: TCP connection to ${MssqlServerFqdn}:1433 failed"
                $failed++
            }
        }
        catch {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: Azure SQL connectivity test failed: $_"
            $failed++
        }
    }
    else {
        Write-Log 'Test 7: SKIPPED - mssql module not deployed (MssqlServerFqdn not provided)'
    }

    # ========================================
    # Test 8: MySQL (port 3306) connectivity to Azure MySQL Flexible Server (PaaS)
    # Required module: mysql
    # ========================================
    if ($MysqlServerFqdn) {
        Write-Log 'Test 8: MySQL (port 3306) connectivity to Azure MySQL Flexible Server...'
        try {
            # DNS resolution
            $ip = Resolve-DnsViaServer -Name $MysqlServerFqdn -DnsServer $dnsServer
            if ($ip -and $ip -match '^10\.') {
                Write-TestResult $moduleName 'PASS' "P2S VPN: $MysqlServerFqdn resolved to private IP $ip"
                $passed++
            }
            elseif ($ip) {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: $MysqlServerFqdn resolved to $ip (expected private IP)"
                $failed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: $MysqlServerFqdn DNS resolution returned no result"
                $failed++
            }

            # TCP connectivity (use resolved IP to bypass .NET system DNS)
            $mysqlTarget = if ($ip) { $ip } else { $MysqlServerFqdn }
            $mysqlReachable = Test-TcpPort -HostName $mysqlTarget -Port 3306
            if ($mysqlReachable) {
                Write-TestResult $moduleName 'PASS' "P2S VPN: TCP connection to ${MysqlServerFqdn}:3306 succeeded"
                $passed++
            }
            else {
                Write-TestResult $moduleName 'FAIL' "P2S VPN: TCP connection to ${MysqlServerFqdn}:3306 failed"
                $failed++
            }
        }
        catch {
            Write-TestResult $moduleName 'FAIL' "P2S VPN: MySQL connectivity test failed: $_"
            $failed++
        }
    }
    else {
        Write-Log 'Test 8: SKIPPED - mysql module not deployed (MysqlServerFqdn not provided)'
    }
}
catch {
    if ($_.Exception.Message -notmatch 'VPN tunnel establishment timed out|Terraform output|P2S VPN gateway not found|VPN profile generation failed|VPN config not found') {
        Write-TestResult $moduleName 'FAIL' "P2S VPN: Unexpected exception: $_"
        $failed++
    }
}
finally {
    # ========================================
    # Teardown: Stop VPN and clean up
    # ========================================
    Write-Log 'Tearing down VPN tunnel and cleaning up...'

    if ($vpnStarted) {
        # Kill OpenVPN process
        if (Test-Path $ovpnPidPath) {
            $ovpnPid = Get-Content -Path $ovpnPidPath -ErrorAction SilentlyContinue
            if ($ovpnPid) {
                try {
                    if ($IsLinux -or $IsMacOS) {
                        & sudo kill $ovpnPid 2>&1 | Out-Null
                    }
                    else {
                        Stop-Process -Id $ovpnPid -Force -ErrorAction SilentlyContinue
                    }
                    Write-Log "OpenVPN process (PID $ovpnPid) terminated."
                }
                catch {
                    Write-Log "WARNING: Could not terminate OpenVPN process (PID $ovpnPid): $_"
                }
            }
        }
        else {
            # Fallback: kill by process name
            try {
                if ($IsLinux -or $IsMacOS) {
                    & sudo pkill -f "openvpn.*$ovpnConfigPath" 2>&1 | Out-Null
                }
                else {
                    Get-Process -Name 'openvpn' -ErrorAction SilentlyContinue | Stop-Process -Force
                }
            }
            catch {
                Write-Log "WARNING: Could not terminate OpenVPN process by name: $_"
            }
        }
    }

    # Remove temp directory and all artifacts
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Temp directory '$tempDir' removed."
    }

    Write-Log 'Cleanup complete.'
}

# Summary
$total = $passed + $failed
Write-TestResult $moduleName 'SUMMARY' "Passed: $passed Failed: $failed Total: $total"
if ($failed -gt 0) { exit 1 } else { exit 0 }
#endregion
