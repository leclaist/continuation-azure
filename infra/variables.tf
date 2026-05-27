variable "rails_master_key" {
  description = "Rails master key (contents of config/master.key)"
  type        = string
  sensitive   = true
}

variable "google_drive_folder_id" {
  description = "Google Drive folder ID containing journal files"
  type        = string
  sensitive   = true
}

variable "google_service_account_json" {
  description = "Google service account JSON as a compact single-line string (no surrounding quotes, no literal newlines)"
  type        = string
  sensitive   = true
}

variable "admin_token" {
  description = "Secret token for the /admin/* maintenance endpoints (X-Admin-Token header)"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key for AI comment generation (optional — omit to disable)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "custom_domain_cert_id" {
  description = "Azure resource ID of the managed certificate for christineclaymoreau.lol. Obtain after running the hostname bind CLI command (see comment in main.tf)."
  type        = string
  default     = "/subscriptions/33ad2025-a25b-412e-bc5a-6eb69d979276/resourceGroups/continuation-rg/providers/Microsoft.App/managedEnvironments/continuation-env/managedCertificates/mc-continuation-e-christineclaymor-6017"
}
