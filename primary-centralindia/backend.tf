# ==============================================================================
# Stack: primary-centralindia  |  Remote state
# Terraform does not allow variables in a backend block, so the connection values
# are supplied from backend.hcl. Generate it with scripts/Bootstrap-TerraformBackend.ps1.
#     terraform init -backend-config="backend.hcl"
# ==============================================================================
terraform {
  backend "azurerm" {}
}
