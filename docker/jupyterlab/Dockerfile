FROM pytorch/pytorch:2.4.0-cuda12.1-cudnn9-runtime
WORKDIR /workspace

# Install uv for fast package management
RUN pip install uv

COPY requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt
RUN mkdir -p /workspace/notebooks /workspace/models
EXPOSE 8888
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--NotebookApp.token=''"]
