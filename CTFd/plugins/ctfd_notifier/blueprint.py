from CTFd.utils.decorators import admins_only
from flask import Blueprint, current_app, render_template, request

from . import notify
from .db_utils import DBUtils

notifier_bp = Blueprint("notifier", __name__, template_folder="templates")

VALID_WEBHOOK_PREFIXES = (
    "https://discord.com/api/webhooks/",
    "https://discordapp.com/api/webhooks/",
    "https://canary.discord.com/api/webhooks/",
    "https://ptb.discord.com/api/webhooks/",
)


def _valid_webhook(url):
    return bool(url) and url.startswith(VALID_WEBHOOK_PREFIXES)


def _validate(config):
    errors = []
    if config.get("discord_notifier") == "true" and not _valid_webhook(
        config.get("discord_webhook_url", "")
    ):
        errors.append("Enter a valid Discord webhook URL to enable notifications.")
    if config.get("discord_scope") == "first_n":
        try:
            if int(config.get("discord_first_n", "3")) < 1:
                errors.append("\"First N\" must be at least 1.")
        except (TypeError, ValueError):
            errors.append("\"First N\" must be a whole number.")
    return errors


def _send_test(config):
    url = config.get("discord_webhook_url", "")
    if not _valid_webhook(url):
        return ["Enter a valid Discord webhook URL before sending a test."]

    fields = {
        "name": "test-team",
        "user": "test-user",
        "team": "test-team",
        "challenge": "Sample Challenge",
        "category": "web",
        "value": 500,
        "score": 1337,
        "place": "1st",
        "solves": 1,
    }
    description = notify.render_message(
        config.get("discord_message_template", "{emoji} {name} solved {challenge}"),
        fields,
        config.get("discord_fb_emoji", ""),
    )
    embed = notify.build_embed(
        fields,
        first_blood=True,
        title=config.get("discord_fb_title", "First Blood!"),
        description="**[TEST]** " + description,
        show_fields=config.get("discord_show_fields", "true") == "true",
        ctf_name="Notifier test",
    )
    ok, err = notify.post_webhook(url, embed, logger=current_app.logger)
    return [] if ok else ["Could not deliver test message: %s" % err]


def load_bp(plugin_route):
    @notifier_bp.route(plugin_route, methods=["GET"])
    @admins_only
    def notifier_config():
        return render_template("ctfd_notifier/config.html", config=DBUtils.get_config())

    @notifier_bp.route(plugin_route, methods=["POST"])
    @admins_only
    def notifier_update():
        form = request.form.to_dict()
        action = form.pop("action", "save")
        form.pop("nonce", None)

        success = None
        if action == "test":
            errors = _send_test(form)
            if not errors:
                success = "Test message sent to Discord."
        else:
            errors = _validate(form)
            if not errors:
                DBUtils.save_config(form.items())
                success = "Notifier settings saved."

        # Reflect what the admin just submitted back into the form.
        config = DBUtils.get_config()
        config.update(form)
        return render_template(
            "ctfd_notifier/config.html", config=config, errors=errors, success=success
        )

    return notifier_bp
