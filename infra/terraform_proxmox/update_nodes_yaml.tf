resource "null_resource" "update_nodes_yaml" {
  triggers = {
    nodes_info = jsonencode({
      for name, details in module.talos.nodes : name => {
        ip               = [for node in var.nodes : node.address if node.name == name][0]
        mac_address      = details.mac_address
        ceph_mac_address = details.mac_address_secondary
      }
    })
  }

  provisioner "local-exec" {
    command = "${path.module}/update_nodes.sh"
    environment = {
      NODES_JSON = jsonencode({
        for name, details in module.talos.nodes : name => {
          ip               = [for node in var.nodes : node.address if node.name == name][0]
          mac_address      = details.mac_address
          ceph_mac_address = details.mac_address_secondary
        }
      })
      NODES_YAML = abspath("${path.root}/../../../home-dc-kubernetes/nodes.yaml")
    }
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [module.talos]
}
