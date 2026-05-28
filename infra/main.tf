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
# Log Analytics workspace
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "main" {
  name                = "continuation-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# ---------------------------------------------------------------------------
# Container Apps environment
#
# Attaching the Log Analytics workspace to an existing environment requires
# a one-time CLI command — azurerm 3.x treats log_analytics_workspace_id as
# ForceNew, so setting it in Terraform would destroy and recreate the
# environment (and lose the custom domain binding). Run this once after
# `terraform apply` creates the workspace:
#
#   WORKSPACE_ID=$(az monitor log-analytics workspace show \
#     --resource-group continuation-rg --workspace-name continuation-logs \
#     --query customerId -o tsv)
#   WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
#     --resource-group continuation-rg --workspace-name continuation-logs \
#     --query primarySharedKey -o tsv)
#   az containerapp env update \
#     --name continuation-env --resource-group continuation-rg \
#     --logs-destination log-analytics \
#     --logs-workspace-id "$WORKSPACE_ID" \
#     --logs-workspace-key "$WORKSPACE_KEY"
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
    name  = "admin-token"
    value = var.admin_token
  }

  secret {
    name  = "google-drive-folder-id"
    value = var.google_drive_folder_id
  }

  secret {
    name  = "google-service-account-json"
    value = var.google_service_account_json
  }

  dynamic "secret" {
    for_each = var.anthropic_api_key != "" ? [1] : []
    content {
      name  = "anthropic-api-key"
      value = var.anthropic_api_key
    }
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
        name        = "ADMIN_TOKEN"
        secret_name = "admin-token"
      }

      env {
        name        = "GOOGLE_DRIVE_FOLDER_ID"
        secret_name = "google-drive-folder-id"
      }

      env {
        name        = "GOOGLE_SERVICE_ACCOUNT_JSON"
        secret_name = "google-service-account-json"
      }

      dynamic "env" {
        for_each = var.anthropic_api_key != "" ? [1] : []
        content {
          name        = "ANTHROPIC_API_KEY"
          secret_name = "anthropic-api-key"
        }
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

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}

# ---------------------------------------------------------------------------
# Custom domain
#
# Bootstrapping a fresh environment: Terraform cannot provision the managed
# certificate itself. After the first `terraform apply`, run these CLI commands
# once, then set `custom_domain_cert_id` in your tfvars to the resulting ID
# and run `terraform apply` again:
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
# ---------------------------------------------------------------------------

# NOTE: azurerm 3.x cannot manage managed certificate bindings — both the
# deprecated custom_domain block and azurerm_container_app_custom_domain reject
# the managedCertificates/... ID format. The domain binding is set up manually
# via the CLI commands above and lives outside Terraform state.

# ---------------------------------------------------------------------------
# Alerting
# ---------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "email" {
  name                = "continuation-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "cont-email"

  email_receiver {
    name                    = "admin"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "http_500" {
  name                = "continuation-500-errors"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  description         = "Fires when any HTTP 5xx response is logged by the Rails app"

  scopes               = [azurerm_log_analytics_workspace.main.id]
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  severity             = 1
  auto_mitigation_enabled = true

  criteria {
    query = <<-QUERY
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "continuation"
      | extend log = parse_json(Log_s)
      | where toint(log.status) >= 500
      | where isnotempty(log.controller)
    QUERY

    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.email.id]
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.workspace_id
}

output "app_url" {
  value = "https://christineclaymoreau.lol"
}

output "app_url_azure" {
  value = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}
