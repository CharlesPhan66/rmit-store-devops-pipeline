#!/usr/bin/env bash
# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Author: Charles Phan - 4131861
# Created date: 07/09/2026
# Last modified: 13/09/2026
# Acknowledgement: None


set -euo pipefail

RDS_ENDPOINT_PARAM=/rmit/RDS_ENDPOINT
DB_USER=rmit
DB_NAME=rmit_store
STAGING_DB_NAME=rmit_staging

die() { printf '\nerror: %s\n' "$1" >&2; exit 1; }

# Preconditions

command -v aws >/dev/null || die "the aws CLI is not installed"

# Check if the session is valid
aws sts get-caller-identity >/dev/null 2>&1 \
  || die "no valid AWS credentials. Learner Lab sessions expire after ~4h;
       refresh them from AWS Details -> AWS CLI -> Show."

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

echo "==> /rmit/staging/DATABASE_URL"
aws ssm put-parameter --name /rmit/staging/DATABASE_URL \
  --type SecureString --overwrite \
  --value "postgres://${DB_USER}:${RDS_PASS}@${RDS}:5432/${STAGING_DB_NAME}" >/dev/null

echo "==> /rmit/prod/DATABASE_URL"
aws ssm put-parameter --name /rmit/prod/DATABASE_URL \
  --type SecureString --overwrite \
  --value "postgres://${DB_USER}:${RDS_PASS}@${RDS}:5432/${DB_NAME}" >/dev/null

echo "==> /rmit/RDS_MASTER_PASSWORD"
aws ssm put-parameter --name /rmit/RDS_MASTER_PASSWORD \
  --type SecureString --overwrite \
  --value "$RDS_PASS" >/dev/null

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

echo "==> /rmit/prod/ADMIN_PASSWORD"
aws ssm put-parameter --name /rmit/prod/ADMIN_PASSWORD \
  --type SecureString --overwrite \
  --value "$PROD_ADMIN_PASS" >/dev/null

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

if [ "$COUNT" -lt 20 ]; then
  die "expected at least 18 parameters, found $COUNT. A CloudFormation stack is
       probably missing - check that all four deployed."
fi

echo "Done. $COUNT parameters."
