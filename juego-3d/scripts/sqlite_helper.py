from __future__ import annotations

import json
import os
import sqlite3
import sys
from datetime import datetime


def connect(db_path: str) -> sqlite3.Connection:
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS highscores (
            id INTEGER PRIMARY KEY,
            player_name TEXT DEFAULT 'Jugador',
            max_score INTEGER,
            date TEXT
        )
        """
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO highscores (id, player_name, max_score, date)
        VALUES (1, 'Jugador', 0, '')
        """
    )
    conn.commit()


def get_best(conn: sqlite3.Connection) -> dict:
    ensure_schema(conn)
    row = conn.execute(
        "SELECT id, player_name, max_score, date FROM highscores ORDER BY max_score DESC, id ASC LIMIT 1"
    ).fetchone()
    if row is None:
        return {"id": 1, "player_name": "Jugador", "max_score": 0, "date": ""}
    return dict(row)


def save_highscore(conn: sqlite3.Connection, player_name: str, max_score: int, date: str) -> dict:
    ensure_schema(conn)
    current = get_best(conn)
    if max_score > int(current.get("max_score", 0)):
        conn.execute(
            "UPDATE highscores SET player_name = ?, max_score = ?, date = ? WHERE id = 1",
            (player_name, max_score, date),
        )
        conn.commit()
        current = get_best(conn)
    return current


def main() -> int:
    if len(sys.argv) < 3:
        print(json.dumps({"error": "usage", "mode": "init|get_best|save_highscore", "db_path": ""}))
        return 1

    mode = sys.argv[1]
    db_path = sys.argv[2]

    conn = connect(db_path)
    try:
        if mode == "init":
            ensure_schema(conn)
            print(json.dumps({"ok": True, "best": get_best(conn)}))
            return 0

        if mode == "get_best":
            print(json.dumps(get_best(conn)))
            return 0

        if mode == "save_highscore":
            player_name = sys.argv[3] if len(sys.argv) > 3 else "Jugador"
            max_score = int(sys.argv[4]) if len(sys.argv) > 4 else 0
            date = sys.argv[5] if len(sys.argv) > 5 else datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            print(json.dumps(save_highscore(conn, player_name, max_score, date)))
            return 0

        print(json.dumps({"error": f"unknown mode {mode}"}))
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
