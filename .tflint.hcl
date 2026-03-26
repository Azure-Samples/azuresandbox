plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
    enabled = true
    version = "0.31.1"
    source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
