
# TODO: add outputs from the proxmox vm
# e.g. default_ipv4_address, ssh_host, ssh_port

output "ignition" {
  description = "The ignition file for each VM created"
  value = [
    for config in data.ct_config.ignition_json : config.rendered
  ]
}
