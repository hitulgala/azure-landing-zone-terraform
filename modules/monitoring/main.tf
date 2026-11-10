# ==============================================================================
# Module  : monitoring   (GOVERNANCE subscription)
# Purpose : Central monitoring for one region:
#             - resource group
#             - Log Analytics workspace
#             - Action group (alert routing: e-mail / webhook)
#             - Service Health alert across all platform subscriptions
#             - Subscription Activity Log -> Log Analytics (switch in tfvars)
# Activity logs are subscription-wide, so enable them in ONE region only.
# ==============================================================================
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.log_analytics.name
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics.retention_in_days
  daily_quota_gb      = var.log_analytics.daily_quota_gb
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "this" {
  name                = var.action_group.name
  short_name          = var.action_group.short_name
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.action_group.email_receivers
    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.action_group.webhook_receivers
    content {
      name                    = webhook_receiver.key
      service_uri             = webhook_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_activity_log_alert" "service_health" {
  name                = var.service_health_alert.name
  resource_group_name = azurerm_resource_group.this.name
  location            = "global"
  scopes              = [for id in var.monitored_subscription_ids : "/subscriptions/${id}"]
  description         = "Azure Service Health events"
  tags                = var.tags

  criteria {
    category = "ServiceHealth"
    service_health {
      events    = var.service_health_alert.events
      locations = length(var.service_health_alert.locations) > 0 ? var.service_health_alert.locations : null
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  for_each = var.activity_log_diagnostics.enabled ? toset(var.monitored_subscription_ids) : toset([])

  name                       = var.activity_log_diagnostics.name
  target_resource_id         = "/subscriptions/${each.value}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(var.activity_log_diagnostics.categories)
    content {
      category = enabled_log.value
    }
  }
}
