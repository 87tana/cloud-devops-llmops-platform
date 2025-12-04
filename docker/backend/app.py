"""
ML Platform Backend - FastAPI with Real Training Jobs
"""

import os
import shutil
import subprocess
import json
from datetime import datetime
from pathlib import Path
import httpx
from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from transformers import pipeline
import torch

app = FastAPI(title="ML Platform API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

MODELS_DIR = Path(os.getenv("MODELS_DIR", "/mnt/models"))
UPLOAD_DIR = Path(os.getenv("UPLOAD_DIR", "/mnt/uploads"))
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

_model_cache = {}

BASE_MODELS = {
    "gpt2": {"name": "GPT-2", "type": "base", "status": "ready"},
}

class ChatRequest(BaseModel):
    message: str
    model_id: str = "gpt2"
    max_tokens: int = 50

class ChatResponse(BaseModel):
    response: str
    model: str
    gpu_used: bool

def load_model(model_id: str):
    if model_id in _model_cache:
        return _model_cache[model_id]
    
    models = get_all_models()
    if model_id not in models:
        return None
    
    model_info = models[model_id]
    model_path = model_info.get("path", model_id)
    
    try:
        print(f"Loading model: {model_id} from {model_path}")
        generator = pipeline(
            "text-generation",
            model=model_path,
            tokenizer=model_path,
            device=-1,
            torch_dtype=torch.float32
        )
        _model_cache[model_id] = generator
        print(f"Model {model_id} loaded successfully")
        return generator
    except Exception as e:
        print(f"Error loading model {model_id}: {e}")
        return None

def check_gpu_worker() -> dict:
    try:
        result = subprocess.run(
            ["kubectl", "get", "nodes", "-l", "nvidia.com/gpu.present=true", "-o", "name"],
            capture_output=True, text=True, timeout=5
        )
        has_gpu = bool(result.stdout.strip())
        return {"available": has_gpu, "method": "k8s"}
    except:
        return {"available": False, "method": "none"}

def scan_models_dir() -> dict:
    finetuned = {}
    if MODELS_DIR.exists():
        # Force blobfuse cache refresh
        subprocess.run(["ls", "-la", str(MODELS_DIR)], capture_output=True)
        
        for model_path in MODELS_DIR.iterdir():
            if model_path.is_dir():
                # Force refresh subdirectory too
                subprocess.run(["ls", "-la", str(model_path)], capture_output=True)
                has_config = (model_path / "config.json").exists()
                has_model = (model_path / "pytorch_model.bin").exists() or (model_path / "model.safetensors").exists()
                if has_config or has_model:
                    model_id = model_path.name
                    finetuned[model_id] = {
                        "name": model_id,
                        "type": "finetuned",
                        "status": "ready",
                        "path": str(model_path)
                    }
    return finetuned

def get_all_models() -> dict:
    models = BASE_MODELS.copy()
    models.update(scan_models_dir())
    return models

def create_training_job(job_id: str, config: dict) -> dict:
    """Create K8s Job for training on GPU."""
    job_manifest = {
        "apiVersion": "batch/v1",
        "kind": "Job",
        "metadata": {
            "name": job_id,
            "namespace": "default"
        },
        "spec": {
            "ttlSecondsAfterFinished": 3600,
            "template": {
                "spec": {
                    "restartPolicy": "Never",
                    "containers": [{
                        "name": "trainer",
                        "image": "mlplatformacr2024.azurecr.io/ml-jupyterlab:v1",
                        "command": ["python3", "-c", f"""
import os
from transformers import AutoTokenizer, AutoModelForCausalLM, TrainingArguments, Trainer, TextDataset, DataCollatorForLanguageModeling

# Config
model_name = "{config['base_model']}"
output_dir = "/mnt/models/{config['model_name']}"
dataset_path = "/mnt/uploads/{config['dataset']}"
epochs = {config['epochs']}
batch_size = {config['batch_size']}
lr = {config['learning_rate']}

print(f"Loading base model: {{model_name}}")
tokenizer = AutoTokenizer.from_pretrained(model_name)
tokenizer.pad_token = tokenizer.eos_token
model = AutoModelForCausalLM.from_pretrained(model_name)

print(f"Loading dataset: {{dataset_path}}")
dataset = TextDataset(tokenizer=tokenizer, file_path=dataset_path, block_size=128)
data_collator = DataCollatorForLanguageModeling(tokenizer=tokenizer, mlm=False)

training_args = TrainingArguments(
    output_dir=output_dir,
    overwrite_output_dir=True,
    num_train_epochs=epochs,
    per_device_train_batch_size=batch_size,
    learning_rate=lr,
    save_steps=500,
    save_total_limit=2,
    logging_steps=100,
    fp16=True,
)

trainer = Trainer(
    model=model,
    args=training_args,
    data_collator=data_collator,
    train_dataset=dataset,
)

print("Starting training...")
trainer.train()

print(f"Saving model to {{output_dir}}")
trainer.save_model(output_dir)
tokenizer.save_pretrained(output_dir)
print("Training complete!")
"""],
                        "resources": {
                            "limits": {
                                "nvidia.com/gpu": "1"
                            }
                        },
                        "volumeMounts": [
                            {"name": "models", "mountPath": "/mnt/models"},
                            {"name": "uploads", "mountPath": "/mnt/uploads"}
                        ]
                    }],
                    "volumes": [
                        {"name": "models", "persistentVolumeClaim": {"claimName": "blob-models-pvc"}},
                        {"name": "uploads", "persistentVolumeClaim": {"claimName": "blob-uploads-pvc"}}
                    ],
                    "nodeSelector": {
                        "nvidia.com/gpu.present": "true"
                    }
                }
            }
        }
    }
    
    manifest_path = f"/tmp/{job_id}.yaml"
    with open(manifest_path, "w") as f:
        import yaml
        yaml.dump(job_manifest, f)
    
    result = subprocess.run(
        ["kubectl", "apply", "-f", manifest_path],
        capture_output=True, text=True
    )
    
    return {
        "kubectl_output": result.stdout,
        "kubectl_error": result.stderr,
        "success": result.returncode == 0
    }

@app.get("/")
def root():
    return {"service": "ml-backend", "docs": "/docs"}

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "models_dir": str(MODELS_DIR),
        "models_dir_exists": MODELS_DIR.exists(),
        "cached_models": list(_model_cache.keys())
    }

@app.get("/gpu/status")
def gpu_status():
    return check_gpu_worker()

@app.get("/models")
def list_models():
    models = []
    for model_id, info in get_all_models().items():
        models.append({
            "id": model_id,
            "name": info["name"],
            "type": info["type"],
            "status": info["status"],
            "path": info.get("path", "huggingface"),
            "loaded": model_id in _model_cache
        })
    return {"models": models, "models_dir": str(MODELS_DIR)}

@app.post("/models/refresh")
def refresh_models():
    """Force refresh model list by clearing cache."""
    global _model_cache
    _model_cache = {}
    subprocess.run(["ls", "-laR", str(MODELS_DIR)], capture_output=True)
    models = get_all_models()
    return {"status": "refreshed", "models": list(models.keys())}

@app.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest):
    models = get_all_models()
    if request.model_id not in models:
        return ChatResponse(
            response=f"[Error] Model '{request.model_id}' not found",
            model=request.model_id,
            gpu_used=False
        )
    
    generator = load_model(request.model_id)
    if not generator:
        return ChatResponse(
            response=f"[Error] Failed to load model '{request.model_id}'",
            model=request.model_id,
            gpu_used=False
        )
    
    try:
        outputs = generator(
            request.message,
            max_new_tokens=request.max_tokens,
            num_return_sequences=1,
            do_sample=True,
            temperature=0.7,
            pad_token_id=generator.tokenizer.eos_token_id
        )
        generated_text = outputs[0]["generated_text"]
        response_text = generated_text[len(request.message):].strip()
        if not response_text:
            response_text = generated_text
        
        return ChatResponse(
            response=response_text,
            model=request.model_id,
            gpu_used=False
        )
    except Exception as e:
        return ChatResponse(
            response=f"[Error] {str(e)}",
            model=request.model_id,
            gpu_used=False
        )

@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"{timestamp}_{file.filename}"
    file_path = UPLOAD_DIR / filename
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"filename": filename, "size_bytes": file_path.stat().st_size}

@app.get("/uploads")
def list_uploads():
    # Force refresh blob cache
    subprocess.run(["ls", "-la", str(UPLOAD_DIR)], capture_output=True)
    files = [{"filename": f.name, "size_bytes": f.stat().st_size} 
             for f in UPLOAD_DIR.iterdir() if f.is_file()]
    return {"files": files}

@app.get("/jobs")
def list_jobs():
    try:
        result = subprocess.run(
            ["kubectl", "get", "jobs", "-o", "json"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            jobs_data = json.loads(result.stdout)
            jobs = []
            for job in jobs_data.get("items", []):
                name = job["metadata"]["name"]
                if name.startswith("train-"):
                    status = "running"
                    if job.get("status", {}).get("succeeded", 0) > 0:
                        status = "completed"
                    elif job.get("status", {}).get("failed", 0) > 0:
                        status = "failed"
                    jobs.append({"name": name, "status": status})
            return {"jobs": jobs}
    except Exception as e:
        return {"jobs": [], "error": str(e)}
    return {"jobs": []}

@app.get("/jobs/{job_id}")
def get_job_status(job_id: str):
    try:
        result = subprocess.run(
            ["kubectl", "get", "job", job_id, "-o", "json"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            return {"error": "Job not found"}
        
        job_data = json.loads(result.stdout)
        status = "running"
        if job_data.get("status", {}).get("succeeded", 0) > 0:
            status = "completed"
        elif job_data.get("status", {}).get("failed", 0) > 0:
            status = "failed"
        
        logs_result = subprocess.run(
            ["kubectl", "logs", f"job/{job_id}", "--tail=50"],
            capture_output=True, text=True, timeout=10
        )
        
        return {
            "job_id": job_id,
            "status": status,
            "logs": logs_result.stdout if logs_result.returncode == 0 else logs_result.stderr
        }
    except Exception as e:
        return {"error": str(e)}

@app.post("/jobs/submit")
async def submit_training_job(
    model_name: str = Form(...),
    dataset_file: str = Form(...),
    base_model: str = Form("gpt2"),
    epochs: int = Form(3),
    batch_size: int = Form(4),
    learning_rate: float = Form(2e-4)
):
    gpu = check_gpu_worker()
    job_id = f"train-{model_name.lower()}-{datetime.now().strftime('%H%M%S')}"
    
    # Force refresh uploads cache
    subprocess.run(["ls", "-la", str(UPLOAD_DIR)], capture_output=True)
    
    dataset_path = UPLOAD_DIR / dataset_file
    if not dataset_path.exists():
        return {"error": "Dataset not found", "hint": "Upload file first"}
    
    config = {
        "model_name": model_name.lower(),
        "base_model": base_model,
        "dataset": dataset_file,
        "epochs": epochs,
        "batch_size": batch_size,
        "learning_rate": learning_rate
    }
    
    if gpu["available"]:
        k8s_result = create_training_job(job_id, config)
        return {
            "job_id": job_id,
            "status": "submitted" if k8s_result["success"] else "failed",
            "gpu_available": True,
            "config": config,
            "output_path": f"/mnt/models/{model_name.lower()}",
            "k8s_result": k8s_result
        }
    else:
        return {
            "job_id": job_id,
            "status": "pending",
            "gpu_available": False,
            "config": config,
            "output_path": f"/mnt/models/{model_name.lower()}",
            "message": "GPU not available - job queued"
        }