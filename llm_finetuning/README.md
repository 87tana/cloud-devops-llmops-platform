# GPT-2 Shakespeare Fine-Tuning (LLMOps Component)

This folder contains a classic GPT-2 (124M) fine-tuning pipeline using
Hugging Face Transformers + Trainer.

## Structure

- `training/train_shakespeare.py` – fine-tune GPT-2 on Tiny Shakespeare
- `inference/test_model.py` – quick local test of the fine-tuned model
- `notebooks/` – optional Colab notebooks

## Usage

### 1. Train

```bash
python llm_finetuning/training/train_shakespeare.py
