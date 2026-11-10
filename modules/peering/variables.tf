# Inputs for the peering module.
variable "name_a_to_b" {
  description = "Name of the peering created on side A."
  type        = string
}

variable "name_b_to_a" {
  description = "Name of the peering created on side B."
  type        = string
}

variable "side_a" {
  description = "VNet on side A (usually the hub)."
  type = object({
    vnet_id                 = string
    vnet_name               = string
    resource_group_name     = string
    allow_forwarded_traffic = optional(bool, true)
    allow_gateway_transit   = optional(bool, false)
    use_remote_gateways     = optional(bool, false)
  })
}

variable "side_b" {
  description = "VNet on side B (a spoke, or the other region's hub)."
  type = object({
    vnet_id                 = string
    vnet_name               = string
    resource_group_name     = string
    allow_forwarded_traffic = optional(bool, true)
    allow_gateway_transit   = optional(bool, false)
    use_remote_gateways     = optional(bool, false)
  })
}
