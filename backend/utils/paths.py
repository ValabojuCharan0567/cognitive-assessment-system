from __future__ import annotations

from pathlib import Path
from tempfile import NamedTemporaryFile


def get_project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def resolve_project_path(*parts: str) -> Path:
    return get_project_root().joinpath(*parts)


def get_models_dir() -> Path:
    return resolve_project_path("models")


def get_reports_dir() -> Path:
    path = resolve_project_path("model_reports")
    path.mkdir(exist_ok=True)
    return path


def get_database_path() -> Path:
    return resolve_project_path("database.db")


def create_temp_file(*, suffix: str) -> Path:
    with NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        return Path(tmp.name)

