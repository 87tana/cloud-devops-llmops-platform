from transformers import pipeline

MODEL_PATH = "./outputs/gpt2-shakespeare-final"

def main():
    generator = pipeline(
        "text-generation",
        model=MODEL_PATH,
        tokenizer=MODEL_PATH,
        device=-1,  # CPU
    )

    prompts = [
        "To be or not to be",
        "The king spoke and said",
        "In the dark forest",
    ]

    for p in prompts:
        out = generator(p, max_length=80, do_sample=True)[0]["generated_text"]
        print("\nPrompt:", p)
        print("Generated:", out)
        print("-" * 60)


if __name__ == "__main__":
    main()
