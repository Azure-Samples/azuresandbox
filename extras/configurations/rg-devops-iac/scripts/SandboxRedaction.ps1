#requires -Version 7.2

# Redaction for everything the Sandbox deployment workflow publishes (job log, annotations, step summary). Only
# environment-specific values are redacted: Entra ID and subscription ids (any GUID), every ARM tag value, and tag names
# outside the root design. Resource names and other details are kept for troubleshooting.

# Tag names from the root `tags` variable design (variables.tf, scripts/bootstrap.sh); any other tag name is redacted.
$script:SandboxDesignTagNames = @('costcenter', 'environment', 'project')

function Get-SandboxTagName {
    param([string]$Name)
    if ($script:SandboxDesignTagNames -contains $Name) { $Name } else { '<tag-name>' }
}

function ConvertTo-SandboxTagRedactedText {
    # Redacts every ARM tag value, and tag names outside the root design, wherever the text shows them as tags. Known
    # values are also redacted as whole words, but not inside names such as rg-sand-dev-x.
    param([string]$Text, [System.Collections.IDictionary]$Tags = @{})
    $pair = '(\\*")([^"\\]*)(\\*"\s*:\s*\\*")([^"\\]*)(\\*")'
    $Text = [regex]::Replace($Text, '(?i)\\*"tags\\*"\s*:\s*\{[^{}]*\}', {
            param($object)
            [regex]::Replace($object.Value, $pair, {
                    param($m)
                    if ($m.Groups[2].Value -ieq 'tags') { return $m.Value }
                    "$($m.Groups[1].Value)$(Get-SandboxTagName $m.Groups[2].Value)$($m.Groups[3].Value)<tag-value>$($m.Groups[5].Value)"
                })
        })
    $Text = [regex]::Replace($Text, '(?i)\btags\s*=\s*\{[^{}]*\}', {
            param($block)
            @(foreach ($line in ($block.Value -split '\n')) {
                    $key = [regex]::Match($line, '^([^"\w]*?)("?)([\w.-]+)("?)(\s*=\s*)(.*)$')
                    if ($key.Success -and $key.Groups[3].Value -ine 'tags') {
                        $rest = [regex]::Replace($key.Groups[6].Value, '"[^"]*"', '"<tag-value>"')
                        "$($key.Groups[1].Value)$($key.Groups[2].Value)$(Get-SandboxTagName $key.Groups[3].Value)$($key.Groups[4].Value)$($key.Groups[5].Value)$rest"
                    }
                    else { $line }
                }) -join "`n"
        })
    $Text = [regex]::Replace($Text, '(?i)(\btags\s*\[\s*\\*[''"]?)([^''"\]\\]+)(\\*[''"]?\s*\])', {
            param($m) "$($m.Groups[1].Value)$(Get-SandboxTagName $m.Groups[2].Value)$($m.Groups[3].Value)"
        })
    $Text = [regex]::Replace($Text, '(?i)(?<![\w.])(tags\.)([\w-]+)', { param($m) "$($m.Groups[1].Value)$(Get-SandboxTagName $m.Groups[2].Value)" })
    # Azure Policy evaluation details for a tag expression carry the tag's value.
    $Text = [regex]::Replace($Text, '\{[^{}]*\btags\b[^{}]*\}', {
            param($object)
            [regex]::Replace($object.Value, '((?:expressionValue|targetValue)\\*"\s*:\s*\\*")([^"\\]*)', '$1<tag-value>')
        })
    foreach ($name in $Tags.Keys) {
        $value = ([string]$Tags[$name]).Trim()
        # Very short values (e.g. "1") would also match counts and exit codes in status messages.
        if ($value.Length -ge 3) {
            $Text = [regex]::Replace($Text, "(?<![\w./-])$([regex]::Escape($value))(?![\w./-])", '<tag-value>')
        }
        if ((Get-SandboxTagName $name) -ne $name) {
            $Text = [regex]::Replace($Text, "(?<![\w./-])$([regex]::Escape($name))(?![\w./-])", '<tag-name>')
        }
    }
    $Text
}

function Get-SandboxRedactionContext {
    # Reads the ids and tags to redact from a run's backend.tf and terraform.tfvars.
    param([string]$Directory)
    $knownIds = [ordered]@{}
    $tags = @{}
    $labels = [ordered]@{ tenant_id = 'tenant'; entra_tenant_id = 'tenant'; subscription_id = 'subscription'; client_id = 'client' }
    foreach ($file in @('backend.tf', 'terraform.tfvars')) {
        $path = Join-Path $Directory $file
        if (-not [System.IO.File]::Exists($path)) { continue }
        $text = [System.IO.File]::ReadAllText($path)
        foreach ($name in $labels.Keys) {
            $match = [regex]::Match($text, "(?m)^\s*$name\s*=\s*`"([^`"\n]+)`"")
            if ($match.Success -and -not $knownIds.Contains($labels[$name])) { $knownIds[$labels[$name]] = $match.Groups[1].Value }
        }
        foreach ($map in [regex]::Matches($text, '(?m)^\s*(?:tags|additional_tags)\s*=\s*\{([^{}]*)\}')) {
            foreach ($entry in [regex]::Matches($map.Groups[1].Value, '"?([\w.-]+)"?\s*=\s*"([^"]*)"')) {
                $tags[$entry.Groups[1].Value] = $entry.Groups[2].Value
            }
        }
    }
    @{ KnownIds = $knownIds; Tags = $tags }
}

function ConvertTo-SandboxRedactedText {
    # Known ids (tenant, subscription, client) become <label>; any other GUID, such as an object id, becomes <id>.
    param(
        [AllowEmptyString()][string]$Text,
        [System.Collections.IDictionary]$KnownIds = @{},
        [System.Collections.IDictionary]$Tags = @{}
    )
    if (-not $Text) { return $Text }
    $Text = ConvertTo-SandboxTagRedactedText $Text $Tags
    foreach ($label in $KnownIds.Keys) {
        if (-not [string]::IsNullOrWhiteSpace($KnownIds[$label])) {
            $Text = [regex]::Replace($Text, [regex]::Escape($KnownIds[$label]), "<$label>", 'IgnoreCase')
        }
    }
    [regex]::Replace($Text, '(?i)(?<![0-9a-f])[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}(?![0-9a-f])', '<id>')
}

function ConvertTo-SandboxRedactedValue {
    # Redacts every string in parsed JSON. Keys, numbers and structure are kept.
    param(
        $Value,
        [System.Collections.IDictionary]$KnownIds = @{},
        [System.Collections.IDictionary]$Tags = @{}
    )
    if ($Value -is [string]) { return ConvertTo-SandboxRedactedText -Text $Value -KnownIds $KnownIds -Tags $Tags }
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) { $copy[$key] = ConvertTo-SandboxRedactedValue $Value[$key] $KnownIds $Tags }
        return $copy
    }
    if ($Value -is [System.Collections.IList]) {
        return , @(foreach ($item in $Value) { , (ConvertTo-SandboxRedactedValue $item $KnownIds $Tags) })
    }
    $Value
}
