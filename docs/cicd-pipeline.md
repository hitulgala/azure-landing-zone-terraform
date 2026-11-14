# CI/CD pipeline

The landing zone is deployed by two GitHub Actions workflows. Nothing reaches Azure without a reviewed plan and an explicit approval.

```
feature branch -> pull request -> Terraform Plan (pull_request)
                                  plan shown in the run Summary; nothing is deployed

merge to main  -> Terraform Plan (push)
                  bootstrap -> fmt -> init -> validate -> plan -> encrypted plan bundle
               -> Terraform Apply (workflow_run)
                  check : plan succeeded? on main? not a PR? any changes?
                  apply : wait for 'prod' approval -> apply the exact saved plan -> summary
```

## Workflows
| File | Trigger | What it does |
|------|---------|--------------|
| `terraform-plan.yml` | Pull request into `main`, push to `main`, manual | Bootstraps the backend, checks formatting of the whole repo, runs `init`, `validate` and `plan`, writes the plan to the run Summary. On `main` and manual runs it uploads an encrypted plan bundle (plan, `backend.hcl`, change flag) for 5 days |
| `terraform-apply.yml` | Completion of **Terraform Plan** | Skips PR runs and plans without changes. Otherwise pauses on the `prod` environment, checks out the planned commit, decrypts the plan and runs `terraform apply tfplan` |

Key behaviours:
* **The reviewed plan is the applied plan.** Apply never re-plans and never uses `-auto-approve`. If the state changed after planning, Terraform refuses with *saved plan is stale*.
* **No changes, no approval.** `terraform plan -detailed-exitcode` sets a flag; apply is skipped when nothing would change.
* **Applies are never cancelled.** The apply workflow uses `cancel-in-progress: false`. Plan runs for the same branch or PR cancel older ones.
* **The pipeline currently covers `primary-centralindia`.** The secondary stack is deployed from a laptop until it is added.

## Setup

### 1. Azure service principal
```powershell
$sub = "<subscription-id>"
az ad sp create-for-rbac --name "gh-alz-terraform" --role "Contributor" --scopes "/subscriptions/$sub" --json-auth
# copy the JSON output: it becomes the TERRAFORM_SP secret

$appId = "<clientId from the JSON>"
az role assignment create --assignee $appId --role "User Access Administrator"   --scope "/subscriptions/$sub"
az role assignment create --assignee $appId --role "Resource Policy Contributor" --scope "/subscriptions/$sub"
```
Repeat the role assignments for every subscription in `subscription_ids`.

| Role | Needed for |
|------|-----------|
| Contributor | All resources |
| User Access Administrator | Role assignments: Key Vault Secrets Officer for the deployer, policy managed identities, Storage Blob Data Contributor and the delete lock created by the bootstrap |
| Resource Policy Contributor | Azure Policy assignments |

User Access Administrator can grant any role, so treat this identity as Owner-equivalent and protect its secret accordingly.

### 2. GitHub variables and secrets
**Settings → Secrets and variables → Actions.** Create these at **repository** level: the plan job has no environment, so it cannot read environment-level values.

| Name | Type | Value |
|------|------|-------|
| `TF_SUBSCRIPTION_ID` | Variable | Subscription that holds the state storage account (governance) |
| `TF_STATE_RG` | Variable | State resource group name |
| `TF_STATE_STORAGE` | Variable | State storage account name (globally unique) |
| `TF_VERSION` | Variable | Exact Terraform version, e.g. `1.13.4`. Plan and apply must use the same version |
| `AZURE_TENANT_ID` | Variable | Entra tenant ID |
| `TF_SUBSCRIPTION_IDS` | Variable | One line of JSON: `{"governance":"<id>","hub":"<id>","identity":"<id>","workload":"<id>"}` |
| `TERRAFORM_SP` | Secret | JSON from `az ad sp create-for-rbac --json-auth` |
| `TF_PLAN_PASSPHRASE` | Secret | Random string used to encrypt the plan artifact |

Generate the passphrase in PowerShell 7:
```powershell
[Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
```

### 3. The `prod` environment
**Settings → Environments → New environment → `prod`**
* **Required reviewers:** at least one person. Leave *Prevent self-review* unchecked if you work alone.
* **Deployment branches and tags:** selected branches, `main` only.

### 4. Protect `main`
**Settings → Rules → Rulesets → New branch ruleset**, targeting the default branch:
* Restrict deletions, block force pushes
* Require a pull request before merging (allowed merge method: squash)
* Require status check `plan (primary-centralindia)`, with branches up to date before merging

Do not add a `paths:` filter to the pull request trigger: a required check that never runs blocks every merge.

## Day-to-day flow
```powershell
git switch main ; git pull origin main
git switch -c feat/<topic>
# edit, then:
terraform fmt -recursive
git commit -am "feat(scope): summary"
git push -u origin feat/<topic>
gh pr create --fill
gh pr checks --watch            # read the plan in the run Summary
gh pr merge --squash --delete-branch
```
After the merge, review the plan of the new **Terraform Plan** run on `main` and approve **Terraform Apply**: in the browser (**Review deployments → prod → Approve and deploy**) or with the GitHub CLI:
```powershell
$repo  = "<owner>/<repo>"
$runId = gh run list --workflow "Terraform Apply" --limit 1 --json databaseId --jq '.[0].databaseId'
$envId = gh api "repos/$repo/environments/prod" --jq '.id'
gh api "repos/$repo/actions/runs/$runId/pending_deployments" -X POST `
  -F "environment_ids[]=$envId" -f state=approved -f comment="Plan reviewed"
```

## Recovery
| Situation | What to do |
|-----------|-----------|
| Apply failed halfway | Do **not** re-run the failed job. Fix the cause, then **Actions → Terraform Plan → Run workflow** on `main` and approve the new plan |
| *Saved plan is stale* | Another apply changed the state. Re-plan and approve the newest run |
| Approval came after the artifact expired (5 days) | Re-run Terraform Plan |
| Two merges close together | Approve the newest apply, reject older ones |
| State lock left behind by a cancelled run | Confirm nothing is running, then break the lease on the state blob or run `terraform force-unlock <lock-id>` locally |

## Security notes
* The plan file contains state, including the generated DC password. It is encrypted with `TF_PLAN_PASSPHRASE` before upload and kept for 5 days.
* In a public repository, workflow logs and run summaries are visible to everyone. Terraform masks values marked `sensitive`, but names, addresses and IPs are shown.
* Workflows triggered from forks receive no secrets, so they cannot reach Azure.
* `TERRAFORM_SP` is a long-lived client secret. Rotate it regularly; moving to OIDC removes it entirely (roadmap).
* Key Vault accepts public network traffic because GitHub-hosted runners have no fixed IP; access is still restricted by Entra ID RBAC. See [deployment-and-dr.md](deployment-and-dr.md#key-vault-network-access).

## Troubleshooting
| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `fmt` step fails | Unformatted files | `terraform fmt -recursive`, commit, push |
| `No value for required variable "tenant_id"` | `AZURE_TENANT_ID` missing or created in an environment | Create it as a repository variable |
| `Invalid value for input variable "subscription_ids"` | `TF_SUBSCRIPTION_IDS` is not valid JSON or misses a key | Re-enter it on one line with all four keys |
| Terraform Apply never starts | Apply file not on `main`, or the plan workflow was renamed | Keep both files on `main`; the plan workflow must be named `Terraform Plan` |
| Apply runs without asking for approval | No required reviewer on `prod` (private repo on GitHub Free) | Make the repository public or use a paid plan |
| `check plan` cannot find the artifact | The plan run was a PR, or failed before upload | Re-run Terraform Plan on `main` |
| `Decrypt plan` fails | `TF_PLAN_PASSPHRASE` changed between plan and apply | Re-run Terraform Plan |
| Required check stays *Expected* | The plan workflow did not run for that PR | Do not filter the pull request trigger by path |
