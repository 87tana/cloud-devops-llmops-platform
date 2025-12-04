FROM python:3.12-slim

WORKDIR /app

# Install uv
RUN pip install uv

COPY requirements.txt .

# uv is much faster than pip
RUN uv pip install --system --no-cache -r requirements.txt

COPY app.py .

EXPOSE 8501

CMD ["streamlit", "run", "app.py", "--server.address=0.0.0.0"]
