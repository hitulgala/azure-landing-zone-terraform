# Outputs of the domain-controllers module.
output "private_ips" {
  description = "Computer name => private IP."
  value       = { for name, nic in azurerm_network_interface.this : name => nic.private_ip_address }
}
