
locals {
  hetzner_server_types = ["CPX11", "CPX21", "CPX31", "CPX41", "CPX51"]
  # hetzner_base_network       = "10.0.0.0/8"
  # us_east_network            = cidrsubnet(local.hetzner_base_network, 8, 10) # "10.10.0.0/16
  # swintronics_cluster_subnet = cidrsubnet(local.us_east_network, 8, 1)       # 10.10.1.0/24
  hetzner_location_to_zone = transpose({
    "ap-southeast" = ["sin"],
    "eu-central"   = ["fsn1", "hel1", "nbg1"],
    "us-east"      = ["ash"],
    "us-west"      = ["hil"],
  })
}

module "subnet_addrs" {
  source = "hashicorp/subnets/cidr"

  base_cidr_block = "10.0.0.0/8"
  networks = [
    {
      name     = "ap-southeast"
      new_bits = 8
    },
    {
      name     = "eu-central"
      new_bits = 8
    },
    {
      name     = "us-east"
      new_bits = 8
    },
    {
      name     = "us-west"
      new_bits = 8
    },
  ]
}
