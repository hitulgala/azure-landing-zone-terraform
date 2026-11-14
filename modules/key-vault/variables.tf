variable "resource_group_name" {
  description = "Identity resource group (created by the network module)."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}

variable "log_analytics_workspace_id" {
  description = "Workspace for Key Vault audit logs."
  type        = string
}

variable "key_vault" {
  description = "Key Vault settings. name must be globally unique (3-24 chars)."
  type = object({
    name                          = string
    sku_name                      = string # standard | premium
    purge_protection_enabled      = bool
    soft_delete_retention_days    = number # 7-90, fixed at creation
    public_network_access_enabled = bool
    allowed_ip_ranges             = optional(list(string), [])
    network_default_action        = optional(string, "Allow") # "Deny" only when Terraform runs inside the VNet or from a fixed IP
    secret_name                   = string
    role_propagation_wait         = string # e.g. "90s"
    diagnostic_setting_name       = string
  })

  validation {
    condition     = contains(["Allow", "Deny"], var.key_vault.network_default_action)
    error_message = "key_vault.network_default_action must be Allow or Deny."
  }
}

variable "private_endpoint" {
  description = "Private endpoint names."
  type = object({
    name            = string
    connection_name = string
  })
}

variable "private_endpoint_subnet_id" {
  description = "Subnet that hosts the private endpoint."
  type        = string
}

variable "private_dns_zone_id" {
  description = "ID of privatelink.vaultcore.azure.net (lives in the primary hub network RG)."
  type        = string
}
