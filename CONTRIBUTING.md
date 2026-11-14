# Contributing

## Ground rules
* Deployment values go in `terraform.tfvars`; tenant and subscription IDs go in `ids.auto.tfvars` (never committed).
* Modules never configure providers and always accept `tags`.
* No commented-out code: make optional behaviour a variable in tfvars instead.
* Never commit state, plan files, `backend.hcl`, `ids.auto.tfvars` or secrets. Run `git status` before every commit.

## Workflow
`main` is protected: every change goes through a pull request and a passing **Terraform Plan** check.

```powershell
git switch main ; git pull origin main          # always start from the latest main
git switch -c feat/<topic>                      # feat/, fix/, chore/, docs/
# make the change
terraform fmt -recursive
cd primary-centralindia ; terraform validate ; terraform plan ; cd ..
git add <files>
git commit -m "feat(scope): short summary"
git push -u origin feat/<topic>
gh pr create --fill
```
Read the plan in the pull request's run Summary before merging. Keep one logical change per pull request.

## Commit messages
[Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`.

| Type | Use for |
|------|---------|
| `feat` | New capability or resource |
| `fix` | Bug fix |
| `chore` | Maintenance with no behaviour change |
| `docs` | Documentation only |
| `ci` | Workflow changes |
| `style` | Formatting only |

## Keeping your local copy current
```powershell
git switch main ; git pull origin main ; git fetch --prune
git branch -D <merged-branch>        # -D because squash merges create a new commit
```
If your pull request falls behind `main`, click **Update branch** or run `git fetch origin`, `git rebase origin/main` and `git push --force-with-lease`.
