# Inputs for the network module (all values come from the stack's terraform.tfvars).
variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags for every taggable resource (must include the mandatory tags)."
  type        = map(string)
}

variable "log_analytics_workspace_id" {
  description = "Workspace that receives NSG diagnostics."
  type        = string
}

variable "network" {
  description = <<-EOT
    Complete network definition:
      resource_group_name      - RG to create
      diagnostic_setting_name  - name used for every NSG diagnostic setting
      vnet                     - { name, address_space, dns_servers }
      subnets                  - map: subnet name => { address_prefixes, nsg, route_table, delegation,
                                 private_endpoint_network_policies, default_outbound_access_enabled }
                                 'nsg' / 'route_table' reference keys of the maps below
      network_security_groups  - map: NSG name => { add_deny_all_inbound, rules = map: rule name => {...} }
      route_tables             - map: route table name => { bgp_route_propagation_enabled, routes = map }
  EOT
  type = object({
    resource_group_name     = string
    diagnostic_setting_name = string

    vnet = object({
      name          = string
      address_space = list(string)
      dns_servers   = optional(list(string), [])
    })

    subnets = map(object({
      address_prefixes = list(string)
      nsg              = optional(string)
      route_table      = optional(string)
      delegation = optional(object({
        name         = string
        service_name = string
        actions      = optional(list(string), [])
      }))
      private_endpoint_network_policies = optional(string, "Disabled")
      default_outbound_access_enabled   = optional(bool, true)
    }))

    network_security_groups = optional(map(object({
      add_deny_all_inbound = optional(bool, true)
      rules = optional(map(object({
        description                  = optional(string, "")
        priority                     = number
        direction                    = string # Inbound | Outbound
        access                       = string # Allow | Deny
        protocol                     = string # Tcp | Udp | Icmp | *
        source_port_range            = optional(string, "*")
        destination_port_ranges      = list(string)
        source_address_prefixes      = list(string)
        destination_address_prefixes = list(string)
      })), {})
    })), {})

    route_tables = optional(map(object({
      bgp_route_propagation_enabled = optional(bool, false)
      routes = map(object({
        address_prefix         = string
        next_hop_type          = string # VirtualAppliance | Internet | VirtualNetworkGateway | VnetLocal | None
        next_hop_in_ip_address = optional(string)
      }))
    })), {})
  })

  # Catch typos in tfvars early: every subnet must point at an NSG / route table that is defined.
  validation {
    condition = alltrue([
      for s in values(var.network.subnets) :
      s.nsg == null || contains(keys(var.network.network_security_groups), s.nsg)
    ])
    error_message = "A subnet references an NSG name that is not defined in network_security_groups."
  }

  validation {
    condition = alltrue([
      for s in values(var.network.subnets) :
      s.route_table == null || contains(keys(var.network.route_tables), s.route_table)
    ])
    error_message = "A subnet references a route table name that is not defined in route_tables."
  }
}
