# Shared GitHub Actions OIDC helpers for the Sandbox deployment workflow (auth_mode = "oidc").
# Azure CLI and Az PowerShell sessions created from a federated token can't refresh it, so callers request a fresh
# GitHub ID token for every sign-in. The Terraform providers request their own tokens with use_oidc = true.

function Get-SandboxGitHubIdToken {
    $requestUrl = $env:ACTIONS_ID_TOKEN_REQUEST_URL
    $requestToken = $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN
    if ([string]::IsNullOrWhiteSpace($requestUrl) -or [string]::IsNullOrWhiteSpace($requestToken)) {
        throw 'GitHub OIDC token request variables are missing. The job needs "permissions: id-token: write".'
    }
    $separator = if ($requestUrl.Contains('?')) { '&' } else { '?' }
    $audience = [uri]::EscapeDataString('api://AzureADTokenExchange')
    $response = Invoke-RestMethod -Method Get -Uri "$requestUrl${separator}audience=$audience" `
        -Headers @{ Authorization = "Bearer $requestToken" } -TimeoutSec 60
    if ($response.value -isnot [string] -or [string]::IsNullOrWhiteSpace($response.value)) {
        throw 'GitHub did not return an OIDC token.'
    }
    $response.value
}
