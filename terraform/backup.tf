# Backup credentials — B2 bucket + restic password + healthchecks.io heartbeat.
#
# These values flow into the Infisical Runtime project, where Ansible reads them
# at deploy time to render docker-services/backup.env on the server.
#
# IMPORTANT: random_password.restic and random_uuid resources are stable in state.
# To preserve an existing repo on a re-pave or new cluster, import before applying:
#   terraform import random_password.restic 'existing-restic-password'
#   terraform import b2_bucket.backups <existing-bucket-id>
#   terraform import healthchecksio_check.heartbeat <existing-check-uuid>
# B2 application keys cannot be imported (the secret is only emitted at create
# time), so a new key is always created — revoke the old one manually after.

locals {
  backup_bucket_name         = var.backup_bucket_name != "" ? var.backup_bucket_name : "${var.project_name}-restic"
  heartbeat_interval_minutes = 5
  heartbeat_grace_seconds    = local.heartbeat_interval_minutes * 60 * 3 + 60
}

resource "b2_bucket" "backups" {
  bucket_name = local.backup_bucket_name
  bucket_type = "allPrivate"

  # B2 "Keep only the last version of the file" preset:
  # on overwrite, hide previous versions immediately; delete hidden versions after 1 day.
  lifecycle_rules {
    file_name_prefix                                       = ""
    days_from_uploading_to_hiding                          = 0
    days_from_hiding_to_deleting                           = 1
    days_from_starting_to_canceling_unfinished_large_files = 0
  }
}

resource "b2_application_key" "backups" {
  key_name   = "${var.project_name}-restic"
  bucket_ids = [b2_bucket.backups.bucket_id]
  capabilities = [
    "deleteFiles",
    "listAllBucketNames",
    "listBuckets",
    "listFiles",
    "readBucketEncryption",
    "readBuckets",
    "readFiles",
    "writeFiles",
  ]
}

resource "random_password" "restic" {
  length      = 32
  special     = true
  min_special = 0

  # Allow `terraform import` of an existing password without triggering a replacement
  # if the imported value's length / character set differs from these defaults.
  lifecycle {
    ignore_changes = [length, special, override_special, min_lower, min_upper, min_numeric, min_special, keepers]
  }
}

resource "healthchecksio_check" "heartbeat" {
  name     = title("${var.project_name} heartbeat")
  desc      = "Five minute heartbeat issued by gatus" 
  schedule = "*/${local.heartbeat_interval_minutes} * * * *"
  grace    = local.heartbeat_grace_seconds
  timezone = var.timezone
  channels  = [
          "5a982502-964c-463f-98a2-eb163c724683"
        ]
  tags     = ["heartbeat", var.project_name]
}

# ── Push values into the Infisical Runtime project ──────────────────────────

resource "infisical_secret" "b2_account_id" {
  name         = "B2_ACCOUNT_ID"
  value        = b2_application_key.backups.application_key_id
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

resource "infisical_secret" "b2_account_key" {
  name         = "B2_ACCOUNT_KEY"
  value        = b2_application_key.backups.application_key
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

resource "infisical_secret" "restic_repository" {
  name         = "RESTIC_REPOSITORY"
  value        = "s3:https://s3.${var.b2_region}.backblazeb2.com/${b2_bucket.backups.bucket_name}/${var.restic_repository_path}"
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

resource "infisical_secret" "restic_password" {
  name         = "RESTIC_PASSWORD"
  value        = random_password.restic.result
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

resource "infisical_secret" "healthchecks_heartbeat_uuid" {
  name         = "HEALTHCHECKS_HEARTBEAT_CHECK_UUID"
  value        = healthchecksio_check.heartbeat.id
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}

# Bootstrap-input value, copied from /terraform to the runtime project so backup.sh
# and the boot/reboot scripts can pause/resume the heartbeat check.
resource "infisical_secret" "healthchecks_api_key" {
  name         = "HEALTHCHECKS_API_KEY"
  value        = data.infisical_secrets.terraform_secrets.secrets["HEALTHCHECKS_API_KEY"].value
  env_slug     = "dev"
  workspace_id = infisical_project.runtime_secrets.id
  folder_path  = "/"
}
