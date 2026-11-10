# Outputs of the monitoring module.
output "log_analytics_workspace_id" {
  description = "Workspace ID used by every diagnostic setting."
  value       = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_name" {
  description = "Workspace name."
  value       = azurerm_log_analytics_workspace.this.name
}

output "action_group_id" {
  description = "Action group ID used by alert rules."
  value       = azurerm_monitor_action_group.this.id
}
