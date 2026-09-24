output "public_ip" {
  value = oci_core_instance.main.public_ip
}

output "ssh" {
  value = "ssh ubuntu@${oci_core_instance.main.public_ip}"
}

output "receiver_health_url" {
  value = "http://${oci_core_instance.main.public_ip}/healthz"
}
