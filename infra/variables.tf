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

variable "anthropic_api_key" {
  description = "Anthropic API key for AI comment generation (optional — omit to disable)"
  type        = string
  sensitive   = true
  default     = ""
}
