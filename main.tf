terraform {
  required_version = "> 1.9.0"
  required_providers {
    /*
      API provisioning support for Proxmox

      see
        - https://registry.terraform.io/providers/Telmate/proxmox/latest
    */
    proxmox = {
      // https://developer.hashicorp.com/terraform/cli/config/config-file#provider-installation
      source  = "Telmate/proxmox"
      version = "3.0.1-rc4" // can't say '>= 3.0.1-rc4'
    }

    /*
      Convert a butane configuration to an ignition JSON configuration

      WARNING: The current flatcar stable release requires ignition v3.3.0 configurations, which
      are supported by the v0.12 provider. The v0.13 CT provider generated v3.4.0 ignition
      configurations which are not supported with Flatcar v3510.2.6. This is all clearly documented in
      the git [README.md](https://github.com/poseidon/terraform-provider-ct)

      see
        - https://github.com/poseidon/terraform-provider-ct
        - https://registry.terraform.io/providers/poseidon/ct/latest
        - https://registry.terraform.io/providers/poseidon/ct/latest/docs
        - https://www.flatcar.org/docs/latest/provisioning/config-transpiler/
    */
    ct = {
      source  = "lucidsolns/ct"
      version = ">= 0.13.1"
    }

    /*
      see
        - https://registry.terraform.io/providers/hashicorp/null
    */
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.2"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.pm_api_url
  pm_tls_insecure = var.pm_tls_insecure
  pm_user         = var.pm_user
  pm_password     = var.pm_password
}


locals {
  has_butane          = var.butane_conf != null && var.butane_conf != ""
  has_virtiofs        = var.virtiofs != null && length(var.virtiofs) > 0
  # The base path used for loading butane snippet files
  butane_snippet_path = var.butane_path != null ? var.butane_path : dirname(var.butane_conf)
}
/**
  Provision a VM with an ignition configuration file.

  see
    - https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/resources/vm_qemu
    - https://pve.proxmox.com/wiki/Manual:_qm.conf
    - https://github.com/qemu/qemu/blob/master/docs/specs/fw_cfg.rst
    - https://www.flatcar.org/docs/latest/installing/vms/libvirt/
    - https://austinsnerdythings.com/2021/09/01/how-to-deploy-vms-in-proxmox-with-terraform/
    - https://www.flatcar.org/
    - https://github.com/flatcar/ignition
    - https://www.qemu.org/docs/master/specs/fw_cfg.html
*/
resource "proxmox_vm_qemu" "proxmox_flatcar_vm" {
  count       = var.vm_count # just want 1 for now, set to 0 and apply to destroy VM
  vmid        = var.vm_count > 1 ? var.vmid + count.index : var.vmid
  name        = var.vm_count > 1 ? "${var.name}-${count.index + 1}" : var.name
  target_node = var.target_node
  pool        = var.pool

  # Create a VM using the flatcar qemu image, and give it a version. This will mean
  # a linked clone can be used to reduce the storage requirements when a large number
  # of clones are created.
  #
  # Download the flatcar_qemu image from https://www.flatcar.org/releases and
  clone      = var.template_name
  full_clone = var.full_clone
  clone_wait = 0

  #
  # The description for the VM is set in the 'notes' field of the VM. This field
  # supports markdown.
  #
  # This field# is hijacked by the provisioning process as a place to store data
  # that can be configured via the API and can be read from the hook scripts.
  #
  # Note: Terraform (at least on Windows) loves putting CRLF sequences to the
  #       string, which just causes problems (so remove the CR's).
  #
  desc = replace(<<EOT
%{if var.description != null && var.description != ""~}
${var.description}
%{endif~}

A VM provisioned with Terraform from template ${var.template_name} on ${timestamp()}

## Configuration

```
%{if local.has_butane ~}
hook-script: local:snippets/cloudinit-to-ignition
cloud-init: ${proxmox_cloud_init_disk.ignition_cloud_init[count.index].id}
%{endif ~}
%{if local.has_virtiofs ~}
hook-script: local:snippets/virtiofsd.pl
%{for i, fs in var.virtiofs[*]~}
virtiofs: --path "${fs.dirid}" --socket /run/virtiofs/vm${var.vmid + count.index}-fs${i}
%{endfor~}
%{endif ~}
```
EOT
    , "\r", "")

  /*
    The QEMU arguments are being used where Proxmox doesn't have first class support
    for a QEMU feature. This includes:
       1. Ignition support via the fw_cfg interface
       2. virtiofs support

    To make the args generate code more readable, the argument are created with line
    breaks in a multiline format, then the linebreaks are replaced with spaces so that
    the generated options are machine readable.

    fw_cfg
    ======

    The 'arguments' parameter for QEMU is parsed in such a way that the string is not
    treated opaquely. The options are split at comma's (',') causing ambiguity with
    options without a value.

    The doubling up of comma's in the fw_cfg configuration overcomes this limitation.
    This is documented in the Qemu documentation in the 'blockdev drive -file' section.

    Setting this args parameter when creating a VM requires local root access
    with password authentication. The ignition file is created in the `/etc/pve/...`
    directory by the helper hook script.

    virtio
    ======

    Note: Each virtiofs declaration also requires a directive in the description
    to get the hookscript to run an instance of the virtiofsd (rust) daemon. See
    the generation of the description field.
 */
  args = trimspace(replace(
    <<-EOT
      %{if local.has_butane}
        -fw_cfg name=opt/org.flatcar-linux/config,file=/etc/pve/local/ignition/${var.vmid + count.index}.ign
      %{endif}

      %{if local.has_virtiofs}
        -object memory-backend-file,id=virtiofs-mem,size=${var.memory}M,mem-path=/dev/shm,share=on
        -machine memory-backend=virtiofs-mem
        %{for i, fs in var.virtiofs[*]}
          -chardev socket,id=virtfs${i},path=/run/virtiofs/vm${var.vmid + count.index}-fs${i}
          -device  vhost-user-fs-pci,queue-size=1024,chardev=virtfs${i},tag=${fs.tag}
        %{endfor}
      %{endif}
      %{for i, fs in var.plan9fs[*]}
        -virtfs local,path=${fs.dirid},mount_tag=${fs.tag},security_model=${fs.security_model},id=p9-vm${var.vmid}-fs${i}${fs.readonly ? ",readonly":""},multidevs=${fs.multidevs}
      %{endfor}
EOT
    ,
    "/[\r\n]+/",
    " "))


  /*
    Enable serial port support. Where the guest provides serial console
    support (which flatcar does out of the box), diagnostics around booting
    and crashing are vastly simplified.

   Use the following command to access the serial port/terminal:
       qm terminal <vm_id>

    This should create QEMU equivalent option:
        -serial unix:/var/run/qemu-server/101.serial,server,nowait

    For ignition errors, look in /run/initramfs/rdsosreport.txt
          #  grep CRITICAL /run/initramfs/rdsosreport.txt

   see:
      - https://pve.proxmox.com/wiki/Serial_Terminal
  */
  serial {
    id   = 0
    type = "socket"
  }

  # The qemu agent must be running in the flatcar instance so that Proxmox can
  # identify when the VM is up (see https://github.com/flatcar/Flatcar/issues/737)
  agent = var.agent ? 1 : 0
  timeouts {
    # use terraform timeouts instead of 'guest_agent_ready_timeout'
    create  = "60s"
    update  = "60s"
    default = "120s"
  }

  # The connection info is obtained via the guest agent once the VM is
  # up and running. This requires the ignition configuration to 'work' and the
  # agent to be running. This will provide feedback that the VM is operational.
  #
  # If this fails, the following error is produced:
  #      Warning: define_connection_info is %t, no further action.
  define_connection_info = true

  # Generally use UEFI ("ovmf") where possible - the default is seabios
  bios = var.bios

  # There seems to be an issue here with duplication
  os_type = var.os_type # qemu identifier
  qemu_os = var.os_type # qemu identifier

  cores   = var.cores
  sockets = 1
  cpu     = var.cpu
  memory  = var.memory
  tags    = join(";", sort(var.tags)) # Proxmox sorts the tags, so sort them here to stop change thrash
  onboot  = var.onboot
  startup = var.startup
  boot    = var.boot
  scsihw  = "virtio-scsi-single"

  // Support an array of virtio network adapters.
  //
  // If multiple VMs are created at the same time then the macaddr may be
  // duplicated due to the time epoch being used to initialise the random
  // seed (seen on Windows). Default to using the Telmate provider 'repeatable'
  // option to generate a non-time based MAC address.
  dynamic "network" {
    for_each = var.networks
    content {
      model  = "virtio"
      bridge = network.value.bridge
      tag    = network.value.tag
      mtu    = network.value.mtu

      // The generated mac address is not unique if multiple VMs are created
      // at the same time (best guess is that the same time epoch is used to seed
      // a random number).
      //
      // This code takes a similar approach to the terraform API with the 'repeatable'
      // strategy used in `config_qemu.go`. However the Linux MAC vendor prefix ('00:18:59')
      // is replaced with the 16 bits of hash generated from the vm name.
      //
      // In the future a repeatable address with the proxmox registered 'bc:24:11'
      // address should be used.
      //
      // The overall MAC address is:
      //  - a zero for the top 8 bits
      //  - 16 bits of md5 of the vm name
      //  - 19 bits of the VM id
      //  - 5 bits of the interface index
      //
      // see:
      //  - https://maclookup.app/macaddress/BC2411
      macaddr = network.value.macaddr != null && network.value.macaddr != "" ? network.value.macaddr : format(
        "%2.2x:%s:%s:%2.2x:%2.2x:%2.2x",
        0,
        substr(md5(var.name), 1, 2),
        substr(md5(var.name), 3, 2),
        floor(((var.vmid + count.index) * 32 + index(var.networks, network.value)) / 65536) % 256,
        floor(((var.vmid + count.index) * 32 + index(var.networks, network.value)) / 256) % 256,
        ((var.vmid + count.index) * 32 + index(var.networks, network.value)) % 256)
    }
  }


  // Support a list of optional disks (in addition to those inherited from the cloned
  // template). Getting these expressed so they don't conflict with disks inherited
  // from the template can be problematic (use slots).
  //
  // see
  //   - https://github.com/Telmate/terraform-provider-proxmox/blob/master/docs/resources/vm_qemu.md#disks-block
  //   - https://developer.hashicorp.com/terraform/language/expressions/dynamic-blocks
  dynamic "disk" {
    for_each = var.disks
    content {
      slot           = disk.value.slot
      storage        = disk.value.storage
      type           = disk.value.type
      id             = disk.value.id
      asyncio        = disk.value.asyncio
      backup         = disk.value.backup
      cache          = disk.value.cache
      discard        = disk.value.discard
      disk_file      = disk.value.disk_file
      emulatessd     = disk.value.emulatessd
      format         = disk.value.format
      iothread       = disk.value.iothread
      iso            = disk.value.iso
      linked_disk_id = disk.value.linked_disk_id
      passthrough    = disk.value.passthrough
      readonly       = disk.value.readonly
      replicate      = disk.value.replicate
      serial         = disk.value.serial
      size           = disk.value.size
      wwn            = disk.value.wwn
    }
  }

  lifecycle {
    prevent_destroy       = false # this resource should be immutable **and** disposable
    create_before_destroy = false
    ignore_changes        = [
      disks, # the disk is provisioned in the template and inherited (but not defined here]
      desc  # the description on the first start, then the user can change it in the UI
    ]
    replace_triggered_by = [
      null_resource.node_replace_trigger[count.index].id
    ]
  }
}

/**
    Convert a butane configuration to an ignition JSON configuration. The template supports
    multiple instances (a count) so that each configuration can be slightly changed.

    see
      - https://github.com/poseidon/terraform-provider-ct
      - https://registry.terraform.io/providers/poseidon/ct/latest
      - https://registry.terraform.io/providers/poseidon/ct/latest/docs
      - https://www.flatcar.org/docs/latest/provisioning/config-transpiler/
      - https://developer.hashicorp.com/terraform/language/functions/templatefile
*/
data "ct_config" "ignition_json" {
  count   = local.has_butane ? var.vm_count : 0
  content = templatefile(var.butane_conf, {
    "vm_id"    = var.vm_count > 1 ? var.vmid + count.index : var.vmid
    "vm_name"  = var.vm_count > 1 ? "${var.name}-${count.index + 1}" : var.name
    "vm_count" = var.vm_count,
    "vm_index" = count.index,
  })
  strict       = true
  pretty_print = true
  files_dir    = local.butane_snippet_path

  snippets = [
    for s in var.butane_conf_snippets : templatefile("${local.butane_snippet_path}/${s}", {
      "vm_id"    = var.vm_count > 1 ? var.vmid + count.index : var.vmid
      "vm_name"  = var.vm_count > 1 ? "${var.name}-${count.index + 1}" : var.name
      "vm_count" = var.vm_count,
      "vm_index" = count.index,
    })
  ]
}

/*
  Create a cloud-init ISO with the ignition configuration as the `meta data` file.

  This is a blatant hack/hijack of the meta-data, as the ignition file is not
  a cloud-init configuration. The ISO will not be attached to the VM and will have
  a lifecycle that is independent of the VM (i.e. if the VM is deleted, then a manual
  deletion of the cloud-init ISO will be required).

  The ignition configuration is put into the ISO as plain text (it can be formatted/pretty
  or in a canonical form). No escaping, or base64 encoding is performed.

  This strategy is used as it allows an arbitrary size configuration file to
  be provisioned into the proxmox nodes. Using fields in the main configuration for
  a VM have size restrictions.

  see:
    - https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/guides/cloud_init
*/
resource "proxmox_cloud_init_disk" "ignition_cloud_init" {
  count     = local.has_butane ? var.vm_count : 0
  name      = var.vm_count > 1 ? "${var.name}-${count.index + 1}" : var.name
  pve_node  = var.target_node
  storage   = var.cloud_init_storage
  meta_data = data.ct_config.ignition_json[count.index].rendered
}

/**
    A null resource to track changes, so that the immutable VM is recreated.
 */
resource "null_resource" "node_replace_trigger" {
  count    = var.vm_count
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    "ignition" = local.has_butane ? data.ct_config.ignition_json[count.index].rendered : ""
    "virtiofs" = <<EOT
       %{for fs in var.virtiofs[*]~}
         fs.devid,fs.tag
      %{endfor~}
   EOT
  }
}