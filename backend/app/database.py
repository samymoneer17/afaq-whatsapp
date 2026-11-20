# -*- coding: utf-8 -*-
"""طبقة قاعدة البيانات SQLite (app_data.db) للأرشفة والرسائل والحالات والإعدادات."""
import json
import sqlite3
import threading
import time

from .config import DATA_DB

_lock = threading.RLock()
_conn: sqlite3.Connection | None = None


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DATA_DB, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    return conn


def get_conn() -> sqlite3.Connection:
    global _conn
    with _lock:
        if _conn is None:
            _conn = _connect()
        return _conn


def init_db() -> None:
    """إنشاء الجداول والفهارس."""
    with _lock:
        conn = get_conn()
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS chats (
                jid TEXT PRIMARY KEY,
                name TEXT,
                last_message TEXT,
                last_time INTEGER DEFAULT 0,
                unread INTEGER DEFAULT 0,
                is_group INTEGER DEFAULT 0,
                is_newsletter INTEGER DEFAULT 0,
                picture TEXT,
                members INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS messages (
                chat_jid TEXT NOT NULL,
                id TEXT NOT NULL,
                sender TEXT,
                sender_name TEXT,
                from_me INTEGER DEFAULT 0,
                type TEXT DEFAULT 'text',
                body TEXT,
                media_path TEXT,
                media_mime TEXT,
                media_name TEXT,
                media_size INTEGER,
                media_duration INTEGER,
                media_width INTEGER,
                media_height INTEGER,
                media_state TEXT DEFAULT 'none',
                timestamp INTEGER DEFAULT 0,
                server_id INTEGER DEFAULT 0,
                quoted_id TEXT,
                quoted_body TEXT,
                quoted_type TEXT,
                quoted_from_me INTEGER DEFAULT 0,
                quoted_sender TEXT,
                reactions TEXT DEFAULT '{}',
                poll_name TEXT,
                poll_options TEXT,
                receipt TEXT DEFAULT 'pending',
                deleted INTEGER DEFAULT 0,
                proto BLOB,
                PRIMARY KEY (chat_jid, id)
            );
            CREATE INDEX IF NOT EXISTS idx_messages_chat_time ON messages(chat_jid, timestamp);
            CREATE TABLE IF NOT EXISTS statuses (
                id TEXT PRIMARY KEY,
                sender TEXT,
                sender_name TEXT,
                type TEXT,
                body TEXT,
                media_path TEXT,
                media_mime TEXT,
                media_state TEXT DEFAULT 'none',
                timestamp INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS kv (
                key TEXT PRIMARY KEY,
                value TEXT
            );
            """
        )
        conn.commit()


def x(sql: str, params: tuple = ()) -> None:
    """تنفيذ استعلام كتابة مع التزام."""
    with _lock:
        get_conn().execute(sql, params)
        get_conn().commit()


def q(sql: str, params: tuple = ()) -> list[sqlite3.Row]:
    """تنفيذ استعلام قراءة."""
    with _lock:
        return get_conn().execute(sql, params).fetchall()


def q1(sql: str, params: tuple = ()) -> sqlite3.Row | None:
    """تنفيذ استعلام قراءة لصف واحد."""
    with _lock:
        return get_conn().execute(sql, params).fetchone()


# ---------------------------------------------------------------- KV
def kv_get(key: str, default=None):
    row = q1("SELECT value FROM kv WHERE key=?", (key,))
    if row is None:
        return default
    return row["value"]


def kv_set(key: str, value: str) -> None:
    x("INSERT INTO kv(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, str(value)))


# ---------------------------------------------------------------- Chats
def upsert_chat(jid: str, name=None, last_message=None, last_time=None,
                is_group=None, is_newsletter=None, bump_unread=False,
                set_unread=None, members=None) -> None:
    """إدراج/تحديث محادثة في القائمة."""
    with _lock:
        conn = get_conn()
        row = conn.execute("SELECT * FROM chats WHERE jid=?", (jid,)).fetchone()
        if row is None:
            conn.execute(
                """INSERT INTO chats(jid, name, last_message, last_time, unread, is_group, is_newsletter, members)
                   VALUES(?,?,?,?,?,?,?,?,?)""",
                (
                    jid,
                    name or jid.split("@")[0] if "@" in jid else jid,
                    last_message or "",
                    int(last_time or time.time()),
                    1 if bump_unread else 0,
                    1 if is_group else 0,
                    1 if is_newsletter else 0,
                    int(members or 0),
                ),
            )
        else:
            sets, params = [], []
            if name:
                sets.append("name=?"); params.append(name)
            if last_message is not None:
                sets.append("last_message=?"); params.append(last_message)
            if last_time:
                sets.append("last_time=?"); params.append(int(last_time))
            if is_group is not None:
                sets.append("is_group=?"); params.append(1 if is_group else 0)
            if is_newsletter is not None:
                sets.append("is_newsletter=?"); params.append(1 if is_newsletter else 0)
            if members is not None:
                sets.append("members=?"); params.append(int(members))
            if set_unread is not None:
                sets.append("unread=?"); params.append(int(set_unread))
            elif bump_unread:
                sets.append("unread=unread+1")
            if sets:
                params.append(jid)
                conn.execute(f"UPDATE chats SET {', '.join(sets)} WHERE jid=?", tuple(params))
        conn.commit()


def get_chats() -> list[sqlite3.Row]:
    return q("SELECT * FROM chats ORDER BY last_time DESC")


def get_chat(jid: str) -> sqlite3.Row | None:
    return q1("SELECT * FROM chats WHERE jid=?", (jid,))


def set_chat_picture(jid: str, picture: str) -> None:
    x("UPDATE chats SET picture=? WHERE jid=?", (picture, jid))


def reset_unread(jid: str) -> None:
    x("UPDATE chats SET unread=0 WHERE jid=?", (jid,))


# ---------------------------------------------------------------- Messages
def insert_message(m: dict) -> None:
    """إدراج رسالة أو تحديثها (idempotent)."""
    x(
        """INSERT INTO messages(chat_jid, id, sender, sender_name, from_me, type, body,
                media_path, media_mime, media_name, media_size, media_duration, media_width,
                media_height, media_state, timestamp, server_id, quoted_id, quoted_body,
                quoted_type, quoted_from_me, quoted_sender, reactions, poll_name, poll_options,
                receipt, deleted, proto)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(chat_jid, id) DO UPDATE SET
                body=excluded.body, media_state=CASE WHEN excluded.media_state='none'
                        THEN messages.media_state ELSE excluded.media_state END,
                receipt=excluded.receipt, deleted=excluded.deleted, proto=excluded.proto""",
        (
            m.get("chat_jid", ""), m.get("id", ""), m.get("sender", ""), m.get("sender_name", ""),
            1 if m.get("from_me") else 0, m.get("type", "text"), m.get("body", ""),
            m.get("media_path", ""), m.get("media_mime", ""), m.get("media_name", ""),
            m.get("media_size", 0), m.get("media_duration", 0), m.get("media_width", 0),
            m.get("media_height", 0), m.get("media_state", "none"), int(m.get("timestamp", time.time())),
            int(m.get("server_id", 0)), m.get("quoted_id", ""), m.get("quoted_body", ""),
            m.get("quoted_type", ""), 1 if m.get("quoted_from_me") else 0, m.get("quoted_sender", ""),
            m.get("reactions", "{}"), m.get("poll_name", ""), m.get("poll_options", "[]"),
            m.get("receipt", "pending"), 1 if m.get("deleted") else 0, m.get("proto"),
        ),
    )


def message_exists(chat_jid: str, msg_id: str) -> bool:
    return q1("SELECT 1 FROM messages WHERE chat_jid=? AND id=?", (chat_jid, msg_id)) is not None


def get_message(chat_jid: str, msg_id: str) -> sqlite3.Row | None:
    return q1("SELECT * FROM messages WHERE chat_jid=? AND id=?", (chat_jid, msg_id))


def get_messages(chat_jid: str, offset: int = 0, limit: int = 50) -> list[sqlite3.Row]:
    return q(
        """SELECT * FROM messages WHERE chat_jid=? AND deleted=0
           ORDER BY timestamp DESC, id DESC LIMIT ? OFFSET ?""",
        (chat_jid, limit, offset),
    )


def update_message(chat_jid: str, msg_id: str, **fields) -> None:
    if not fields:
        return
    sets = ", ".join(f"{k}=?" for k in fields)
    x(f"UPDATE messages SET {sets} WHERE chat_jid=? AND id=?", (*fields.values(), chat_jid, msg_id))


def set_messages_receipt(ids: list[str], receipt: str, from_me: bool = True) -> list[str]:
    """تحديث حالة التسليم لعدة رسائل، وإرجاع المحادثات المتأثرة."""
    chats: list[str] = []
    with _lock:
        conn = get_conn()
        for msg_id in ids:
            rows = conn.execute(
                "SELECT chat_jid FROM messages WHERE id=? AND from_me=?",
                (msg_id, 1 if from_me else 0),
            ).fetchall()
            for row in rows:
                chat = row["chat_jid"]
                if chat not in chats:
                    chats.append(chat)
            conn.execute(
                "UPDATE messages SET receipt=? WHERE id=? AND from_me=? AND receipt!='read'",
                (receipt, msg_id, 1 if from_me else 0),
            )
        conn.commit()
    return chats


def set_reactions(chat_jid: str, msg_id: str, reactions_json: str) -> sqlite3.Row | None:
    update_message(chat_jid, msg_id, reactions=reactions_json)
    return get_message(chat_jid, msg_id)


def mark_deleted(chat_jid: str, msg_id: str) -> None:
    update_message(chat_jid, msg_id, deleted=1, body="")


def unread_total() -> int:
    row = q1("SELECT COALESCE(SUM(unread), 0) AS total FROM chats")
    return int(row["total"]) if row else 0


# ---------------------------------------------------------------- Statuses
def insert_status(s: dict) -> None:
    x(
        """INSERT INTO statuses(id, sender, sender_name, type, body, media_path, media_mime,
                media_state, timestamp)
           VALUES(?,?,?,?,?,?,?,?,?)
           ON CONFLICT(id) DO UPDATE SET
                media_state=CASE WHEN excluded.media_state='none'
                        THEN statuses.media_state ELSE excluded.media_state END,
                body=excluded.body""",
        (
            s.get("id", ""), s.get("sender", ""), s.get("sender_name", ""), s.get("type", "text"),
            s.get("body", ""), s.get("media_path", ""), s.get("media_mime", ""),
            s.get("media_state", "none"), int(s.get("timestamp", time.time())),
        ),
    )


def get_statuses() -> list[sqlite3.Row]:
    return q("SELECT * FROM statuses ORDER BY timestamp DESC LIMIT 200")


# ---------------------------------------------------------------- Search
def search_chats(term: str) -> list[sqlite3.Row]:
    like = f"%{term}%"
    return q(
        """SELECT * FROM chats WHERE name LIKE ? OR jid LIKE ? OR last_message LIKE ?
           ORDER BY last_time DESC LIMIT 30""",
        (like, like, like),
    )


def search_messages_in_chat(chat_jid: str, term: str, limit: int = 50) -> list[sqlite3.Row]:
    like = f"%{term}%"
    return q(
        """SELECT * FROM messages WHERE chat_jid=? AND deleted=0 AND body LIKE ?
           ORDER BY timestamp DESC LIMIT ?""",
        (chat_jid, like, limit),
    )
