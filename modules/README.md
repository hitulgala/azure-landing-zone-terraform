# Modules

Nine single-purpose modules, called by both stacks. Rules for every module:
* No provider configuration: stacks pass the right subscription in with `providers = { azurerm = azurerm.<alias> }`.
* No hard-coded deployment values: everything arrives through typed, validated variables.
* `tags` is a required input and is applied to every taggable resource.

| Module | Subscription | What it builds |
|--------|--------------|----------------|
| `monitoring` | Governance | Resource group, Log Analytics workspace, action group, Service Health alert, Activity Log forwarding |
| `network` | Hub / Identity / Workload | Resource group, VNet, subnets, NSGs and rules, route tables, NSG diagnostics |
| `firewall` | Hub | Azure Firewall Standard, firewall policy, rules, diagnostics, health alert |
| `dns` | Hub | DNS Private Resolver, forwarding rules, Private DNS zones (primary only) and VNet links |
| `peering` | Two sides | Both halves of a VNet peering, across subscriptions |
| `key-vault` | Identity | Key Vault (RBAC, purge protection, configurable network access), private endpoint, generated DC password |
| `domain-controllers` | Identity | Optional availability set, DC NICs, OS and data disks, VMs |
| `recovery-vault` | Workload | Recovery Services Vault, daily VM backup policy |
| `policy` | Any (one call per subscription) | Mandatory-tag policies, allowed locations, allowed VM SKUs and other built-in policies |
