from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="LLM Backend")

# Allow frontend (Streamlit) to call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # in local dev this is ok
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/chat")
def chat(q: str):
    """
    Simple placeholder endpoint.
    For now it just echoes the question.
    Later you can plug in GPT-2 inference here.
    """
    if not q.strip():
        raise HTTPException(status_code=400, detail="Empty question")
    answer = f"You asked: {q}"
    return {"answer": answer}
