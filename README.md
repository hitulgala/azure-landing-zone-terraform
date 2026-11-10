# Azure Landing Zone - Terraform

Hub-and-spoke landing zone for **Central India (primary)** and **South India (secondary, active-passive)** across four existing subscriptions: Governance, Hub, Identity, Workload.

**One rule drives the design: every value lives in `terraform.tfvars`.** Names, subnet prefixes, NSG rules, routes, firewall rules, VM settings, e-mail addresses - all of it. The `.tf` files only wire modules together, so you can clone the repo, edit one file per region, and deploy.

## Layout
```
scripts/New-TerraformBackend.ps1   creates the state storage account + folders + backend.hcl files
modules/                           8 single-purpose modules (see modules/README.md)
primary-centralindia/              main.tf + terraform.tfvars  (all four subscriptions, primary region)
secondary-southindia/              main.tf + terraform.tfvars  (all four subscriptions, secondary region)
docs/                              decisions and post-deployment/DR notes
```
Each region folder contains the same files: `main.tf` (wiring), `variables.tf` (declarations), **`terraform.tfvars` (your values)**, `providers.tf`, `backend.tf`, `versions.tf`, `outputs.tf`.

## Deploy
```powershell
# 1. Once: create the remote backend (governance subscription)
.\scripts\New-TerraformBackend.ps1 -SubscriptionId "<governance-sub-id>" `
    -ResourceGroupName "rg-tfstate-prd-cin" -StorageAccountName "<unique-name>"

# 2. Primary region
cd primary-centralindia
#   edit terraform.tfvars (search for "<--")
terraform init -backend-config="backend.hcl"
terraform plan -out tfplan
terraform apply tfplan

# 3. Secondary region (after the primary succeeded)
cd ..\secondary-southindia
#   edit terraform.tfvars (same IDs; the primary_hub block comes from the primary's outputs)
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan
```
After both applies, compare the two `firewall_private_ip` outputs with the firewall IPs written in the other region's tfvars (see `docs/deployment-and-dr.md`).

## Mandatory tags and Azure Policy
**Tags.** `mandatory_tag_names` in tfvars lists the tags every resource must carry (default: `environment`, `workload`, `owner`, `cost_center`, `managed_by`). Four layers keep them mandatory:
1. `terraform plan` fails if `tags` lacks a value for any mandatory name.
2. `tags` is a **required** input of every module, and is applied to all 26 taggable resource definitions (audited).
3. Azure Policy (below) denies resource groups without the tags and makes resources inherit missing tags from their resource group.
4. Resource types that Azure cannot tag (subnets, NSG rules, peerings, diagnostic settings, role assignments, ...) are skipped automatically.

**Policy, per subscription.** Policies are assigned at **subscription scope** (no management group) from the `policies` block of the *primary* tfvars - policy is not regional, so the secondary does not repeat it. Every subscription has its own block, so rules can differ: tag enforcement, allowed locations, allowed VM SKUs, "no public IP on NICs", or any other built-in policy added by display name. Assignments start in **audit mode** (`enforce = false`), except the mandatory-tag policies.

## What each region builds
| Subscription | Resources |
|--------------|-----------|
| Governance | RG, Log Analytics workspace, action group, Service Health alert, Activity Log forwarding (primary only) |
| Hub | RG, VNet, Azure Firewall Standard + policy + rules, DNS Private Resolver, Private DNS zones (created in primary, linked from secondary), cross-region UDR |
| Identity | RG, VNet, NSGs, route table, Key Vault + private endpoint, DC VMs (3 zonal in Central India; 2 in an availability set in South India). **No AD DS promotion.** |
| Workload | RG, VNet, NSGs, route table, Recovery Services Vault + daily VM backup policy. **No VMs.** |

## IP plan
| Region | Supernet | Hub | Identity | Workload |
|--------|----------|-----|----------|----------|
| Central India | 10.10.0.0/16 | 10.10.0.0/22 | 10.10.4.0/24 | 10.10.8.0/22 |
| South India   | 10.20.0.0/16 | 10.20.0.0/22 | 10.20.4.0/24 | 10.20.8.0/22 |

