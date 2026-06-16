plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
    enabled = true
    version = "0.32.0"
    source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# This is an ephemeral starter configuration that is provisioned and torn down
# on demand, so prevent_destroy is intentionally not used. Disable the rule.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
