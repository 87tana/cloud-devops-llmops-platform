# ML Platform - Cloud DevOps LLMOps

A Kubernetes-based ML platform on Azure for fine-tuning and serving GPT-2 models.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    NGINX Ingress (:31622)                   │
│              /  →  Frontend  │  /api  →  Backend            │
│                              │  /jupyter  →  JupyterLab     │
└─────────────────────────────────────────────────────────────┘
                               │
        ┌──────────────────────┴──────────────────────┐
        │                                             │
┌───────┴───────┐                           ┌────────┴────────┐
│ Control Plane │                           │   GPU Worker    │
│  (Standard)   │                           │  (NC4as T4 v3)  │
├───────────────┤                           ├─────────────────┤
│ • Backend     │                           │ • JupyterLab    │
│ • Frontend    │                           │ • Training Jobs │
│ • K8s Control │                           │ • NVIDIA T4 GPU │
└───────┬───────┘                           └────────┬────────┘
        │                                            │
        └────────────────┬───────────────────────────┘
                         │
              ┌──────────┴──────────┐
              │  Azure Blob Storage │
              │  (uploads, models)  │
              └─────────────────────┘
```

## Components

| Component | Description |
|-----------|-------------|
| **Frontend** | Streamlit UI for chat and model management |
| **Backend** | FastAPI for inference and training job submission |
| **JupyterLab** | Interactive notebooks with GPU access |
| **NGINX Ingress** | Unified access with path-based routing |

## Quick Start

### Prerequisites
- Azure subscription
- Terraform installed
- Docker installed

### Deploy Infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform apply
```

### Build and Push Images

```bash
# Login to ACR
az acr login --name <acr-name>

# Build images
docker build -t <acr>.azurecr.io/ml-backend:v1 docker/backend/
docker build -t <acr>.azurecr.io/ml-frontend:v1 docker/frontend/
docker build -t <acr>.azurecr.io/ml-jupyterlab:v1 docker/jupyterlab/

# Push images
docker push <acr>.azurecr.io/ml-backend:v1
docker push <acr>.azurecr.io/ml-frontend:v1
docker push <acr>.azurecr.io/ml-jupyterlab:v1
```

### Deploy to Kubernetes

```bash
kubectl apply -f k8s/
```

### Access Services

Via NGINX Ingress (port 31622):
- Frontend: `http://<control-plane-ip>:31622/`
- Backend API: `http://<control-plane-ip>:31622/api/`
- JupyterLab: `http://<control-plane-ip>:31622/jupyter/`

## Project Structure

```
├── terraform/          # Azure infrastructure (VMs, ACR, Storage)
├── cloud-init/         # VM initialization scripts
├── docker/             # Container images
│   ├── backend/        # FastAPI backend
│   ├── frontend/       # Streamlit frontend
│   └── jupyterlab/     # JupyterLab with GPU support
├── k8s/                # Kubernetes manifests
└── architecture-diagram/
```

## Key Challenges Solved

1. **Blob Storage Cache Delay** - Azure blobfuse has 120s cache; fixed by forcing `ls` refresh before file reads

2. **Wrong ACR URL** - Hardcoded registry URL; fixed by using environment variable

3. **Missing imagePullSecrets** - Training jobs couldn't pull images; added ACR credentials to job spec

4. **Wrong Namespace** - Jobs created in `default` instead of `ml-platform`; fixed namespace reference

5. **kubeadm Version Mismatch** - Worker/control plane version drift; ensure same K8s version

6. **Missing CNI Plugins** - Pods failed with "loopback not found"; manually installed CNI binaries

7. **NVIDIA Driver Order** - GPU not visible in containers; install driver before container toolkit

## Tech Stack

- **Cloud**: Azure (VMs, ACR, Blob Storage)
- **Orchestration**: Kubernetes (kubeadm)
- **ML**: PyTorch, Transformers, GPT-2
- **Backend**: FastAPI
- **Frontend**: Streamlit
- **GPU**: NVIDIA T4 with CUDA 12.1
