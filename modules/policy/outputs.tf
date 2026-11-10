# Outputs of the policy module.
output "assignment_ids" {
  description = "Policy assignment name => ID."
  value       = { for name, a in azurerm_subscription_policy_assignment.this : name => a.id }
}
