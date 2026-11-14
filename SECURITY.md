# Security Policy

## Reporting a vulnerability
Please **do not open a public issue** for security problems. Use **Security → Report a vulnerability** (private advisory) on this repository. Expect an acknowledgement within a few days.

## Scope
This repository is a reference implementation of an Azure Landing Zone deployed through GitHub Actions. Relevant reports include insecure defaults in the modules, secrets handling in Terraform or the pipeline, and documentation that could lead to an insecure deployment.

Known, documented trade-offs (see [docs/decisions.md](docs/decisions.md) and [docs/cicd-pipeline.md](docs/cicd-pipeline.md#security-notes)):
* The generated domain controller password is stored in Key Vault **and** in Terraform state and plan files. Plan artifacts are therefore encrypted.
* Key Vault accepts public network traffic (protected by Entra ID RBAC) while Terraform runs on GitHub-hosted runners.
* The pipeline authenticates with a service principal client secret; OIDC is on the roadmap.

## Keeping the repository clean
* Never commit tenant or subscription IDs, credentials, state files, plan files or `backend.hcl`. `.gitignore` excludes the common cases; IDs belong in `ids.auto.tfvars` locally and in repository variables for CI.
* Keep the service principal secret and the plan passphrase in GitHub Secrets only.
* If a secret is committed by mistake, rotate it immediately, then remove it from history.
