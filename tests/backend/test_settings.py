# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Author: Le Nguyen Thanh Trung - 4123479
# Created date: 22/08/2026
# Last modified: 11/09/2026
# Acknowledgement: None

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
