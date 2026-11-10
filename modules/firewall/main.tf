# ==============================================================================
# Module  : firewall   (HUB subscription)
# Purpose : Azure Firewall (Standard) with ONE firewall policy per region:
#             public IP, policy (DNS proxy), network rule collection group,
#             firewall, diagnostics and a health alert.
#
# The firewall's private IP is the first free address of AzureFirewallSubnet.
# Spoke route tables and DNS settings in tfvars reference that IP; the stack's
# 'check' block warns if the real IP differs from what tfvars expects.
# zones = [] for regions without Availability Zones.
# ==============================================================================
resource "azurerm_public_ip" "this" {
  name                = var.firewall.public_ip_name
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = length(var.firewall.zones) > 0 ? var.firewall.zones : null
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  name                     = var.firewall.policy_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  sku                      = var.firewall.sku_tier
  threat_intelligence_mode = var.firewall.threat_intelligence_mode
  tags                     = var.tags

  # DNS proxy: spokes use the firewall as DNS; it forwards to dns_servers
  # (the DNS Private Resolver inbound endpoint).
  dns {
    proxy_enabled = var.firewall.dns_proxy_enabled
    servers       = length(var.firewall.dns_servers) > 0 ? var.firewall.dns_servers : null
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "network" {
  count = length(var.firewall.network_rule_collections) > 0 ? 1 : 0

  name               = var.firewall.rule_collection_group.name
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = var.firewall.rule_collection_group.priority

  dynamic "network_rule_collection" {
    for_each = var.firewall.network_rule_collections
    content {
      name     = network_rule_collection.value.name
      priority = network_rule_collection.value.priority
      action   = network_rule_collection.value.action

      dynamic "rule" {
        for_each = network_rule_collection.value.rules
        content {
          name                  = rule.value.name
          protocols             = rule.value.protocols
          source_addresses      = rule.value.source_addresses
          destination_addresses = rule.value.destination_addresses
          destination_ports     = rule.value.destination_ports
        }
      }
    }
  }
}

resource "azurerm_firewall" "this" {
  name                = var.firewall.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall.sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this.id
  zones               = length(var.firewall.zones) > 0 ? var.firewall.zones : null
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig-fw"
    subnet_id            = var.subnet_id # must be AzureFirewallSubnet
    public_ip_address_id = azurerm_public_ip.this.id
  }

  # Rules must exist before the firewall starts enforcing the policy.
  depends_on = [azurerm_firewall_policy_rule_collection_group.network]
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = var.firewall.diagnostic_setting_name
  target_resource_id             = azurerm_firewall.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated" # resource-specific tables

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics" # deprecated block name only in azurerm 5.x
  }
}

resource "azurerm_monitor_metric_alert" "health" {
  name                = var.firewall.health_alert.name
  resource_group_name = var.resource_group_name
  scopes              = [azurerm_firewall.this.id]
  description         = "Azure Firewall health below threshold"
  severity            = var.firewall.health_alert.severity
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Network/azureFirewalls"
    metric_name      = "FirewallHealth"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.firewall.health_alert.threshold
  }

  action {
    action_group_id = var.action_group_id
  }
}
