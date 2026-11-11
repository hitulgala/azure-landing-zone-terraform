# ==============================================================================
# Module  : policy   (ONE call per subscription; subscription-scope assignments)
# Purpose : Azure Policy for a single subscription, driven entirely by tfvars:
#             * MANDATORY TAGS   - for every tag in mandatory_tag_names:
#                 - require the tag on resource groups   (Deny)
#                 - inherit the tag from the resource group when missing (Modify)
#                 - optionally require the tag on every resource (Deny)
#             * ANY other built-in policy: allowed VM SKUs, allowed locations,
#               no public IPs on NICs, ... defined in 'assignments'.
#
# enforce = false  -> "DoNotEnforce": evaluated and reported, nothing blocked (audit).
# enforce = true   -> Deny / Modify effects are active.
#
# Modify policies (tag inheritance) run under a system-assigned managed identity.
# This module grants that identity the roles listed IN THE POLICY DEFINITION
# (Contributor for the built-in inherit-tag policy) on this subscription only.
# That needs Owner / User Access Administrator for the deploying identity.
# ==============================================================================
locals {
  subscription_scope = "/subscriptions/${var.subscription_id}"

  # ---- Mandatory-tag assignments, expanded from the tag list --------------------------
  tag_assignments = merge(
    {
      for tag in var.mandatory_tag_names : "tag-rg-${tag}" => {
        display_name            = "Require tag '${tag}' on resource groups"
        definition_display_name = var.policy_definition_names.require_tag_on_resource_groups
        enforce                 = var.mandatory_tags.enforce
        parameters              = { tagName = tag }
        identity                = false
      } if var.mandatory_tags.require_on_resource_groups
    },
    {
      for tag in var.mandatory_tag_names : "tag-inherit-${tag}" => {
        display_name            = "Inherit tag '${tag}' from the resource group"
        definition_display_name = var.policy_definition_names.inherit_tag_from_resource_group
        enforce                 = var.mandatory_tags.enforce
        parameters              = { tagName = tag }
        identity                = true # Modify effect needs a managed identity
      } if var.mandatory_tags.inherit_from_resource_group
    },
    {
      for tag in var.mandatory_tag_names : "tag-res-${tag}" => {
        display_name            = "Require tag '${tag}' on resources"
        definition_display_name = var.policy_definition_names.require_tag_on_resources
        enforce                 = var.mandatory_tags.enforce
        parameters              = { tagName = tag }
        identity                = false
      } if var.mandatory_tags.require_on_resources
    }
  )

  # ---- Everything to assign: tag policies + the free-form assignments ------------------
  all_assignments = {
    for name, a in merge(local.tag_assignments, var.assignments) : name => {
      display_name            = a.display_name
      definition_display_name = a.definition_display_name
      enforce                 = a.enforce
      parameters              = a.parameters
      identity                = a.identity
    }
  }

  # ---- Roles for the managed identities (taken from each policy definition) ------------
  identity_roles = merge([
    for name, a in local.all_assignments : {
      for idx, role_id in data.azurerm_policy_definition.this[a.definition_display_name].role_definition_ids :
      "${name}|${idx}" => {
        assignment = name
        role_guid  = element(split("/", role_id), length(split("/", role_id)) - 1)
      }
    } if a.identity
  ]...)
}

data "azurerm_policy_definition" "this" {
  for_each     = toset([for a in values(local.all_assignments) : a.definition_display_name])
  display_name = each.value
}

resource "azurerm_subscription_policy_assignment" "this" {
  for_each = local.all_assignments

  name                 = each.key # max 64 characters at subscription scope
  display_name         = each.value.display_name
  subscription_id      = local.subscription_scope
  policy_definition_id = data.azurerm_policy_definition.this[each.value.definition_display_name].id
  enforce              = each.value.enforce

  # Parameter values are wrapped as { name = { value = ... } } as Azure expects.
  parameters = length(each.value.parameters) > 0 ? jsonencode({ for k, v in each.value.parameters : k => { value = v } }) : null

  # A location is only needed (and allowed) when the assignment has an identity.
  location = each.value.identity ? var.location : null

  dynamic "identity" {
    for_each = each.value.identity ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }
}

resource "azurerm_role_assignment" "policy_identity" {
  for_each = local.identity_roles

  scope              = local.subscription_scope
  role_definition_id = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${each.value.role_guid}"
  principal_id       = azurerm_subscription_policy_assignment.this[each.value.assignment].identity[0].principal_id

  # The new identity may not be visible in Entra ID yet; skip the lookup instead of failing.
  skip_service_principal_aad_check = true
}
