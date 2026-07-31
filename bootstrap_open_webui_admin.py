#!/usr/bin/env python3
"""Bootstrap an Open WebUI admin without storing credentials in GitHub."""

import os
import secrets
import sqlite3
import stat
import sys
import time
import uuid


TRUE_VALUES = {"1", "true", "yes", "y", "on"}


def enabled(value: str) -> bool:
    return value.strip().lower() in TRUE_VALUES


def wait_for_tables(db_path: str, timeout_seconds: int = 90) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if os.path.exists(db_path):
            try:
                with sqlite3.connect(db_path) as con:
                    rows = con.execute(
                        "select name from sqlite_master where type='table' and name in ('auth', 'user')"
                    ).fetchall()
                if {row[0] for row in rows} == {"auth", "user"}:
                    return True
            except sqlite3.Error:
                pass
        time.sleep(1)
    return False


def get_password(password_file: str) -> tuple[str, bool]:
    password = os.environ.get("OPEN_WEBUI_ADMIN_PASSWORD", "")
    if password:
        return password, False

    if os.path.exists(password_file):
        with open(password_file, "r", encoding="utf-8") as handle:
            return handle.read().strip(), False

    password = secrets.token_urlsafe(24)
    with open(password_file, "w", encoding="utf-8") as handle:
        handle.write(password + "\n")
    os.chmod(password_file, stat.S_IRUSR | stat.S_IWUSR)
    return password, True


def hash_password(password: str) -> str:
    try:
        import bcrypt
    except ImportError as exc:
        raise RuntimeError("bcrypt is required; run this with the Open WebUI virtualenv Python") from exc

    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def main() -> int:
    if not enabled(os.environ.get("OPEN_WEBUI_BOOTSTRAP_ADMIN", "false")):
        print("[open-webui-admin] Bootstrap disabled.")
        return 0

    email = os.environ.get("OPEN_WEBUI_ADMIN_EMAIL", "").strip()
    if not email:
        print("[open-webui-admin] OPEN_WEBUI_ADMIN_EMAIL is required when bootstrap is enabled.", file=sys.stderr)
        return 1

    name = os.environ.get("OPEN_WEBUI_ADMIN_NAME", "").strip() or email
    data_dir = os.environ.get("DATA_DIR", "/workspace/open-webui")
    db_path = os.environ.get("OPEN_WEBUI_DB", os.path.join(data_dir, "webui.db"))
    password_file = os.environ.get("OPEN_WEBUI_ADMIN_PASSWORD_FILE", "/tmp/open-webui-admin-password")

    if not wait_for_tables(db_path):
        print(f"[open-webui-admin] Open WebUI auth tables were not ready in {db_path}.", file=sys.stderr)
        return 1

    password, generated = get_password(password_file)
    password_hash = hash_password(password)
    now = int(time.time())

    with sqlite3.connect(db_path) as con:
        row = con.execute("select id from user where lower(email) = lower(?)", (email,)).fetchone()
        user_id = row[0] if row else str(uuid.uuid4())

        if row:
            con.execute(
                'update user set name = ?, role = ?, updated_at = ? where id = ?',
                (name, "admin", now, user_id),
            )
        else:
            con.execute(
                """
                insert into user (
                  id, name, email, role, profile_image_url, last_active_at, updated_at,
                  created_at, username, bio, gender, date_of_birth, profile_banner_image_url,
                  timezone, presence_state, status_emoji, status_message, status_expires_at,
                  oauth, info, settings, scim, variables
                )
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_id,
                    name,
                    email,
                    "admin",
                    "",
                    now,
                    now,
                    now,
                    None,
                    None,
                    None,
                    None,
                    "",
                    None,
                    None,
                    None,
                    None,
                    None,
                    "null",
                    "null",
                    '{"ui":{"version":"0.11.0"}}',
                    "null",
                    "null",
                ),
            )

        auth_row = con.execute("select id from auth where id = ?", (user_id,)).fetchone()
        if auth_row:
            con.execute(
                "update auth set email = ?, password = ?, active = ? where id = ?",
                (email, password_hash, 1, user_id),
            )
        else:
            con.execute(
                "insert into auth (id, email, password, active) values (?, ?, ?, ?)",
                (user_id, email, password_hash, 1),
            )
        con.commit()

    print(f"[open-webui-admin] Admin ready: {email}")
    if generated:
        print(f"[open-webui-admin] Generated password file: {password_file}")
    else:
        print(f"[open-webui-admin] Password source: {password_file if os.path.exists(password_file) else 'OPEN_WEBUI_ADMIN_PASSWORD'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
