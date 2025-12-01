from transformers import (
    GPT2LMHeadModel,
    GPT2Tokenizer,
    Trainer,
    TrainingArguments,
    DataCollatorForLanguageModeling,
)
from datasets import load_dataset
import torch
import os


def main(output_path: str = "./outputs/gpt2-shakespeare-final"):
    # 1) Load model + tokenizer
    model_name = "gpt2"
    tokenizer = GPT2Tokenizer.from_pretrained(model_name)
    model = GPT2LMHeadModel.from_pretrained(model_name)

    tokenizer.pad_token = tokenizer.eos_token
    model.config.pad_token_id = tokenizer.pad_token_id

    # 2) Load Tiny Shakespeare
    try:
        dataset = load_dataset("karpathy/tiny_shakespeare")
    except Exception:
        dataset = load_dataset(
            "text",
            data_files={"train": "tiny_shakespeare.txt"},
        )

    # 3) Tokenization
    def tokenize_fn(examples):
        return tokenizer(
            examples["text"],
            truncation=True,
            max_length=256,
            padding="max_length",
        )

    tokenized = dataset.map(
        tokenize_fn,
        batched=True,
        remove_columns=["text"],
    )

    # 4) Collator
    data_collator = DataCollatorForLanguageModeling(
        tokenizer=tokenizer,
        mlm=False,
    )

    # 5) Training args
    training_args = TrainingArguments(
        output_dir="./outputs/gpt2-shakespeare",
        overwrite_output_dir=True,
        num_train_epochs=3,
        per_device_train_batch_size=8,
        logging_steps=100,
        save_steps=500,
        fp16=torch.cuda.is_available(),
        report_to="none",
    )

    # 6) Trainer
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=tokenized["train"],
        data_collator=data_collator,
    )

    trainer.train()

    # 7) Save model
    os.makedirs(output_path, exist_ok=True)
    trainer.save_model(output_path)
    tokenizer.save_pretrained(output_path)


if __name__ == "__main__":
    main()
