import json
import os

from CTFd.plugins import register_admin_plugin_menu_bar

from .blueprint import load_bp
from .db_utils import DBUtils
from .hooks import load_hooks

PLUGIN_PATH = os.path.dirname(__file__)
with open(os.path.join(PLUGIN_PATH, "config.json")) as f:
    CONFIG = json.load(f)


def load(app):
    with app.app_context():
        app.db.create_all()
        DBUtils.load_default()

    app.register_blueprint(load_bp(CONFIG["route"]))
    register_admin_plugin_menu_bar(CONFIG["name"], CONFIG["route"])
    load_hooks(app)
