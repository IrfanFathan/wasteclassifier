#!/usr/bin/env python3
"""augment_check.py — Dataset class-distribution audit and augmentation advisor.

Usage:
    python scripts/augment_check.py --dataset <path_to_dataset> [--output augment.json]

The dataset directory is expected to follow the standard YOLO layout:

    dataset/
        images/
            train/  (or just images/ if flat)
        labels/
            train/  (*.txt files — one per image, YOLO format)

The script:
  1. Counts instances per class across all label files.
  2. Reports which classes are under-represented relative to the most-common class.
  3. Writes a Roboflow-compatible augmentation config JSON with recommended
     multipliers so that every class reaches at least the target count.

Exit codes:
    0  — all classes are balanced (within 20 % of the median count)
    1  — one or more classes are under-represented; augmentation config written
    2  — no label files found
"""

import argparse
import json
import math
import os
import sys
from collections import Counter
from pathlib import Path


# ─── Helpers ──────────────────────────────────────────────────────────────────

def find_label_files(dataset_root: Path) -> list[Path]:
    """Return all *.txt label files under <dataset_root>/labels/ recursively.
    Falls back to <dataset_root>/*.txt if the labels/ sub-tree is absent."""
    labels_dir = dataset_root / "labels"
    if labels_dir.is_dir():
        files = sorted(labels_dir.rglob("*.txt"))
    else:
        files = sorted(dataset_root.rglob("*.txt"))

    # Exclude any YAML / classes descriptor named classes.txt
    return [f for f in files if f.name != "classes.txt"]


def load_class_names(dataset_root: Path) -> dict[int, str]:
    """Try to load class names from data.yaml or classes.txt."""
    # data.yaml (YOLOv5/v8 convention)
    yaml_path = dataset_root / "data.yaml"
    if yaml_path.exists():
        try:
            import yaml  # PyYAML is optional
            with yaml_path.open() as fh:
                data = yaml.safe_load(fh)
            names = data.get("names", [])
            if isinstance(names, list):
                return {i: n for i, n in enumerate(names)}
            if isinstance(names, dict):
                return {int(k): v for k, v in names.items()}
        except Exception:
            pass

    # classes.txt (one class name per line)
    classes_txt = dataset_root / "classes.txt"
    if not classes_txt.exists():
        classes_txt = dataset_root / "labels" / "classes.txt"
    if classes_txt.exists():
        lines = classes_txt.read_text().splitlines()
        return {i: line.strip() for i, line in enumerate(lines) if line.strip()}

    return {}


def count_instances(label_files: list[Path]) -> Counter:
    """Count YOLO bounding-box instances per class index."""
    counts: Counter = Counter()
    for path in label_files:
        for line in path.read_text(errors="replace").splitlines():
            parts = line.strip().split()
            if not parts:
                continue
            try:
                cls = int(parts[0])
                counts[cls] += 1
            except ValueError:
                continue
    return counts


def build_augmentation_config(
    counts: Counter,
    class_names: dict[int, str],
    target_multiplier: float = 1.5,
    balance_threshold: float = 0.20,
) -> dict:
    """Return a Roboflow-compatible augmentation config dict.

    Each class that falls below (1 - balance_threshold) × median count gets a
    recommended augmentation multiplier so it reaches at least the target
    instance count.

    Args:
        counts:              {class_index: instance_count}
        class_names:         {class_index: class_name}
        target_multiplier:   the desired ratio of max_count / min_count after aug
        balance_threshold:   fraction below median that triggers a recommendation
    """
    if not counts:
        return {}

    median_count = sorted(counts.values())[len(counts) // 2]
    max_count = max(counts.values())
    threshold = median_count * (1 - balance_threshold)

    classes_config = []
    for cls_idx in sorted(counts.keys()):
        n = counts[cls_idx]
        name = class_names.get(cls_idx, f"class_{cls_idx}")
        recommended_aug = 1

        if n < threshold:
            # How many times do we need to augment to reach target_multiplier × median?
            target = math.ceil(median_count * target_multiplier)
            recommended_aug = max(2, math.ceil(target / max(n, 1)))

        classes_config.append({
            "class_index": cls_idx,
            "class_name": name,
            "instance_count": n,
            "recommended_augmentation_multiplier": recommended_aug,
        })

    # Global augmentation steps to apply (sensible defaults for waste imagery)
    augmentation_steps = [
        {"type": "flip",        "horizontal": True, "vertical": False},
        {"type": "rotation",    "degrees": 15},
        {"type": "brightness",  "range": [-25, 25]},
        {"type": "exposure",    "range": [-15, 15]},
        {"type": "blur",        "max_pixels": 1.5},
        {"type": "noise",       "max_percent": 2},
        {"type": "cutout",      "count": 3, "percent": 10},
    ]

    return {
        "version": "1.0",
        "target_balance_threshold": balance_threshold,
        "median_instance_count": median_count,
        "max_instance_count": max_count,
        "classes": classes_config,
        "augmentation_steps": augmentation_steps,
    }


def print_report(counts: Counter, class_names: dict[int, str]) -> None:
    """Pretty-print the class distribution to stdout."""
    if not counts:
        print("No instances found.")
        return

    total = sum(counts.values())
    max_count = max(counts.values())
    bar_width = 40

    print(f"\n{'Class':<30} {'Count':>7}  {'%':>6}  Distribution")
    print("─" * 78)
    for cls_idx in sorted(counts.keys()):
        n = counts[cls_idx]
        name = class_names.get(cls_idx, f"class_{cls_idx}")
        pct = 100 * n / total if total else 0
        bar = "█" * int(bar_width * n / max_count)
        print(f"{name:<30} {n:>7}  {pct:>5.1f}%  {bar}")
    print("─" * 78)
    print(f"{'TOTAL':<30} {total:>7}\n")


# ─── Main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit YOLO dataset class distribution and produce augmentation config.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--dataset",
        required=True,
        metavar="PATH",
        help="Root directory of the YOLO dataset.",
    )
    parser.add_argument(
        "--output",
        default="augment.json",
        metavar="PATH",
        help="Output path for the Roboflow augmentation config JSON (default: augment.json).",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.20,
        metavar="FRAC",
        help="Fraction below median count that flags a class as under-represented (default: 0.20).",
    )
    args = parser.parse_args()

    dataset_root = Path(args.dataset).resolve()
    if not dataset_root.is_dir():
        print(f"ERROR: dataset path does not exist: {dataset_root}", file=sys.stderr)
        return 2

    label_files = find_label_files(dataset_root)
    if not label_files:
        print(f"ERROR: no label files found under {dataset_root}", file=sys.stderr)
        return 2

    print(f"Found {len(label_files)} label file(s) in {dataset_root}")

    class_names = load_class_names(dataset_root)
    counts = count_instances(label_files)

    if not counts:
        print("ERROR: label files contained no valid annotations.", file=sys.stderr)
        return 2

    print_report(counts, class_names)

    config = build_augmentation_config(
        counts, class_names, balance_threshold=args.threshold
    )

    output_path = Path(args.output)
    output_path.write_text(json.dumps(config, indent=2))
    print(f"Augmentation config written to: {output_path}")

    # Exit 1 if any class needs augmentation
    needs_aug = any(
        c["recommended_augmentation_multiplier"] > 1 for c in config["classes"]
    )
    if needs_aug:
        under = [
            c["class_name"]
            for c in config["classes"]
            if c["recommended_augmentation_multiplier"] > 1
        ]
        print(
            f"\nWARNING: {len(under)} class(es) are under-represented: "
            + ", ".join(under)
        )
        return 1

    print("Dataset is balanced — no augmentation required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
