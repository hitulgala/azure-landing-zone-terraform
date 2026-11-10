# ==============================================================================
# Stack: primary-centralindia  |  Variable declarations
# This file only DECLARES inputs. Every value lives in terraform.tfvars.
# Large nested settings use "any" here; the detailed schema (and validation) is
# enforced by the module that consumes them - see modules/<name>/variables.tf.
# ==============================================================================
variable "tenant_id" {
  description = "Microsoft Entra tenant ID."
  type        = string
}

variable "subscription_ids" {
  description = "The four platform subscription IDs."
  type = object({
    governance = string
    hub        = string
    identity   = string
    workload   = string
  })
}

variable "location" {
  description = "Azure region of this stack."
  type        = string
}

variable "mandatory_tag_names" {
  description = "Tags every resource must carry. Terraform fails at plan if 'tags' lacks one, and Azure Policy enforces them (see 'policies')."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to every taggable resource created by this stack."
  type        = map(string)

  validation {
    condition     = alltrue([for t in var.mandatory_tag_names : contains(keys(var.tags), t) && trimspace(var.tags[t]) != ""])
    error_message = "tags must contain a non-empty value for every name in mandatory_tag_names."
  }
}

variable "expected_firewall_private_ip" {
  description = "IP the firewall is expected to receive (first free address of AzureFirewallSubnet). Must match the IP used in the spoke route tables and DNS servers. A 'check' warns if it differs."
  type        = string
}

variable "governance" {
  description = "Settings for modules/monitoring."
  type = object({
    resource_group_name      = string
    log_analytics            = any
    action_group             = any
    service_health_alert     = any
    activity_log_diagnostics = any
  })
}

variable "hub" {
  description = "Hub subscription: network (modules/network), firewall, dns_resolver and private_dns (modules/dns)."
  type = object({
    network      = any
    firewall     = any
    dns_resolver = any
    private_dns  = any
  })
}

variable "identity" {
  description = "Identity subscription: network, key_vault and domain_controllers."
  type = object({
    network            = any
    key_vault          = any
    domain_controllers = any
  })
}

variable "workload" {
  description = "Workload subscription: network and recovery_vault."
  type = object({
    network        = any
    recovery_vault = any
  })
}

variable "peerings" {
  description = "Names of the peering halves: { hub_identity = { hub_to_spoke, spoke_to_hub }, hub_workload = { ... } }."
  type        = any
}

variable "policy_definition_names" {
  description = "Display names of the built-in definitions used for the mandatory-tag policies."
  type = object({
    require_tag_on_resource_groups  = string
    inherit_tag_from_resource_group = string
    require_tag_on_resources        = string
  })
}

variable "policies" {
  description = <<-EOT
    Azure Policy per subscription (assigned at SUBSCRIPTION scope, by the primary stack only).
    Each subscription: { mandatory_tags = {...}, assignments = {...} } - schema in modules/policy/variables.tf.
  EOT
  type = object({
    governance = any
    hub        = any
    identity   = any
    workload   = any
  })
}
