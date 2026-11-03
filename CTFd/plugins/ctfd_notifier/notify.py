"""Discord delivery helpers for the Notifier plugin.

Message rendering and webhook delivery. Delivery always uses a timeout and, on
the solve path, runs on a daemon thread (see hooks.py) so a slow or unreachable
webhook can never stall a player's solve submission.
"""
import threading
from datetime import datetime, timezone

import requests

# (connect, read) timeout in seconds. A hung webhook must never block a solve.
TIMEOUT = (5, 10)

COLOR_FIRST_BLOOD = 0xE74C3C  # red
COLOR_SOLVE = 0x5865F2  # blurple


class _SafeDict(dict):
    """dict that leaves unknown {placeholders} untouched instead of raising."""

    def __missing__(self, key):
        return "{" + key + "}"


def render_message(template, fields, emoji):
    """Render a {placeholder} template. Never raises on a bad template."""
    data = dict(fields)
    data["emoji"] = emoji or ""
    try:
        return template.format_map(_SafeDict(data))
    except Exception:
        return "{0} {1} solved {2}".format(
            data.get("emoji", ""), data.get("name", ""), data.get("challenge", "")
        ).strip()


def build_embed(fields, *, first_blood, title, description, show_fields, ctf_name=None):
    embed = {
        "title": title or ("First Blood!" if first_blood else "Challenge Solved"),
        "description": description,
        "color": COLOR_FIRST_BLOOD if first_blood else COLOR_SOLVE,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    if show_fields:
        embed["fields"] = [
            {"name": "Challenge", "value": str(fields.get("challenge", "")) or "—", "inline": True},
            {"name": "Category", "value": str(fields.get("category", "")) or "—", "inline": True},
            {"name": "Points", "value": str(fields.get("value", "")) or "—", "inline": True},
        ]
    if ctf_name:
        embed["footer"] = {"text": str(ctf_name)}
    return embed


def post_webhook(url, embed, *, content=None, logger=None):
    """POST an embed to a Discord webhook. Returns (ok, error_message)."""
    payload = {
        "embeds": [embed],
        # Never ping anyone unless an explicit mention is configured.
        "allowed_mentions": {"parse": []},
    }
    if content:
        payload["content"] = content
    try:
        resp = requests.post(url, json=payload, timeout=TIMEOUT)
        if resp.status_code >= 300:
            msg = "Discord returned HTTP %s" % resp.status_code
            if logger:
                logger.warning("ctfd_notifier: %s", msg)
            return False, msg
        return True, None
    except requests.exceptions.RequestException as e:
        if logger:
            logger.warning("ctfd_notifier: Discord webhook post failed: %s", e)
        return False, str(e)


def post_webhook_async(app, url, embed, *, content=None):
    """Fire-and-forget delivery on a daemon thread so solves never block."""
    logger = getattr(app, "logger", None)

    def _run():
        post_webhook(url, embed, content=content, logger=logger)

    threading.Thread(target=_run, name="ctfd-notifier-discord", daemon=True).start()
