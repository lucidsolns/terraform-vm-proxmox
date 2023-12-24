terraform {
  required_version = "> 1.6.0"
}

//
// A simple Flatcar VM with a plan9fs
//
// Note: As of November 2023, Flatcar Linux doesn't support virtiofs; thus this
//  uses plan9fs as an alternative.
//
// Make sure the prerequisites are satisfied before provisioning (see the main README.md)
//
module "flatcar_plan9fs_sample" {
  source        = "lucidsolns/proxmox/vm"
  version       = ">= 0.0.13"
  vm_id         = 991
  name          = "flatcar-plan9fs.example.com"
  description   = <<-EOT
      An example **Flatcar** Linux VM provisioned using Terraform.
  EOT
  tags          = ["flatcar", "terraform", "plan9fs", "example"]
  pm_api_url    = var.pm_api_url
  target_node   = var.target_node
  pm_user       = var.pm_user
  pm_password   = var.pm_password
  template_name = "flatcar-production-qemu-3602.2.1"
  butane_conf   = "${path.module}/flatcar.bu.tftpl"
  butane_path   = "${path.module}/butane.d"
  memory        = 1024
  networks      = [{ bridge = var.bridge, tag = var.network_tag }]
  plan9fs       = [
    {
      dirid = "/tmp"
      tag   = "tmp"
    }
  ]
}

