terraform {
  required_version = "> 1.9.0"
}

//
// A simple Flatcar VM.
//
// Make sure the prerequisites (in the main README.md) are satisfied before provisioning.
//
module "flatcar_sample" {
  source               = "lucidsolns/proxmox/vm"
  version              = ">= 0.1.0"
  vmid                 = 990
  name                 = "flatcar-terraform.example.com"
  description          = <<-EOT
      An example **Flatcar** Linux VM provisioned using Terraform.
  EOT
  startup              = "order=999"
  tags                 = ["flatcar", "terraform", "example"]
  pm_api_url           = var.pm_api_url
  target_node          = var.target_node
  pm_user              = var.pm_user
  pm_password          = var.pm_password
  template_name        = "flatcar-production-qemu-stable-3975.2.0"
  butane_conf          = "${path.module}/flatcar.bu.tftpl"
  butane_path          = "${path.module}/butane.d"
  butane_conf_snippets = ["users.bu.tftpl"]
  memory               = 1024
  networks             = [{ bridge = var.bridge, tag = var.network_tag }]
  disks                = [
    // A mirror of the cloned Flatcar VM disks
    { slot = "scsi0", storage = "local", size = "8694M" }
  ]
}

