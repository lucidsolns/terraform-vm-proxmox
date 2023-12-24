terraform {
  required_version = "> 1.6.0"
}

//
// A simple Flatcar VM.
//
// Make sure the prerequisites (in the main README.md) are satisfied before provisioning.
//
module "flatcar_sample" {
  source        = "lucidsolns/proxmox/vm"
  version       = ">= 0.0.13"
  vm_id         = 990
  name          = "flatcar-terraform.example.com"
  description   = <<-EOT
      An example **Flatcar** Linux VM provisioned using Terraform.
  EOT
  startup       = "order=999"
  tags          = ["flatcar", "terraform", "example"]
  pm_api_url    = var.pm_api_url
  target_node   = var.target_node
  pm_user       = var.pm_user
  pm_password   = var.pm_password
  template_name = "flatcar-production-qemu-3602.2.1"
  butane_conf   = "${path.module}/flatcar.bu.tftpl"
  butane_path   = "${path.module}/butane.d"
  butane_conf_snippets = ["users.bu.tftpl"]
  memory        = 1024
  networks      = [{ bridge = var.bridge, tag = var.network_tag }]
}

