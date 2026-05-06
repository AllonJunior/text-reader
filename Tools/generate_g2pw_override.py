#!/usr/bin/env python3
"""Generate a TextReader external pinyin override JSON from Chinese text using g2pW.

Usage:
    python3 Tools/generate_g2pw_override.py \
        --input TextReader/modules/zh-cn/xiao_ya/sample/sample.txt \
        --output /tmp/sample_g2pw_override.json
"""

from __future__ import annotations

import argparse
import json
import importlib.util
import sys
import unicodedata
from pathlib import Path
from typing import Iterable, List, Optional


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate TextReader pinyin override JSON with g2pW")
    parser.add_argument("--input", required=True, help="Path to the UTF-8 text file")
    parser.add_argument("--output", required=True, help="Path to write the override JSON")
    parser.add_argument(
        "--enable-non-traditional-chinese",
        action="store_true",
        help="Pass g2pW's enable_non_tradional_chinese=True for simplified/non-traditional text",
    )
    parser.add_argument(
        "--source-label",
        default="g2pW",
        help="Optional source label written into the JSON metadata",
    )
    return parser.parse_args()


def is_punctuation(ch: str) -> bool:
    category = unicodedata.category(ch)
    return category.startswith("P") or ch in {"…", "—", "·"}


def build_tokens(text: str, predicted: Iterable[Optional[str]]) -> List[str]:
    predictions = list(predicted)
    if len(text) != len(predictions):
        raise ValueError(f"Prediction length mismatch: text={len(text)} predictions={len(predictions)}")

    tokens: List[str] = []
    for ch, pinyin in zip(text, predictions):
        if pinyin:
            tokens.append(pinyin)
        elif ch.isspace() or is_punctuation(ch):
            tokens.append(ch)
        else:
            # Keep unsupported raw characters so the app still preserves alignment as much as possible.
            tokens.append(ch)
    return tokens


def normalize_source_text(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n").lstrip("\ufeff")


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.is_file():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        return 1

    text = normalize_source_text(input_path.read_text(encoding="utf-8-sig")).strip()
    if not text:
        print("Input text is empty after trimming.", file=sys.stderr)
        return 1

    try:
        from g2pw import G2PWConverter
    except Exception as error:  # pragma: no cover - runtime environment dependent
        g2pw_spec = importlib.util.find_spec("g2pw")
        torch_spec = importlib.util.find_spec("torch")
        detail_lines = [
            f"Python executable: {sys.executable}",
            f"g2pw visible to this interpreter: {'yes' if g2pw_spec else 'no'}",
            f"torch visible to this interpreter: {'yes' if torch_spec else 'no'}",
        ]
        print(
            "Failed to import g2pW runtime. This is usually caused by either:\n"
            "  1) installing g2pW into a different python interpreter, or\n"
            "  2) missing g2pW runtime dependencies such as torch.\n\n"
            "Try installing into the exact interpreter that runs this script, for example:\n"
            f"  {sys.executable} -m pip install g2pw torch\n\n"
            + "\n".join(detail_lines)
            + f"\n\nImport error: {error}",
            file=sys.stderr,
        )
        return 2

    converter = G2PWConverter(
        style="pinyin",
        enable_non_tradional_chinese=args.enable_non_traditional_chinese,
    )
    predicted = converter(text)
    if isinstance(predicted, list) and predicted and isinstance(predicted[0], list):
        predicted = predicted[0]

    tokens = build_tokens(text, predicted)
    payload = {
        "text": text,
        "tokens": tokens,
        "source": args.source_label,
        "notes": f"Generated from {input_path.name}",
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
