# ==============================================================================
# Module  : domain-controllers   (IDENTITY subscription)
# Purpose : Domain-controller-ready Windows Server VMs (NO AD DS promotion):
#             optional availability set + per DC: NIC (static private IP, no public
#             IP), OS disk, dedicated NTDS data disk, VM.
#
# Placement (set in tfvars)
#   Region WITH Availability Zones  : availability_set = null, each DC has a zone
#   Region WITHOUT Availability Zones: availability_set = {...}, every zone = null
#
# NTDS disk: AD database/logs go on a separate disk with host caching = None
# (Microsoft guidance). Choose it for NTDS, logs and SYSVOL during promotion.
# ==============================================================================
resource "azurerm_availability_set" "this" {
  count = var.availability_set == null ? 0 : 1

  name                         = var.availability_set.name
  resource_group_name          = var.resource_group_name
  location                     = var.location
  managed                      = true
  platform_fault_domain_count  = var.availability_set.platform_fault_domain_count
  platform_update_domain_count = var.availability_set.platform_update_domain_count
  tags                         = var.tags
}

resource "azurerm_network_interface" "this" {
  for_each = var.domain_controllers

  name                           = each.value.nic_name
  resource_group_name            = var.resource_group_name
  location                       = var.location
  accelerated_networking_enabled = var.settings.accelerated_networking_enabled
  tags                           = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static" # DCs need fixed IPs
    private_ip_address            = each.value.private_ip
  }
}

resource "azurerm_managed_disk" "ntds" {
  for_each = var.domain_controllers

  name                 = each.value.ntds_disk_name
  resource_group_name  = var.resource_group_name
  location             = var.location
  storage_account_type = var.settings.data_disk_type
  create_option        = "Empty"
  disk_size_gb         = var.settings.ntds_disk_size_gb
  zone                 = each.value.zone # must match the VM zone; null with an availability set
  tags                 = var.tags
}

resource "azurerm_windows_virtual_machine" "this" {
  for_each = var.domain_controllers

  name                  = each.value.vm_name
  computer_name         = each.key # NetBIOS name, max 15 chars
  resource_group_name   = var.resource_group_name
  location              = var.location
  size                  = var.settings.vm_size
  admin_username        = var.settings.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.this[each.key].id]
  zone                  = each.value.zone
  availability_set_id   = var.availability_set == null ? null : azurerm_availability_set.this[0].id
  license_type          = var.settings.license_type # "Windows_Server" = Azure Hybrid Benefit
  timezone              = var.settings.timezone
  tags                  = var.tags

  os_disk {
    name                 = each.value.os_disk_name
    caching              = "ReadWrite"
    storage_account_type = var.settings.os_disk_type
  }

  source_image_reference {
    publisher = var.settings.image.publisher
    offer     = var.settings.image.offer
    sku       = var.settings.image.sku
    version   = var.settings.image.version
  }

  boot_diagnostics {} # managed boot diagnostics, no storage account needed
}

resource "azurerm_virtual_machine_data_disk_attachment" "ntds" {
  for_each = var.domain_controllers

  managed_disk_id    = azurerm_managed_disk.ntds[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.this[each.key].id
  lun                = 0
  caching            = "None"
}
