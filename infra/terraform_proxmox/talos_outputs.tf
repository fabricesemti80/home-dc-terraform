output "node_ips" {
  description = "Static IP addresses assigned to each node"
  value       = { for node in var.nodes : node.name => node.address }
}

output "nodes_info" {
  description = "Node information including IP addresses and MAC addresses"
  value = {
    for name, details in module.talos.nodes : name => {
      ip                    = [for node in var.nodes : node.address if node.name == name][0]
      mac_address           = details.mac_address
      mac_address_secondary = details.mac_address_secondary
    }
  }
}
