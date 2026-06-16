@{
    # PSScriptAnalyzer settings for the Azure Sandbox repo.
    # Run with: Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
    #
    # Start from the full default rule set, then exclude rules that conflict with
    # intentional patterns in this deployment-automation codebase or that are
    # false positives. Everything not listed here remains enabled.
    IncludeDefaultRules = $true

    ExcludeRules        = @(
        # Deployment/config and test scripts intentionally write progress and
        # results to the host console (Write-Host / a custom Write-Log helper).
        'PSAvoidUsingWriteHost',

        # False positive: the project defines its own 'Write-Log' helper, which
        # the analyzer incorrectly maps to a Windows PowerShell built-in cmdlet.
        'PSAvoidOverwritingBuiltInCmdlets',

        # Required by design: unattended VM configuration converts secrets passed
        # in from Terraform/Key Vault into SecureString for automation. There is
        # no interactive prompt available in this context.
        'PSAvoidUsingConvertToSecureStringWithPlainText',

        # Many run-command and orchestrator-driven test scripts declare a uniform
        # parameter contract; not every script consumes every parameter. The
        # parameters are intentionally retained for a consistent calling surface.
        'PSReviewUnusedParameter',

        # A byte order mark is discouraged for cross-platform PowerShell 7.x on
        # Linux/WSL, which is the primary execution environment for this repo.
        'PSUseBOMForUnicodeEncodedFile',

        # Internal automation helpers are invoked non-interactively from Terraform
        # run-commands and cloud-init; -WhatIf/-Confirm prompting is not applicable.
        'PSUseShouldProcessForStateChangingFunctions',

        # Pluralized nouns in internal script/function names are acceptable; these
        # are not published, discoverable cmdlets.
        'PSUseSingularNouns'
    )
}
