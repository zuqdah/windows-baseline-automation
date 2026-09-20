data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# Azure requires a local administrator password even when nobody will ever
# sign in. It is generated here, stored in Key Vault, and never printed.
resource "random_password" "admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  name     = "winbase-${random_string.suffix.result}"
  location = coalesce(var.location, data.azurerm_resource_group.lab.location)

  tags = merge(var.tags, {
    workload   = "windows-baseline-automation"
    managed-by = "terraform"
    repo       = "github.com/zuqdah/windows-baseline-automation"
  })
}

# ---------------------------------------------------------------------------
# Network: no public address, no inbound path
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name}"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.lab.name
  address_space       = ["10.42.0.0/24"]
  tags                = local.tags
}

resource "azurerm_subnet" "this" {
  name                 = "snet-servers"
  resource_group_name  = data.azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.42.0.0/26"]
}

# Azure denies inbound from the internet by default; this states it, so the
# intent survives someone else's later edit.
resource "azurerm_network_security_group" "this" {
  name                = "nsg-${local.name}"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

resource "azurerm_network_interface" "this" {
  name                = "nic-${local.name}"
  location            = local.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    # Deliberately no public_ip_address_id: the pipeline reaches this machine
    # through the Azure agent, not the network.
  }
}

# ---------------------------------------------------------------------------
# The server
# ---------------------------------------------------------------------------

resource "azurerm_windows_virtual_machine" "this" {
  #checkov:skip=CKV_AZURE_50:The pipeline configures this machine through Run Command by design; that is the alternative to opening RDP.
  #checkov:skip=CKV_AZURE_151:Host-level encryption needs a disk encryption set; Azure encrypts managed disks at rest with platform keys.
  name                  = "vm-${local.name}"
  computer_name         = "WINBASE01"
  resource_group_name   = data.azurerm_resource_group.lab.name
  location              = local.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = random_password.admin.result
  network_interface_ids = [azurerm_network_interface.this.id]
  tags                  = local.tags

  # Trusted launch: secure boot and a virtual TPM.
  secure_boot_enabled = true
  vtpm_enabled        = true

  # Server Core, Azure Edition: no GUI to attack, and hotpatching, which
  # removes most reboots from the patch cycle.
  patch_mode          = "AutomaticByPlatform"
  hotpatching_enabled = var.hotpatching_enabled

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "osdisk-${local.name}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.vm_image_sku
    version   = "latest"
  }
}

# ---------------------------------------------------------------------------
# Break-glass credential
# ---------------------------------------------------------------------------

module "keyvault" {
  # 335bc3b is tag v1.0.0 of the landing zone lab.
  source = "git::https://github.com/zuqdah/azure-agent-landing-zone.git//modules/keyvault?ref=335bc3bb3b64b633c028b6df8d21599a294e8f6c"

  name                = replace(local.name, "-", "")
  location            = local.location
  resource_group_name = data.azurerm_resource_group.lab.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = module.keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "rbac_propagation" {
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}

resource "time_offset" "secret_expiry" {
  offset_days = 30
}

resource "azurerm_key_vault_secret" "admin_password" {
  name            = "vm-admin-password"
  value           = random_password.admin.result
  key_vault_id    = module.keyvault.id
  content_type    = "Local administrator password, break-glass only"
  expiration_date = time_offset.secret_expiry.rfc3339

  depends_on = [time_sleep.rbac_propagation]
}
