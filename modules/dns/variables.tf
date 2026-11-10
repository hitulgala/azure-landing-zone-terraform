# Inputs for the dns module (values come from terraform.tfvars).
variable "resource_group_name" {
  description = "Hub network resource group (resolver resources)."
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

variable "vnet_id" {
  description = "Hub VNet ID."
  type        = string
}

variable "inbound_subnet_id" {
  description = "Delegated subnet for the resolver inbound endpoint."
  type        = string
}

variable "outbound_subnet_id" {
  description = "Delegated subnet for the resolver outbound endpoint."
  type        = string
}

variable "resolver" {
  description = "DNS Private Resolver settings. forwarding_rules domain names must end with a dot."
  type = object({
    name                   = string
    inbound_endpoint_name  = string
    inbound_static_ip      = string # first usable address of the inbound subnet (.4)
    outbound_endpoint_name = string
    ruleset_name           = string
    ruleset_vnet_link_name = string
    forwarding_rules = map(object({
      domain_name        = string
      target_dns_servers = list(string)
    }))
  })

  validation {
    condition     = alltrue([for r in values(var.resolver.forwarding_rules) : endswith(r.domain_name, ".")])
    error_message = "Every forwarding rule domain_name must end with a dot, e.g. corp.example.com."
  }
}

variable "private_dns" {
  description = <<-EOT
    Private DNS zone settings:
      create_zones        - true in the PRIMARY region, false in the SECONDARY
      resource_group_name - RG that holds the zones (the primary hub network RG)
      zone_names          - zones to create / link
      vnet_link_name      - name of the link from this hub VNet to each zone
  EOT
  type = object({
    create_zones        = bool
    resource_group_name = string
    zone_names          = list(string)
    vnet_link_name      = string
  })
}
