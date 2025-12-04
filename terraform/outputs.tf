# =============================================================================
# ML Platform Infrastructure - Outputs
# =============================================================================

# =============================================================================
# Resource Group
# =============================================================================

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# =============================================================================
# Network
# =============================================================================

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "control_plane_subnet_id" {
  description = "ID of the control plane subnet"
  value       = azurerm_subnet.control_plane.id
}

output "gpu_worker_subnet_id" {
  description = "ID of the GPU worker subnet"
  value       = azurerm_subnet.gpu_worker.id
}

# =============================================================================
# Virtual Machines
# =============================================================================

output "control_plane_public_ip" {
  description = "Public IP address of the control plane VM"
  value       = azurerm_public_ip.control_plane.ip_address
}

output "control_plane_private_ip" {
  description = "Private IP address of the control plane VM"
  value       = var.control_plane_private_ip
}

output "gpu_worker_public_ip" {
  description = "Public IP address of the GPU worker VM"
  value       = azurerm_public_ip.gpu_worker.ip_address
}

output "gpu_worker_private_ip" {
  description = "Private IP address of the GPU worker VM"
  value       = var.gpu_worker_private_ip
}

output "control_plane_vm_name" {
  description = "Name of the control plane VM"
  value       = azurerm_linux_virtual_machine.control_plane.name
}

output "gpu_worker_vm_name" {
  description = "Name of the GPU worker VM"
  value       = azurerm_linux_virtual_machine.gpu_worker.name
}

# =============================================================================
# Container Registry
# =============================================================================

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = var.create_container_registry ? azurerm_container_registry.main[0].name : null
}

output "acr_login_server" {
  description = "Login server URL for the ACR"
  value       = var.create_container_registry ? azurerm_container_registry.main[0].login_server : null
}

output "acr_admin_username" {
  description = "Admin username for ACR"
  value       = var.create_container_registry ? azurerm_container_registry.main[0].admin_username : null
  sensitive   = true
}

output "acr_admin_password" {
  description = "Admin password for ACR"
  value       = var.create_container_registry ? azurerm_container_registry.main[0].admin_password : null
  sensitive   = true
}

# =============================================================================
# Storage Account
# =============================================================================

output "storage_account_name" {
  description = "Name of the storage account"
  value       = var.create_storage_account ? azurerm_storage_account.main[0].name : null
}

output "storage_account_primary_key" {
  description = "Primary access key for the storage account"
  value       = var.create_storage_account ? azurerm_storage_account.main[0].primary_access_key : null
  sensitive   = true
}

output "storage_account_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = var.create_storage_account ? azurerm_storage_account.main[0].primary_connection_string : null
  sensitive   = true
}

output "blob_containers" {
  description = "Names of created blob containers"
  value       = var.create_storage_account ? [for c in azurerm_storage_container.containers : c.name] : []
}

# =============================================================================
# SSH Commands
# =============================================================================

output "ssh_control_plane" {
  description = "SSH command to connect to control plane"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.control_plane.ip_address}"
}

output "ssh_gpu_worker" {
  description = "SSH command to connect to GPU worker"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.gpu_worker.ip_address}"
}

# =============================================================================
# Kubernetes Setup Commands
# =============================================================================

output "k8s_init_command" {
  description = "Command to initialize Kubernetes cluster (run on control plane after cloud-init completes)"
  value       = "sudo kubeadm init --pod-network-cidr=${var.pod_network_cidr} --apiserver-advertise-address=${var.control_plane_private_ip}"
}

output "k8s_join_token_command" {
  description = "Command to generate join token (run on control plane)"
  value       = "sudo kubeadm token create --print-join-command"
}

# =============================================================================
# Docker Build Commands
# =============================================================================

output "docker_build_commands" {
  description = "Commands to build and push Docker images"
  value = (
    var.create_container_registry ? <<-EOT
    # Login to ACR
    az acr login --name ${azurerm_container_registry.main[0].name}

    # Build and push images
    docker build -t ${azurerm_container_registry.main[0].login_server}/ml-backend:v1 ./docker/backend/
    docker build -t ${azurerm_container_registry.main[0].login_server}/ml-frontend:v1 ./docker/frontend/
    docker build -t ${azurerm_container_registry.main[0].login_server}/ml-jupyterlab:v1 ./docker/jupyterlab/

    docker push ${azurerm_container_registry.main[0].login_server}/ml-backend:v1
    docker push ${azurerm_container_registry.main[0].login_server}/ml-frontend:v1
    docker push ${azurerm_container_registry.main[0].login_server}/ml-jupyterlab:v1
    EOT
    : null
  )
}

# =============================================================================
# Summary
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value       = <<-EOT

    ═══════════════════════════════════════════════════════════════════════════
    ML Platform Infrastructure Deployed Successfully!
    ═══════════════════════════════════════════════════════════════════════════

    Resource Group: ${azurerm_resource_group.main.name}
    Location: ${azurerm_resource_group.main.location}

    ─────────────────────────────────────────────────────────────────────────
    VIRTUAL MACHINES
    ─────────────────────────────────────────────────────────────────────────
    Control Plane:
      Name: ${azurerm_linux_virtual_machine.control_plane.name}
      Public IP: ${azurerm_public_ip.control_plane.ip_address}
      Private IP: ${var.control_plane_private_ip}
      SSH: ssh ${var.admin_username}@${azurerm_public_ip.control_plane.ip_address}

    GPU Worker:
      Name: ${azurerm_linux_virtual_machine.gpu_worker.name}
      Public IP: ${azurerm_public_ip.gpu_worker.ip_address}
      Private IP: ${var.gpu_worker_private_ip}
      SSH: ssh ${var.admin_username}@${azurerm_public_ip.gpu_worker.ip_address}

    ─────────────────────────────────────────────────────────────────────────
    CONTAINER REGISTRY
    ─────────────────────────────────────────────────────────────────────────
    ${var.create_container_registry ? "Name: ${azurerm_container_registry.main[0].name}\n    Login Server: ${azurerm_container_registry.main[0].login_server}" : "Not created"}

    ─────────────────────────────────────────────────────────────────────────
    STORAGE ACCOUNT
    ─────────────────────────────────────────────────────────────────────────
    ${var.create_storage_account ? "Name: ${azurerm_storage_account.main[0].name}\n    Containers: ${join(", ", var.blob_containers)}" : "Not created"}

    ─────────────────────────────────────────────────────────────────────────
    NEXT STEPS
    ─────────────────────────────────────────────────────────────────────────
    1. Wait for cloud-init to complete on both VMs (~5-10 minutes)
       ssh ${var.admin_username}@${azurerm_public_ip.control_plane.ip_address}
       sudo cloud-init status --wait

    2. Initialize Kubernetes cluster on control plane:
       sudo kubeadm init --pod-network-cidr=${var.pod_network_cidr}

    3. Setup kubectl:
       mkdir -p $HOME/.kube
       sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
       sudo chown $(id -u):$(id -g) $HOME/.kube/config

    4. Install Flannel CNI:
       kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

    5. Get join command and run on GPU worker:
       sudo kubeadm token create --print-join-command

    6. Build and push Docker images to ACR

    7. Apply Kubernetes manifests:
       kubectl apply -f k8s/

    ═══════════════════════════════════════════════════════════════════════════
  EOT
}
