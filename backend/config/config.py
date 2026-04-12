from __future__ import annotations

import os
from pathlib import Path

DEFAULT_DATASET_PATH = Path.home() / "Datasets" / "CognitiveAssessment"
DATASET_PATH = Path(
    os.getenv("DATASET_PATH", str(DEFAULT_DATASET_PATH))
).expanduser()
DEMO_MODE = not DATASET_PATH.exists()


def dataset_subpath(*parts: str) -> Path:
    return DATASET_PATH.joinpath(*parts)


def get_dataset_subpath(*parts: str) -> Path:
    return dataset_subpath(*parts)


def validate_dataset(required_dirs: list[str] | tuple[str, ...] | None = None) -> Path:
    dataset_path = DATASET_PATH.expanduser()
    if not str(dataset_path).strip():
        raise RuntimeError(
            "DATASET_PATH is not set.\n"
            "Use: export DATASET_PATH=/path/to/dataset"
        )

    if not dataset_path.exists():
        raise RuntimeError(
            f"DATASET_PATH does not exist: {dataset_path}"
        )

    if required_dirs:
        missing = []
        for directory in required_dirs:
            full_path = dataset_path / directory
            if not full_path.exists():
                missing.append(str(full_path))
        if missing:
            raise RuntimeError(
                "Missing required dataset folders:\n" + "\n".join(missing)
            )

    print(f"Dataset validated at: {dataset_path}", flush=True)
    return dataset_path
