# ==============================================================================
# Stack: primary-centralindia  |  PARENT ORCHESTRATION
#
# This file only WIRES modules together. It contains no environment values:
# every name, address, port and setting comes from terraform.tfvars.
# ==============================================================================

# ---------------------------------------------------------------- Governance subscription
module "governance" {
  source    = "../modules/monitoring"
  providers = { azurerm = azurerm.governance }

  resource_group_name        = var.governance.resource_group_name
  location                   = var.location
  tags                       = var.tags
  monitored_subscription_ids = values(var.subscription_ids)
  log_analytics              = var.governance.log_analytics
  action_group               = var.governance.action_group
  service_health_alert       = var.governance.service_health_alert
  activity_log_diagnostics   = var.governance.activity_log_diagnostics
}

# ---------------------------------------------------------------- Hub subscription
module "hub_network" {
  source    = "../modules/network"
  providers = { azurerm = azurerm.hub }

  location                   = var.location
  tags                       = var.tags
  network                    = var.hub.network
  log_analytics_workspace_id = module.governance.log_analytics_workspace_id
}

module "hub_firewall" {
  source    = "../modules/firewall"
  providers = { azurerm = azurerm.hub }

  resource_group_name        = module.hub_network.resource_group_name
  location                   = var.location
  tags                       = var.tags
  subnet_id                  = module.hub_network.subnet_ids[var.hub.firewall.subnet_name]
  firewall                   = var.hub.firewall
  log_analytics_workspace_id = module.governance.log_analytics_workspace_id
  action_group_id            = module.governance.action_group_id
}

module "hub_dns" {
  source    = "../modules/dns"
  providers = { azurerm = azurerm.hub }

  # The Private DNS zones are created in the hub network RG, so it must exist first.
  depends_on = [module.hub_network]

  resource_group_name = module.hub_network.resource_group_name
  location            = var.location
  tags                = var.tags
  vnet_id             = module.hub_network.vnet_id
  inbound_subnet_id   = module.hub_network.subnet_ids[var.hub.dns_resolver.inbound_subnet_name]
  outbound_subnet_id  = module.hub_network.subnet_ids[var.hub.dns_resolver.outbound_subnet_name]
  resolver            = var.hub.dns_resolver
  private_dns         = var.hub.private_dns
}

# ---------------------------------------------------------------- Identity subscription
module "identity_network" {
  source    = "../modules/network"
  providers = { azurerm = azurerm.identity }

  location                   = var.location
  tags                       = var.tags
  network                    = var.identity.network
  log_analytics_workspace_id = module.governance.log_analytics_workspace_id
}

module "key_vault" {
  source    = "../modules/key-vault"
  providers = { azurerm = azurerm.identity }

  resource_group_name        = module.identity_network.resource_group_name
  location                   = var.location
  tags                       = var.tags
  key_vault                  = var.identity.key_vault
  private_endpoint           = var.identity.key_vault.private_endpoint
  private_endpoint_subnet_id = module.identity_network.subnet_ids[var.identity.key_vault.private_endpoint.subnet_name]
  private_dns_zone_id        = module.hub_dns.private_dns_zone_ids[var.identity.key_vault.private_dns_zone_name]
  log_analytics_workspace_id = module.governance.log_analytics_workspace_id
}

module "domain_controllers" {
  source    = "../modules/domain-controllers"
  providers = { azurerm = azurerm.identity }

  resource_group_name = module.identity_network.resource_group_name
  location            = var.location
  tags                = var.tags
  subnet_id           = module.identity_network.subnet_ids[var.identity.domain_controllers.subnet_name]
  admin_password      = module.key_vault.admin_password # available only after the secret is stored
  settings            = var.identity.domain_controllers.settings
  availability_set    = var.identity.domain_controllers.availability_set
  domain_controllers  = var.identity.domain_controllers.servers
}

# ---------------------------------------------------------------- Workload subscription
module "workload_network" {
  source    = "../modules/network"
  providers = { azurerm = azurerm.workload }

  location                   = var.location
  tags                       = var.tags
  network                    = var.workload.network
  log_analytics_workspace_id = module.governance.log_analytics_workspace_id
}

module "recovery_vault" {
  source    = "../modules/recovery-vault"
  providers = { azurerm = azurerm.workload }

  resource_group_name        = module.workload_network.resource_group_name
  location                   = var.location
  tags                       = var.tags
  vault                      = var.workload.recovery_vault.vault
  vm_backup_policy           = var.workload.recovery_vault.vm_backup_policy
  log_analytics_workspace_id = module.governance.log_analytics_workspace_id
}

# ---------------------------------------------------------------- Hub <-> spoke peerings
module "peering_hub_identity" {
  source = "../modules/peering"
  providers = {
    azurerm.side_a = azurerm.hub
    azurerm.side_b = azurerm.identity
  }

  name_a_to_b = var.peerings.hub_identity.hub_to_spoke
  name_b_to_a = var.peerings.hub_identity.spoke_to_hub

  side_a = {
    vnet_id             = module.hub_network.vnet_id
    vnet_name           = module.hub_network.vnet_name
    resource_group_name = module.hub_network.resource_group_name
  }
  side_b = {
    vnet_id             = module.identity_network.vnet_id
    vnet_name           = module.identity_network.vnet_name
    resource_group_name = module.identity_network.resource_group_name
  }
}

module "peering_hub_workload" {
  source = "../modules/peering"
  providers = {
    azurerm.side_a = azurerm.hub
    azurerm.side_b = azurerm.workload
  }

  name_a_to_b = var.peerings.hub_workload.hub_to_spoke
  name_b_to_a = var.peerings.hub_workload.spoke_to_hub

  side_a = {
    vnet_id             = module.hub_network.vnet_id
    vnet_name           = module.hub_network.vnet_name
    resource_group_name = module.hub_network.resource_group_name
  }
  side_b = {
    vnet_id             = module.workload_network.vnet_id
    vnet_name           = module.workload_network.vnet_name
    resource_group_name = module.workload_network.resource_group_name
  }
}

/*
# ---------------------------------------------------------------- Azure Policy (subscription scope)
# Policy is subscription-wide, not regional, so ONLY the primary stack assigns it.
# One call per subscription; each subscription has its own rules in tfvars (policies.<name>).
module "policy_governance" {
  source    = "../modules/policy"
  providers = { azurerm = azurerm.governance }

  subscription_id         = var.subscription_ids.governance
  location                = var.location
  mandatory_tag_names     = var.mandatory_tag_names
  policy_definition_names = var.policy_definition_names
  mandatory_tags          = var.policies.governance.mandatory_tags
  assignments             = var.policies.governance.assignments
}

module "policy_hub" {
  source    = "../modules/policy"
  providers = { azurerm = azurerm.hub }

  subscription_id         = var.subscription_ids.hub
  location                = var.location
  mandatory_tag_names     = var.mandatory_tag_names
  policy_definition_names = var.policy_definition_names
  mandatory_tags          = var.policies.hub.mandatory_tags
  assignments             = var.policies.hub.assignments
}

module "policy_identity" {
  source    = "../modules/policy"
  providers = { azurerm = azurerm.identity }

  subscription_id         = var.subscription_ids.identity
  location                = var.location
  mandatory_tag_names     = var.mandatory_tag_names
  policy_definition_names = var.policy_definition_names
  mandatory_tags          = var.policies.identity.mandatory_tags
  assignments             = var.policies.identity.assignments
}

module "policy_workload" {
  source    = "../modules/policy"
  providers = { azurerm = azurerm.workload }

  subscription_id         = var.subscription_ids.workload
  location                = var.location
  mandatory_tag_names     = var.mandatory_tag_names
  policy_definition_names = var.policy_definition_names
  mandatory_tags          = var.policies.workload.mandatory_tags
  assignments             = var.policies.workload.assignments
}


# ---------------------------------------------------------------- Safety check
# The spoke route tables and DNS settings in tfvars hard-wire the firewall IP.
# This warns (it does not fail the apply) if Azure assigned a different address.
check "firewall_private_ip_matches_tfvars" {
  assert {
    condition     = module.hub_firewall.private_ip_address == var.expected_firewall_private_ip
    error_message = "The firewall got a different private IP than expected_firewall_private_ip in terraform.tfvars. Update the IP in the route tables / dns_servers in tfvars and re-apply."
  }
}
*/