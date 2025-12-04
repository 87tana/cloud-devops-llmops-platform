# =============================================================================
# ML Platform Infrastructure - Variables
# =============================================================================
# NEW naming convention to avoid conflicts with existing resources:
# - Existing: rg-llm-finetuning, mlplatformacr2024, vm-llm-finetuning
# - New: rg-mlplatform-auto, mlplatformauto*, vm-mlplatform-*
# =============================================================================

variable "project_name" {
  description = "Project name used for resource naming (keep short for Azure naming limits)"
  type        = string
  default     = "mlplatform"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "auto"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-mlplatform-auto"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "eastus"
}

variable "admin_ips" {
  description = "List of admin public IPs for SSH/K8s API access (CIDR format)"
  type        = list(string)
  default     = []
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

# =============================================================================
# VM Configuration
# =============================================================================

variable "control_plane_vm_size" {
  description = "VM size for control plane (needs 4+ vCPUs for K8s)"
  type        = string
  default     = "Standard_B4ms"
}

variable "gpu_vm_size" {
  description = "VM size for GPU worker (T4 GPU)"
  type        = string
  default     = "Standard_NC4as_T4_v3"
}

variable "vm_image" {
  description = "VM image configuration"
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "control_plane_subnet_prefix" {
  description = "Subnet prefix for control plane"
  type        = string
  default     = "10.1.1.0/24"
}

variable "gpu_worker_subnet_prefix" {
  description = "Subnet prefix for GPU workers"
  type        = string
  default     = "10.1.2.0/24"
}

variable "control_plane_private_ip" {
  description = "Static private IP for control plane"
  type        = string
  default     = "10.1.1.10"
}

variable "gpu_worker_private_ip" {
  description = "Static private IP for GPU worker"
  type        = string
  default     = "10.1.2.10"
}

# =============================================================================
# Kubernetes Configuration
# =============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version to install (must match on all nodes)"
  type        = string
  default     = "1.31"
}

variable "pod_network_cidr" {
  description = "CIDR for Kubernetes pod network (Flannel default)"
  type        = string
  default     = "10.244.0.0/16"
}

# =============================================================================
# Storage Configuration
# =============================================================================

variable "create_storage_account" {
  description = "Create Azure Storage Account for model/data storage"
  type        = bool
  default     = true
}

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
}

variable "blob_containers" {
  description = "Blob containers to create"
  type        = list(string)
  default     = ["models", "uploads", "datasets"]
}

# =============================================================================
# Container Registry Configuration
# =============================================================================

variable "create_container_registry" {
  description = "Create Azure Container Registry"
  type        = bool
  default     = true
}

variable "acr_sku" {
  description = "ACR SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Basic"
}

# =============================================================================
# GPU Auto-shutdown Configuration
# =============================================================================

variable "gpu_auto_shutdown_enabled" {
  description = "Enable auto-shutdown for GPU VM to save costs"
  type        = bool
  default     = true
}

variable "gpu_auto_shutdown_time" {
  description = "Daily shutdown time in HHmm format (UTC)"
  type        = string
  default     = "2300"
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ml-platform-auto"
    Environment = "dev"
    ManagedBy   = "terraform"
    Purpose     = "k8s-ml-training"
  }
}
