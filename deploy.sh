#!/bin/bash
# =============================================================================
# ML Platform - End-to-End Deployment Script
# =============================================================================
# This script automates the complete deployment of the ML Platform infrastructure
# including Azure resources, Kubernetes cluster setup, and application deployment.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
K8S_DIR="${SCRIPT_DIR}/k8s"
DOCKER_DIR="${SCRIPT_DIR}/docker"

# Log functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Pre-flight Checks
# =============================================================================
preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check required tools
    local required_tools=("az" "terraform" "ssh" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    log_success "All required tools are installed"

    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure CLI. Run: az login"
        exit 1
    fi
    log_success "Azure CLI is authenticated"

    # Check terraform.tfvars exists
    if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
        log_warn "terraform.tfvars not found. Creating from example..."
        cp "${TERRAFORM_DIR}/terraform.tfvars.example" "${TERRAFORM_DIR}/terraform.tfvars"
        log_warn "Please edit ${TERRAFORM_DIR}/terraform.tfvars with your settings"
        log_warn "Then run this script again"
        exit 1
    fi
    log_success "terraform.tfvars exists"

    # Check SSH key
    local ssh_key_path
    ssh_key_path=$(grep -E "^admin_ssh_public_key_path" "${TERRAFORM_DIR}/terraform.tfvars" | cut -d'"' -f2)
    ssh_key_path="${ssh_key_path/#\~/$HOME}"
    if [[ ! -f "$ssh_key_path" ]]; then
        log_error "SSH public key not found at: $ssh_key_path"
        log_info "Generate one with: ssh-keygen -t rsa -b 4096"
        exit 1
    fi
    log_success "SSH public key exists"
}

# =============================================================================
# Phase 1: Terraform Infrastructure
# =============================================================================
deploy_terraform() {
    log_info "=== Phase 1: Deploying Azure Infrastructure ==="

    cd "${TERRAFORM_DIR}"

    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init

    # Plan deployment
    log_info "Planning infrastructure changes..."
    terraform plan -out=tfplan

    # Apply changes
    log_info "Applying infrastructure changes (this may take 5-10 minutes)..."
    terraform apply tfplan

    # Export outputs
    log_info "Extracting Terraform outputs..."
    terraform output -json > "${SCRIPT_DIR}/terraform_outputs.json"

    log_success "Azure infrastructure deployed successfully"
}

# =============================================================================
# Phase 2: Build and Push Docker Images
# =============================================================================
build_and_push_images() {
    log_info "=== Phase 2: Building and Pushing Docker Images ==="

    # Get ACR details from Terraform output
    local acr_name acr_login_server
    acr_name=$(jq -r '.acr_name.value' "${SCRIPT_DIR}/terraform_outputs.json")
    acr_login_server=$(jq -r '.acr_login_server.value' "${SCRIPT_DIR}/terraform_outputs.json")

    # Login to ACR
    log_info "Logging into Azure Container Registry: ${acr_name}..."
    az acr login --name "${acr_name}"

    # Build and push images
    local images=("backend" "frontend" "jupyterlab")
    for image in "${images[@]}"; do
        if [[ -d "${DOCKER_DIR}/${image}" ]]; then
            log_info "Building ml-${image}:v1..."
            docker build -t "${acr_login_server}/ml-${image}:v1" "${DOCKER_DIR}/${image}"

            log_info "Pushing ml-${image}:v1 to ACR..."
            docker push "${acr_login_server}/ml-${image}:v1"

            log_success "ml-${image}:v1 pushed successfully"
        else
            log_warn "Docker directory not found for ${image}, skipping..."
        fi
    done

    log_success "All Docker images built and pushed"
}

# =============================================================================
# Phase 3: Update Kubernetes Manifests with ACR URL
# =============================================================================
update_k8s_manifests() {
    log_info "=== Phase 3: Updating Kubernetes Manifests ==="

    local acr_login_server
    acr_login_server=$(jq -r '.acr_login_server.value' "${SCRIPT_DIR}/terraform_outputs.json")

    # Update image references in K8s manifests
    log_info "Updating image references to use ACR: ${acr_login_server}"

    # Create updated manifests directory
    mkdir -p "${K8S_DIR}/generated"

    for manifest in "${K8S_DIR}"/*.yaml; do
        local filename
        filename=$(basename "$manifest")

        # Skip if already in generated folder
        [[ "$manifest" == *"/generated/"* ]] && continue

        # Replace placeholder image names with ACR URLs
        sed -e "s|image: ml-backend:v1|image: ${acr_login_server}/ml-backend:v1|g" \
            -e "s|image: ml-frontend:v1|image: ${acr_login_server}/ml-frontend:v1|g" \
            -e "s|image: ml-jupyterlab:v1|image: ${acr_login_server}/ml-jupyterlab:v1|g" \
            "$manifest" > "${K8S_DIR}/generated/${filename}"
    done

    log_success "Kubernetes manifests updated with ACR URLs"
}

# =============================================================================
# Phase 4: Initialize Kubernetes Cluster (OPTIMIZED - Parallel Cloud-Init)
# =============================================================================
init_kubernetes_cluster() {
    log_info "=== Phase 4: Initializing Kubernetes Cluster (Parallel Mode) ==="

    local control_plane_ip gpu_worker_ip ssh_user
    control_plane_ip=$(jq -r '.control_plane_public_ip.value' "${SCRIPT_DIR}/terraform_outputs.json")
    gpu_worker_ip=$(jq -r '.gpu_worker_public_ip.value' "${SCRIPT_DIR}/terraform_outputs.json")
    ssh_user=$(jq -r '.ssh_username.value' "${SCRIPT_DIR}/terraform_outputs.json")

    log_info "Control Plane IP: ${control_plane_ip}"
    log_info "GPU Worker IP: ${gpu_worker_ip}"

    # Start GPU worker cloud-init check in background
    log_info "Starting parallel cloud-init monitoring..."
    local gpu_ready_file="/tmp/gpu_cloud_init_done_$$"
    (
        while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
            "${ssh_user}@${gpu_worker_ip}" "cloud-init status" 2>/dev/null | grep -q "status: done"; do
            sleep 20
        done
        touch "$gpu_ready_file"
    ) &
    local gpu_wait_pid=$!

    # Wait for control plane cloud-init (foreground)
    log_info "Waiting for control plane cloud-init..."
    while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes \
        "${ssh_user}@${control_plane_ip}" "cloud-init status" 2>/dev/null | grep -q "status: done"; do
        log_info "Waiting for control plane to be ready..."
        sleep 20
    done
    log_success "Control plane cloud-init completed"

    # Initialize Kubernetes cluster immediately
    log_info "Initializing Kubernetes cluster on control plane..."
    ssh -o StrictHostKeyChecking=no "${ssh_user}@${control_plane_ip}" "sudo /usr/local/bin/k8s-init-cluster.sh"

    # Get kubeconfig
    log_info "Copying kubeconfig to local machine..."
    mkdir -p ~/.kube/clusters
    ssh -o StrictHostKeyChecking=no "${ssh_user}@${control_plane_ip}" "sudo cat /etc/kubernetes/admin.conf" > ~/.kube/clusters/mlplatform-auto.conf

    # Get join command
    log_info "Getting worker join command..."
    local join_command
    join_command=$(ssh -o StrictHostKeyChecking=no "${ssh_user}@${control_plane_ip}" "sudo kubeadm token create --print-join-command 2>/dev/null")

    # Now wait for GPU worker if not ready yet
    if [[ -f "$gpu_ready_file" ]]; then
        log_success "GPU worker cloud-init already completed (parallel execution saved time!)"
    else
        log_info "Waiting for GPU worker cloud-init to finish..."
        wait $gpu_wait_pid 2>/dev/null || true
        log_success "GPU worker cloud-init completed"
    fi
    rm -f "$gpu_ready_file"

    # Verify GPU on worker
    log_info "Verifying GPU on worker node..."
    ssh -o StrictHostKeyChecking=no "${ssh_user}@${gpu_worker_ip}" "sudo /usr/local/bin/verify-gpu.sh" || true

    # Join worker to cluster
    log_info "Joining GPU worker to cluster..."
    ssh -o StrictHostKeyChecking=no "${ssh_user}@${gpu_worker_ip}" "sudo ${join_command}"

    # Label GPU node
    log_info "Labeling GPU node..."
    export KUBECONFIG=~/.kube/clusters/mlplatform-auto.conf
    local gpu_node_name
    gpu_node_name=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$gpu_node_name" ]]; then
        kubectl label node "$gpu_node_name" nvidia.com/gpu.present=true --overwrite
    else
        log_warn "GPU node not found yet, skipping label (apply manually later)"
    fi

    log_success "Kubernetes cluster initialized with GPU worker"
}

# =============================================================================
# Phase 5: Create ACR Pull Secret
# =============================================================================
create_acr_secret() {
    log_info "=== Phase 5: Creating ACR Pull Secret ==="

    export KUBECONFIG=~/.kube/clusters/mlplatform-auto.conf

    local acr_name acr_login_server
    acr_name=$(jq -r '.acr_name.value' "${SCRIPT_DIR}/terraform_outputs.json")
    acr_login_server=$(jq -r '.acr_login_server.value' "${SCRIPT_DIR}/terraform_outputs.json")

    # Get ACR credentials
    local acr_username acr_password
    acr_username=$(az acr credential show --name "${acr_name}" --query "username" -o tsv)
    acr_password=$(az acr credential show --name "${acr_name}" --query "passwords[0].value" -o tsv)

    # Create namespace first if not exists
    kubectl apply -f "${K8S_DIR}/generated/00-namespace.yaml" || kubectl apply -f "${K8S_DIR}/00-namespace.yaml"

    # Create docker registry secret
    kubectl create secret docker-registry acr-secret \
        --docker-server="${acr_login_server}" \
        --docker-username="${acr_username}" \
        --docker-password="${acr_password}" \
        -n ml-platform \
        --dry-run=client -o yaml | kubectl apply -f -

    log_success "ACR pull secret created"
}

# =============================================================================
# Phase 6: Deploy Kubernetes Manifests
# =============================================================================
deploy_k8s_manifests() {
    log_info "=== Phase 6: Deploying Kubernetes Manifests ==="

    export KUBECONFIG=~/.kube/clusters/mlplatform-auto.conf

    local manifest_dir="${K8S_DIR}/generated"
    [[ -d "$manifest_dir" ]] || manifest_dir="${K8S_DIR}"

    # Deploy in order
    local manifests=(
        "00-namespace.yaml"
        "01-storage.yaml"
        "02-configmap.yaml"
        "06-nvidia-device-plugin.yaml"
        "03-backend.yaml"
        "04-frontend.yaml"
        "05-jupyterlab.yaml"
    )

    for manifest in "${manifests[@]}"; do
        if [[ -f "${manifest_dir}/${manifest}" ]]; then
            log_info "Applying ${manifest}..."
            kubectl apply -f "${manifest_dir}/${manifest}"
        else
            log_warn "Manifest not found: ${manifest}"
        fi
    done

    log_success "All Kubernetes manifests applied"
}

# =============================================================================
# Phase 7: Wait for Deployments and Display Access Info
# =============================================================================
wait_and_display_info() {
    log_info "=== Phase 7: Waiting for Deployments ==="

    export KUBECONFIG=~/.kube/clusters/mlplatform-auto.conf

    # Wait for deployments
    log_info "Waiting for backend deployment..."
    kubectl rollout status deployment/ml-backend -n ml-platform --timeout=300s || true

    log_info "Waiting for frontend deployment..."
    kubectl rollout status deployment/ml-frontend -n ml-platform --timeout=300s || true

    log_info "Waiting for jupyterlab deployment (may take longer due to GPU)..."
    kubectl rollout status deployment/ml-jupyterlab -n ml-platform --timeout=600s || true

    # Get access information
    local control_plane_ip gpu_worker_ip
    control_plane_ip=$(jq -r '.control_plane_public_ip.value' "${SCRIPT_DIR}/terraform_outputs.json")
    gpu_worker_ip=$(jq -r '.gpu_worker_public_ip.value' "${SCRIPT_DIR}/terraform_outputs.json")

    echo ""
    log_success "=============================================="
    log_success "  ML Platform Deployment Complete!"
    log_success "=============================================="
    echo ""
    echo -e "${GREEN}Access URLs:${NC}"
    echo -e "  Frontend (Streamlit):  http://${control_plane_ip}:30501"
    echo -e "  Backend (FastAPI):     http://${control_plane_ip}:30800"
    echo -e "  JupyterLab:            http://${gpu_worker_ip}:30888"
    echo -e "                         Token: mlplatform2024"
    echo ""
    echo -e "${GREEN}SSH Access:${NC}"
    echo -e "  Control Plane:  ssh azureuser@${control_plane_ip}"
    echo -e "  GPU Worker:     ssh azureuser@${gpu_worker_ip}"
    echo ""
    echo -e "${GREEN}Kubernetes:${NC}"
    echo -e "  export KUBECONFIG=~/.kube/clusters/mlplatform-auto.conf"
    echo -e "  kubectl get pods -n ml-platform"
    echo ""
    echo -e "${YELLOW}Note: Services may take a few minutes to become fully available.${NC}"
    echo ""
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    echo ""
    echo "=============================================="
    echo "  ML Platform - End-to-End Deployment"
    echo "=============================================="
    echo ""

    # Parse arguments
    local skip_terraform=false
    local skip_docker=false
    local skip_k8s=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-terraform)
                skip_terraform=true
                shift
                ;;
            --skip-docker)
                skip_docker=true
                shift
                ;;
            --skip-k8s)
                skip_k8s=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-terraform    Skip Terraform deployment"
                echo "  --skip-docker       Skip Docker image build/push"
                echo "  --skip-k8s          Skip Kubernetes deployment"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Run phases
    preflight_checks

    if [[ "$skip_terraform" == false ]]; then
        deploy_terraform
    else
        log_warn "Skipping Terraform deployment"
        if [[ ! -f "${SCRIPT_DIR}/terraform_outputs.json" ]]; then
            cd "${TERRAFORM_DIR}"
            terraform output -json > "${SCRIPT_DIR}/terraform_outputs.json"
        fi
    fi

    if [[ "$skip_docker" == false ]]; then
        build_and_push_images
    else
        log_warn "Skipping Docker image build/push"
    fi

    update_k8s_manifests

    if [[ "$skip_k8s" == false ]]; then
        init_kubernetes_cluster
        create_acr_secret
        deploy_k8s_manifests
        wait_and_display_info
    else
        log_warn "Skipping Kubernetes deployment"
        log_info "Updated manifests are in: ${K8S_DIR}/generated/"
    fi
}

# Run main function
main "$@"
