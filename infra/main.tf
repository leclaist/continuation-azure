terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# Resource group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "main" {
  name     = "continuation-rg"
  location = "East US"
}

# ---------------------------------------------------------------------------
# Azure Container Registry
# ---------------------------------------------------------------------------

resource "azurerm_container_registry" "main" {
  name                = "continuationacr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
}

# ---------------------------------------------------------------------------
# Container Apps environment
# ---------------------------------------------------------------------------

resource "azurerm_container_app_environment" "main" {
  name                = "continuation-env"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# ---------------------------------------------------------------------------
# Storage account + file share
#
# Provisioned but not used for the database. Azure Files SMB does not support
# POSIX file locking, so SQLite cannot reliably use it. The file share is kept
# in the infrastructure and mounted at /data in the container in case it is
# ever needed (e.g. for uploaded files). The database uses local ephemeral
# container storage at /rails/storage/ instead.
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "main" {
  name                     = "continuationdata"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_share" "main" {
  name                 = "continuation-data"
  storage_account_name = azurerm_storage_account.main.name
  quota                = 50
}

resource "azurerm_container_app_environment_storage" "main" {
  name                         = "sqlite-storage"
  container_app_environment_id = azurerm_container_app_environment.main.id
  account_name                 = azurerm_storage_account.main.name
  share_name                   = azurerm_storage_share.main.name
  access_key                   = azurerm_storage_account.main.primary_access_key
  access_mode                  = "ReadWrite"
}

# ---------------------------------------------------------------------------
# Container App
# ---------------------------------------------------------------------------

resource "azurerm_container_app" "main" {
  name                         = "continuation"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }

  secret {
    name  = "rails-master-key"
    value = var.rails_master_key
  }

  secret {
    name  = "google-drive-folder-id"
    value = var.google_drive_folder_id
  }

  secret {
    name  = "google-service-account-json"
    value = var.google_service_account_json
  }

  secret {
    name  = "anthropic-api-key"
    value = var.anthropic_api_key
  }

  template {
    min_replicas = 0
    max_replicas = 1

    # Azure Files mount — kept for potential future use, not used for SQLite.
    volume {
      name         = "sqlite-vol"
      storage_name = azurerm_container_app_environment_storage.main.name
      storage_type = "AzureFile"
    }

    container {
      name   = "continuation"
      image  = "${azurerm_container_registry.main.login_server}/continuation:latest"
      cpu    = 0.5
      memory = "1Gi"

      # Override the image default (sqlite3:///data/production.sqlite3) to use
      # local ephemeral storage instead of the Azure Files mount.
      env {
        name  = "DATABASE_URL"
        value = "sqlite3:///rails/storage/production.sqlite3"
      }

      # Thruster cannot bind to port 80 as a non-root user. HTTP_PORT sets its
      # external listen port; TARGET_PORT sets the internal Puma port it proxies to.
      env {
        name  = "HTTP_PORT"
        value = "3000"
      }

      env {
        name  = "TARGET_PORT"
        value = "3001"
      }

      env {
        name        = "RAILS_MASTER_KEY"
        secret_name = "rails-master-key"
      }

      env {
        name        = "GOOGLE_DRIVE_FOLDER_ID"
        secret_name = "google-drive-folder-id"
      }

      env {
        name        = "GOOGLE_SERVICE_ACCOUNT_JSON"
        secret_name = "google-service-account-json"
      }

      env {
        name        = "ANTHROPIC_API_KEY"
        secret_name = "anthropic-api-key"
      }

      volume_mounts {
        name = "sqlite-vol"
        path = "/data"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "auto"

    # Custom domain with Azure-managed TLS certificate.
    #
    # Bootstrapping a fresh environment: Terraform cannot provision the managed
    # certificate itself. After `terraform apply`, run these two CLI commands
    # once, then update `custom_domain_cert_id` in your tfvars with the
    # resulting certificate ID:
    #
    #   az containerapp hostname add \
    #     --hostname christineclaymoreau.lol \
    #     --name continuation --resource-group continuation-rg
    #
    #   az containerapp hostname bind \
    #     --hostname christineclaymoreau.lol \
    #     --name continuation --resource-group continuation-rg \
    #     --environment continuation-env --validation-method HTTP
    #
    #   az containerapp env certificate list \
    #     --name continuation-env --resource-group continuation-rg \
    #     --query "[?properties.subjectName=='christineclaymoreau.lol'].id" -o tsv
    #
    # Required DNS records (set at your registrar):
    #   A   @     48.206.132.78
    #   TXT asuid 89EB5A6DAE4034C02D11B2D11AF4B369738734587B91C06887B4A4592D5E173A
    custom_domain {
      name                     = "christineclaymoreau.lol"
      certificate_binding_type = "SniEnabled"
      certificate_id           = var.custom_domain_cert_id
    }

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "app_url" {
  value = "https://christineclaymoreau.lol"
}

output "app_url_azure" {
  value = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}
