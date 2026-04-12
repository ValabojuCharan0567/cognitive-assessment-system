from __future__ import annotations

import re
from pathlib import Path

import librosa
import numpy as np
import pandas as pd
from config import dataset_subpath


ROOT = Path(__file__).resolve().parents[1]
SPEECH_DIR = dataset_subpath("speech_data")
OUT_CSV = SPEECH_DIR / "audio_labels.csv"
MANIFEST_CSV = SPEECH_DIR / "audio_label_manifest.csv"

AUDIO_EXTENSIONS = {".wav", ".mp3", ".flac", ".m4a", ".ogg"}

DISFLUENCY_PATTERNS = [
    r"<disfluency>",
    r"\[um\]",
    r"\[uh\]",
    r"<unclear>",
    r"\[noise\]",
]

EMOTION_TO_COGNITIVE = {
    "neutral": "Low",
    "calm": "Low",
    "happy": "Medium",
    "surprise": "Medium",
    "sad": "Medium",
    "fear": "High",
    "angry": "High",
    "anger": "High",
    "disgust": "High",
}


def _find_sps_tsv() -> Path | None:
    matches = sorted(SPEECH_DIR.glob("sps-corpus-*/ss-corpus-en.tsv"))
    return matches[0] if matches else None


def _count_disfluencies(text: str) -> int:
    sample = (text or "").lower()
    return int(sum(len(re.findall(pattern, sample)) for pattern in DISFLUENCY_PATTERNS))


def _build_sps_labels() -> tuple[pd.DataFrame, pd.DataFrame]:
    tsv_path = _find_sps_tsv()
    if tsv_path is None:
        return pd.DataFrame(columns=["path", "label"]), pd.DataFrame()

    sps_root = tsv_path.parent
    df = pd.read_csv(tsv_path, sep="\t")

    df = df[df["audio_file"].notna()].copy()
    df["transcription"] = df["transcription"].fillna("")
    df["duration_ms"] = pd.to_numeric(df["duration_ms"], errors="coerce").fillna(0.0)
    df["char_per_sec"] = pd.to_numeric(df["char_per_sec"], errors="coerce").fillna(0.0)
    df["votes"] = pd.to_numeric(df.get("votes", 0), errors="coerce").fillna(0.0)
    df["disfluency_count"] = df["transcription"].map(_count_disfluencies)

    df["path"] = df["audio_file"].map(
        lambda name: f"{sps_root.name}/audios/{str(name).strip()}"
    )
    df["abs_path"] = df["path"].map(lambda rel: SPEECH_DIR / rel)
    df = df[df["abs_path"].map(lambda path: path.exists())].copy()

    duration_sec = df["duration_ms"] / 1000.0
    speaking_rate = df["char_per_sec"]
    disfluency_penalty = df["disfluency_count"] * 1.25
    short_clip_penalty = np.clip(5.0 - duration_sec, 0.0, None) * 0.35
    low_vote_penalty = np.clip(1.0 - df["votes"], 0.0, None) * 0.25

    df["fluency_proxy"] = (
        speaking_rate
        - disfluency_penalty
        - short_clip_penalty
        - low_vote_penalty
    )

    ranked_proxy = df["fluency_proxy"].rank(method="first")
    df["label"] = pd.qcut(
        ranked_proxy,
        q=3,
        labels=["Low", "Medium", "High"],
    ).astype(str)
    df["source"] = "sps_corpus"

    labels = df[["path", "label"]].drop_duplicates(subset=["path"]).copy()
    manifest = df[
        [
            "path",
            "label",
            "source",
            "fluency_proxy",
            "char_per_sec",
            "disfluency_count",
            "duration_ms",
            "votes",
            "transcription",
        ]
    ].copy()
    return labels, manifest


def _build_emotion_folder_labels() -> tuple[pd.DataFrame, pd.DataFrame]:
    rows: list[dict] = []
    manifest_rows: list[dict] = []

    for language_dir in sorted(p for p in SPEECH_DIR.iterdir() if p.is_dir()):
        for emotion_dir in sorted(p for p in language_dir.iterdir() if p.is_dir()):
            emotion = emotion_dir.name.strip().lower()
            mapped_label = EMOTION_TO_COGNITIVE.get(emotion)
            if mapped_label is None:
                continue

            for audio_path in sorted(emotion_dir.rglob("*")):
                if not audio_path.is_file() or audio_path.suffix.lower() not in AUDIO_EXTENSIONS:
                    continue
                rel_path = audio_path.relative_to(SPEECH_DIR).as_posix()
                rows.append({"path": rel_path, "label": mapped_label})
                manifest_rows.append(
                    {
                        "path": rel_path,
                        "label": mapped_label,
                        "source": f"emotion_folder:{language_dir.name}",
                        "emotion": emotion,
                    }
                )

    return pd.DataFrame(rows), pd.DataFrame(manifest_rows)


def _build_flat_audio_proxy_labels() -> tuple[pd.DataFrame, pd.DataFrame]:
    """Fallback for flat unlabeled audio dumps.

    The current speech dataset folder is a mixed MP3/FLAC collection with
    no metadata CSV. Build pseudo fluency labels from lightweight acoustic
    proxies so training can still proceed end-to-end.
    """
    rows: list[dict] = []

    audio_files = [
        path for path in sorted(SPEECH_DIR.rglob("*"))
        if path.is_file() and path.suffix.lower() in AUDIO_EXTENSIONS
    ]
    if not audio_files:
        return pd.DataFrame(columns=["path", "label"]), pd.DataFrame()

    for audio_path in audio_files:
        try:
            # Keep this lightweight: short mono load is enough for ranking.
            y, sr = librosa.load(audio_path.as_posix(), sr=16000, mono=True, duration=8.0)
            if y.size < 1024:
                continue

            duration_sec = float(librosa.get_duration(y=y, sr=sr))
            rms = librosa.feature.rms(y=y).flatten()
            zcr = librosa.feature.zero_crossing_rate(y).flatten()
            onset = librosa.onset.onset_strength(y=y, sr=sr)

            rows.append(
                {
                    "path": audio_path.relative_to(SPEECH_DIR).as_posix(),
                    "duration_sec": duration_sec,
                    "rms_mean": float(np.mean(rms)),
                    "rms_std": float(np.std(rms)),
                    "zcr_mean": float(np.mean(zcr)),
                    "onset_std": float(np.std(onset)),
                    "source": "flat_audio_proxy",
                }
            )
        except Exception:
            continue

    if len(rows) < 30:
        return pd.DataFrame(columns=["path", "label"]), pd.DataFrame()

    df = pd.DataFrame(rows)

    # Rank-based normalization is robust across mixed corpora.
    df["duration_rank"] = np.clip(df["duration_sec"], 0.5, 8.0).rank(pct=True)
    df["energy_rank"] = df["rms_mean"].rank(pct=True)
    df["stability_rank"] = 1.0 - df["rms_std"].rank(pct=True)
    df["clarity_rank"] = 1.0 - df["zcr_mean"].rank(pct=True)
    df["rhythm_rank"] = 1.0 - df["onset_std"].rank(pct=True)

    df["fluency_proxy"] = (
        (0.28 * df["duration_rank"])
        + (0.24 * df["energy_rank"])
        + (0.20 * df["stability_rank"])
        + (0.14 * df["clarity_rank"])
        + (0.14 * df["rhythm_rank"])
    )

    ranked_proxy = df["fluency_proxy"].rank(method="first")
    df["label"] = pd.qcut(ranked_proxy, q=3, labels=["Low", "Medium", "High"]).astype(str)

    labels = df[["path", "label"]].drop_duplicates(subset=["path"]).copy()
    manifest = df[
        [
            "path",
            "label",
            "source",
            "fluency_proxy",
            "duration_sec",
            "rms_mean",
            "rms_std",
            "zcr_mean",
            "onset_std",
        ]
    ].copy()
    return labels, manifest


def build_audio_labels() -> pd.DataFrame:
    label_parts: list[pd.DataFrame] = []
    manifest_parts: list[pd.DataFrame] = []

    sps_labels, sps_manifest = _build_sps_labels()
    if not sps_labels.empty:
        label_parts.append(sps_labels)
        manifest_parts.append(sps_manifest)

    emotion_labels, emotion_manifest = _build_emotion_folder_labels()
    if not emotion_labels.empty:
        label_parts.append(emotion_labels)
        manifest_parts.append(emotion_manifest)

    if not label_parts:
        proxy_labels, proxy_manifest = _build_flat_audio_proxy_labels()
        if not proxy_labels.empty:
            label_parts.append(proxy_labels)
            manifest_parts.append(proxy_manifest)

    if not label_parts:
        raise FileNotFoundError(
            f"No usable audio label sources found under {SPEECH_DIR}. "
            "Expected either sps-corpus metadata, emotion-named folders, or enough audio files for flat-folder proxy labeling."
        )

    labels = pd.concat(label_parts, ignore_index=True)
    labels = labels.drop_duplicates(subset=["path"]).copy()
    labels.to_csv(OUT_CSV, index=False)

    manifest = pd.concat(manifest_parts, ignore_index=True, sort=False) if manifest_parts else labels.copy()
    manifest = manifest.drop_duplicates(subset=["path"]).copy()
    manifest.to_csv(MANIFEST_CSV, index=False)

    print(f"Prepared {len(labels)} labeled audio rows")
    print(f"Saved labels CSV: {OUT_CSV}")
    print(f"Saved manifest CSV: {MANIFEST_CSV}")
    print("Label distribution:", labels["label"].value_counts().to_dict())
    return labels


if __name__ == "__main__":
    build_audio_labels()
