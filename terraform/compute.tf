data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  is_flex = length(regexall("Flex$", var.instance_shape)) > 0

  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    compose_b64 = base64encode(file("${path.module}/../deploy/docker-compose.yml"))
    caddy_b64   = base64encode(file("${path.module}/../deploy/Caddyfile"))
    env_b64 = base64encode(<<-ENV
      SITE_ADDRESS=${var.site_address}
      RECEIVER_IMAGE=${var.receiver_image}
      RECEIVER_API_TOKEN=${var.receiver_api_token}
      WATCHTOWER_POLL_INTERVAL=${var.watchtower_poll_interval}
      RETENTION_DAYS=${var.retention_days}
      DISCORD_WEBHOOK_URL=${var.discord_webhook_url}
    ENV
    )
  })
}

resource "oci_core_instance" "main" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "${var.name_prefix}-vm"
  shape               = var.instance_shape

  dynamic "shape_config" {
    for_each = local.is_flex ? [1] : []
    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_gbs
    }
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.cloud_init)
  }

  lifecycle {
    ignore_changes = [metadata["user_data"], source_details[0].source_id]
  }
}
