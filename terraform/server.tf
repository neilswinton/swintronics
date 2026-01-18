
locals {
  immich_data_location    = "${var.data_disk_mountpoint}/immich"
  paperless_data_location = "${var.data_disk_mountpoint}/paperless-ngx"
  user_data = templatefile("${path.module}/scripts/cloud-init.yml", {
    admin_public_key        = trimspace(tls_private_key.admin.public_key_openssh)
    admin_user              = nonsensitive(data.infisical_secrets.root_secrets.secrets["username"].value)
    timezone                = var.timezone
    project                 = var.project_name
    repo                    = var.source_repo
    mountpoint              = var.data_disk_mountpoint
    custom_userdata         = split("\n", data.infisical_secrets.terraform_secrets.secrets["RUNCMD"].value)
    immich_data_location    = local.immich_data_location
    paperless_data_location = local.paperless_data_location
  })
}


resource "hcloud_server" "server" {

  count        = length(var.server_types)
  name         = "${var.project_name}-${count.index}"
  image        = var.image
  server_type  = lower(var.server_types[count.index])
  location     = var.region
  firewall_ids = [hcloud_firewall.cluster.id]
  ssh_keys     = [hcloud_ssh_key.server_public_key.name]

  user_data = local.user_data

  lifecycle {
    ignore_changes = [ssh_keys, user_data]
  }


  public_net {
    ipv6_enabled = true
    ipv4_enabled = true
  }
}

resource "hcloud_volume" "server_disk" {
  count             = length(var.server_types)
  name              = "${var.project_name}-${count.index}-data"
  size              = var.volume_size
  location          = var.region
  automount         = false
  format            = "ext4"
  delete_protection = var.volume_delete_protection
}

resource "hcloud_volume_attachment" "server" {
  count = length(var.server_types)

  volume_id = hcloud_volume.server_disk[count.index].id
  server_id = hcloud_server.server[count.index].id
  automount = false
}


resource "local_file" "cloudinit" {
  content         = local.user_data
  filename        = "${path.module}/artifacts/cloud-init.yml"
  file_permission = "0644"
}

resource "local_file" "immich_env" {
  filename        = "${path.module}/artifacts/immich.env"
  file_permission = "0644"
  content = templatefile("${path.module}/../docker-services/immich-app/template.env", {
    IMMICH_DATA_LOCATION = local.immich_data_location
    TZ                   = var.timezone
    IMMICH_DB_PASSWORD   = random_password.immich_postgres_password.result
  })
}

resource "local_file" "root_env" {
  filename        = "${path.module}/artifacts/docker-services.env"
  file_permission = "0644"
  content = templatefile("${path.module}/../docker-services/template.env", {
    SERVER_DOMAIN = var.domain_name
    TZ            = var.timezone
  })
}

resource "local_file" "linkwarden_env" {
  filename        = "${path.module}/artifacts/linkwarden.env"
  file_permission = "0644"
  content = templatefile("${path.module}/../docker-services/linkwarden/template.env", {
    SERVER_DOMAIN     = "linkwarden.${var.domain_name}"
    CERT_RESOLVER     = "production"
    POSTGRES_PASSWORD = random_password.linkwarden_passwords["POSTGRES_PASSWORD"].result
    NEXTAUTH_SECRET   = random_password.linkwarden_passwords["NEXTAUTH_SECRET"].result
    MEILI_MASTER_KEY  = random_password.linkwarden_passwords["MEILI_MASTER_KEY"].result
    TZ                = var.timezone
  })
}

resource "local_file" "karakeep_env" {
  filename        = "${path.module}/artifacts/karakeep.env"
  file_permission = "0644"
  content = templatefile("${path.module}/../docker-services/karakeep-app/template.env", {
    SERVER_DOMAIN    = "${var.domain_name}"
    CERT_RESOLVER    = "production"
    NEXTAUTH_SECRET  = random_password.karakeep_passwords["NEXTAUTH_SECRET"].result
    MEILI_MASTER_KEY = random_password.karakeep_passwords["MEILI_MASTER_KEY"].result
    TZ               = var.timezone
  })
}
