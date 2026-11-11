variable "subscription_id" {
  description = "Subscription the policies are assigned to."
  type        = string
}

variable "location" {
  description = "Region for the managed identities of Modify policies (metadata only)."
  type        = string
}

variable "mandatory_tag_names" {
  description = "Tag names that every resource group / resource must carry."
  type        = list(string)
}

variable "policy_definition_names" {
  description = "Display names of the built-in definitions used for the mandatory-tag policies."
  type = object({
    require_tag_on_resource_groups  = string
    inherit_tag_from_resource_group = string
    require_tag_on_resources        = string
  })
}

variable "mandatory_tags" {
  description = <<-EOT
    How the mandatory tags are enforced in this subscription:
      require_on_resource_groups  - Deny resource groups missing the tag
      inherit_from_resource_group - Modify: resources copy a missing tag from their RG
      require_on_resources        - Deny resources missing the tag (usually off when inheriting)
      enforce                     - false = audit only, true = active
  EOT
  type = object({
    require_on_resource_groups  = bool
    inherit_from_resource_group = bool
    require_on_resources        = bool
    enforce                     = bool
  })
}

variable "assignments" {
  description = <<-EOT
    Any other built-in policy, keyed by assignment name (max 64 chars):
      display_name            - shown in the portal
      definition_display_name - display name of the built-in policy definition
      enforce                 - false = audit only
      parameters              - policy parameters as plain values, e.g. { listOfAllowedSKUs = ["Standard_D2as_v6"] }
      identity                - true only for Modify / DeployIfNotExists policies
  EOT
  type = map(object({
    display_name            = string
    definition_display_name = string
    enforce                 = optional(bool, false)
    parameters              = optional(any, {})
    identity                = optional(bool, false)
  }))
  default = {}
}
