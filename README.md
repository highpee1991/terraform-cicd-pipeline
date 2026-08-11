# terraform-cicd-pipeline — Runbook

A GitHub Actions pipeline that manages Azure infrastructure through Terraform, so no engineer ever runs `terraform apply` by hand against production. Every infrastructure change goes through a pull request; the pipeline validates and plans it, and only applies once that change is merged to `main`.

## Scenario

> No engineer manually runs `terraform apply` in production ever again. Every infrastructure change goes through a pull request. The pipeline validates it, posts the plan as a comment, and applies it only when the PR is merged to main. If it fails, it fails in the pipeline, not in production.

## Repository layout

```
terraform-cicd-pipeline/
├── .github/
│   └── workflows/
│       └── terraform.yml
├── environments/
│   └── payments/
│       ├── providers.tf      # backend + provider blocks
│       ├── main.tf           # module call + variable declarations + outputs
│       └── terraform.tfvars  # non-sensitive config values
└── modules/
    └── infrastructure/
        ├── main.tf           # resource group, vnet, subnet, NSG, public IP, NIC, VM
        ├── variables.tf
        ├── outputs.tf
        └── cloud-init.yaml   # VM provisioning script
```

`modules/infrastructure` and `environments/payments` were copied over from an earlier `terraform-enterprise` project and reused here as the scope this pipeline manages.

## Backend (created manually, same as prior projects)

```bash
az group create --name ci-cd-pipeline-backend-rg --location eastus
az storage account create --name cicdpipestorageacc --resource-group ci-cd-pipeline-backend-rg --location eastus --sku Standard_LRS --kind StorageV2
az storage container create --name ci-cd-container --account-name cicdpipestorageacc --auth-mode login
```

## Azure authentication for the pipeline

A Service Principal, not a personal account, authenticates the pipeline to Azure:

```bash
MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
  --name "github-actions-terraform" \
  --role Contributor \
  --scopes /subscriptions/<subscription-id> \
  --sdk-auth
```

`MSYS_NO_PATHCONV=1` is needed on Git Bash / Windows specifically — without it, MSYS silently rewrites `/subscriptions/...` into a local filesystem path before Azure CLI ever sees it, causing a confusing `MissingSubscription` error that has nothing to do with the subscription ID itself.

Store the four values as separate GitHub repository secrets (Settings → Secrets and variables → Actions): `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`.

Two separate things read these secrets, for two separate reasons:

- **`azure/login` action** — logs the Azure CLI itself into the runner, useful for any plain `az` commands in the workflow.
- **`ARM_CLIENT_ID` / `ARM_CLIENT_SECRET` / `ARM_SUBSCRIPTION_ID` / `ARM_TENANT_ID` environment variables**, set at job level — this is what the `azurerm` Terraform provider and backend actually authenticate with. Terraform does not inherit the Azure CLI's login session automatically; without these, `terraform init` fails with "Authenticating using the Azure CLI is only supported as a User (not a Service Principal)."

Both are needed. Neither replaces the other.

## Workflow structure

Three jobs, run in sequence via `needs:`:

1. **`terraform-validate`** — `terraform init`, `terraform fmt -check -recursive`, `terraform validate`. Runs on every push and pull request.
2. **`terraform-plan`** — `terraform init`, `terraform plan -input=false -out=tfplan`, then uploads the plan file as a build artifact.
3. **`terraform-apply`** — downloads the plan artifact, `terraform init`, `terraform apply -input=false -auto-approve tfplan`. Gated by:
   ```yaml
   if: github.ref == 'refs/heads/main' && github.event_name == 'push'
   ```
   This is what enforces the actual rule from the scenario — apply only fires on a real push to `main`, which in practice means only after a PR has been merged, never on the PR itself.

`-input=false` on both `plan` and `apply` is deliberate: without it, Terraform silently waits forever for interactive input if a required variable is missing, and a GitHub Actions runner has no one there to answer. With it, a missing variable fails immediately and visibly instead of hanging indefinitely.

## Variables and secrets

Non-sensitive config (`project_name`, `admin_username`, `address_space`, `subnet_prefix`, `environment`, `backend_state_key`) lives in `terraform.tfvars`, committed to the repo. **`.gitignore` had a `*.tfvars` rule by default that silently excluded this file from every push** — the pipeline checks out only what's actually in the GitHub repo, never anything from a local machine, so a gitignored file simply doesn't exist as far as the runner is concerned. Removing that rule and committing the file was the fix.

`ssh_public_key` is passed as a `TF_VAR_ssh_public_key` environment variable sourced from a GitHub secret, since it's easier to manage as a secret and doesn't need to be a literal file path — the module accepts the key's raw text content (`var.ssh_public_key`) directly, not a path plus a `file()` call, since a file path resolved on a CI runner would point at a file that doesn't exist there.

## VM provisioning via cloud-init

Rather than SSHing into the VM from the pipeline after creation, provisioning happens automatically at boot via `custom_data`:

```hcl
custom_data = filebase64("${path.module}/cloud-init.yaml")
```

```yaml
#cloud-config
package_update: true
package_upgrade: true

packages:
  - nginx
  - git

runcmd:
  - rm -rf /var/www/html
  - git clone https://github.com/highpee1991/cloud-devops-portfolio-repo.git /var/www/html
  - systemctl enable nginx
  - systemctl restart nginx
```

This is the more standard, declarative way to provision a VM's initial software with Terraform — no private SSH key needs to live in the pipeline's secrets, and the VM configures itself the moment it exists.

Important behavior: any change to `custom_data` forces a full VM destroy-and-recreate on the next apply, since it can't be changed on a running VM. A new VM also gets brand-new SSH host keys, which will trigger a "REMOTE HOST IDENTIFICATION HAS CHANGED" warning locally — clear it with `ssh-keygen -R <ip>` before reconnecting.

## Troubleshooting log

- **`//subscriptions/...` or `MissingSubscription`** — a leading single slash gets silently rewritten into a Windows path by Git Bash. Fix: `MSYS_NO_PATHCONV=1` before the command.
- **JSON syntax errors in the `azure/login` creds block** — every property in the JSON needs a trailing comma except the last one; this is plain JSON syntax, unrelated to GitHub Actions expressions.
- **Job casing mismatches** (`Terraform-validate` vs `needs: terraform-validate`) — job IDs are case-sensitive.
- **`Terraform_version` vs `terraform_version`, capitalized `terraform Init`/`Validate`** — GitHub Actions input keys and Terraform CLI subcommands are both case-sensitive and lowercase-only respectively.
- **Silent multi-minute hang with no error** — Terraform waiting on interactive input for a missing variable, with no one there to answer it. Fixed with `-input=false`; the missing variable then fails immediately with a clear message instead.
- **"Error acquiring the state lock" / "state blob is already locked"** — an orphaned lock left behind after a run was cancelled or a network connection dropped mid-operation. Fix: `terraform force-unlock <lock-id>` run locally against the same backend (the lock lives on the Azure Storage blob itself, not inside GitHub Actions — any client authenticated to that backend can clear it).
- **`Error: Invalid function argument` on `file(pathexpand(var.ssh_public_key_path))`** — a file path that exists on a local machine does not exist on a disposable CI runner. Fix: pass the key's actual text content as a variable instead of a path.
- **Portfolio site not appearing, but no visible error** — cloud-init's `#cloud-config` header must be exactly that, no space (`# cloud config` is read as an ordinary comment and the whole file is silently ignored). Separately, cloud-init's real key names use underscores, not hyphens (`package_update`, not `package-update`) — a schema validation failure here can cause the whole final-stage module to be skipped with no obvious error in the general log. Diagnosed with:
  ```bash
  sudo cloud-init status --long
  sudo cloud-init schema --system
  ```
- **`ERR_CONNECTION_REFUSED` in the browser after a seemingly successful apply, with nginx actually not installed at all** — traced through Browser → Nginx → `/var/www/html` → missing repo → cloud-init schema error → systemd failure → OOM killer. Root cause: `Standard_B1ls` (≈393Mi RAM) was too small to survive `apt upgrade` plus package installs unattended; the kernel's OOM killer terminated the process mid-operation. Fixed by sizing up to `Standard_B2s` (≈3.8Gi RAM). The alternative fix, worth knowing about for smaller instances generally, is adding swap space via cloud-init rather than paying for a larger VM.

## What's still outstanding

- Posting the `terraform plan` output as a comment on the pull request itself (the actual mechanism the original scenario asked for so a reviewer sees the plan without opening the Actions tab).
- A separate scheduled workflow for tearing down the environment on a timer, kept deliberately separate from the deploy workflow since teardown timing is its own decision.
- Displaying the public IP more visibly (e.g. in the GitHub Actions job summary) rather than only in the raw Terraform output.
