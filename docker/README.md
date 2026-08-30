# Container images

Two images, built from the **repo root** because Tom's application is vendored
under `app/` and each build needs to reach into it.

| File | Produces | Base | Contains |
|---|---|---|---|
| `api.Dockerfile` | Django + gunicorn | `python:3.12-slim` | app source, a venv, collected static files |
| `client.Dockerfile` | the SPA behind nginx | `nginx:1.27-alpine` | `dist/` only — **no Node** |
| `client-entrypoint.sh` | — | — | renders `config.js` from `$API_BASE_URL` at container start |
| `client-nginx.conf` | — | — | SPA fallback, cache rules, `/nginx-health` |
| `userdata-api.sh` | — | — | EC2 user data for the API host: hostname, Docker, git |
| `userdata-client.sh` | — | — | the same, for the frontend host |

The two user-data scripts differ by one effective line — the hostname. Every
other difference between the two machines lives inside the images. Paste one
into the launch wizard under **Advanced details → User data**, or pass
`--user-data file://docker/userdata-api.sh` to `aws ec2 run-instances`. They run
once, on first boot, as root. Never put a secret in them: user data is readable
from inside the instance by any process, without privileges.

## Build

```bash
# from the repo root — the trailing dot is the build context
docker build -f docker/api.Dockerfile    -t rmit-api:local .
docker build -f docker/client.Dockerfile -t rmit-client:local .
```

With a version stamp, so `GET /api/version/` identifies the build:

```bash
docker build -f docker/api.Dockerfile \
  --build-arg APP_VERSION=1.2.0 \
  --build-arg GIT_COMMIT="$(git rev-parse --short HEAD)" \
  -t rmit-api:1.2.0 .
```

## Run

The API takes its configuration as environment variables. It never reads a
`.env` file inside the image — `.dockerignore` keeps one out.

```bash
docker run -d --name rmit-api -p 80:8000 --env-file api.env \
  --restart unless-stopped rmit-api:local
```

```bash
docker run -d --name rmit-client -p 80:80 \
  -e API_BASE_URL=http://<api-public-ip>/api \
  --restart unless-stopped rmit-client:local
```

## Three decisions worth knowing before you change anything

**`collectstatic` runs at build time.** Its output is a pure function of the
source, and whitenoise's manifest storage raises on a missing manifest, so it
must exist before gunicorn starts.

**`migrate` runs in neither the image nor an entrypoint.** It changes shared
state outside the container; N replicas migrating at boot is a race. Run it as
a one-shot container, once per release:

```bash
docker run --rm --env-file api.env rmit-api:local python manage.py migrate
```

**The API URL is not baked into the frontend bundle.** It is rendered into
`config.js` at container start. One image serves staging and production; only
`$API_BASE_URL` differs. Promoting the exact artifact that passed its tests
depends on this.

## Media

With `USE_S3=false`, uploads land on the container's writable layer and vanish
with the container. Mount a volume for a single-host run:

```bash
-v rmit-media:/srv/app/media
```

A volume does not survive a second host. Once the API runs on more than one
instance, set `USE_S3=true` and give the instance an IAM role — no code
change, and no AWS keys anywhere.
