# Outputs of the peering module.
output "peering_ids" {
  description = "IDs of both peering halves."
  value = {
    a_to_b = azurerm_virtual_network_peering.a_to_b.id
    b_to_a = azurerm_virtual_network_peering.b_to_a.id
  }
}
