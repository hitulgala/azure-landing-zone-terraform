# Architecture diagrams

All diagrams are kept as text in [`docs/diagrams/`](diagrams) (Mermaid) and exported as PNG to [`docs/images/`](images). Edit the `.mmd` source, then regenerate the image:

```powershell
npx -p @mermaid-js/mermaid-cli mmdc -i docs/diagrams/05-identity-dr.mmd -o docs/images/05-identity-dr.png -b white -s 2
```

IP addresses shown are the defaults from `terraform.tfvars`; if you change the address plan, update the diagrams too.

## Overview
![Architecture overview](images/architecture.png)

Editable vector version: [architecture.svg](images/architecture.svg).

## 1. Landscape
Four subscriptions per region; hubs connected by global VNet peering.

![Landscape](images/01-landscape.png)

## 2. Network topology
Hub-and-spoke per region with Azure Firewall and DNS Private Resolver in each hub.

![Network topology](images/02-network-topology.png)

## 3. DNS resolution
Spoke VMs query the firewall DNS proxy, which forwards to the resolver; AD names go to the domain controllers, privatelink names to the Private DNS zones.

![DNS resolution](images/03-dns-resolution.png)

## 4. Cross-region traffic
Spoke traffic to the other region passes through both firewalls.

![Cross-region traffic](images/04-cross-region-traffic.png)

## 5. Identity and DR
Domain controllers in availability sets (optional third DC in Central India), one AD site per region with change notification on the site link.

![Identity and DR](images/05-identity-dr.png)

## 6. Deployment flow
![Deployment flow](images/06-deployment-flow.png)

## 7. Terraform module dependencies
![Terraform dependencies](images/07-terraform-dependencies.png)

## 8. State and providers
One state file per stack in the governance subscription; four aliased providers per stack.

![State and providers](images/08-state-and-providers.png)

## 9. Policy model
![Policy model](images/09-policy-model.png)

## 10. CI/CD pipeline
From feature branch to an approved apply of the reviewed plan. Details: [cicd-pipeline.md](cicd-pipeline.md).

![CI/CD pipeline](images/10-ci-pipeline.png)

## 11. Failure scenarios
![Failure scenarios](images/11-failure-scenarios.png)
