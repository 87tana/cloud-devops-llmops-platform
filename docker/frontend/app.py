"""
ML Platform Frontend - Streamlit Dashboard
"""
import os
import streamlit as st
import requests

BACKEND_URL = os.getenv("BACKEND_URL", "http://ml-backend:8000")

st.set_page_config(page_title="ML Platform", page_icon="🧠", layout="wide")
st.title("🧠 ML Platform")

# ============ SIDEBAR ============
with st.sidebar:
    st.header("ℹ️ Info")
    try:
        r = requests.get(f"{BACKEND_URL}/health", timeout=3)
        st.success("✅ Backend Connected")
    except:
        st.error("❌ Backend Disconnected")
    
    st.markdown("---")
    st.markdown("[API Docs](http://localhost:8000/docs)")
    st.caption(f"Backend: {BACKEND_URL}")

# ============ TABS ============
tab_user, tab_developer = st.tabs(["💬 User - Chat", "🔧 Developer - Finetune"])

# ============ USER TAB ============
with tab_user:
    st.header("Chat with AI Models")
    
    # Model Selection
    col1, col2 = st.columns([2, 1])
    
    with col1:
        model_options = {"GPT-2": "gpt2"}  # Default fallback
        try:
            r = requests.get(f"{BACKEND_URL}/models", timeout=5)
            if r.status_code == 200:
                models = r.json().get("models", [])
                if models:
                    model_options = {m["name"]: m["id"] for m in models if m["status"] == "ready"}
                    if not model_options:
                        model_options = {"GPT-2": "gpt2"}
        except Exception as e:
            st.warning(f"⚠️ Could not fetch models")
        
        model_names = list(model_options.keys())
        selected_model_name = st.selectbox("Select Model", model_names, index=0)
        selected_model_id = model_options.get(selected_model_name, "gpt2")
    
    with col2:
        st.metric("Active Model", selected_model_id)
        if st.button("🔄 Refresh Models"):
            st.rerun()
    
    st.divider()
    
    # Chat Interface
    if "messages" not in st.session_state:
        st.session_state.messages = []
    
    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.write(msg["content"])
    
    if prompt := st.chat_input("Type a message..."):
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.write(prompt)
        
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                try:
                    r = requests.post(
                        f"{BACKEND_URL}/chat",
                        json={"message": prompt, "model_id": selected_model_id, "max_tokens": 50},
                        timeout=60
                    )
                    data = r.json()
                    response = data.get("response", "No response")
                except Exception as e:
                    response = f"[Error] {str(e)}"
            
            st.write(response)
            st.session_state.messages.append({"role": "assistant", "content": response})
    
    if st.button("🗑️ Clear Chat"):
        st.session_state.messages = []
        st.rerun()

# ============ DEVELOPER TAB ============
with tab_developer:
    st.header("Finetune & Train Models")
    
    # System Status
    st.subheader("📊 System Status")
    col1, col2, col3 = st.columns(3)
    
    with col1:
        try:
            r = requests.get(f"{BACKEND_URL}/health", timeout=3)
            st.success("✅ Backend Online")
        except:
            st.error("❌ Backend Offline")
    
    with col2:
        try:
            r = requests.get(f"{BACKEND_URL}/gpu/status", timeout=3)
            if r.json().get("available"):
                st.success("✅ GPU Available")
            else:
                st.warning("⚠️ GPU Offline")
        except:
            st.error("❌ GPU Check Failed")
    
    with col3:
        try:
            r = requests.get(f"{BACKEND_URL}/models", timeout=3)
            model_count = len(r.json().get("models", []))
            st.info(f"📦 {model_count} Models")
        except:
            st.info("📦 ? Models")
    
    st.divider()
    
    # Upload Section
    st.subheader("📁 Step 1: Upload Training Data")
    uploaded_file = st.file_uploader("Upload dataset", type=["jsonl", "csv", "txt"])
    
    if uploaded_file and st.button("⬆️ Upload File"):
        files = {"file": (uploaded_file.name, uploaded_file.getvalue())}
        try:
            r = requests.post(f"{BACKEND_URL}/upload", files=files, timeout=30)
            result = r.json()
            if "filename" in result:
                st.success(f"✅ Uploaded: {result['filename']}")
                st.session_state["uploaded_file"] = result["filename"]
        except Exception as e:
            st.error(f"❌ {e}")
    
    with st.expander("📂 View Uploaded Files"):
        try:
            r = requests.get(f"{BACKEND_URL}/uploads", timeout=5)
            files = r.json().get("files", [])
            if files:
                for f in files:
                    st.text(f"• {f['filename']} ({f['size_bytes']} bytes)")
            else:
                st.caption("No files uploaded yet")
        except:
            st.caption("Could not fetch files")
    
    st.divider()
    
    # Training Configuration
    st.subheader("⚙️ Step 2: Configure Training Job")
    
    col1, col2 = st.columns(2)
    with col1:
        model_name = st.text_input("New Model Name", placeholder="my-model")
        dataset_file = st.text_input("Dataset Filename", value=st.session_state.get("uploaded_file", ""))
    
    with col2:
        base_model = st.selectbox("Base Model", ["gpt2"])
        epochs = st.slider("Epochs", 1, 20, 3)
    
    st.divider()
    
    # Submit
    st.subheader("🚀 Step 3: Submit Job")
    if st.button("🚀 Start Training", type="primary", use_container_width=True):
        if not model_name or not dataset_file:
            st.error("❌ Enter model name and dataset file")
        else:
            try:
                r = requests.post(
                    f"{BACKEND_URL}/jobs/submit",
                    data={
                        "model_name": model_name,
                        "dataset_file": dataset_file,
                        "base_model": base_model,
                        "epochs": epochs,
                        "batch_size": 4,
                        "learning_rate": 2e-4
                    },
                    timeout=30
                )
                result = r.json()
                if "error" in result:
                    st.error(f"❌ {result['error']}")
                else:
                    st.success(f"✅ Job: {result['job_id']}")
                    st.json(result)
            except Exception as e:
                st.error(f"❌ {e}")
