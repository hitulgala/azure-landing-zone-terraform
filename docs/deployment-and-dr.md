# Deployment notes and DR outline

## Permissions
Roles are assigned outside this repository. The identity that runs Terraform (the pipeline's service principal, or you when running locally) needs on **every subscription** in `subscription_ids`:

| Role | Why |
|------|-----|
| Contributor | Creates and manages all resources |
| User Access Administrator | Creates role assignments: Key Vault Secrets Officer for the deployer, roles for the policy managed identities, and (in the bootstrap) Storage Blob Data Contributor and a delete lock |
| Resource Policy Contributor | Creates the Azure Policy assignments |

The bootstrap script grants the caller **Storage Blob Data Contributor** on the state storage account, because the backend uses Entra ID authentication only (no storage keys).

## Deployment order
1. **Backend.** `scripts/Bootstrap-TerraformBackend.ps1` creates the state resource group, storage account, container and a `backend.hcl` in each stack folder. The pipeline runs it on every plan; it is idempotent.
2. **Primary** (`primary-centralindia`): through the pipeline (see [cicd-pipeline.md](cicd-pipeline.md)).
3. **Secondary** (`secondary-southindia`): currently from a laptop, after the primary succeeded. Copy `hub_network_resource_group_name` and `hub_vnet_name` from the primary outputs into its `primary_hub` block (they match the defaults if you kept the naming).
4. **Verify the firewall IPs.** Each region's firewall IP is hard-wired in tfvars (spoke routes, DNS servers and the other region's hub route). A `check` block warns during apply if Azure assigned a different address than `expected_firewall_private_ip`. If it does, correct that IP everywhere in the affected tfvars and re-apply both stacks.

## Key Vault network access
GitHub-hosted runners use a different public IP on every run, so the vault cannot be locked to an IP allow-list while Terraform runs from them. The vault therefore accepts public network traffic and relies on Entra ID RBAC (`rbac_authorization_enabled = true`), in addition to its private endpoint.

When Terraform runs from inside the network (a self-hosted runner in the hub or identity VNet):
* restrict network access with the Key Vault network settings in `identity.key_vault` (default action and `allowed_ip_ranges`, plain IPs without `/32`), or
* set `identity.key_vault.public_network_access_enabled = false` to allow the private endpoint only.

## Azure Policy
* Assigned by the **primary** stack only. Policy is subscription-wide, so resources of the secondary region are covered too.
* Roll out in two steps: deploy with `enforce = false` (audit), review **Portal → Policy → Compliance**, then set `enforce = true` in a separate pull request.
* Assignments take up to about 30 minutes to become effective.
* Before enforcing the mandatory-tag policies, make sure every resource group carries all mandatory tags, **including the state resource group** created by the bootstrap script (its `-Tags` parameter). Resource groups created later without the tags are denied.
* Tag inheritance (Modify) only affects resources created or updated after assignment. For existing resources, run a remediation task (**Portal → Policy → Remediation**).
* The domain controller VM size must be in the identity `allowed-vm-skus` list before that assignment is enforced.

## After the first apply
1. Read the DC password from the Key Vault secret (outputs `key_vault_name` and `key_vault_secret_name`). Rotate it after promotion.
2. Promote the DCs manually and put NTDS, logs and SYSVOL on the data disk. Central India: create the forest on the first DC, then add the others. South India: add its DCs as additional domain controllers.
3. AD Sites and Services: one site per region with its subnets, an inter-site link, and **change notification enabled on the link** (default replication interval is 180 minutes) so cross-region RPO is minutes.
4. Make all DCs global catalog servers, keep the FSMO roles on a Central India DC, and enable **AD Recycle Bin**.
5. Optionally set the identity VNet `dns_servers` to the DC IPs once DNS is healthy.

## DR outline (active-passive)
| Failure | Domain controllers | Workload VMs (created outside this repo) |
|---------|--------------------|-------------------------------------------|
| Host or rack (Central India) | Automatic: the other DC in the availability set keeps serving | Per application design |
| Availability zone (Central India) | The availability set is not zonal, so both DCs may be affected: clients use the South India DCs. Give each DC a zone in tfvars for zone resilience | Per application design |
| Region | Automatic: clients use the other region's DCs; seize FSMO roles only if needed | Azure Site Recovery to South India with the secondary-region vault, recovery plan, then repoint DNS |
| Deletion or corruption | No backup by design; use AD Recycle Bin | Azure Backup with the VM backup policy defined in tfvars |

Never restore a DC from a snapshot or an ASR replica (USN rollback). If Central India is down, the secondary stack still needs the state storage account; GZRS storage failover is customer-initiated.

The pipeline itself depends on GitHub, the state storage account and the service principal. If any of them is unavailable during an incident, deploy from a laptop with the same backend and record the change in a pull request afterwards.
