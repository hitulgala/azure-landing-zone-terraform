# Inputs for the domain-controllers module (values come from terraform.tfvars).
variable "resource_group_name" {
  description = "Identity resource group (created by the network module)."
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

variable "subnet_id" {
  description = "Domain controller subnet ID."
  type        = string
}

variable "admin_password" {
  description = "Local administrator password (from the key-vault module)."
  type        = string
  sensitive   = true
}

variable "settings" {
  description = "VM settings shared by all DCs. Gen2 image SKU is required for the v6 VM series."
  type = object({
    admin_username                 = string
    vm_size                        = string
    os_disk_type                   = string
    data_disk_type                 = string
    ntds_disk_size_gb              = number
    license_type                   = string # "Windows_Server" for Hybrid Benefit, or null
    timezone                       = string
    accelerated_networking_enabled = bool
    image = object({
      publisher = string
      offer     = string
      sku       = string
      version   = string
    })
  })
}

variable "availability_set" {
  description = "Availability set for regions WITHOUT Availability Zones; null when DCs use zones."
  type = object({
    name                         = string
    platform_fault_domain_count  = number
    platform_update_domain_count = number
  })
  default = null
}

variable "domain_controllers" {
  description = "Map of computer name (max 15 chars) => DC definition. zone = \"1\"/\"2\"/\"3\" or null."
  type = map(object({
    vm_name        = string
    nic_name       = string
    os_disk_name   = string
    ntds_disk_name = string
    private_ip     = string
    zone           = optional(string)
  }))

  validation {
    condition     = alltrue([for name in keys(var.domain_controllers) : length(name) <= 15])
    error_message = "Domain controller map keys are Windows computer names and must be 15 characters or fewer."
  }

  validation {
    condition = var.availability_set == null ? (
      alltrue([for dc in values(var.domain_controllers) : dc.zone != null])
      ) : (
      alltrue([for dc in values(var.domain_controllers) : dc.zone == null])
    )
    error_message = "With availability_set = null every DC needs a zone; with an availability set every zone must be null."
  }
}
