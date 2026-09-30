#!/usr/bin/env python3
"""
LoRA finetune of openai/whisper-medium on the user's personal voice corpus
(~/.local/share/qs_voice_corpus/manifest.jsonl), categories "commands" and
"reading" only (25 clips total). Produces a merged HF checkpoint, then
converts it to CTranslate2 format so it's a drop-in replacement for
faster-whisper via QS_STT_MODEL=<output_dir>/ct2.

Run inside voice/venv_whisper_ft (see setup notes in job report).
"""
import json, os, sys

import torch
from datasets import Dataset, Audio
from transformers import (
    WhisperProcessor, WhisperForConditionalGeneration,
    Seq2SeqTrainer, Seq2SeqTrainingArguments,
)
from peft import LoraConfig, get_peft_model

MANIFEST = os.path.expanduser("~/.local/share/qs_voice_corpus/manifest.jsonl")
BASE_MODEL = "openai/whisper-medium"
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models", "whisper-medium-personal")
HF_OUT = os.path.join(OUT_DIR, "hf-merged")
CT2_OUT = os.path.join(OUT_DIR, "ct2")


def load_manifest():
    rows = []
    with open(MANIFEST) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            if d["category"] in ("commands", "reading"):
                rows.append({"audio": d["wav"], "text": d["text"]})
    return rows


def main():
    rows = load_manifest()
    print(f"loaded {len(rows)} labeled clips (commands+reading)")
    if len(rows) < 5:
        print("too few clips, aborting")
        sys.exit(1)

    # small held-out split for eyeball comparison
    n_val = max(2, len(rows) // 6)
    val_rows = rows[:n_val]
    train_rows = rows[n_val:]
    print(f"train={len(train_rows)} val={len(val_rows)}")

    processor = WhisperProcessor.from_pretrained(BASE_MODEL, language=None, task="transcribe")
    model = WhisperForConditionalGeneration.from_pretrained(BASE_MODEL)
    model.generation_config.language = None
    model.generation_config.task = "transcribe"
    model.generation_config.forced_decoder_ids = None

    lora_config = LoraConfig(
        r=8, lora_alpha=16, target_modules=["q_proj", "v_proj"],
        lora_dropout=0.05, bias="none",
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    def make_ds(rows_):
        ds = Dataset.from_list(rows_)
        ds = ds.cast_column("audio", Audio(sampling_rate=16000))
        return ds

    train_ds = make_ds(train_rows)
    val_ds = make_ds(val_rows)

    def prepare(batch):
        audio = batch["audio"]
        batch["input_features"] = processor.feature_extractor(
            audio["array"], sampling_rate=16000
        ).input_features[0]
        batch["labels"] = processor.tokenizer(batch["text"]).input_ids
        return batch

    train_ds = train_ds.map(prepare, remove_columns=train_ds.column_names)
    val_ds = val_ds.map(prepare, remove_columns=val_ds.column_names)

    from dataclasses import dataclass
    from typing import Any, Dict, List, Union

    @dataclass
    class DataCollatorSpeechSeq2SeqWithPadding:
        processor: Any

        def __call__(self, features: List[Dict[str, Union[List[int], torch.Tensor]]]) -> Dict[str, torch.Tensor]:
            input_features = [{"input_features": f["input_features"]} for f in features]
            batch = self.processor.feature_extractor.pad(input_features, return_tensors="pt")
            label_features = [{"input_ids": f["labels"]} for f in features]
            labels_batch = self.processor.tokenizer.pad(label_features, return_tensors="pt")
            labels = labels_batch["input_ids"].masked_fill(labels_batch.attention_mask.ne(1), -100)
            if (labels[:, 0] == self.processor.tokenizer.bos_token_id).all().cpu().item():
                labels = labels[:, 1:]
            batch["labels"] = labels
            return batch

    collator = DataCollatorSpeechSeq2SeqWithPadding(processor=processor)

    training_args = Seq2SeqTrainingArguments(
        output_dir=os.path.join(OUT_DIR, "checkpoints"),
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,
        learning_rate=1e-3,
        num_train_epochs=8,
        eval_strategy="epoch",
        save_strategy="no",
        fp16=torch.cuda.is_available(),
        report_to=[],
        remove_unused_columns=False,
        label_names=["labels"],
        logging_steps=2,
        predict_with_generate=False,
    )

    trainer = Seq2SeqTrainer(
        args=training_args,
        model=model,
        train_dataset=train_ds,
        eval_dataset=val_ds,
        data_collator=collator,
        tokenizer=processor.feature_extractor,
    )
    trainer.train()

    print("training done, merging LoRA weights and saving HF checkpoint")
    merged = model.merge_and_unload()
    os.makedirs(HF_OUT, exist_ok=True)
    merged.save_pretrained(HF_OUT)
    processor.save_pretrained(HF_OUT)

    print("converting to CTranslate2 format")
    os.system(f"ct2-transformers-converter --model {HF_OUT} --output_dir {CT2_OUT} --copy_files tokenizer.json preprocessor_config.json --quantization int8_float16 --force")

    print(f"done. CTranslate2 model at {CT2_OUT}")
    print(f"try it via: QS_STT_MODEL={CT2_OUT} ./stt.sh")


if __name__ == "__main__":
    main()
