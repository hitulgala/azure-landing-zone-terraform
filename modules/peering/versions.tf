# Two azurerm provider configurations are required (one per VNet side).
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = ">= 4.30.0, < 5.0.0"
      configuration_aliases = [azurerm.side_a, azurerm.side_b]
    }
  }
}
