#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../../../..')).Path
$temp = Join-Path ([IO.Path]::GetTempPath()) ("sandbox-result-privacy-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Read-TestAst {
    param([string]$Path)
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    Assert-True (-not $parseErrors) "Invalid PowerShell syntax: $Path"
    return $ast
}

try {
    $parent = Read-TestAst (Join-Path $root 'scripts/Invoke-UnitTests.ps1')
    foreach ($function in $parent.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] }) {
        . ([scriptblock]::Create($function.Extent.Text))
    }
    $script:messages = [Collections.Generic.List[string]]::new()
    function Write-Log {
        param([string]$msg)
        $script:messages.Add($msg)
    }

    $childFiles = @('scripts', 'modules', 'extras/modules') | ForEach-Object {
        Get-ChildItem -LiteralPath (Join-Path $root $_) -Filter 'Test-*.ps1' -Recurse -File
    }
    $assertedCalls = 0
    function Write-Log {
        param([string]$msg)
        Write-Output $msg
    }
    foreach ($file in $childFiles) {
        $ast = Read-TestAst $file.FullName
        Assert-True ('VerboseResults' -in $ast.ParamBlock.Parameters.Name.VariablePath.UserPath) "Missing optional verbose parameter: $($file.Name)"
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        $baselineText = (& git -C $root show "HEAD:$relative") -join "`n"
        Assert-True ($LASTEXITCODE -eq 0) 'Cannot load baseline child script.'
        $baselineTokens = $null; $baselineErrors = $null
        $baseline = [System.Management.Automation.Language.Parser]::ParseInput($baselineText, [ref]$baselineTokens, [ref]$baselineErrors)
        foreach ($parameter in $baseline.ParamBlock.Parameters) {
            $current = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $parameter.Name.VariablePath.UserPath }
            Assert-True ($current.Extent.Text -eq $parameter.Extent.Text) 'An existing child parameter changed.'
        }
        $oldCalls = $baseline.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-TestResult'
        }, $true)
        $newCalls = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-TestResult'
        }, $true)
        Assert-True ($oldCalls.Count -eq $newCalls.Count) 'Existing result calls were removed or added.'
        for ($index = 0; $index -lt $oldCalls.Count; $index++) {
            for ($argument = 0; $argument -lt 4; $argument++) {
                Assert-True ($oldCalls[$index].CommandElements[$argument].Extent.Text -eq $newCalls[$index].CommandElements[$argument].Extent.Text) 'An existing result expression changed.'
            }
        }
        $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-TestResult' }, $true)
        . ([scriptblock]::Create($function.Extent.Text))
        $public = Get-PublicTestDescriptions $file.FullName
        Assert-True ($public.Count -gt 0) "Missing public descriptions: $($file.Name)"
        $script:logPath = Join-Path $temp 'child.log'
        $script:VerboseResults = 'false'
        $safe = $public[0]
        $output = Write-TestResult 'test-module' 'PASS' 'private-host.example.invalid 10.234.56.78' -SanitizedMessage $safe
        Assert-True ("$output" -like "*$safe*") 'Default child output lost its static description.'
        Assert-True ("$output" -notlike '*private-host.example.invalid*') 'Default child output leaked a hostname.'
        $script:VerboseResults = 'true'
        $output = Write-TestResult 'test-module' 'FAIL' 'private-host.example.invalid 10.234.56.78' -SanitizedMessage $safe
        Assert-True ("$output" -like '*private-host.example.invalid*') 'Verbose child output did not preserve original detail.'
        $script:VerboseResults = 'false'
        $output = Write-TestResult 'test-module' 'SUMMARY' 'Passed: 1 Failed: 1 Total: 2'
        Assert-True ("$output" -like '*Passed: 1 Failed: 1 Total: 2*') 'Summary protocol changed.'
        foreach ($call in $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-TestResult'
                }, $true)) {
            if ($call.CommandElements[2].Value -eq 'SUMMARY') { continue }
            Assert-True ('SanitizedMessage' -in $call.CommandElements.ParameterName) "Missing static check label: $($file.Name):$($call.Extent.StartLineNumber)"
            $assertedCalls++
        }
    }

    function Write-Log {
        param([string]$msg)
        $script:messages.Add($msg)
    }
    $script:VerboseResults = $false
    $privateDetail = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee private-host.example.invalid 10.234.56.78 private-user /subscriptions/private-subscription'
    $lines = @(
        '[MODULE:test] [PASS] DNS check completed',
        '[MODULE:test] [FAIL] Authentication check failed',
        "[MODULE:test] [FAIL] Exception: $privateDetail",
        $privateDetail
    )
    $script:runStartedAt = Get-Date
    $script:resultsJsonFullPath = Join-Path $temp 'results.json'
    $script:junitXmlFullPath = Join-Path $temp 'results.xml'
    $script:overallPassed = 1
    $script:overallFailed = 1
    $script:Module = 'vnet_app'
    $script:Integration = $false

    foreach ($verboseMode in @($false, $true)) {
        $script:VerboseResults = $verboseMode
        $checks = ConvertFrom-TestOutput -Lines $lines -PublicDescriptions @('DNS check completed', 'Authentication check failed')
        Assert-True ($checks.Count -eq 2) 'Exception detail changed check counts.'
        $script:suiteResults = [Collections.Generic.List[object]]::new()
        $watch = [Diagnostics.Stopwatch]::StartNew()
        Add-SuiteResult -Name 'vnet-app (jumpwin1)' -Type 'module' -ModuleName 'vnet_app' -Target 'jumpwin1' `
            -TestResult @{ Passed = 1; Failed = 1; Checks = $checks } -StartedAt (Get-Date) -Stopwatch $watch
        Add-SkippedSuite -Name 'optional module' -Type 'module' -ModuleName 'avd' -Target 'local' -Reason 'Module not deployed.'
        foreach ($exitCode in @(0, 1, 2)) {
            Write-ResultFiles -ExitCode $exitCode -ErrorMessage $(if ($exitCode -eq 2) { $privateDetail } else { $null })
            $jsonText = [IO.File]::ReadAllText($script:resultsJsonFullPath)
            $xmlText = [IO.File]::ReadAllText($script:junitXmlFullPath)
            $doc = $jsonText | ConvertFrom-Json
            [xml]$xml = $xmlText
            Assert-True ($doc.schemaVersion -eq 1 -and $doc.exitCode -eq $exitCode) 'JSON schema or exit code changed.'
            Assert-True ($doc.totals.passed -eq 1 -and $doc.totals.failed -eq 1) 'JSON totals changed.'
            Assert-True ([int]$xml.testsuites.failures -eq 1 -and [int]$xml.testsuites.skipped -eq 1) 'JUnit status counts changed.'
            foreach ($marker in $privateDetail.Split(' ')) {
                if ($verboseMode) {
                    Assert-True ($jsonText.Contains($marker) -and $xmlText.Contains($marker)) 'Verbose results omitted original diagnostics.'
                }
                else {
                    Assert-True (-not $jsonText.Contains($marker) -and -not $xmlText.Contains($marker)) 'Default results exposed private diagnostics.'
                }
            }
        }
    }

    $script:VerboseResults = $false
    $checks = ConvertFrom-TestOutput -Lines @("[MODULE:test] [PASS] $privateDetail")
    Assert-True ($checks[0].name -eq 'Unrecognized check description (details withheld)') 'Unknown child output was trusted.'
    $script:suiteResults = [Collections.Generic.List[object]]::new()
    Add-SuiteResult -Name 'harness' -Type 'module' -ModuleName 'vnet_app' -Target 'local' `
        -TestResult @{ Passed = 0; Failed = 1; Checks = @(); HarnessError = $privateDetail } -StartedAt (Get-Date) -Stopwatch $watch
    Write-ResultFiles -ExitCode 1
    Assert-True (-not ([IO.File]::ReadAllText($script:resultsJsonFullPath)).Contains('private-host.example.invalid')) 'Harness details leaked in JSON.'
    Assert-True (-not ([IO.File]::ReadAllText($script:junitXmlFullPath)).Contains('private-host.example.invalid')) 'Harness details leaked in XML.'

    $fixturePath = Join-Path $temp 'fixture.ps1'
    @'
param([string]$Target, [ValidateSet('true', 'false')][string]$VerboseResults = 'false')
function Write-TestResult {
    param([string]$module, [string]$status, [string]$msg, [string]$SanitizedMessage)
    if ($VerboseResults -ne 'true') { $msg = $SanitizedMessage }
    Write-Output "[MODULE:$module] [$status] $msg"
}
Write-TestResult fixture PASS $Target -SanitizedMessage 'Fixture check completed'
Write-Output '[MODULE:fixture] [SUMMARY] Passed: 1 Failed: 0 Total: 1'
'@ | Set-Content -LiteralPath $fixturePath
    foreach ($verboseMode in @($false, $true)) {
        $script:VerboseResults = $verboseMode
        $local = Invoke-LocalTest -ScriptPath $fixturePath -Parameters @{ Target = 'private-host.example.invalid' } -Label 'fixture'
        Assert-True ($local.Passed -eq 1 -and $local.Failed -eq 0) 'Local child result counts changed.'
        Assert-True ($local.Checks[0].name.Contains('private-host.example.invalid') -eq $verboseMode) 'Local child verbosity was not forwarded.'
    }

    function Invoke-AzVMRunCommand {
        param($ResourceGroupName, $VMName, $CommandId, $ScriptPath, $Parameter)
        $script:forwardedParameters = $Parameter
        $message = if ($Parameter.VerboseResults -eq 'true') { 'private-host.example.invalid' } else { 'Fixture check completed' }
        return [pscustomobject]@{
            Value = @([pscustomobject]@{ Code = 'ComponentStatus/StdOut/succeeded'; Message = "[MODULE:fixture] [PASS] $message`n[MODULE:fixture] [SUMMARY] Passed: 1 Failed: 0 Total: 1" })
        }
    }
    foreach ($verboseMode in @($false, $true)) {
        $script:VerboseResults = $verboseMode
        $vm = Invoke-VMTest -ResourceGroupName 'fixture' -VMName 'fixture' -CommandId 'RunPowerShellScript' `
            -ScriptPath $fixturePath -Parameters @{ Target = 'private-host.example.invalid' } -Label 'fixture'
        Assert-True ($vm.Passed -eq 1 -and $vm.Failed -eq 0) 'VM child result counts changed.'
        Assert-True ($script:forwardedParameters.VerboseResults -eq $verboseMode.ToString().ToLowerInvariant()) 'VM verbosity parameter was not forwarded.'
        Assert-True ($vm.Checks[0].name.Contains('private-host.example.invalid') -eq $verboseMode) 'VM child verbosity was not respected.'
    }

    $bashPath = Join-Path $root 'modules/vm-jumpbox-linux/scripts/test-vm-jumpbox-linux.sh'
    $bashDescriptions = Get-PublicTestDescriptions $bashPath
    Assert-True ($bashDescriptions.Count -eq 34) 'Linux public check descriptions were not recognized.'

    Write-Host "PASS: $($childFiles.Count) child scripts, $assertedCalls static check labels, JSON/JUnit privacy and verbose compatibility."
}
finally {
    Get-ChildItem -LiteralPath $temp -File | Remove-Item -Force
    Remove-Item -LiteralPath $temp -Force
}
