import CTFd.cache as cache
from CTFd.models import Challenges, Solves, Teams, Users
from CTFd.utils import get_config
from CTFd.utils.config import is_teams_mode
from CTFd.utils.modes import get_model
from sqlalchemy.event import listen

from . import notify
from .db_utils import DBUtils


def _solve_count(challenge_id):
    """Non-hidden, non-banned solves for a challenge (includes the new one)."""
    Model = get_model()
    return (
        Solves.query.join(Model, Solves.account_id == Model.id)
        .filter(
            Solves.challenge_id == challenge_id,
            Model.hidden == False,  # noqa: E712
            Model.banned == False,  # noqa: E712
        )
        .count()
    )


def _should_notify(config, count):
    scope = config.get("discord_scope", "first_blood")
    if scope == "all":
        return True
    if scope == "first_n":
        try:
            n = int(config.get("discord_first_n", "3"))
        except (TypeError, ValueError):
            n = 3
        return count <= n
    return count == 1  # first_blood


def _build_fields(solve, count):
    user = Users.query.filter_by(id=solve.user_id).first()
    challenge = Challenges.query.filter_by(id=solve.challenge_id).first()

    team = None
    if is_teams_mode() and user is not None and user.team_id:
        team = Teams.query.filter_by(id=user.team_id).first()

    account = team if team is not None else user
    name = account.name if account is not None else "Someone"

    try:
        cache.clear_standings()
        score = account.get_score() if account is not None else 0
        place = account.get_place() if account is not None else None
    except Exception:
        score, place = 0, None

    return {
        "name": name,
        "user": user.name if user is not None else "",
        "team": team.name if team is not None else "",
        "challenge": challenge.name if challenge is not None else "",
        "category": (challenge.category if challenge is not None else "") or "",
        "value": challenge.value if challenge is not None else "",
        "score": score if score is not None else 0,
        "place": place if place else "an unranked spot",
        "solves": count,
    }


def load_hooks(app):
    def on_solve(mapper, connection, solve):
        # Wrap everything: an exception raised from an after_insert event would
        # roll back the player's solve. A notification must never do that.
        try:
            config = DBUtils.get_config()
            if config.get("discord_notifier") != "true":
                return
            url = config.get("discord_webhook_url", "")
            if not url:
                return

            count = _solve_count(solve.challenge_id)
            if not _should_notify(config, count):
                return

            first_blood = count == 1
            fields = _build_fields(solve, count)

            emoji_key = "discord_fb_emoji" if first_blood else "discord_solve_emoji"
            title_key = "discord_fb_title" if first_blood else "discord_solve_title"
            template = config.get(
                "discord_message_template", "{emoji} {name} solved {challenge}"
            )
            description = notify.render_message(template, fields, config.get(emoji_key, ""))

            embed = notify.build_embed(
                fields,
                first_blood=first_blood,
                title=config.get(title_key, ""),
                description=description,
                show_fields=config.get("discord_show_fields", "true") == "true",
                ctf_name=get_config("ctf_name"),
            )
            # Network delivery happens off the solve path.
            notify.post_webhook_async(app, url, embed)
        except Exception as e:
            try:
                app.logger.warning("ctfd_notifier: on_solve failed: %s", e)
            except Exception:
                pass

    listen(Solves, "after_insert", on_solve)
