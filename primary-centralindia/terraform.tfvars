# ==============================================================================
# primary-centralindia  |  ALL deployment values live in this file.
# IP plan:  Central India 10.10.0.0/16   South India 10.20.0.0/16
# ==============================================================================

# ------------------------------------------------------------------ Tenant, subscriptions, placement
tenant_id = "4c3b2be2-63ec-40e2-bcb9-56f1caa72da4" # <-- Entra tenant ID

subscription_ids = {
  governance = "baaabd58-ecaf-4bb9-bed8-d32a83075120" # <-- Governance subscription
  hub        = "baaabd58-ecaf-4bb9-bed8-d32a83075120" # <-- Hub subscription
  identity   = "baaabd58-ecaf-4bb9-bed8-d32a83075120" # <-- Identity subscription
  workload   = "baaabd58-ecaf-4bb9-bed8-d32a83075120" # <-- Workload subscription
}

location = "centralindia"

# MANDATORY tags. Every name in mandatory_tag_names must have a value in 'tags'
# (Terraform fails at plan otherwise). 'tags' is applied to EVERY taggable resource, and the
# policies further down enforce the same tags in Azure. The secondary tfvars must use the same values.
mandatory_tag_names = ["environment", "workload", "owner", "cost_center", "managed_by"]

tags = {
  environment = "production"
  workload    = "platform-landing-zone"
  owner       = "platform-team@example.com" # <-- change
  cost_center = "CC-0000"                   # <-- change
  managed_by  = "terraform"
}

# First free address of AzureFirewallSubnet. Must equal the next-hop IP used in the
# spoke route tables and the DNS servers below. A 'check' warns if Azure assigns another.
expected_firewall_private_ip = "10.10.0.4"

# ------------------------------------------------------------------ GOVERNANCE subscription
governance = {
  resource_group_name = "rg-gov-prd-cin-001"

  log_analytics = {
    name              = "log-platform-prd-cin-001"
    retention_in_days = 90
    daily_quota_gb    = -1
  }

  action_group = {
    name       = "ag-platform-prd-cin-001"
    short_name = "platform-ag" # max 12 characters
    email_receivers = {
      platform-team = "platform-team@example.com"
    }
  }

  service_health_alert = {
    name      = "alert-svchealth-prd-cin-001"
    events    = ["Incident", "Maintenance", "ActionRequired", "Security"]
    locations = ["centralindia", "southindia"]
  }

  # Activity Logs are subscription-wide: enabled here (primary), disabled in the secondary.
  activity_log_diagnostics = {
    enabled    = true
    name       = "diag-activitylog-to-law"
    categories = ["Administrative", "Security", "ServiceHealth", "Alert", "Recommendation", "Policy", "Autoscale", "ResourceHealth"]
  }
}

# ------------------------------------------------------------------ HUB subscription
hub = {

  # ---- network: RG, VNet, subnets, NSGs, route tables
  network = {
    resource_group_name     = "rg-net-prd-cin-001"
    diagnostic_setting_name = "diag-nsg-to-law"

    vnet = {
      name          = "vnet-hub-prd-cin-001"
      address_space = ["10.10.0.0/22"]
      dns_servers   = [] # hub uses Azure-provided DNS so the resolver works
    }

    subnets = {
      # Exact names are mandated by Azure for these three.
      AzureFirewallSubnet = {
        address_prefixes = ["10.10.0.0/26"]
        route_table      = "rt-afw-prd-cin-001" # cross-region route (below)
      }
      GatewaySubnet = {
        address_prefixes = ["10.10.0.128/27"] # reserved for on-premises connectivity
      }
      AzureBastionSubnet = {
        address_prefixes = ["10.10.0.192/26"] # reserved for Bastion
      }
      # 10.10.0.64/26 is unallocated (AzureFirewallManagementSubnet if ever needed)

      snet-dns-inbound = {
        address_prefixes = ["10.10.1.0/28"]
        delegation = {
          name         = "dnsresolver"
          service_name = "Microsoft.Network/dnsResolvers"
          actions      = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }
      snet-dns-outbound = {
        address_prefixes = ["10.10.1.16/28"]
        delegation = {
          name         = "dnsresolver"
          service_name = "Microsoft.Network/dnsResolvers"
          actions      = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }
      snet-shared = {
        address_prefixes                  = ["10.10.1.64/26"]
        nsg                               = "nsg-shared-prd-cin-001"
        private_endpoint_network_policies = "Enabled"
      }
    }

    network_security_groups = {
      "nsg-shared-prd-cin-001" = {
        add_deny_all_inbound = true
        rules = {
          "Allow-Internal-PrivateEndpoints" = {
            description                  = "HTTPS and SQL to private endpoints from internal networks"
            priority                     = 100
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["443", "1433"]
            source_address_prefixes      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_address_prefixes = ["10.10.1.64/26"]
          }
        }
      }
    }

    route_tables = {
      # Applied to AzureFirewallSubnet: send the OTHER region's ranges to the OTHER region's firewall.
      "rt-afw-prd-cin-001" = {
        bgp_route_propagation_enabled = true
        routes = {
          "default-to-internet" = {
            address_prefix = "0.0.0.0/0"
            next_hop_type  = "Internet"
          }
          "to-south-india" = {
            address_prefix         = "10.20.0.0/16"
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = "10.20.0.4" # <-- secondary firewall IP; verify after the secondary deploy
          }
        }
      }
    }
  }

  # ---- Azure Firewall (Standard) with its single policy
  firewall = {
    subnet_name              = "AzureFirewallSubnet"
    name                     = "afw-prd-cin-001"
    public_ip_name           = "pip-afw-prd-cin-001"
    policy_name              = "afwp-prd-cin-001"
    sku_tier                 = "Standard"
    zones                    = ["1", "2", "3"]
    threat_intelligence_mode = "Alert"
    dns_proxy_enabled        = true
    dns_servers              = ["10.10.1.4"] # = dns_resolver.inbound_static_ip below
    diagnostic_setting_name  = "diag-afw-to-law"

    rule_collection_group = {
      name     = "rcg-net-prd-cin-001"
      priority = 200
    }

    # Azure Firewall denies everything not allowed. These rules let internal networks use
    # Active Directory and let the DC subnets replicate. Internet egress (e.g. Windows Update)
    # needs application rules and is NOT included.
    network_rule_collections = [
      {
        name     = "allow-active-directory"
        priority = 100
        action   = "Allow"
        rules = [
          {
            name                  = "ad-tcp"
            protocols             = ["TCP"]
            source_addresses      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_addresses = ["10.10.4.0/27", "10.20.4.0/27"] # DC subnets, both regions
            destination_ports     = ["53", "88", "135", "389", "445", "464", "636", "3268", "3269", "9389", "49152-65535"]
          },
          {
            name                  = "ad-udp"
            protocols             = ["UDP"]
            source_addresses      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_addresses = ["10.10.4.0/27", "10.20.4.0/27"]
            destination_ports     = ["53", "88", "123", "389", "464"]
          },
          {
            name                  = "dc-to-dc-replication"
            protocols             = ["Any"]
            source_addresses      = ["10.10.4.0/27", "10.20.4.0/27"]
            destination_addresses = ["10.10.4.0/27", "10.20.4.0/27"]
            destination_ports     = ["*"]
          }
        ]
      },
      {
        name     = "allow-internal-icmp"
        priority = 110
        action   = "Allow"
        rules = [
          {
            name                  = "icmp-internal"
            protocols             = ["ICMP"]
            source_addresses      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_addresses = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_ports     = ["*"]
          }
        ]
      }
    ]

    health_alert = {
      name      = "alert-afw-health-prd-cin"
      severity  = 1
      threshold = 90
    }
  }

  # ---- DNS Private Resolver
  dns_resolver = {
    inbound_subnet_name    = "snet-dns-inbound"
    outbound_subnet_name   = "snet-dns-outbound"
    name                   = "dnspr-prd-cin"
    inbound_endpoint_name  = "dnspr-prd-cin-inbound"
    inbound_static_ip      = "10.10.1.4" # first usable address of snet-dns-inbound
    outbound_endpoint_name = "dnspr-prd-cin-outbound"
    ruleset_name           = "dnspr-prd-cin-ruleset"
    ruleset_vnet_link_name = "link-ruleset-hub-prd-cin"

    # AD domain -> domain controllers (local region first, then the other region). Trailing dot required.
    forwarding_rules = {
      "ad-domain" = {
        domain_name        = "corp.example.com." # replace with your domain name here.
        target_dns_servers = ["10.10.4.4", "10.10.4.5", "10.10.4.6", "10.20.4.4", "10.20.4.5"]
      }
    }
  }

  # ---- Private DNS zones: CREATED here (primary), only LINKED from the secondary
  private_dns = {
    create_zones = true
    #resource_group_name = "rg-net-prd-cin" # same as hub.network.resource_group_name
    resource_group_name = "rg-net-prd-cin-001"
    vnet_link_name      = "link-hub-prd-cin"
    zone_names = [
      "privatelink.vaultcore.azure.net", # Key Vault (used by identity.key_vault below)
      "privatelink.blob.core.windows.net",
      "privatelink.file.core.windows.net",
      "privatelink.database.windows.net"
    ]
  }
}

# ------------------------------------------------------------------ IDENTITY subscription
identity = {

  network = {
    resource_group_name     = "rg-adds-prd-cin-001"
    diagnostic_setting_name = "diag-nsg-to-law"

    vnet = {
      name          = "vnet-adds-prd-cin-001"
      address_space = ["10.10.4.0/24"]
      dns_servers   = ["10.10.0.4"] # hub firewall (DNS proxy). After AD promotion you may switch to the DC IPs.
    }

    subnets = {
      snet-dc-001 = {
        address_prefixes                = ["10.10.4.0/27"]
        nsg                             = "nsg-dc-prd-cin-001"
        route_table                     = "rt-adds-prd-cin-001"
        default_outbound_access_enabled = false
      }
      snet-mgmt-001 = {
        address_prefixes                = ["10.10.4.32/27"]
        nsg                             = "nsg-mgmt-prd-cin-001"
        route_table                     = "rt-adds-prd-cin-001"
        default_outbound_access_enabled = false
      }
      snet-pe-001 = {
        address_prefixes                  = ["10.10.4.64/27"]
        nsg                               = "nsg-pe-prd-cin-001"
        private_endpoint_network_policies = "Enabled"
      }
    }

    network_security_groups = {
      "nsg-dc-prd-cin-001" = {
        add_deny_all_inbound = true
        rules = {
          "Allow-AD-TCP-Inbound" = {
            description                  = "Active Directory TCP from internal networks"
            priority                     = 100
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["53", "88", "135", "389", "445", "464", "636", "3268", "3269", "9389", "49152-65535"]
            source_address_prefixes      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_address_prefixes = ["10.10.4.0/27"]
          }
          "Allow-AD-UDP-Inbound" = {
            description                  = "Active Directory UDP (DNS, Kerberos, NTP, LDAP)"
            priority                     = 110
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Udp"
            destination_port_ranges      = ["53", "88", "123", "389", "464"]
            source_address_prefixes      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_address_prefixes = ["10.10.4.0/27"]
          }
          "Allow-RDP-From-Bastion" = {
            description                  = "RDP from the reserved hub Bastion subnet (remove if you will not use Bastion)"
            priority                     = 200
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["3389"]
            source_address_prefixes      = ["10.10.0.192/26"]
            destination_address_prefixes = ["10.10.4.0/27"]
          }
        }
      }
      "nsg-mgmt-prd-cin-001" = {
        add_deny_all_inbound = true
        rules = {
          "Allow-RDP-From-Bastion" = {
            priority                     = 100
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["3389"]
            source_address_prefixes      = ["10.10.0.192/26"]
            destination_address_prefixes = ["10.10.4.32/27"]
          }
        }
      }
      "nsg-pe-prd-cin-001" = {
        add_deny_all_inbound = true
        rules = {
          "Allow-Internal-HTTPS" = {
            description                  = "HTTPS to the Key Vault private endpoint"
            priority                     = 100
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["443"]
            source_address_prefixes      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_address_prefixes = ["10.10.4.64/27"]
          }
        }
      }
    }

    route_tables = {
      "rt-adds-prd-cin-001" = {
        bgp_route_propagation_enabled = false
        routes = {
          "default-to-firewall" = {
            address_prefix         = "0.0.0.0/0"
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = "10.10.0.4" # hub firewall = expected_firewall_private_ip
          }
        }
      }
    }
  }

  key_vault = {
    name                          = "kv-adds-prd-cin-001" # <-- globally unique, 3-24 chars
    sku_name                      = "standard"
    purge_protection_enabled      = true
    soft_delete_retention_days    = 90
    public_network_access_enabled = true # keep true only while Terraform runs OUTSIDE the VNet
    #allowed_ip_ranges             = ["223.181.58.89"] # <-- your runner's public IP (plain IP, not /32)
    secret_name             = "dc-local-admin-password"
    role_propagation_wait   = "90s"
    diagnostic_setting_name = "diag-kv-to-law"

    private_endpoint = {
      name            = "pe-kv-adds-prd-cin"
      connection_name = "psc-kv-adds-prd-cin"
      subnet_name     = "snet-pe-001" # subnet of identity.network that hosts the endpoint
    }
    private_dns_zone_name = "privatelink.vaultcore.azure.net" # must be in hub.private_dns.zone_names
  }

  domain_controllers = {
    subnet_name = "snet-dc-001"

    settings = {
      admin_username                 = "dcadmin" # <-- change (not Administrator / admin)
      vm_size                        = "Standard_B2ats_v2"
      os_disk_type                   = "StandardSSD_LRS"
      data_disk_type                 = "StandardSSD_LRS"
      ntds_disk_size_gb              = 32
      license_type                   = null # "Windows_Server" to use Azure Hybrid Benefit
      timezone                       = "India Standard Time"
      accelerated_networking_enabled = true
      image = {
        publisher = "MicrosoftWindowsServer"
        offer     = "WindowsServer"
        sku       = "2019-datacenter-gensecond"
        version   = "latest"
      }
    }

    availability_set = {
      name                         = "avset-adds-prd-cin-001"
      platform_fault_domain_count  = 2
      platform_update_domain_count = 5
    } # Comment this block if you do not want VMs in Availability Sets

    # Map key = Windows computer name (max 15 chars). First usable IP is .4
    servers = {
      CINDC01 = {
        vm_name        = "vm-cin-dc01"
        nic_name       = "nic-cindc01"
        os_disk_name   = "osdisk-cindc01"
        ntds_disk_name = "datadisk-cindc01"
        private_ip     = "10.10.4.4"
        zone           = null # Update this to Zone Number "1" if want VMs in Availability Zones
      }
      CINDC02 = {
        vm_name        = "vm-cin-dc02"
        nic_name       = "nic-cindc02"
        os_disk_name   = "osdisk-cindc02"
        ntds_disk_name = "datadisk-cindc02"
        private_ip     = "10.10.4.5"
        zone           = null # Update this to Zone Number "2" if want VMs in Availability Zones
      }
      /* CINDC03 = {
        vm_name        = "vm-adds-cin-dc03"
        nic_name       = "nic-cindc03"
        os_disk_name   = "osdisk-cindc03"
        ntds_disk_name = "datadisk-cindc03"
        private_ip     = "10.10.4.6"
        zone           = "3"
      }*/
    }
  }
}

# ------------------------------------------------------------------ WORKLOAD subscription
workload = {

  network = {
    resource_group_name     = "rg-wld-prd-cin-001"
    diagnostic_setting_name = "diag-nsg-to-law"

    vnet = {
      name          = "vnet-wld-prd-cin-001"
      address_space = ["10.10.8.0/22"]
      dns_servers   = ["10.10.0.4"] # hub firewall (DNS proxy)
    }

    subnets = {
      snet-app-001 = {
        address_prefixes                = ["10.10.8.0/25"]
        nsg                             = "nsg-app-prd-cin-001"
        route_table                     = "rt-wld-prd-cin-001"
        default_outbound_access_enabled = false
      }
      snet-data-001 = {
        address_prefixes                = ["10.10.8.128/26"]
        nsg                             = "nsg-data-prd-cin-001"
        route_table                     = "rt-wld-prd-cin-001"
        default_outbound_access_enabled = false
      }
      snet-pe-001 = {
        address_prefixes                  = ["10.10.8.192/26"]
        nsg                               = "nsg-pe-wld-prd-cin-001"
        private_endpoint_network_policies = "Enabled"
      }
    }

    network_security_groups = {
      "nsg-app-prd-cin-001" = {
        add_deny_all_inbound = true
        rules = {
          "Allow-App-Inbound" = {
            description                  = "Application ports from internal networks"
            priority                     = 100
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["443"] # <-- ports your application listens on
            source_address_prefixes      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_address_prefixes = ["10.10.8.0/25"]
          }
          "Allow-Admin-From-Bastion" = {
            description                  = "RDP/SSH from the reserved hub Bastion subnet (remove if unused)"
            priority                     = 200
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["3389", "22"]
            source_address_prefixes      = ["10.10.0.192/26"]
            destination_address_prefixes = ["10.10.8.0/25"]
          }
        }
      }
      "nsg-data-prd-cin-001" = {
        add_deny_all_inbound = true
        rules = {
          "Allow-SQL-From-App" = {
            description                  = "SQL from the app subnet only"
            priority                     = 100
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["1433"]
            source_address_prefixes      = ["10.10.8.0/25"]
            destination_address_prefixes = ["10.10.8.128/26"]
          }
        }
      }
      "nsg-pe-wld-prd-cin-001" = {
        add_deny_all_inbound = true
        rules = {
          "Allow-Internal-PrivateEndpoints" = {
            description                  = "HTTPS and SQL to private endpoints"
            priority                     = 100
            direction                    = "Inbound"
            access                       = "Allow"
            protocol                     = "Tcp"
            destination_port_ranges      = ["443", "1433"]
            source_address_prefixes      = ["10.10.0.0/16", "10.20.0.0/16"]
            destination_address_prefixes = ["10.10.8.192/26"]
          }
        }
      }
    }

    route_tables = {
      "rt-wld-prd-cin-001" = {
        bgp_route_propagation_enabled = false
        routes = {
          "default-to-firewall" = {
            address_prefix         = "0.0.0.0/0"
            next_hop_type          = "VirtualAppliance"
            next_hop_in_ip_address = "10.10.0.4" # hub firewall = expected_firewall_private_ip
          }
        }
      }
    }
  }

  recovery_vault = {
    vault = {
      name                         = "rsv-wld-prd-cin-001"
      storage_mode_type            = "GeoRedundant"
      cross_region_restore_enabled = true
      immutability                 = "Disabled"
      diagnostic_setting_name      = "diag-rsv-to-law"
    }
    vm_backup_policy = {
      name                           = "bkppolicy-vm-daily"
      timezone                       = "India Standard Time"
      time                           = "23:00"
      daily_retention_days           = 30
      instant_restore_retention_days = 2
    }
  }
}

# ------------------------------------------------------------------ Peering names
peerings = {
  hub_identity = {
    hub_to_spoke = "peer-hub-to-adds-prd-cin-001"
    spoke_to_hub = "peer-adds-to-hub-prd-cin-001"
  }
  hub_workload = {
    hub_to_spoke = "peer-hub-to-wld-prd-cin-001"
    spoke_to_hub = "peer-wld-to-hub-prd-cin-001"
  }
}

# ------------------------------------------------------------------ AZURE POLICY (per subscription, subscription scope)
# Built-in policy definitions are looked up by display name. Names are Azure-defined; if one is
# ever renamed, the plan fails with a clear "policy definition not found" - correct it here.
policy_definition_names = {
  require_tag_on_resource_groups  = "Require a tag on resource groups"
  inherit_tag_from_resource_group = "Inherit a tag from the resource group if missing"
  require_tag_on_resources        = "Require a tag on resources"
}

# Each subscription has its OWN block, so rules can differ per subscription.
#   mandatory_tags.enforce = true : resource groups without the tags are denied and resources
#                                   inherit missing tags from their resource group.
#   assignments.*.enforce  = false: audit only (shown in the compliance report, nothing blocked).
#                                   Set true once the compliance report is clean.
# Assignments take up to ~30 min to become effective. Existing resources need a remediation task.
policies = {

  governance = {
    mandatory_tags = {
      require_on_resource_groups  = true
      inherit_from_resource_group = true
      require_on_resources        = false # not needed while resources inherit from their RG
      enforce                     = true
    }
    assignments = {
      "allowed-locations" = {
        display_name            = "Allowed locations"
        definition_display_name = "Allowed locations"
        enforce                 = false
        parameters              = { listOfAllowedLocations = ["centralindia", "southindia", "global"] }
      }
      "allowed-locations-rg" = {
        display_name            = "Allowed locations for resource groups"
        definition_display_name = "Allowed locations for resource groups"
        enforce                 = false
        parameters              = { listOfAllowedLocations = ["centralindia", "southindia"] }
      }
    }
  }

  hub = {
    mandatory_tags = {
      require_on_resource_groups  = true
      inherit_from_resource_group = true
      require_on_resources        = false
      enforce                     = true
    }
    assignments = {
      "allowed-locations" = {
        display_name            = "Allowed locations"
        definition_display_name = "Allowed locations"
        enforce                 = false
        parameters              = { listOfAllowedLocations = ["centralindia", "southindia", "global"] }
      }
      "allowed-locations-rg" = {
        display_name            = "Allowed locations for resource groups"
        definition_display_name = "Allowed locations for resource groups"
        enforce                 = false
        parameters              = { listOfAllowedLocations = ["centralindia", "southindia"] }
      }
    }
  }

  identity = {
    mandatory_tags = {
      require_on_resource_groups  = true
      inherit_from_resource_group = true
      require_on_resources        = false
      enforce                     = true
    }
    assignments = {
      "allowed-locations" = {
        display_name            = "Allowed locations"
        definition_display_name = "Allowed locations"
        enforce                 = false
        parameters              = { listOfAllowedLocations = ["centralindia", "southindia", "global"] }
      }
      "allowed-locations-rg" = {
        display_name            = "Allowed locations for resource groups"
        definition_display_name = "Allowed locations for resource groups"
        enforce                 = false
        parameters              = { listOfAllowedLocations = ["centralindia", "southindia"] }
      }
      "allowed-vm-skus" = {
        display_name            = "Allowed VM SKUs (domain controllers)"
        definition_display_name = "Allowed virtual machine size SKUs"
        enforce                 = false
        parameters              = { listOfAllowedSKUs = ["Standard_D2as_v6", "Standard_D4as_v6"] } # <-- must include the DC size
      }
      "nic-no-public-ip" = {
        display_name            = "Network interfaces should not have public IPs"
        definition_display_name = "Network interfaces should not have public IPs"
        enforce                 = false
      }
    }
  }

  workload = {
    mandatory_tags = {
      require_on_resource_groups  = true
      inherit_from_resource_group = true
      require_on_resources        = false
      enforce                     = true
    }
    assignments = {
      "allowed-locations" = {
        display_name            = "Allowed locations"
        definition_display_name = "Allowed locations"
        enforce                 = false
        parameters              = { listOfAllowedLocations = ["centralindia", "southindia", "global"] }
      }
      "allowed-locations-rg" = {
        display_name            = "Allowed locations for resource groups"
        definition_display_name = "Allowed locations for resource groups"
        enforce                 = false
        parameters              = { listOfAllowedLocations = ["centralindia", "southindia"] }
      }
      "allowed-vm-skus" = {
        display_name            = "Allowed VM SKUs (application servers)"
        definition_display_name = "Allowed virtual machine size SKUs"
        enforce                 = false
        parameters              = { listOfAllowedSKUs = ["Standard_D2as_v6", "Standard_D4as_v6", "Standard_D8as_v6"] } # <-- adjust to your approved sizes
      }
      "nic-no-public-ip" = {
        display_name            = "Network interfaces should not have public IPs"
        definition_display_name = "Network interfaces should not have public IPs"
        enforce                 = false
      }
    }
  }
}
