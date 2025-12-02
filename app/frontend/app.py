import os
import requests
import streamlit as st

BACKEND_URL = os.getenv("BACKEND_URL", "http://localhost:8000")

st.set_page_config(page_title="LLM Fine-Tuning Demo", layout="centered")

st.title("LLM Fine-Tuning Demo App")
st.subheader("📄 Upload dataset (optional)")
uploaded_file = st.file_uploader("Upload a training .txt file", type=["txt"])

if uploaded_file is not None:
    st.info("⚠️ Training endpoint not wired yet – this is just a demo for now.")

st.subheader("💬 Chat with the fine-tuned model (demo)")

question = st.text_input("Your question:")

if st.button("Ask"):
    if not question.strip():
        st.warning("Please enter a question.")
    else:
        with st.spinner("Generating response..."):
            try:
                resp = requests.get(
                    f"{BACKEND_URL}/chat",
                    params={"q": question},
                    timeout=30,
                )
                resp.raise_for_status()
                data = resp.json()
                answer = data.get("answer", "(no answer)")
                st.success("Answer:")
                st.write(answer)
            except Exception as e:
                st.error(f"Backend error: {e}")
