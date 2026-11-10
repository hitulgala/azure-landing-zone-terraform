# Inputs for the firewall module (values come from terraform.tfvars).
variable "resource_group_name" {
  description = "Hub network resource group (created by the network module)."
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

variable "subnet_id" {
  description = "ID of AzureFirewallSubnet."
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Workspace for firewall logs."
  type        = string
}

variable "action_group_id" {
  description = "Action group notified by the health alert."
  type        = string
}

variable "firewall" {
  description = "Firewall settings (see terraform.tfvars for a full example)."
  type = object({
    name                     = string
    public_ip_name           = string
    policy_name              = string
    sku_tier                 = string                     # Standard
    zones                    = list(string)               # ["1","2","3"] or []
    threat_intelligence_mode = string                     # Off | Alert | Deny
    dns_proxy_enabled        = bool
    dns_servers              = list(string)               # resolver inbound IP
    diagnostic_setting_name  = string
    rule_collection_group = object({
      name     = string
      priority = number
    })
    network_rule_collections = list(object({
      name     = string
      priority = number
      action   = string # Allow | Deny
      rules = list(object({
        name                  = string
        protocols             = list(string) # TCP | UDP | ICMP | Any
        source_addresses      = list(string)
        destination_addresses = list(string)
        destination_ports     = list(string)
      }))
    }))
    health_alert = object({
      name      = string
      severity  = number
      threshold = number
    })
  })
}
