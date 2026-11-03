from CTFd.models import db

from .models import NotifierConfig


class DBUtils:
    # Discord-only. Twitter/Telegram from the upstream plugin were removed to
    # drop the heavy (and CTFd-conflicting) aiogram/tweepy/oauthlib deps.
    DEFAULT_CONFIG = [
        ("discord_notifier", "false"),
        ("discord_webhook_url", ""),
        # first_blood | first_n | all
        ("discord_scope", "first_blood"),
        ("discord_first_n", "3"),
        ("discord_fb_title", "🩸 First Blood!"),
        ("discord_solve_title", "🚩 Challenge Solved"),
        ("discord_fb_emoji", "🩸"),
        ("discord_solve_emoji", "🚩"),
        (
            "discord_message_template",
            "{emoji} **{name}** solved **{challenge}** "
            "({category} · {value} pts) — now {place} with {score} pts!",
        ),
        ("discord_show_fields", "true"),
    ]

    ALLOWED_KEYS = {key for key, _ in DEFAULT_CONFIG}

    @staticmethod
    def get(key):
        return NotifierConfig.query.filter_by(key=key).first()

    @staticmethod
    def get_config():
        return {
            str(c.key): (c.value if c.value is not None else "")
            for c in NotifierConfig.query.all()
        }

    @staticmethod
    def save_config(items):
        # Only persist known keys so stray form fields (nonce, action, ...)
        # can never be written into the config table.
        for key, value in items:
            if key not in DBUtils.ALLOWED_KEYS:
                continue
            record = NotifierConfig.query.filter_by(key=key).one_or_none()
            if record:
                record.value = value
            else:
                db.session.add(NotifierConfig(key=key, value=value))
        db.session.commit()

    @staticmethod
    def load_default():
        existing = {c.key for c in NotifierConfig.query.all()}
        for key, value in DBUtils.DEFAULT_CONFIG:
            if key not in existing:
                db.session.add(NotifierConfig(key=key, value=value))
        db.session.commit()
