#!/usr/bin/env python3
"""Compile the 33-dimension The Factory image prompt.

Adapted from the same system used in Enterprise_Autonomous_Research
(prompts/images/, scripts/compile_image_prompt.py) — same mechanism,
same 33-file numbering convention, content rewritten for The Factory's
own photorealistic cinematic style instead of that project's graphite
Evidence Laboratory style.

Assembles the 32 fixed dimension files under prompts/images/ (02_environment.md
through 33_history.md) together with exactly one subject file
(X_N_subject.md) into a single, complete prompt, in dimension order, with the
subject placed first (it is dimension 1: Subject).

The 32 fixed files never change between illustrations. Only the subject file
changes, and the caller always supplies it explicitly or lets this script pick
the highest-numbered X_N_subject.md automatically.

Output is organised per case, so every compiled illustration is reproducible:

    compiled/
        F-001/
            prompt.md       the flat, ready-to-paste prompt
            prompt.json     the same prompt broken into its 33 sections
            metadata.json   what produced it: case, subject, dimension count,
                             subject version, per-file dimension versions,
                             content hash, aspect ratio, alt text, timestamp
            alt_text.md     accessibility description, written only if the
                             subject file has a '# Alt Text: ...' header

The case ID and subject title are parsed from the subject file's own header
line ("# Article: F-001 - The Permission You Didn't Mean to Give"); pass
--case to override. Alt text is likewise author-written in the subject file,
not derived from the prompt: the prompt describes what was requested, not
necessarily what the model rendered, so alt text has to be a deliberate
description of the actual image, not a mechanical summary.

Usage:
    compile_image_prompt.py --subject ./prompts/images/X_1_subject.md
    compile_image_prompt.py                       # auto-picks the latest X_N_subject.md
    compile_image_prompt.py --list                # show available subject files
    compile_image_prompt.py --subject ... --print  # also dump the compiled prompt to stdout
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

SUBJECT_PATTERN = re.compile(r"^X_(\d+)_subject\.md$")
# Fixed dimension files are numbered 02..33. 01 is intentionally excluded: it
# is a placeholder (01_subject.md) explaining that dimension 1, Subject,
# lives in the evolving X_N_subject.md files instead, never a fixed file.
DIMENSION_PATTERN = re.compile(r"^(0[2-9]|[12]\d|3[0-3])_.+\.md$")
ARTICLE_HEADER_PATTERN = re.compile(r"^#\s*Article:\s*([A-Za-z0-9_-]+)\s*[–—-]\s*(.+)$")
VERSION_HEADER_PATTERN = re.compile(r"^#\s*Version:\s*(.+)$")
ALT_TEXT_PATTERN = re.compile(r"^#\s*Alt Text:\s*(.+)$")
TITLE_HEADER_PATTERN = re.compile(r"^#\s*(.+)$")
ASPECT_RATIO_PATTERN = re.compile(r"\b(\d{1,2}:\d{1,2})\b")
CASE_ID_SANITIZE_PATTERN = re.compile(r"[^A-Za-z0-9_-]+")

DEFAULT_IMAGES_DIR = Path(__file__).resolve().parent.parent / "prompts" / "images"


def find_subject_files(images_dir: Path) -> list[tuple[int, Path]]:
    found = []
    for path in images_dir.glob("X_*_subject.md"):
        match = SUBJECT_PATTERN.match(path.name)
        if match:
            found.append((int(match.group(1)), path))
    return sorted(found, key=lambda item: item[0])


def latest_subject_file(images_dir: Path) -> Path | None:
    subjects = find_subject_files(images_dir)
    return subjects[-1][1] if subjects else None


def dimension_files(images_dir: Path) -> list[Path]:
    """The 32 fixed dimension files, 02..33, in numeric order. Files matching
    the subject pattern are never included here even if they somehow also
    matched the numeric pattern (they don't, by construction)."""
    files = [
        path
        for path in images_dir.glob("*.md")
        if DIMENSION_PATTERN.match(path.name) and not SUBJECT_PATTERN.match(path.name)
    ]
    return sorted(files, key=lambda path: path.name)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def file_title(path: Path, text: str) -> str:
    """The first '# ...' header line, used as a human-readable section title."""
    for line in text.splitlines()[:3]:
        match = TITLE_HEADER_PATTERN.match(line)
        if match:
            return match.group(1).strip()
    return path.stem


def file_version(text: str) -> str | None:
    for line in text.splitlines()[:5]:
        match = VERSION_HEADER_PATTERN.match(line)
        if match:
            return match.group(1).strip()
    return None


def alt_text(subject_text: str) -> str | None:
    """The subject file's own '# Alt Text: ...' header line, if present. Alt
    text is authored by hand in the subject file rather than derived from the
    compiled prompt: the prompt describes intent, not the pixels the model
    actually produced. This just extracts what the author wrote."""
    for line in subject_text.splitlines()[:10]:
        match = ALT_TEXT_PATTERN.match(line)
        if match:
            return match.group(1).strip()
    return None


def parse_case(subject_path: Path, subject_text: str) -> tuple[str, str | None]:
    """Returns (case_id, subject_title), parsed from the subject file's own
    '# Article: F-001 - Title' header line. Falls back to the subject file's
    X_N label (and no title) if that header is absent."""
    for line in subject_text.splitlines()[:6]:
        match = ARTICLE_HEADER_PATTERN.match(line)
        if match:
            return match.group(1).strip(), match.group(2).strip()
    subject_match = SUBJECT_PATTERN.match(subject_path.name)
    fallback = f"X_{subject_match.group(1)}" if subject_match else subject_path.stem
    return fallback, None


def sanitize_case_id(case_id: str) -> str:
    return CASE_ID_SANITIZE_PATTERN.sub("-", case_id).strip("-") or "unknown-case"


def extract_aspect_ratio(images_dir: Path) -> str | None:
    path = images_dir / "21_aspect_ratio.md"
    if not path.is_file():
        return None
    match = ASPECT_RATIO_PATTERN.search(read(path))
    return match.group(1) if match else None


def build_sections(subject_path: Path, fixed_files: list[Path]) -> list[dict[str, str]]:
    sections = []
    for path in [subject_path, *fixed_files]:
        text = read(path)
        sections.append(
            {
                "id": path.stem,
                "file": path.name,
                "title": file_title(path, text),
                "version": file_version(text) or "",
                "content": text,
            }
        )
    return sections


def compiled_text_from(sections: list[dict[str, str]]) -> str:
    return "\n\n\n".join(section["content"] for section in sections) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compile The Factory image prompt from its 32 dimension files.",
    )
    parser.add_argument(
        "--subject",
        type=Path,
        default=None,
        help="Path to the subject file (e.g. ./prompts/images/X_1_subject.md). "
        "Defaults to the highest-numbered X_N_subject.md found in --images-dir.",
    )
    parser.add_argument(
        "--images-dir",
        type=Path,
        default=DEFAULT_IMAGES_DIR,
        help=f"Directory containing the dimension files (default: {DEFAULT_IMAGES_DIR})",
    )
    parser.add_argument(
        "--case",
        default=None,
        help="Override the case ID used for the output folder name (default: parsed from the "
        "subject file's '# Article: <CASE> - <Title>' header).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Root 'compiled' directory (default: <images-dir>/compiled). Each case is written "
        "to its own <output-dir>/<CASE>/ subfolder.",
    )
    parser.add_argument(
        "--print",
        dest="print_prompt",
        action="store_true",
        help="Also print the compiled prompt to stdout.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available subject files in --images-dir and exit.",
    )
    args = parser.parse_args()

    images_dir = args.images_dir.resolve()
    if not images_dir.is_dir():
        print(f"error: images directory not found: {images_dir}", file=sys.stderr)
        return 1

    if args.list:
        subjects = find_subject_files(images_dir)
        if not subjects:
            print(f"No X_N_subject.md files found in {images_dir}")
            return 0
        print(f"Subject files in {images_dir}:")
        for number, path in subjects:
            print(f"  X_{number}  ->  {path.name}")
        return 0

    subject_path = args.subject
    if subject_path is None:
        subject_path = latest_subject_file(images_dir)
        if subject_path is None:
            print(
                f"error: no X_N_subject.md files found in {images_dir}. Pass --subject explicitly.",
                file=sys.stderr,
            )
            return 1
        print(
            f"No --subject given; using the latest subject file: {subject_path.name}",
            file=sys.stderr,
        )
    else:
        subject_path = subject_path.resolve()
        if not subject_path.is_file():
            print(f"error: subject file not found: {subject_path}", file=sys.stderr)
            return 1
        if not SUBJECT_PATTERN.match(subject_path.name):
            print(
                f"warning: {subject_path.name} does not match the X_N_subject.md naming convention; "
                "continuing anyway.",
                file=sys.stderr,
            )

    fixed_files = dimension_files(images_dir)
    expected = 32
    if len(fixed_files) != expected:
        print(
            f"warning: expected {expected} dimension files (02..33) in {images_dir}, found {len(fixed_files)}.",
            file=sys.stderr,
        )

    sections = build_sections(subject_path, fixed_files)
    compiled_text = compiled_text_from(sections)
    subject_text = sections[0]["content"]

    case_id, subject_title = parse_case(subject_path, subject_text)
    if args.case:
        case_id = args.case
    case_id = sanitize_case_id(case_id)

    alt_text_value = alt_text(subject_text)
    if not alt_text_value:
        print(
            f"warning: {subject_path.name} has no '# Alt Text: ...' header line; "
            "alt_text.md will not be written.",
            file=sys.stderr,
        )

    output_root = args.output_dir or (images_dir / "compiled")
    case_dir = output_root / case_id
    case_dir.mkdir(parents=True, exist_ok=True)

    prompt_md_path = case_dir / "prompt.md"
    prompt_json_path = case_dir / "prompt.json"
    metadata_path = case_dir / "metadata.json"
    alt_text_path = case_dir / "alt_text.md"

    prompt_md_path.write_text(compiled_text, encoding="utf-8")

    if alt_text_value:
        alt_text_path.write_text(alt_text_value + "\n", encoding="utf-8")
    elif alt_text_path.exists():
        # Stale alt_text.md from a previous run where the subject file did
        # have the header; don't leave mismatched alt text behind silently.
        alt_text_path.unlink()

    prompt_json_path.write_text(
        json.dumps(
            {"case": case_id, "subject_file": subject_path.name, "sections": sections},
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    content_hash = hashlib.sha256(compiled_text.encode("utf-8")).hexdigest()
    metadata = {
        "case": case_id,
        "subject": subject_title,
        "subject_file": subject_path.name,
        "compiled_dimensions": len(fixed_files),
        "version": file_version(subject_text),
        "created": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generator": "compile_image_prompt.py",
        "hash": f"sha256:{content_hash}",
        "aspect_ratio": extract_aspect_ratio(images_dir),
        "alt_text": alt_text_value,
        "dimension_versions": {
            section["file"]: section["version"] for section in sections[1:]
        },
    }
    metadata_path.write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print(
        f"Compiled {len(sections)} files ({subject_path.name} + {len(fixed_files)} dimension files) "
        f"for case {case_id}",
        file=sys.stderr,
    )
    print(f"-> {prompt_md_path}", file=sys.stderr)
    print(f"-> {prompt_json_path}", file=sys.stderr)
    print(f"-> {metadata_path}", file=sys.stderr)
    if alt_text_value:
        print(f"-> {alt_text_path}", file=sys.stderr)

    if args.print_prompt:
        print(compiled_text)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
