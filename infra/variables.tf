variable "resource_group_name" {
  description = "Existing resource group created by bootstrap/."
  type        = string
  default     = "rg-winbase-lab"
}

variable "location" {
  description = "Region override. Defaults to the resource group's region."
  type        = string
  default     = null
}

variable "vm_size" {
  description = "VM size. A B-series burstable is ample for a baseline run."
  type        = string
  default     = "Standard_B2s"
}

variable "vm_image_sku" {
  description = "Windows Server image SKU. Core has no GUI; Azure Edition supports hotpatching."
  type        = string
  default     = "2025-datacenter-azure-edition-core-smalldisk"
}

variable "hotpatching_enabled" {
  description = "Hotpatching applies most security updates without a reboot. Requires an Azure Edition Core image."
  type        = bool
  default     = true
}

variable "admin_username" {
  description = "Local administrator account. Nobody signs in with it; it exists because Azure requires one."
  type        = string
  default     = "labadmin"
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
