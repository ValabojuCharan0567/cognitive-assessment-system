"""SQLite database for Child Cognitive Assessment System."""

from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Generator

from utils.paths import get_database_path


DB_PATH = get_database_path()


def get_connection() -> sqlite3.Connection:
    """Return a connection to the database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def get_db() -> Generator[sqlite3.Connection, None, None]:
    """Context manager for database connections."""
    conn = get_connection()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db() -> None:
    """Create all tables if they do not exist."""
    with get_db() as conn:
        cur = conn.cursor()

        cur.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT,
                email TEXT UNIQUE,
                password TEXT,
                email_verified INTEGER DEFAULT 0,
                verification_code TEXT,
                verification_sent_at TEXT
            )
        """)

        # Lightweight migrations for older local databases.
        cur.execute("PRAGMA table_info(users)")
        cols = {row["name"] for row in cur.fetchall()}

        if "email_verified" not in cols:
            cur.execute("ALTER TABLE users ADD COLUMN email_verified INTEGER DEFAULT 0")
            # Existing users predate verification flow; mark as verified.
            cur.execute("UPDATE users SET email_verified = 1 WHERE email_verified IS NULL")
        if "verification_code" not in cols:
            cur.execute("ALTER TABLE users ADD COLUMN verification_code TEXT")
        if "verification_sent_at" not in cols:
            cur.execute("ALTER TABLE users ADD COLUMN verification_sent_at TEXT")

        cur.execute("""
            CREATE TABLE IF NOT EXISTS children (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                name TEXT,
                age INTEGER,
                gender TEXT,
                grade TEXT,
                difficulty_level INTEGER DEFAULT 1,
                dob TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS assessments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                child_id INTEGER,
                type TEXT,
                status TEXT DEFAULT 'in_progress',
                behavioral_score REAL,
                eeg_score REAL,
                audio_score REAL,
                face_score REAL,
                cognitive_score REAL,
                memory_score REAL,
                attention_score REAL,
                language_score REAL,
                linked_pre_report_id INTEGER,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                completed_at TIMESTAMP,
                FOREIGN KEY (child_id) REFERENCES children(id)
            )
        """)

        cur.execute("PRAGMA table_info(assessments)")
        assessment_cols = {row["name"] for row in cur.fetchall()}
        if "linked_pre_report_id" not in assessment_cols:
            cur.execute("ALTER TABLE assessments ADD COLUMN linked_pre_report_id INTEGER")

        cur.execute("""
            CREATE TABLE IF NOT EXISTS reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                child_id INTEGER,
                assessment_id INTEGER,
                report_json TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (child_id) REFERENCES children(id),
                FOREIGN KEY (assessment_id) REFERENCES assessments(id)
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS recommendations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                child_id INTEGER,
                skill TEXT,
                game1 TEXT,
                game2 TEXT,
                game3 TEXT,
                FOREIGN KEY (child_id) REFERENCES children(id)
            )
        """)
