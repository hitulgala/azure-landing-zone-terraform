# ==============================================================================
# Module  : dns   (HUB subscription)
# Purpose : Name resolution for the region:
#             - DNS Private Resolver: inbound endpoint (STATIC IP), outbound
#               endpoint, forwarding ruleset + rules (e.g. AD domain -> DCs)
#             - Private DNS zones (created in ONE region) and VNet links
#
# Private DNS zones are global resources. The PRIMARY stack creates them
# (private_dns.create_zones = true); the SECONDARY stack sets it to false and
# only creates links from its own hub VNet to the existing zones.
# Only the hub VNet needs links: spokes resolve through the firewall DNS proxy,
# which queries the resolver, which resolves from the hub VNet.
# ==============================================================================
resource "azurerm_private_dns_resolver" "this" {
  name                = var.resolver.name
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_network_id  = var.vnet_id
  tags                = var.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  name                    = var.resolver.inbound_endpoint_name
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location
  tags                    = var.tags

  ip_configurations {
    private_ip_allocation_method = "Static"
    private_ip_address           = var.resolver.inbound_static_ip
    subnet_id                    = var.inbound_subnet_id
  }
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "this" {
  name                    = var.resolver.outbound_endpoint_name
  private_dns_resolver_id = azurerm_private_dns_resolver.this.id
  location                = var.location
  subnet_id               = var.outbound_subnet_id
  tags                    = var.tags
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "this" {
  name                                       = var.resolver.ruleset_name
  resource_group_name                        = var.resource_group_name
  location                                   = var.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.this.id]
  tags                                       = var.tags
}

resource "azurerm_private_dns_resolver_forwarding_rule" "this" {
  for_each = var.resolver.forwarding_rules

  name                      = each.key
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  domain_name               = each.value.domain_name # must end with a dot
  enabled                   = true

  dynamic "target_dns_servers" {
    for_each = each.value.target_dns_servers
    content {
      ip_address = target_dns_servers.value
      port       = 53
    }
  }
}

resource "azurerm_private_dns_resolver_virtual_network_link" "this" {
  name                      = var.resolver.ruleset_vnet_link_name
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.this.id
  virtual_network_id        = var.vnet_id
}

# ---------------------------------------------------------------- Private DNS zones
resource "azurerm_private_dns_zone" "this" {
  for_each = var.private_dns.create_zones ? toset(var.private_dns.zone_names) : toset([])

  name                = each.value
  resource_group_name = var.private_dns.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = azurerm_private_dns_zone.this

  name = "${var.private_dns.vnet_link_name}-${replace(each.value.name, ".", "-")}"
  resource_group_name   = var.private_dns.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = var.vnet_id

  registration_enabled = false

  tags = var.tags
}

#resource_group_name   = var.private_dns.resource_group_name
#private_dns_zone_name = var.private_dns.create_zones ? azurerm_private_dns_zone.this[each.value].name : each.value
