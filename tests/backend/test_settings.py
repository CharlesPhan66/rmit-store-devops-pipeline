# Import all configurations from the upstream app
from config.settings.dev import *

# Override the database to use an isolated, in-memory SQLite database
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
    }
}

# Override password hashers to use MD5.
# This makes creating test users drastically faster during unit tests.
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.MD5PasswordHasher",
]
