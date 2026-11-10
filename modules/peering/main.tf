# ==============================================================================
# Module  : peering
# Purpose : Creates BOTH halves of a VNet peering (A->B and B->A).
#
# Two provider aliases are needed because the VNets are usually in different
# subscriptions:   providers = { azurerm.side_a = azurerm.hub, azurerm.side_b = azurerm.identity }
# For hub-to-hub peering (same subscription) pass the same provider twice.
# The deploying identity needs Network Contributor on BOTH VNets.
# ==============================================================================
resource "azurerm_virtual_network_peering" "a_to_b" {
  provider = azurerm.side_a

  name                         = var.name_a_to_b
  resource_group_name          = var.side_a.resource_group_name
  virtual_network_name         = var.side_a.vnet_name
  remote_virtual_network_id    = var.side_b.vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = var.side_a.allow_forwarded_traffic
  allow_gateway_transit        = var.side_a.allow_gateway_transit
  use_remote_gateways          = var.side_a.use_remote_gateways
}

resource "azurerm_virtual_network_peering" "b_to_a" {
  provider = azurerm.side_b

  name                         = var.name_b_to_a
  resource_group_name          = var.side_b.resource_group_name
  virtual_network_name         = var.side_b.vnet_name
  remote_virtual_network_id    = var.side_a.vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = var.side_b.allow_forwarded_traffic
  allow_gateway_transit        = var.side_b.allow_gateway_transit
  use_remote_gateways          = var.side_b.use_remote_gateways
}
