from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path
from typing import Dict, Iterable, Optional

import kagglehub
import pandas as pd
from config import dataset_subpath


ROOT = Path(__file__).resolve().parents[1]
SPEECH_DIR = dataset_subpath("speech_data")
AUDIO_LABELS_CSV = SPEECH_DIR / "audio_labels.csv"


# Emotion -> cognitive-load mapping used for training labels.
EMOTION_TO_COGNITIVE = {
    "neutral": "Low",
    "calm": "Low",
    "happy": "Medium",
    "surprise": "Medium",
    "sad": "Medium",
    "fear": "High",
    "angry": "High",
    "disgust": "High",
}

EMOTION_ALIASES = {
    "anger": "angry",
    "fearful": "fear",
    "surprised": "surprise",
    "happiness": "happy",
}


def _scan_wav_files(root_dir: Path) -> list[Path]:
    return sorted(p for p in root_dir.rglob("*.wav") if p.is_file())


def _infer_emotion(path: Path) -> Optional[str]:
    text = " ".join(path.parts).lower()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    tokens = text.split()

    for token in tokens:
        normalized = EMOTION_ALIASES.get(token, token)
        if normalized in EMOTION_TO_COGNITIVE:
            return normalized

    return None


def _infer_speaker_id(path: Path) -> str:
    stem = path.stem
    prefix = stem.split("_")[0]
    if prefix:
        return prefix
    return path.parent.name


def _copy_dataset_audio(
    src_files: Iterable[Path],
    src_root: Path,
    dst_root: Path,
    prefix: Optional[str],
) -> pd.DataFrame:
    rows: list[dict] = []
    dst_root.mkdir(parents=True, exist_ok=True)

    for src_file in src_files:
        rel = src_file.relative_to(src_root)
        safe_rel = Path(*[part.replace(" ", "_") for part in rel.parts])
        dst_rel = (Path(prefix) / safe_rel) if prefix else safe_rel
        dst_abs = SPEECH_DIR / dst_rel
        dst_abs.parent.mkdir(parents=True, exist_ok=True)

        if not dst_abs.exists():
            shutil.copy2(src_file, dst_abs)

        emotion = _infer_emotion(rel)
        rows.append(
            {
                "path": str(dst_rel).replace("\\", "/"),
                "emotion": emotion,
                "label": EMOTION_TO_COGNITIVE.get(emotion) if emotion else None,
                "speaker_id": _infer_speaker_id(rel),
                "source": prefix,
            }
        )

    return pd.DataFrame(rows)


def _append_to_audio_labels(df: pd.DataFrame) -> int:
    train_df = pd.read_csv(AUDIO_LABELS_CSV)
    append_df = df[df["label"].notna()][["path", "label"]].copy()

    before = len(train_df)
    combined = pd.concat([train_df, append_df], ignore_index=True)
    combined = combined.drop_duplicates(subset=["path"], keep="first")
    combined.to_csv(AUDIO_LABELS_CSV, index=False)
    return len(combined) - before


def import_besd(
    append_to_training: bool,
    min_labeled_only: bool,
) -> None:
    print("Downloading BESD from Kaggle...")
    dataset_root = Path(kagglehub.dataset_download("pranuthi19/bilingual-emotion-speech-datasetbesd"))
    print(f"Downloaded BESD to: {dataset_root}")

    wav_files = _scan_wav_files(dataset_root)
    if not wav_files:
        raise RuntimeError(f"No .wav files found in {dataset_root}")

    print(f"Found {len(wav_files)} wav files")
    besd_df = _copy_dataset_audio(
        src_files=wav_files,
        src_root=dataset_root,
        dst_root=SPEECH_DIR,
        prefix=None,
    )

    if min_labeled_only:
        besd_df = besd_df[besd_df["label"].notna()].copy()

    out_csv = SPEECH_DIR / "external_besd_labels.csv"
    besd_df.to_csv(out_csv, index=False)

    labeled = int(besd_df["label"].notna().sum())
    unlabeled = int(besd_df["label"].isna().sum())
    print(f"Saved BESD manifest: {out_csv}")
    print(f"Labeled for cognitive mapping: {labeled}")
    print(f"Unmapped emotion files: {unlabeled}")

    if append_to_training:
        appended = _append_to_audio_labels(besd_df)
        print(f"Appended {appended} BESD rows into {AUDIO_LABELS_CSV}")


def import_kids_unlabeled(kids_dir: Path) -> None:
    if not kids_dir.exists():
        raise FileNotFoundError(f"Kids dataset path not found: {kids_dir}")

    wav_files = _scan_wav_files(kids_dir)
    if not wav_files:
        raise RuntimeError(f"No .wav files found in {kids_dir}")

    print(f"Found {len(wav_files)} kids wav files")
    kids_df = _copy_dataset_audio(
        src_files=wav_files,
        src_root=kids_dir,
        dst_root=SPEECH_DIR / "external_kids_unlabeled",
        prefix="external_kids_unlabeled",
    )

    out_csv = SPEECH_DIR / "external_kids_unlabeled_manifest.csv"
    kids_df.to_csv(out_csv, index=False)
    print(f"Saved kids manifest: {out_csv}")
    print("Use pseudo-labeling on external_kids_unlabeled for automatic cognitive labels.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=f"Import external speech datasets into {SPEECH_DIR}"
    )
    parser.add_argument(
        "--import-besd",
        action="store_true",
        help="Download and import BESD (emotion dataset from Kaggle)",
    )
    parser.add_argument(
        "--kids-dir",
        type=Path,
        default=None,
        help="Optional local path for unlabeled kids dataset to import",
    )
    parser.add_argument(
        "--append-to-training",
        action="store_true",
        help="Append mapped BESD labels into audio_labels.csv",
    )
    parser.add_argument(
        "--labeled-only",
        action="store_true",
        help="Keep only rows where emotion->cognitive mapping exists",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    SPEECH_DIR.mkdir(parents=True, exist_ok=True)

    if not args.import_besd and args.kids_dir is None:
        raise RuntimeError("Nothing to do. Use --import-besd and/or --kids-dir <path>.")

    if args.import_besd:
        import_besd(
            append_to_training=args.append_to_training,
            min_labeled_only=args.labeled_only,
        )

    if args.kids_dir is not None:
        import_kids_unlabeled(args.kids_dir)


if __name__ == "__main__":
    main()
