variable "resource_group_name" {
  description = "Governance resource group to create."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
}

variable "monitored_subscription_ids" {
  description = "Subscriptions whose Activity Log is forwarded to the workspace."
  type        = list(string)
}

variable "log_analytics" {
  description = "Workspace settings."
  type = object({
    name              = string
    retention_in_days = number # interactive retention, 30-730
    daily_quota_gb    = number # -1 = unlimited
  })
}

variable "action_group" {
  description = "Action group settings. short_name max 12 characters."
  type = object({
    name              = string
    short_name        = string
    email_receivers   = map(string) # receiver name => e-mail address
    webhook_receivers = optional(map(string), {})
  })

  validation {
    condition     = length(var.action_group.short_name) <= 12
    error_message = "action_group.short_name must be 12 characters or fewer."
  }
}

variable "activity_log_diagnostics" {
  description = "Forward subscription Activity Logs to the workspace. enabled = true in ONE region only."
  type = object({
    enabled    = bool
    name       = string
    categories = list(string)
  })
}
