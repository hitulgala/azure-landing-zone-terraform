# ==============================================================================
# Stack: primary-centralindia  |  Providers
# One azurerm configuration per subscription. Each module call picks the
# subscription it deploys into with  providers = { azurerm = azurerm.<alias> }.
# There is deliberately NO default provider, so nothing can land in the wrong
# subscription by accident. Subscription IDs come from terraform.tfvars.
#
# The identity running Terraform needs: Contributor on all four subscriptions,
# Private DNS Zone Contributor on the hub network RG, User Access Administrator
# on the identity subscription (one role assignment is created), and
# Monitoring Contributor on all four (Activity Log forwarding).
# ==============================================================================
provider "azurerm" {
  alias           = "governance"
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_ids.governance
  features {}
}

provider "azurerm" {
  alias           = "hub"
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_ids.hub
  features {}
}

provider "azurerm" {
  alias           = "identity"
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_ids.identity
  features {}
}

provider "azurerm" {
  alias           = "workload"
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_ids.workload
  features {}
}
