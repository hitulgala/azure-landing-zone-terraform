# ==============================================================================
# Module  : network
# Purpose : One resource group + VNet with its subnets, NSGs (and rules) and
#           route tables. Used for the hub VNet and for every spoke VNet.
#
# Everything (names, prefixes, rules, routes) comes from the caller's tfvars.
# ==============================================================================
locals {
  # Flatten  nsg -> rules  into one map so a single resource can create them all.
  nsg_rules = merge([
    for nsg_name, nsg in var.network.network_security_groups : {
      for rule_name, rule in nsg.rules :
      "${nsg_name}|${rule_name}" => merge(rule, { nsg_name = nsg_name, rule_name = rule_name })
    }
  ]...)

  # NSGs that get the explicit deny-all baseline.
  deny_all_nsgs = {
    for name, nsg in var.network.network_security_groups : name => nsg if nsg.add_deny_all_inbound
  }

  # NSG diagnostic categories defined by Azure (NSGs expose no metrics).
  nsg_log_categories = ["NetworkSecurityGroupEvent", "NetworkSecurityGroupRuleCounter"]
}

resource "azurerm_resource_group" "this" {
  name     = var.network.resource_group_name
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------- NSGs
resource "azurerm_network_security_group" "this" {
  for_each = var.network.network_security_groups

  name                = each.key
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_network_security_rule" "custom" {
  for_each = local.nsg_rules

  name                         = each.value.rule_name
  description                  = each.value.description
  resource_group_name          = azurerm_resource_group.this.name
  network_security_group_name  = azurerm_network_security_group.this[each.value.nsg_name].name
  priority                     = each.value.priority
  direction                    = each.value.direction
  access                       = each.value.access
  protocol                     = each.value.protocol
  source_port_range            = each.value.source_port_range
  destination_port_ranges      = each.value.destination_port_ranges
  source_address_prefixes      = each.value.source_address_prefixes
  destination_address_prefixes = each.value.destination_address_prefixes
}

# A custom DenyAll (4096) would also block Azure Load Balancer health probes, because Azure's default AllowAzureLoadBalancerInBound sits at 65001. So the probe rule is added first (4000) whenever the deny-all baseline is enabled.
resource "azurerm_network_security_rule" "allow_azure_lb" {
  for_each = local.deny_all_nsgs

  name                        = "Allow-AzureLoadBalancer-Inbound"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this[each.key].name
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "deny_all_inbound" {
  for_each = local.deny_all_nsgs

  name                        = "Deny-All-Inbound"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.this[each.key].name
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

# ---------------------------------------------------------------- Route tables
resource "azurerm_route_table" "this" {
  for_each = var.network.route_tables

  name                          = each.key
  resource_group_name           = azurerm_resource_group.this.name
  location                      = var.location
  bgp_route_propagation_enabled = each.value.bgp_route_propagation_enabled # azurerm 4.x name
  tags                          = var.tags

  dynamic "route" {
    for_each = each.value.routes
    content {
      name                   = route.key
      address_prefix         = route.value.address_prefix
      next_hop_type          = route.value.next_hop_type
      next_hop_in_ip_address = route.value.next_hop_in_ip_address
    }
  }
}

# ---------------------------------------------------------------- VNet + subnets
resource "azurerm_virtual_network" "this" {
  name                = var.network.vnet.name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  address_space       = var.network.vnet.address_space
  dns_servers         = length(var.network.vnet.dns_servers) > 0 ? var.network.vnet.dns_servers : null
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.network.subnets

  name                 = each.key
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value.address_prefixes

  private_endpoint_network_policies = each.value.private_endpoint_network_policies
  default_outbound_access_enabled   = each.value.default_outbound_access_enabled

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service_name
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = { for name, subnet in var.network.subnets : name => subnet.nsg if subnet.nsg != null }

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.value].id
}

resource "azurerm_subnet_route_table_association" "this" {
  for_each = { for name, subnet in var.network.subnets : name => subnet.route_table if subnet.route_table != null }

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.this[each.value].id
}

# ---------------------------------------------------------------- NSG diagnostics -> Log Analytics
resource "azurerm_monitor_diagnostic_setting" "nsg" {
  for_each = var.network.network_security_groups

  name                       = var.network.diagnostic_setting_name
  target_resource_id         = azurerm_network_security_group.this[each.key].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(local.nsg_log_categories)
    content {
      category = enabled_log.value
    }
  }
}
