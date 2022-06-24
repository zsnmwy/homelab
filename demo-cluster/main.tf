provider "vsphere" {
  user           = var.user
  password       = var.password
  vsphere_server = var.vsphere_server

  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = var.resource_pool
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.template
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "vm" {

  count = 2

  name             = "${var.name}-${count.index}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id

  num_cpus = var.cpus
  memory   = var.memory
  guest_id = data.vsphere_virtual_machine.template.guest_id

  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  wait_for_guest_net_timeout = 60
  wait_for_guest_ip_timeout  = 60

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  cdrom {
    client_device = true
  }

  vapp {
    properties = {
      user-data = "${base64encode(file("cloud-init.yaml"))}"
    }
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = self.default_ip_address
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "file" {
    source = "env.sh"
    destination = "/root/env.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod a+x /root/env.sh",
      "/root/env.sh"
    ]
  }
}

output "vm-ip-address" {
  value = vsphere_virtual_machine.vm.*.default_ip_address
}


resource "null_resource" "k8s-master-init" {

  connection {
    type        = "ssh"
    user        = "root"
    host        = vsphere_virtual_machine.vm[0].default_ip_address
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "file" {
    source      = "k8s-install.sh"
    destination = "/root/k8s-install.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod a+x /root/k8s-install.sh",
      "/root/k8s-install.sh",
      "kubeadm token create --print-join-command > /root/join.sh"
    ]
  }


  provisioner "local-exec" {
    command = "scp -o 'StrictHostKeyChecking no' root@${vsphere_virtual_machine.vm[0].default_ip_address}:/etc/kubernetes/admin.conf admin-${vsphere_virtual_machine.vm[0].default_ip_address}.conf"
  }

  provisioner "local-exec" {
    command = "ssh -o 'StrictHostKeyChecking no' root@${vsphere_virtual_machine.vm[0].default_ip_address} cat /root/join.sh > join.sh && sleep 10"
  }

  # provisioner "local-exec" {
  #   when = destroy
  #   command = "rm -rf admin-${vsphere_virtual_machine.vm[0].default_ip_address}.conf join-${vsphere_virtual_machine.vm[0].default_ip_address}.sh"
  # }

}

  locals {
    workers = slice(vsphere_virtual_machine.vm, 1, length(vsphere_virtual_machine.vm))
  }


resource "null_resource" "k8s-worker-join" {


  for_each = {
    for vm in local.workers : vm.default_ip_address => vm
  }

  connection {
    type        = "ssh"
    user        = "root"
    host        = each.value.default_ip_address
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "file" {
    source      = "join.sh"
    destination = "/root/join-${vsphere_virtual_machine.vm[0].default_ip_address}.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "echo join ${each.value.default_ip_address} into cluster",
      "bash /root/join-${vsphere_virtual_machine.vm[0].default_ip_address}.sh",
    ]
  }

  depends_on = [vsphere_virtual_machine.vm, local.workers, null_resource.k8s-master-init]
}
