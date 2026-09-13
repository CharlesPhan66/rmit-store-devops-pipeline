#!/usr/bin/env bash
# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Author: Charles Phan - 4131861
# Created date: 07/09/2026
# Last modified: 13/09/2026
# Acknowledgement: None

#
# This file is to prompt you for secrets to be stored in SSM Parameter Store
# As in production, these secrets are up to you to manage, so we do not take them as command line arguments and assume that as "Automation"
#
#   ./scripts/put-secrets.sh
#
# Run it once, after the rmit-data stack exists. Re-running is safe: the two
# database parameters are overwritten, and SECRET_KEY is only ever created.
#
# For automation, export RDS_PASS, ADMIN_PASS, PROD_ADMIN_PASS, EMAIL_ADDRESS,
# EMAIL_PASSWORD, JENKINS_ADMIN_PASS and GITHUB_PAT beforehand

set -euo pipefail

RDS_ENDPOINT_PARAM=/rmit/RDS_ENDPOINT
DB_USER=rmit
DB_NAME=rmit_store
STAGING_DB_NAME=rmit_staging

die() { printf '\nerror: %s\n' "$1" >&2; exit 1; }

# Preconditions

# Check the aws CLI is installed so it can be used to verify credentials and write the secrets
# Otherwise, the script will fail with a less helpful error message when it tries to use the aws CLI
# Please use cloudshell instead if you do not have the aws CLI installed locally, or install them (recommended)
# Figure out how to install the aws cli and have aws session of learner lab on your local machine if you want to run this script locally
command -v aws >/dev/null || die "the aws CLI is not installed"

# Check if the session is valid
aws sts get-caller-identity >/dev/null 2>&1 \
  || die "no valid AWS credentials. Learner Lab sessions expire after ~4h;
       refresh them from AWS Details -> AWS CLI -> Show."

# The RDS endpoint is the one value here that must already exist. Its absence
# means the data stack has not been deployed, and prod's DATABASE_URL would
# otherwise be written pointing at nothing.
RDS=$(aws ssm get-parameter --name "$RDS_ENDPOINT_PARAM" \
        --query Parameter.Value --output text 2>/dev/null) \
  || die "$RDS_ENDPOINT_PARAM not found. Deploy cloudformation/data.yml first."

echo "RDS endpoint: $RDS"
echo

# Passwords

# Check if the password is valid (Do not use @ : / or # in the password, as django-environ splits the URL on those)
reject_url_unsafe() {
  case "$2" in
    *[@:/#]*) die "$1 must not contain @ : / or # - django-environ splits the
       URL on those. Use letters, digits and -_. only." ;;
  esac
  [ -n "$2" ] || die "$1 must not be empty"
}

if [ -z "${RDS_PASS:-}" ]; then
  read -rsp 'RDS master password (the DbPassword given to data.yml): ' RDS_PASS
  echo
fi
reject_url_unsafe "The RDS password" "$RDS_PASS"

echo

# --- Both environments, one instance, two databases --------------------------
# Staging travels the identical network and secret path to production. That is
# the whole point: a throwaway container would prove nothing about the security
# group on 5432, about delivering DATABASE_URL as a secret, or about RDS's
# master account not being a real superuser.
#
# The databases stay separate, so a seed_demo --flush on staging still cannot
# reach a single production row. Ansible creates rmit_staging on first run -
# CloudFormation cannot, because RDS has no route out of its private subnet.

echo "==> /rmit/staging/DATABASE_URL"
aws ssm put-parameter --name /rmit/staging/DATABASE_URL \
  --type SecureString --overwrite \
  --value "postgres://${DB_USER}:${RDS_PASS}@${RDS}:5432/${STAGING_DB_NAME}" >/dev/null

echo "==> /rmit/prod/DATABASE_URL"
aws ssm put-parameter --name /rmit/prod/DATABASE_URL \
  --type SecureString --overwrite \
  --value "postgres://${DB_USER}:${RDS_PASS}@${RDS}:5432/${DB_NAME}" >/dev/null

# Ansible needs the raw password too, to run CREATE DATABASE. Parsing it back
# out of a DATABASE_URL would break on the first password containing a colon.
echo "==> /rmit/RDS_MASTER_PASSWORD"
aws ssm put-parameter --name /rmit/RDS_MASTER_PASSWORD \
  --type SecureString --overwrite \
  --value "$RDS_PASS" >/dev/null

# --- Staging's store administrator -------------------------------------------
# `manage.py create_admin` reads this from the container environment, which
# Ansible writes into compose.env. seed_demo has no environment fallback and
# aborts on an empty database without it, so the staging deploy needs both.
# Staging only: production is never seeded with demo data.

# One per environment, for the same reason SECRET_KEY is: a staging password
# that leaked must not open the production admin.
if [ -z "${ADMIN_PASS:-}" ]; then
  read -rsp 'STAGING store admin password (admin@rmit.edu.au): ' ADMIN_PASS
  echo
fi
[ -n "$ADMIN_PASS" ] || die "The staging admin password must not be empty"

if [ -z "${PROD_ADMIN_PASS:-}" ]; then
  read -rsp 'PRODUCTION store admin password (admin@rmit.edu.au): ' PROD_ADMIN_PASS
  echo
fi
[ -n "$PROD_ADMIN_PASS" ] || die "The production admin password must not be empty"

echo "==> /rmit/staging/ADMIN_PASSWORD"
aws ssm put-parameter --name /rmit/staging/ADMIN_PASSWORD \
  --type SecureString --overwrite \
  --value "$ADMIN_PASS" >/dev/null

# Ansible turns this into the Docker secret DJANGO_SUPERUSER_PASSWORD, which
# the api entrypoint exports as an env var of the same name.
echo "==> /rmit/prod/ADMIN_PASSWORD"
aws ssm put-parameter --name /rmit/prod/ADMIN_PASSWORD \
  --type SecureString --overwrite \
  --value "$PROD_ADMIN_PASS" >/dev/null

# One Gmail account handles app emails and Jenkins alerts.
# The address is public; only the App Password is stored as SecureString (generated once at https://myaccount.google.com/apppasswords (2-Step Verification required first)
# Both services share the same Gmail sending quota.
if [ -z "${EMAIL_ADDRESS:-}" ]; then
  read -rp 'Gmail address for real email delivery (same one used for Jenkins alerts): ' EMAIL_ADDRESS
fi
[ -n "$EMAIL_ADDRESS" ] || die "The email address must not be empty"

if [ -z "${EMAIL_PASSWORD:-}" ]; then
  read -rsp 'Gmail App Password (16 characters, no spaces): ' EMAIL_PASSWORD
  echo
fi
[ -n "$EMAIL_PASSWORD" ] || die "The email app password must not be empty"

echo "==> /rmit/EMAIL_ADDRESS"
aws ssm put-parameter --name /rmit/EMAIL_ADDRESS \
  --type String --overwrite \
  --value "$EMAIL_ADDRESS" >/dev/null

echo "==> /rmit/EMAIL_PASSWORD"
aws ssm put-parameter --name /rmit/EMAIL_PASSWORD \
  --type SecureString --overwrite \
  --value "$EMAIL_PASSWORD" >/dev/null


if [ -z "${JENKINS_ADMIN_PASS:-}" ]; then
  read -rsp 'Jenkins admin password (for the admin account Ansible creates): ' JENKINS_ADMIN_PASS
  echo
fi
[ -n "$JENKINS_ADMIN_PASS" ] || die "The Jenkins admin password must not be empty"

echo "==> /rmit/JENKINS_ADMIN_PASSWORD"
aws ssm put-parameter --name /rmit/JENKINS_ADMIN_PASSWORD \
  --type SecureString --overwrite \
  --value "$JENKINS_ADMIN_PASS" >/dev/null

if [ -z "${GITHUB_PAT:-}" ]; then
  read -rsp 'GitHub PAT (repo + admin:repo_hook scopes, for Jenkins checkout and the webhook): ' GITHUB_PAT
  echo
fi
[ -n "$GITHUB_PAT" ] || die "The GitHub PAT must not be empty"

echo "==> /rmit/GITHUB_PAT"
aws ssm put-parameter --name /rmit/GITHUB_PAT \
  --type SecureString --overwrite \
  --value "$GITHUB_PAT" >/dev/null

# --- SECRET_KEY, one per environment -----------------------------------------
# Created, never overwritten. Rotating this signing key invalidates every
# issued JWT and every outstanding password-reset link, so a careless re-run of
# this script must not do it. Two different keys, so a session minted on
# staging is worthless against production.

for ENV in staging prod; do
  NAME="/rmit/$ENV/SECRET_KEY"
  if aws ssm get-parameter --name "$NAME" >/dev/null 2>&1; then
    echo "==> $NAME already exists, left alone"
  else
    echo "==> $NAME (generated)"
    aws ssm put-parameter --name "$NAME" --type SecureString \
      --value "$(python3 -c 'import secrets;print(secrets.token_urlsafe(50),end="")')" >/dev/null
  fi
done

unset RDS_PASS ADMIN_PASS PROD_ADMIN_PASS EMAIL_PASSWORD JENKINS_ADMIN_PASS GITHUB_PAT

# Verify

echo
echo "SSM now holds:"
aws ssm get-parameters-by-path --path /rmit --recursive \
  --query 'Parameters[].[Name,Type]' --output table

COUNT=$(aws ssm get-parameters-by-path --path /rmit --recursive \
          --query 'length(Parameters)' --output text)

# 10 String from CloudFormation + the 10 written here (9 SecureString + 1
# String). JENKINS_PUBKEY makes 21, but Ansible has not run yet at this point
# in the runbook.
if [ "$COUNT" -lt 20 ]; then
  die "expected at least 18 parameters, found $COUNT. A CloudFormation stack is
       probably missing - check that all four deployed."
fi

echo "Done. $COUNT parameters."
