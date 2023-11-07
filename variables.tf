variable "name" {
  type        = string
  default     = "Flatcar-Linux"
  description = "The base name of the VM"
}

variable "description" {
  type        = string
  description = "A description that is put into the VM description (in addition to the information added by this module)"
  default     = null
  nullable    = true
}

# This allows cattle (c.f. pets) to be provisioned. Subsequent VM will
# be provisioned with an incrementing ID. The name will be suffixed with
# the index and count of VM's.
variable "vm_count" {
  description = "The number of VMs to provision"
  type        = number
  default     = 1
}

variable "vm_id" {
  type    = number
  default = 0
}

variable "tags" {
  description = "Tags to apply to the VM"
  type        = list(string)
  default     = ["flatcar"]
}

#
# The optional name of a butane configuration file.
#
# When butane configuration is provided then the VM will be configured:
#   - the butane will be compiled for each VM instance to ignition
#   - the ignition will be uploaded as a cloud-init ISO image
#   - the VM will get a hookscript to copy the ISO 'meta' file to a PVE file
#   - the VM will be configured with a fw_cfg to load the ignition file
#
variable "butane_conf" {
  type        = string
  description = "YAML Butane configuration for the VM"
  default     = null
}

variable "butane_conf_snippets" {
  type        = list(string)
  default     = []
  description = "Additional YAML Butane configuration(s) for the VM"
}

variable "target_node" {
  description = "The name of the target proxmox node"
  type        = string
}

variable "storage" {
  description = "The name of the storage used for storing VM images"
  type        = string
  default     = "local"
}

/*
  The name of a VM that has been converted to a template. The creation of this
  process is manual, and has not been automated. The flatcar qemu image is a qcow2
  image, and not a raw disk image as the name implies.

  Steps:
    1. Download the latest flatcar qemu image (noting the version number)
           > wget https://stable.release.flatcar-linux.net/amd64-usr/3510.2.6/flatcar_production_qemu_image.img.bz2
    2. Create a new VM with the name 'flatcar-production-qemu-<version>' (e.g. flatcar-production-qemu-3510.2.6)
           - UEFI boot
           - with no network
           - with no disks
           - delete the CDROM
    3. Decompress the flatcar qcow2 image
           > bunzip2 flatcar_production_qemu_image.img.bz2
    4. Add the qcow2 image to the VM
           > qm importdisk 900 flatcar_production_qemu_image.img vmroot --format qcow2
    5. Adopt the new disk into the VM
           > qm set 900 -efidisk0 vm-900-disk-0.qcow2:0,format=qcow2,efitype=4m,pre-enrolled-keys=1
    6. Convert the VM to a Template

  see
    - https://www.flatcar.org/releases
*/
variable "template_name" {
  type    = string
  default = "flatcar_qemu"
}

variable "cores" {
  type    = number
  default = 2
}

variable "cpu" {
  type        = string
  default     = "host"
  description = "The features that are declared for the CPU e.g. x86-64-v2-AES"
}

variable "memory" {
  description = "The memory size of the VM in megabytes"
  type        = number
  default     = 2048
}

variable "networks" {
  description = "An ordered list of network interfaces"
  type = list(object({
    bridge = optional(string, "vmbr0")
    tag    = optional(number)
    mtu    = optional(number)
  }))
  default = [
    {
      bridge = "vmbr0",
    }
  ]
}


variable "disks" {
  description = "An ordered list of disks"
  // see https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/resources/vm_qemu#argument-reference
  type = list(object({
    type    = string
    storage = string
    size    = string
    file    = optional(string)
    format  = optional(string)
    volume  = optional(string)
    slot    = optional(number)
  }))
  default = []
}

/*
  This data scripture is used to configure a directory to be exported from
  the host Proxmox into the VM using virtiofs.

  The parameters are modeled on the June 2023 patch by Markus Frank, which
  defines the parameters for each share as 'dirid', 'tag', 'cache' and 'direct-io'.
  Taking this approach should allow for an easy migration to the official support
  once it is fully integrated into proxmox.

  see:
    - https://lists.proxmox.com/pipermail/pve-devel/2023-June/057270.html
 */
variable "virtiofs" {
  description = "An ordered list of filesystems paths for the host"
  // see https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/resources/vm_qemu#argument-reference
  type = list(object({
    dirid     = string
    tag       = string
    cache     = optional(string) # auto, always, never
    direct-io = optional(string) # "auto", always", "never"
  }))
  default = [] // no virtiofs shares are performed by default
}


variable "os_type" {
  type        = string
  default     = "l26"
  description = "The short OS name identifier"
}

variable "os_type_name" {
  type        = string
  default     = "Linux 2.6 - 6.X Kernel"
  description = "os_type_name='Linux 2.6 - 6.X Kernel'"
}


variable "pm_api_url" {
  description = "The FQDN and path to the API of the proxmox server e.g. https://example.com:8006/api2/json"
  type        = string
}


/*
  The API secret from the proxmox datacenter.

  The identity must have the permission 'PVEVMAdmin' to the correct path ('/'). Due to possible issues
  in the API and hoe authorisation is performed, the

  With the incorrect permissions, the following error is generated:
      Error: user greg@pam has valid credentials but cannot retrieve user list, check privilege
      separation of api token
  Which corresponds to the following GET from /var/log/pveproxy/access.log
      GET /api2/json/access/users?full=1

  Required Privileges
  ===================

  user must be 'root@pam'                            <=== ugly
  userid-group, Sys.Audit -> GET users

  see
    - https://forum.proxmox.com/threads/root-pam-token-api-restricted.83866/
    - https://pve.proxmox.com/pve-docs/api-viewer/index.html#/access/users
    - https://github.com/Telmate/terraform-provider-proxmox/issues/385
    - https://bugzilla.proxmox.com/show_bug.cgi?id=4068
*/
variable "pm_api_token_secret" {
  description = "secret hash"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pm_user" {
  description = "A username for password based authentication of the Proxmox API"
  type        = string
  default     = ""
}

variable "pm_password" {
  description = "A password for password based authentication of the Proxmox API"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pm_tls_insecure" {
  description = "leave tls_insecure set to true unless you have a valid proxmox SSL certificate "
  default     = true
  type        = bool
}
variable "bios" {
  description = "Whether to use UEFI (ovmf) or SeaBIOS"
  default     = "ovmf" # UEFI boot
  type        = string
  validation {
    condition = var.bios == "ovmf" || var.bios == "seabios"
    error_message = "The BIOS parameter supports ovmf or seabios"
  }
}

variable "agent" {
  description = "Whether the guest will have QEMU agent software running"
  default     = true
  type        = bool
}