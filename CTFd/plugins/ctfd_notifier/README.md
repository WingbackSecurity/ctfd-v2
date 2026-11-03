# CTFd Notifier (Discord)

Announces challenge solves to a Discord channel via webhook, configured entirely
from the CTFd admin panel (**Admin → Notifier**). No redeploy needed to change
settings.

This is a trimmed, hardened fork of
[emberzero/ctfd-notifier](https://github.com/emberzero/ctfd-notifier) (MIT).
Changes from upstream:

- **Discord only.** The Twitter and Telegram backends were removed, which also
  drops the heavy `aiogram` / `tweepy` / `oauthlib` / `pydantic` dependencies and
  the `requests==2.31.0` pin that conflicted with CTFd's own `requests`. This
  plugin needs **no extra dependencies** (`requests` ships with CTFd), so there
  is no `requirements.txt`.
- **Non-blocking delivery.** The webhook POST runs on a daemon thread with a
  timeout, so a slow or unreachable Discord can never stall or roll back a
  player's solve. All send errors are logged, never raised.
- **Configurable scope.** Announce *first blood only*, the *first N solves*, or
  *every solve*.
- **Templated messages + emoji.** Customize the title, emoji, and a message
  template with `{name} {user} {team} {challenge} {category} {value} {score}
  {place} {solves}` placeholders. Unicode emoji and Discord custom emoji
  (`<:name:id>`) both work.
- **Send test message** button to verify the webhook without waiting for a real
  solve.
- Webhook URL is masked in the UI; notifications never ping (`@everyone`/roles)
  unless you put a mention in the template.

## Config keys (stored in the `notifier_config` table)

| key | meaning |
| --- | --- |
| `discord_notifier` | `true` / `false` |
| `discord_webhook_url` | Discord webhook URL |
| `discord_scope` | `first_blood` \| `first_n` \| `all` |
| `discord_first_n` | N, when scope is `first_n` |
| `discord_fb_title` / `discord_solve_title` | embed titles |
| `discord_fb_emoji` / `discord_solve_emoji` | emoji per event |
| `discord_message_template` | embed description template |
| `discord_show_fields` | show challenge/category/points embed fields |

## Requirements

CTFd >= 3.0 (developed and verified against 3.8.2).
