output "vm_name" {
  description = "Name of the Windows Server VM the pipeline configures."
  value       = azurerm_windows_virtual_machine.this.name
}

output "resource_group_name" {
  description = "Resource group holding the lab."
  value       = data.azurerm_resource_group.lab.name
}

output "key_vault_name" {
  description = "Key Vault holding the break-glass administrator password."
  value       = module.keyvault.name
}

output "private_ip" {
  description = "The VM's private address. There is no public one."
  value       = azurerm_network_interface.this.private_ip_address
}

output "image_sku" {
  description = "Windows Server image the VM was built from."
  value       = azurerm_windows_virtual_machine.this.source_image_reference[0].sku
}
