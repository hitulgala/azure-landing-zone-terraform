# Outputs of the service-health-alert module.
output "id" {
  description = "Alert rule ID."
  value       = azurerm_monitor_activity_log_alert.this.id
}
