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

variable "storage_dir" {
  type        = string
  description = "Private host directory for virtual disks, never shared into the guest."
}

resource "libvirt_pool" "hermes" {
  name    = "hermes-voice"
  type    = "dir"
  target  = { path = var.storage_dir }
  destroy = { delete = false }

  lifecycle {
    prevent_destroy = true
  }
}

resource "libvirt_volume" "state" {
  name       = "hermes-state.qcow2"
  pool       = libvirt_pool.hermes.name
  capacity   = 16 * 1024 * 1024 * 1024
  allocation = 0
  target     = { format = { type = "qcow2" } }

  lifecycle {
    prevent_destroy = true
  }
}

output "pool_name" {
  value = libvirt_pool.hermes.name
}

output "state_disk_path" {
  value = libvirt_volume.state.path
}
