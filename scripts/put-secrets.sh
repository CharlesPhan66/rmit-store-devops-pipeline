#!/usr/bin/env bash
#
# Put the five SecureString parameters the pipeline needs into SSM.
#
#   ./scripts/put-secrets.sh
#
# CloudFormation cannot do this: AWS::SSM::Parameter accepts String and
# StringList only, never SecureString. So these five live outside the
# templates, and this script is the whole of that manual step.
#
# Run it once, after the rmit-data stack exists. Re-running is safe: the two
# database parameters are overwritten, and SECRET_KEY is only ever created.
#
# For automation, export RDS_PASS and STAGING_PASS beforehand and nothing is
# prompted. Prefer the prompts interactively - a typed password ends up in
# ~/.zsh_history and in the process table.

set -euo pipefail

RDS_ENDPOINT_PARAM=/rmit/prod/RDS_ENDPOINT
DB_USER=rmit
DB_NAME=rmit_store

die() { printf '\nerror: %s\n' "$1" >&2; exit 1; }

# --- Preconditions -----------------------------------------------------------

command -v aws >/dev/null || die "the aws CLI is not installed"

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

# --- Passwords ---------------------------------------------------------------

# django-environ splits DATABASE_URL on these characters, so a password
# containing one of them makes Django connect to a host name that is really a
# fragment of the password. Refuse rather than produce a URL that parses wrong.
reject_url_unsafe() {
  case "$2" in
    *[@:/#]*) die "$1 must not contain @ : / or # - django-environ splits the
       URL on those. Use letters, digits and -_. only." ;;
  esac
  [ -n "$2" ] || die "$1 must not be empty"
}

# The RDS master password: exactly the value passed as DbPassword when
# cloudformation/data.yml was deployed. NoEcho hides it from describe-stacks,
# so there is no way to read it back - a mismatch here surfaces later as
# `password authentication failed for user "rmit"` in the production logs.
if [ -z "${RDS_PASS:-}" ]; then
  read -rsp 'RDS master password (the DbPassword given to data.yml): ' RDS_PASS
  echo
fi
reject_url_unsafe "The RDS password" "$RDS_PASS"

# Staging's password authenticates against nothing. It CREATES the account
# inside the db container of docker-compose.prod.yml, the first time the pgdata
# volume is initialised. Its only requirement is matching staging's own
# DATABASE_URL, which this script guarantees by writing both from one value.
if [ -z "${STAGING_PASS:-}" ]; then
  read -rsp 'Staging Postgres password (anything, unrelated to RDS): ' STAGING_PASS
  echo
fi
reject_url_unsafe "The staging password" "$STAGING_PASS"

echo

# --- staging: the db container -----------------------------------------------
# Host `db` is the Compose service name, resolved inside Docker's own network.
# Staging never opens a connection to RDS, which is why a seed_demo --flush
# there cannot reach production data.

echo "==> /rmit/staging/DATABASE_URL"
aws ssm put-parameter --name /rmit/staging/DATABASE_URL \
  --type SecureString --overwrite \
  --value "postgres://${DB_USER}:${STAGING_PASS}@db:5432/${DB_NAME}" >/dev/null

echo "==> /rmit/staging/POSTGRES_PASSWORD"
aws ssm put-parameter --name /rmit/staging/POSTGRES_PASSWORD \
  --type SecureString --overwrite \
  --value "$STAGING_PASS" >/dev/null

# --- prod: RDS ---------------------------------------------------------------
# No POSTGRES_PASSWORD for prod: swarm/stack.yml has no db service, so there is
# no account for it to create. Writing one would be a parameter nothing reads.

echo "==> /rmit/prod/DATABASE_URL"
aws ssm put-parameter --name /rmit/prod/DATABASE_URL \
  --type SecureString --overwrite \
  --value "postgres://${DB_USER}:${RDS_PASS}@${RDS}:5432/${DB_NAME}" >/dev/null

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

unset RDS_PASS STAGING_PASS

# --- Verify ------------------------------------------------------------------

echo
echo "SSM now holds:"
aws ssm get-parameters-by-path --path /rmit --recursive \
  --query 'Parameters[].[Name,Type]' --output table

COUNT=$(aws ssm get-parameters-by-path --path /rmit --recursive \
          --query 'length(Parameters)' --output text)

# 8 String from CloudFormation + the 5 written here. JENKINS_PUBKEY makes 14,
# but Ansible has not run yet at this point in the runbook.
if [ "$COUNT" -lt 13 ]; then
  die "expected at least 13 parameters, found $COUNT. A CloudFormation stack is
       probably missing - check that all four deployed."
fi

echo "Done. $COUNT parameters."
