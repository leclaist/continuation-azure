Set up or update the Azure infrastructure for this app and wire it into the GitHub Actions deploy pipeline.

## Usage

Run `/azure-setup` with no arguments. All resource names and the target region are defined in the **Configuration** section below — edit that section if you need to change them.

## Configuration

```
RESOURCE_GROUP=continuation-rg
LOCATION=eastus
ACR_NAME=continuationacr
CONTAINER_ENV=continuation-env
STORAGE_ACCOUNT=continuationdata
FILE_SHARE=continuation-data
STORAGE_MOUNT=sqlite-storage
APP_NAME=continuation
```

> ACR and storage account names must be globally unique across all of Azure. If creation fails with a "name already taken" error, change `ACR_NAME` or `STORAGE_ACCOUNT` above and re-run.

## What to do

Work through each step. Every step is idempotent — check whether the resource exists before creating it.

### 1. Verify prerequisites

```bash
az account show
```

If this fails, tell the user to run `az login` first and stop. If it succeeds, print the active subscription name and ID so the user can confirm it's the right one.

### 2. Read local secrets

- Read `RAILS_MASTER_KEY` from `config/master.key`
- Read `GOOGLE_DRIVE_FOLDER_ID` and `GOOGLE_SERVICE_ACCOUNT_JSON` from `.env`
- Read `ANTHROPIC_API_KEY` from `.env` if present (optional — skip silently if absent)

If `.env` is missing, show the user which values they need to fill in and stop. Never print secret values.

### 3. Create resource group (idempotent)

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION
```

`az group create` is idempotent — safe to re-run.

### 4. Create Azure Container Registry

Check first:
```bash
az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP 2>/dev/null
```

Create only if not found:
```bash
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true
```

### 5. Build and push the Docker image

```bash
az acr build \
  --registry $ACR_NAME \
  --image continuation:latest \
  .
```

This builds remotely on Azure — no local Docker required.

### 6. Create Container Apps environment

Check first:
```bash
az containerapp env show --name $CONTAINER_ENV --resource-group $RESOURCE_GROUP 2>/dev/null
```

Create only if not found:
```bash
az containerapp env create \
  --name $CONTAINER_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

### 7. Create storage account and file share for SQLite

Check and create storage account:
```bash
az storage account show --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP 2>/dev/null || \
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS
```

Get the storage key:
```bash
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT \
  --query '[0].value' -o tsv)
```

Check and create file share:
```bash
az storage share exists \
  --account-name $STORAGE_ACCOUNT \
  --name $FILE_SHARE \
  --account-key $STORAGE_KEY \
  --query exists -o tsv
```

Create only if output is `false`:
```bash
az storage share create \
  --account-name $STORAGE_ACCOUNT \
  --name $FILE_SHARE \
  --account-key $STORAGE_KEY
```

### 8. Mount the file share to the Container Apps environment

Check first:
```bash
az containerapp env storage show \
  --name $CONTAINER_ENV \
  --resource-group $RESOURCE_GROUP \
  --storage-name $STORAGE_MOUNT 2>/dev/null
```

Create only if not found:
```bash
az containerapp env storage set \
  --name $CONTAINER_ENV \
  --resource-group $RESOURCE_GROUP \
  --storage-name $STORAGE_MOUNT \
  --azure-file-account-name $STORAGE_ACCOUNT \
  --azure-file-account-key $STORAGE_KEY \
  --azure-file-share-name $FILE_SHARE \
  --access-mode ReadWrite
```

### 9. Create or update the Container App

Get the ACR password:
```bash
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query 'passwords[0].value' -o tsv)
```

Check if the app already exists:
```bash
az containerapp show --name $APP_NAME --resource-group $RESOURCE_GROUP 2>/dev/null
```

**If it does not exist**, create it. Build the `--env-vars` list from the secrets read in step 2 — include `ANTHROPIC_API_KEY` only if it was present in `.env`:

```bash
az containerapp create \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_ENV \
  --image $ACR_NAME.azurecr.io/continuation:latest \
  --registry-server $ACR_NAME.azurecr.io \
  --registry-username $ACR_NAME \
  --registry-password $ACR_PASSWORD \
  --target-port 80 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 1 \
  --env-vars \
    RAILS_MASTER_KEY="<from config/master.key>" \
    GOOGLE_DRIVE_FOLDER_ID="<from .env>" \
    GOOGLE_SERVICE_ACCOUNT_JSON="<from .env>" \
    DATABASE_URL="sqlite3:///data/production.sqlite3" \
  --volume-name sqlite-vol \
  --volume-storage-name $STORAGE_MOUNT \
  --volume-mount-path /data
```

**If it already exists**, update only the image:

```bash
az containerapp update \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image $ACR_NAME.azurecr.io/continuation:latest
```

### 10. Print the app URL

```bash
az containerapp show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn -o tsv
```

Report the URL to the user.

### 11. Update GitHub Actions workflow

Check if `.github/workflows/azure-deploy.yml` already exists. If it does, skip this step and tell the user.

If it does not exist, create `.github/workflows/azure-deploy.yml` with the following content — substituting the real `$ACR_NAME` and `$APP_NAME` values:

```yaml
name: Deploy to Azure

on:
  workflow_run:
    workflows: ["Deploy"]
    types: [completed]
    branches: [main]

jobs:
  deploy-azure:
    name: Deploy to Azure Container Apps
    runs-on: ubuntu-latest
    concurrency: deploy-azure
    if: ${{ github.event.workflow_run.conclusion == 'success' }}
    steps:
      - uses: actions/checkout@v6

      - uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Build and push image to ACR
        run: |
          az acr build \
            --registry $ACR_NAME \
            --image continuation:${{ github.sha }} \
            --image continuation:latest \
            .

      - name: Deploy to Container Apps
        run: |
          az containerapp update \
            --name $APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --image $ACR_NAME.azurecr.io/continuation:${{ github.sha }}

      - name: Get app URL
        run: |
          az containerapp show \
            --name $APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --query properties.configuration.ingress.fqdn -o tsv
```

This workflow triggers after the existing Fly.io deploy workflow succeeds — so Azure only gets updated after Fly staging is verified.

### 12. Create the Azure service principal for GitHub Actions

This step requires user confirmation before running. Explain:

> To deploy from GitHub Actions, we need a service principal with push access to ACR and deploy access to Container Apps. The JSON output will need to be added as a GitHub secret named `AZURE_CREDENTIALS`.

Run:
```bash
az ad sp create-for-rbac \
  --name "continuation-github-deploy" \
  --role contributor \
  --scopes /subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP \
  --json-auth
```

Replace `<subscription-id>` with the active subscription ID from step 1.

Print the full JSON output and tell the user:
> Add this as a GitHub secret named `AZURE_CREDENTIALS` at: https://github.com/<owner>/<repo>/settings/secrets/actions

Ask the user to get their repo path from `git remote get-url origin`.

## Notes

- Never print the values of `RAILS_MASTER_KEY`, `GOOGLE_SERVICE_ACCOUNT_JSON`, or `ANTHROPIC_API_KEY`.
- SQLite lives on an Azure Files SMB mount at `/data`. It works fine for low-traffic personal use.
- `--min-replicas 1` keeps one instance always running so the app doesn't cold-start. Set to `0` to save cost during idle periods.
- The `GOOGLE_SERVICE_ACCOUNT_JSON` value must be a single-line JSON string. If the value in `.env` has literal newlines in the private key, they should already be encoded as `\n` — pass it as-is.
