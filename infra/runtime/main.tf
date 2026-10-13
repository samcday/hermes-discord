terraform {
  required_version = ">= 1.10, < 2.0"
  backend "local" {}
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "= 0.9.9"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

variable "libvirt_uri" {
  type    = string
  default = "qemu:///session"
}

variable "image" {
  type        = string
  description = "Uncompressed mkosi-derived qcow2 artifact, already sized for the guest."
}

variable "storage_state" {
  type        = string
  description = "Local OpenTofu state for the independently managed durable disks."
}

data "terraform_remote_state" "storage" {
  backend = "local"
  config  = { path = var.storage_state }
}

locals {
  image_id = filesha256(var.image)
}

resource "libvirt_volume" "os" {
  name       = "hermes-os-${substr(local.image_id, 0, 16)}.qcow2"
  pool       = data.terraform_remote_state.storage.outputs.pool_name
  capacity   = 20 * 1024 * 1024 * 1024
  allocation = 0
  target     = { format = { type = "qcow2" } }
  create     = { content = { url = abspath(var.image) } }
}

resource "libvirt_domain" "hermes" {
  name        = "hermes-voice"
  type        = "kvm"
  memory      = 4096
  memory_unit = "MiB"
  vcpu        = 4
  running     = true
  autostart   = false
  # Whisper/CTranslate2 need modern SIMD; libvirt's generic CPU lacks it.
  cpu = { mode = "host-passthrough" }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
    firmware_info = {
      features = [
        { name = "enrolled-keys", enabled = "no" },
        { name = "secure-boot", enabled = "no" }
      ]
    }
  }
  features = { acpi = true }

  # Longer than Hermes' 300-second drain window plus the rest of guest shutdown.
  update  = { shutdown = { timeout = 420 } }
  destroy = { shutdown = { timeout = 420 } }

  devices = {
    disks = [
      {
        device = "disk"
        driver = { name = "qemu", type = "qcow2" }
        source = { file = { file = libvirt_volume.os.path } }
        target = { dev = "vda", bus = "virtio" }
        boot   = { order = 1 }
      },
      {
        device = "disk"
        driver = { name = "qemu", type = "qcow2" }
        source = { file = { file = data.terraform_remote_state.storage.outputs.state_disk_path } }
        target = { dev = "vdb", bus = "virtio" }
        serial = "hermes-state"
      }
    ]
    interfaces = [{
      source  = { user = {} }
      backend = { type = "passt" }
      model   = { type = "virtio" }
      port_forward = [{
        proto   = "tcp"
        address = "127.0.0.1"
        ranges  = [{ start = 22222, to = 22 }]
      }]
    }]
    # libvirt defaults an omitted character-device source to an allocated PTY.
    # Explicit source.pty.path would make the provider own a runtime /dev/pts/N.
    serials  = [{ target = { type = "isa-serial", port = 0 } }]
    consoles = [{ target = { type = "serial", port = 0 } }]
  }

  lifecycle {
    # Shut down the old guest before replacing the disk it is using.
    replace_triggered_by = [libvirt_volume.os]
  }
}

output "image_id" {
  value = local.image_id
}

output "instance_id" {
  value = libvirt_domain.hermes.uuid
}

output "ssh" {
  value = "127.0.0.1:22222 (dedicated key via scripts/vm-ssh)"
}
