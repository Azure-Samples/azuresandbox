#requires -Version 7.2

# Terraform error reporting for failed preflight and apply stages. Each Terraform `Error:` block is published in full,
# keeping its layout, after the redaction in SandboxRedaction.ps1.

$script:SandboxErrorMaxBytes = 16384
$script:SandboxLogTimestamp = '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[^\]]+\] '

function Get-SandboxTerraformError {
    # Returns the Error blocks printed by the last command in a stage log, only when that command was terraform and it
    # exited non-zero. Blocks keep Terraform's formatting: plain (-no-color) or boxed with the │/╵ gutter.
    param([AllowEmptyCollection()][string[]]$Lines)
    $start = -1
    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        if ($Lines[$i] -cmatch ($script:SandboxLogTimestamp + '(\[.*\])$')) {
            $start = $i
            $command = $Matches[1]
            break
        }
    }
    if ($start -lt 0) { return }
    try { $arguments = @(ConvertFrom-Json -InputObject $command) }
    catch { return }
    if ($arguments.Count -eq 0 -or $arguments[0] -cne 'terraform') { return }
    $blocks = [System.Collections.Generic.List[string]]::new()
    $current = $null
    $exitCode = $null
    $finish = {
        while ($current.Count -gt 0 -and $current[$current.Count - 1] -cmatch '^\s*│?\s*$') { $current.RemoveAt($current.Count - 1) }
        if ($current.Count -gt 0) { $blocks.Add($current -join "`n") }
    }
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -cmatch ($script:SandboxLogTimestamp + 'Exit code: (-?[0-9]+)$')) { $exitCode = [int]$Matches[1] }
        $boundary = $line -cmatch $script:SandboxLogTimestamp -or
            $line -cmatch '^(?:│ )?(?:Error|Warning): ' -or
            $line -cmatch '^Releasing state lock' -or
            $line -cmatch '^\S+: (?:Still |Creating\.\.\.|Creation |Modifying\.\.\.|Modifications |Destroying\.\.\.|Destruction |Reading\.\.\.|Read complete|Refreshing state)'
        if ($null -ne $current -and $boundary) {
            . $finish
            $current = $null
        }
        if ($line -cmatch $script:SandboxLogTimestamp) { break }
        if ($line -cmatch '^(?:│ )?Error: ') { $current = [System.Collections.Generic.List[string]]::new() }
        if ($null -ne $current) {
            $current.Add($line)
            if ($line -cmatch '^╵') {
                . $finish
                $current = $null
            }
        }
    }
    if ($null -ne $current) { . $finish }
    if ($exitCode -eq 0) { return }
    $blocks.ToArray()
}

function ConvertTo-SandboxTerraformErrorReport {
    # Redacts the blocks and caps the size of the report.
    param(
        [AllowEmptyCollection()][string[]]$Blocks,
        [System.Collections.IDictionary]$KnownIds = @{},
        [System.Collections.IDictionary]$Tags = @{},
        [int]$MaxBytes = $script:SandboxErrorMaxBytes
    )
    if ($Blocks.Count -eq 0) { return $null }
    $redacted = @(foreach ($block in $Blocks) { ConvertTo-SandboxRedactedText -Text $block -KnownIds $KnownIds -Tags $Tags })
    $kept = [System.Collections.Generic.List[string]]::new()
    $bytes = 0
    $notes = [System.Collections.Generic.List[string]]::new()
    for ($i = $redacted.Count - 1; $i -ge 0; $i--) {
        $size = [System.Text.Encoding]::UTF8.GetByteCount($redacted[$i]) + 2
        if ($bytes + $size -le $MaxBytes) {
            $kept.Insert(0, $redacted[$i])
            $bytes += $size
            continue
        }
        if ($kept.Count -eq 0) {
            # The last block alone exceeds the limit: keep whole lines up to it and say how many were left out.
            $lines = @($redacted[$i] -split '\n')
            $partial = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $lines) {
                $size = [System.Text.Encoding]::UTF8.GetByteCount($line) + 1
                if ($bytes + $size -gt $MaxBytes) { break }
                $partial.Add($line)
                $bytes += $size
            }
            $kept.Add($partial -join "`n")
            $notes.Add("[$($lines.Count - $partial.Count) more line(s) of this error block omitted: the report is limited to $MaxBytes bytes.]")
            $i--
        }
        if ($i -ge 0) { $notes.Insert(0, "[$($i + 1) earlier error block(s) omitted: the report is limited to $MaxBytes bytes.]") }
        break
    }
    (@($kept) + @($notes)) -join "`n`n"
}

function ConvertTo-SandboxAnnotationData {
    param([string]$Text)
    $Text.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
}

function ConvertTo-SandboxErrorMarkdown {
    # A GitHub CAUTION alert (rendered red) holding the report in a fenced text block.
    param([string]$Stage, [string]$Report)
    $longest = 0
    foreach ($match in [regex]::Matches($Report, '`+')) { $longest = [Math]::Max($longest, $match.Length) }
    $fence = '`' * [Math]::Max(3, $longest + 1)
    $quoted = @($Report -split '\n' | ForEach-Object { if ($_) { "> $_" } else { '>' } }) -join "`n"
    "### Last Terraform error ($Stage)`n`n> [!CAUTION]`n> ${fence}text`n$quoted`n> $fence`n`n"
}
