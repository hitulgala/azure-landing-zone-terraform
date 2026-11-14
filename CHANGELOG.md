# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-11-14
First public release.

### Added
- Hub-and-spoke landing zone for Central India (primary) and South India (secondary) across four subscriptions, as two regional stacks with provider aliases.
- Nine modules: monitoring, network, firewall, dns, peering, key-vault, domain-controllers, recovery-vault, policy.
- Mandatory tags validated at plan, applied to every taggable resource and enforced by subscription-scope Azure Policy (audit first, then enforce).
- `scripts/Bootstrap-TerraformBackend.ps1`: idempotent creation of the GZRS state storage account with Entra ID authentication only.
- GitHub Actions pipeline: **Terraform Plan** on pull requests and `main`; **Terraform Apply** started by `workflow_run`, gated by the `prod` environment, applying the exact reviewed and encrypted plan.
- `ids.auto.tfvars.example`: tenant and subscription IDs kept out of Git (local file, `TF_VAR_*` in CI).
- Documentation: CI/CD pipeline, deployment and DR, design decisions, architecture diagrams, contributing guide, security policy, issue and pull request templates, Dependabot configuration.

[Unreleased]: https://github.com/hitulgala/azure-landing-zone-terraform/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hitulgala/azure-landing-zone-terraform/releases/tag/v1.0.0
