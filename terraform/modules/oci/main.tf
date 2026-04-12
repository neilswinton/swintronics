# Look up the first available domain in the region
data "oci_identity_availability_domain" "ad" {
  compartment_id = var.compartment_ocid
  ad_number      = 1
}

# Find the latest Ubuntu 24.04 ARM image for A1.Flex
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_vcn" "server" {
  compartment_id = var.compartment_ocid
  cidr_block     = "10.0.0.0/16"
  display_name   = "${var.project_name}-vcn"
}

resource "oci_core_internet_gateway" "server" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.server.id
  display_name   = "${var.project_name}-igw"
  enabled        = true
}

resource "oci_core_route_table" "server" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.server.id
  display_name   = "${var.project_name}-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.server.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_security_list" "server" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.server.id
  display_name   = "${var.project_name}-sl"

  # Allow all outbound traffic
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # SSH from caller IP only
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "${var.my_ip}/32"
    tcp_options {
      max = 22
      min = 22
    }
  }

  # Tailscale UDP from anywhere
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      max = 41641
      min = 41641
    }
  }
}

resource "oci_core_subnet" "server" {
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.server.id
  cidr_block        = "10.0.0.0/24"
  display_name      = "${var.project_name}-subnet"
  route_table_id    = oci_core_route_table.server.id
  security_list_ids = [oci_core_security_list.server.id]
}

resource "oci_core_instance" "server" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domain.ad.name
  display_name        = var.project_name
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_in_gbs
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm.images[0].id
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.server.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.admin_public_key
    user_data           = base64encode(var.user_data)
  }

  lifecycle {
    ignore_changes = [source_details, metadata]
  }
}
