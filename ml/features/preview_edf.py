from __future__ import annotations

import argparse
from pathlib import Path

import mne
import matplotlib.pyplot as plt

from eeg_features import extract_features_from_edf


def _make_demo_edf() -> Path:
    """Generate a small synthetic EDF file (random noise) and return its path."""
    import tempfile
    from mne import create_info
    from mne.io import RawArray
    import numpy as np

    sfreq = 100.0
    n_channels = 2
    duration = 10.0  # seconds
    data = np.random.randn(n_channels, int(sfreq * duration)) * 1e-5
    ch_names = ["EEG 001", "EEG 002"]
    info = create_info(ch_names=ch_names, sfreq=sfreq, ch_types=["eeg"] * n_channels)
    raw = RawArray(data, info)

    tmp = tempfile.NamedTemporaryFile(suffix=".edf", delete=False)
    # mne.export may complain if file already exists; overwrite if needed
    raw.export(tmp.name, fmt="edf", physical_range="auto", overwrite=True, verbose=False)
    return Path(tmp.name)


def main():
    parser = argparse.ArgumentParser(
        description="Preview an EDF file: prints extracted features and shows raw signal plot."
    )
    parser.add_argument(
        "file",
        type=str,
        nargs="?",
        help="Path to the .edf file to preview (use --demo for synthetic sample)",
    )
    parser.add_argument(
        "--demo",
        action="store_true",
        help="Generate and preview a small synthetic EDF recording",
    )

    args = parser.parse_args()

    if args.demo:
        edf_path = _make_demo_edf()
        print(f"Demo EDF generated at {edf_path}")
    elif args.file:
        edf_path = Path(args.file)
        if not edf_path.exists():
            print(f"Error: file not found: {edf_path}")
            return
    else:
        parser.print_help()
        return

    print("Extracting summary features...")
    feats = extract_features_from_edf(edf_path)
    for k, v in feats.items():
        print(f"{k}: {v}")

    print("Opening interactive plot (matplotlib/mne). Close window to exit.")
    raw = mne.io.read_raw_edf(str(edf_path), preload=True, verbose=False)
    raw.plot(scalings="auto", show=True)


if __name__ == "__main__":
    main()
