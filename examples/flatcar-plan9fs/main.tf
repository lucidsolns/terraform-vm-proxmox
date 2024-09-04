terraform {
  required_version = "> 1.9.0"
}

//
// A simple Flatcar VM with a plan9fs
//
// Note: As of November 2023, Flatcar Linux doesn't support virtiofs; thus this
// uses plan9fs as an alternative.
//
// Make sure the prerequisites are satisfied before provisioning (see the main README.md)
//
module "flatcar_plan9fs_sample" {
  source        = "lucidsolns/proxmox/vm"
  version       = ">= 0.1.1"
  vmid          = 991
  name          = "flatcar-plan9fs.example.com"
  description   = <<-EOT
      An example **Flatcar** Linux VM with a plan9 filesystem provisioned using Terraform.
  EOT
  tags          = ["flatcar", "terraform", "plan9fs", "example"]
  pm_api_url    = var.pm_api_url
  target_node   = var.target_node
  pm_user       = var.pm_user
  pm_password   = var.pm_password
  template_name = "flatcar-production-qemu-stable-3975.2.0"
  butane_conf   = "${path.module}/flatcar.bu.tftpl"
  butane_path   = "${path.module}/butane.d"
  memory        = 1024
  networks      = [{ bridge = var.bridge, tag = var.network_tag }]
  plan9fs = [
    // export the local '/tmp' directory of the host to the VM with the tag 'tmp'
    { dirid = "/tmp", tag = "tmp" }
  ]
  disks = [
    // A mirror of the cloned Flatcar VM disks
    { slot = "scsi0", storage = "local", size = "8694M" }
  ]
}

