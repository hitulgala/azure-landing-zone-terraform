# ==============================================================================
# Module  : service-health-alert   (any subscription)
# Purpose : One Service Health activity log alert for ONE subscription.
#
# Azure rule: an activity log alert can only monitor scopes inside the
# subscription it is created in. A single alert for several subscriptions is
# rejected, so the stack calls this module once per distinct subscription,
# each time with that subscription's provider and a resource group in it.
# The action group may live in another subscription (governance).
# ==============================================================================
resource "azurerm_monitor_activity_log_alert" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = "global" # Azure-mandated for activity log alerts
  scopes              = ["/subscriptions/${var.subscription_id}"]
  description         = "Azure Service Health events"
  tags                = var.tags

  criteria {
    category = "ServiceHealth"
    service_health {
      events    = var.events
      locations = length(var.locations) > 0 ? var.locations : null
    }
  }

  action {
    action_group_id = var.action_group_id
  }
}
