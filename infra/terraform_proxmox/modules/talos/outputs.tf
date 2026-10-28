output "nodes" {
  description = "Provisioned Talos nodes and their Proxmox MAC addresses"
  value = {
    for node in proxmox_virtual_environment_vm.talos_node : node.name => {
      vm_id       = node.vm_id
      vm_name     = node.name
      node_name   = node.node_name
      mac_address = length(node.mac_addresses) > 0 ? node.mac_addresses[0] : null
    }
  }
}
