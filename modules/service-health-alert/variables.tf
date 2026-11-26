# Inputs of the service-health-alert module.
variable "name" {
  description = "Alert rule name (unique within its resource group)."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group, in the SAME subscription as subscription_id."
  type        = string
}

variable "subscription_id" {
  description = "The subscription this alert monitors (must be the provider's subscription)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID."
  }
}

variable "tags" {
  description = "Tags applied to the alert rule."
  type        = map(string)
}

variable "events" {
  description = "Service Health event types: Incident, Maintenance, Informational, ActionRequired, Security."
  type        = list(string)
}

variable "locations" {
  description = "Regions to alert on. [] = all regions."
  type        = list(string)
  default     = []
}

variable "action_group_id" {
  description = "Action group notified by the alert (may be in another subscription)."
  type        = string
}
