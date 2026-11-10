# Modules

| Module | Subscription | What it builds |
|--------|--------------|----------------|
| `monitoring` | Governance | RG, Log Analytics, action group, Service Health alert, Activity Log forwarding |
| `network` | Hub / Identity / Workload | RG, VNet, subnets, NSGs + rules, route tables, NSG diagnostics |
| `firewall` | Hub | Azure Firewall Standard, policy, rules, diagnostics, health alert |
| `dns` | Hub | DNS Private Resolver, Private DNS zones and VNet links |
| `peering` | Hub + spoke | Both halves of a VNet peering |
| `key-vault` | Identity | Key Vault, private endpoint, generated DC password |
| `domain-controllers` | Identity | Availability set (optional), DC NICs/disks/VMs |
| `recovery-vault` | Workload | Recovery Services Vault, VM backup policy |
| `policy` | Any (one call per subscription) | Mandatory-tag policies, allowed VM SKUs, allowed locations, other built-in policies |

