# =============================================================================
# ML Platform Infrastructure - Main Terraform Configuration
# =============================================================================
# Creates a complete ML platform with:
# - Control Plane VM (K8s master)
# - GPU Worker VM (K8s worker with NVIDIA T4)
# - Azure Container Registry
# - Azure Blob Storage
# - Virtual Network with proper security
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# =============================================================================
# Random suffix for globally unique names
# =============================================================================

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

locals {
  # Unique suffix for globally unique resource names
  unique_suffix = random_string.suffix.result

  # Resource naming
  acr_name             = "${var.project_name}acr${local.unique_suffix}"
  storage_account_name = "stg${var.project_name}${local.unique_suffix}"

  # Network naming
  vnet_name            = "vnet-${var.project_name}-${var.environment}"
  control_subnet_name  = "snet-control-${var.environment}"
  gpu_subnet_name      = "snet-gpu-${var.environment}"
  nsg_name             = "nsg-${var.project_name}-${var.environment}"

  # VM naming
  control_vm_name      = "vm-${var.project_name}-control"
  gpu_vm_name          = "vm-${var.project_name}-gpu"

  # Common tags
  common_tags = merge(var.tags, {
    CreatedBy = "terraform"
    Suffix    = local.unique_suffix
  })
}

# =============================================================================
# Resource Group
# =============================================================================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# =============================================================================
# Virtual Network and Subnets
# =============================================================================

resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "control_plane" {
  name                 = local.control_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.control_plane_subnet_prefix]
}

resource "azurerm_subnet" "gpu_worker" {
  name                 = local.gpu_subnet_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.gpu_worker_subnet_prefix]
}

# =============================================================================
# Network Security Group
# =============================================================================

resource "azurerm_network_security_group" "main" {
  name                = local.nsg_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# SSH Access (from admin IPs only)
resource "azurerm_network_security_rule" "ssh" {
  name                        = "Allow-SSH"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = length(var.admin_ips) > 0 ? var.admin_ips : ["0.0.0.0/0"]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

# Kubernetes API (6443)
resource "azurerm_network_security_rule" "k8s_api" {
  name                        = "Allow-K8s-API"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6443"
  source_address_prefixes     = length(var.admin_ips) > 0 ? var.admin_ips : ["0.0.0.0/0"]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

# Kubelet API (10250)
resource "azurerm_network_security_rule" "kubelet" {
  name                        = "Allow-Kubelet"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "10250"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

# etcd (2379-2380)
resource "azurerm_network_security_rule" "etcd" {
  name                        = "Allow-etcd"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "2379-2380"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

# Flannel VXLAN (8472 UDP)
resource "azurerm_network_security_rule" "flannel" {
  name                        = "Allow-Flannel"
  priority                    = 140
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "8472"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

# NodePort Services (30000-32767)
resource "azurerm_network_security_rule" "nodeports" {
  name                        = "Allow-NodePorts"
  priority                    = 150
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "30000-32767"
  source_address_prefixes     = length(var.admin_ips) > 0 ? var.admin_ips : ["0.0.0.0/0"]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

# HTTP/HTTPS for web services
resource "azurerm_network_security_rule" "http" {
  name                        = "Allow-HTTP"
  priority                    = 160
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443", "8501", "8000", "8888"]
  source_address_prefixes     = length(var.admin_ips) > 0 ? var.admin_ips : ["0.0.0.0/0"]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

# Associate NSG with subnets
resource "azurerm_subnet_network_security_group_association" "control_plane" {
  subnet_id                 = azurerm_subnet.control_plane.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_subnet_network_security_group_association" "gpu_worker" {
  subnet_id                 = azurerm_subnet.gpu_worker.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# =============================================================================
# Azure Container Registry
# =============================================================================

resource "azurerm_container_registry" "main" {
  count               = var.create_container_registry ? 1 : 0
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = true
  tags                = local.common_tags
}

# =============================================================================
# Azure Storage Account
# =============================================================================

resource "azurerm_storage_account" "main" {
  count                    = var.create_storage_account ? 1 : 0
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication

  blob_properties {
    versioning_enabled = false
  }

  tags = local.common_tags
}

# Blob Containers
resource "azurerm_storage_container" "containers" {
  for_each              = var.create_storage_account ? toset(var.blob_containers) : []
  name                  = each.value
  storage_account_name  = azurerm_storage_account.main[0].name
  container_access_type = "private"
}

# =============================================================================
# Public IPs
# =============================================================================

resource "azurerm_public_ip" "control_plane" {
  name                = "pip-${local.control_vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_public_ip" "gpu_worker" {
  name                = "pip-${local.gpu_vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# =============================================================================
# Network Interfaces
# =============================================================================

resource "azurerm_network_interface" "control_plane" {
  name                = "nic-${local.control_vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.control_plane.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.control_plane_private_ip
    public_ip_address_id          = azurerm_public_ip.control_plane.id
  }
}

resource "azurerm_network_interface" "gpu_worker" {
  name                = "nic-${local.gpu_vm_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.gpu_worker.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.gpu_worker_private_ip
    public_ip_address_id          = azurerm_public_ip.gpu_worker.id
  }
}

# =============================================================================
# Control Plane VM
# =============================================================================

resource "azurerm_linux_virtual_machine" "control_plane" {
  name                = local.control_vm_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.control_plane_vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.control_plane.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  custom_data = base64encode(templatefile("${path.module}/../cloud-init/control-plane.yaml", {
    kubernetes_version   = var.kubernetes_version
    pod_network_cidr     = var.pod_network_cidr
    control_plane_ip     = var.control_plane_private_ip
    admin_username       = var.admin_username
    acr_name             = var.create_container_registry ? local.acr_name : ""
    acr_login_server     = var.create_container_registry ? "${local.acr_name}.azurecr.io" : ""
    storage_account_name = var.create_storage_account ? local.storage_account_name : ""
    storage_account_key  = var.create_storage_account ? azurerm_storage_account.main[0].primary_access_key : ""
  }))

  tags = local.common_tags

  # Ignore cloud-init changes after initial creation (cloud-init only runs once)
  lifecycle {
    ignore_changes = [custom_data]
  }
}

# =============================================================================
# GPU Worker VM
# =============================================================================

resource "azurerm_linux_virtual_machine" "gpu_worker" {
  name                = local.gpu_vm_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.gpu_vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.gpu_worker.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 256
  }

  source_image_reference {
    publisher = var.vm_image.publisher
    offer     = var.vm_image.offer
    sku       = var.vm_image.sku
    version   = var.vm_image.version
  }

  custom_data = base64encode(templatefile("${path.module}/../cloud-init/gpu-worker.yaml", {
    kubernetes_version   = var.kubernetes_version
    control_plane_ip     = var.control_plane_private_ip
    admin_username       = var.admin_username
    acr_name             = var.create_container_registry ? local.acr_name : ""
    acr_login_server     = var.create_container_registry ? "${local.acr_name}.azurecr.io" : ""
    storage_account_name = var.create_storage_account ? local.storage_account_name : ""
    storage_account_key  = var.create_storage_account ? azurerm_storage_account.main[0].primary_access_key : ""
  }))

  tags = local.common_tags

  # Ignore cloud-init changes after initial creation (cloud-init only runs once)
  lifecycle {
    ignore_changes = [custom_data]
  }

  # No depends_on needed - both VMs can be created in parallel
  # The only real dependency is K8s cluster init before worker join,
  # which is handled in deploy.sh, not Terraform
}

# =============================================================================
# GPU VM Auto-Shutdown (Cost Savings)
# =============================================================================

resource "azurerm_dev_test_global_vm_shutdown_schedule" "gpu_shutdown" {
  count              = var.gpu_auto_shutdown_enabled ? 1 : 0
  virtual_machine_id = azurerm_linux_virtual_machine.gpu_worker.id
  location           = azurerm_resource_group.main.location
  enabled            = true

  daily_recurrence_time = var.gpu_auto_shutdown_time
  timezone              = "UTC"

  notification_settings {
    enabled = false
  }

  tags = local.common_tags
}
