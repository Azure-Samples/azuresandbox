#requires -Version 7.2

function Get-SandboxProgress {
    param(
        [AllowEmptyCollection()][string[]]$Lines,
        [ValidateSet('apply', 'unit-test')][string]$Stage = 'apply'
    )
    $latest = [ordered]@{}
    $counts = @{}
    $resourcePattern = '^((?:module\.[A-Za-z_][A-Za-z0-9_-]*(?:\[[0-9]+\])?\.)*(?:azurerm_[A-Za-z0-9_]+|azapi_[A-Za-z0-9_]+|azuread_[A-Za-z0-9_]+|random_[A-Za-z0-9_]+|time_[A-Za-z0-9_]+|tls_[A-Za-z0-9_]+|cloudinit_[A-Za-z0-9_]+|null_resource|terraform_data)\.[A-Za-z_][A-Za-z0-9_-]*(?:\[[0-9]+\])?): (Still (?:creating|modifying|destroying)\.\.\. \[[0-9hms ]+ elapsed\]|(?:Creating|Modifying|Destroying)\.\.\.|(?:Creation|Modifications|Destruction) complete after [0-9hms ]+)'
    $modules = @('vnet-shared', 'vnet-app', 'vm-jumpbox-linux', 'vm-mssql-win',
        'mssql', 'mysql', 'vwan', 'avd', 'petstore', 'vnet-onprem', 'integration')
    $integrations = @{
        'SSH: jumpwin1 -> jumplinux1' = 'SSH connectivity'
        'SQL: jumpwin1 -> mssqlwin1' = 'SQL connectivity'
        'Azure SQL: jumpwin1 -> testdb' = 'Azure SQL connectivity'
        'MySQL: jumpwin1 -> mysql' = 'MySQL connectivity'
        'Petstore API: jumpwin1 -> petstore' = 'Petstore API connectivity'
        'P2S VPN: local -> sandbox endpoints' = 'P2S VPN connectivity'
        'AVD: personal session host config' = 'AVD personal configuration'
        'AVD: remoteapp session host config' = 'AVD remoteapp configuration'
        'Onprem -> cloud connectivity' = 'On-premises to cloud connectivity'
        'Cloud -> onprem DNS' = 'Cloud to on-premises DNS'
    }
    foreach ($line in $Lines) {
        if ($Stage -eq 'apply') {
            $match = [regex]::Match($line, $resourcePattern)
            if ($match.Success) {
                $key = $match.Groups[1].Value
                $latest.Remove($key)
                $latest[$key] = $match.Value.TrimEnd()
            }
            continue
        }
        $header = [regex]::Match($line, '\b(Module|Integration): (.+?) \|')
        if ($header.Success) {
            $kind = $header.Groups[1].Value
            $name = $header.Groups[2].Value
            $label = $null
            if ($kind -ceq 'Module' -and $modules -ccontains $name) {
                $label = $name
            }
            elseif ($kind -ceq 'Integration' -and $integrations.ContainsKey($name)) {
                $label = $integrations[$name]
            }
            if ($label) {
                $key = "${kind}: $label"
                $latest.Remove($key)
                $latest[$key] = $key
            }
        }
        $result = [regex]::Match($line, '\[MODULE:([A-Za-z0-9_-]+)\] \[(PASS|FAIL|SKIP|SUMMARY)\]')
        if ($result.Success -and $modules -ccontains $result.Groups[1].Value) {
            $module = $result.Groups[1].Value
            $status = $result.Groups[2].Value
            $key = "Results: $module"
            $summary = [regex]::Match($line.Substring($result.Index + $result.Length),
                '^ Passed:\s*([0-9]+)\s+Failed:\s*([0-9]+)\s+Total:\s*([0-9]+)\b')
            if ($status -ceq 'SUMMARY' -and $summary.Success) {
                $message = "${module}: Passed=$($summary.Groups[1].Value) Failed=$($summary.Groups[2].Value) Total=$($summary.Groups[3].Value)"
            }
            elseif ($status -cin @('PASS', 'FAIL', 'SKIP')) {
                if (-not $counts.ContainsKey($module)) {
                    $counts[$module] = @{ PASS = 0; FAIL = 0; SKIP = 0 }
                }
                $counts[$module][$status]++
                $message = "${module}: recent result lines PASS=$($counts[$module].PASS) FAIL=$($counts[$module].FAIL) SKIP=$($counts[$module].SKIP)"
            }
            else {
                $message = "${module}: result details withheld"
            }
            $latest.Remove($key)
            $latest[$key] = $message
        }
        $overall = [regex]::Match($line, '\bOverall: Passed=([0-9]+) Failed=([0-9]+) Total=([0-9]+)\b')
        if ($overall.Success) {
            $latest['overall'] = "Overall: Passed=$($overall.Groups[1].Value) Failed=$($overall.Groups[2].Value) Total=$($overall.Groups[3].Value)"
        }
        $outcome = [regex]::Match($line, '\bRESULT: (PASS|FAIL)\s*$')
        if ($outcome.Success) { $latest['result'] = "RESULT: $($outcome.Groups[1].Value)" }
    }
    @($latest.Values) | Select-Object -Last 4
}

function Read-SandboxProgress {
    param(
        [Parameter(Mandatory)][string]$Path,
        [long]$Start = 0,
        [ValidateSet('apply', 'unit-test')][string]$Stage = 'apply'
    )
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $offset = [Math]::Max($Start, $stream.Length - 65536)
        if ($offset -gt 0) {
            $stream.Position = $offset - 1
            if ($stream.ReadByte() -ne 10) {
                while (($value = $stream.ReadByte()) -ne -1 -and $value -ne 10) {}
            }
        }
        $buffer = [byte[]]::new(65536)
        $length = 0
        while ($length -lt $buffer.Length) {
            $read = $stream.Read($buffer, $length, $buffer.Length - $length)
            if ($read -eq 0) { break }
            $length += $read
        }
        $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $length)
        $lines = @($text -split '\r?\n')
        if ($lines.Count -gt 0) {
            # Discard the empty trailing element or an incomplete final line.
            $lines = @($lines | Select-Object -SkipLast 1)
        }
        Get-SandboxProgress -Lines $lines -Stage $Stage
    }
    finally { $stream.Dispose() }
}
