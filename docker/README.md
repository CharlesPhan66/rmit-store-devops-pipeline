# Container images

Two images, built from the **repo root** because Tom's application is vendored
under `app/` and each build needs to reach into it.

| File | Produces | Base | Contains |
|---|---|---|---|
| `api.Dockerfile` | Django + gunicorn | `python:3.12-slim` | app source, a venv, collected static files |
| `client.Dockerfile` | the SPA behind nginx | `nginx:1.27-alpine` | `dist/` only — **no Node** |
| `client-entrypoint.sh` | — | — | renders `config.js` from `$API_BASE_URL` at container start |
| `client-nginx.conf` | — | — | SPA fallback, cache rules, `/nginx-health` |
| `client-nginx-compose.conf` | — | — | the same plus `/api/`, `/media/`, `/static/` proxied to the `api` service — used only by `docker-compose.yml` |
| `userdata-api.sh` | — | — | EC2 user data for the API host: hostname, Docker, git |
| `userdata-client.sh` | — | — | the same, for the frontend host |
| `userdata-jenkins.sh` | — | — | the Jenkins controller: `/tmp` resize, Java 21, Docker, Jenkins |

Paste one into the launch wizard under **Advanced details → User data**, or pass
`--user-data file://docker/userdata-api.sh` to `aws ec2 run-instances`. They run
once, on first boot, as root. Never put a secret in them: user data is readable
from inside the instance by any process, without privileges.

`userdata-api.sh` and `userdata-client.sh` differ by one effective line — the
hostname. Every other difference between those two machines lives inside the
images.

`userdata-jenkins.sh` is genuinely different, because the Jenkins host is the
one machine that is not just a container runtime. Three things in it are not
obvious and each one costs an hour if missed:

- **`/tmp` grown to 3G.** On AL2023 `/tmp` is a tmpfs at 50% of RAM. Jenkins
  marks its own node OFFLINE when the temp directory has under 1G free, so on a
  t3.small it refuses to build anything. `size=` is a cap, not an allocation.
- **Java 21, not 17.** Current Jenkins exits with code 1 on Java 17, and
  `systemctl status` shows only a restart loop — the reason is in
  `journalctl -u jenkins`.
- **`usermod -aG docker jenkins` before the service starts.** Group membership
  applies only to processes started afterwards.

It provisions the host, not Jenkins itself. Unlocking, plugins, credentials,
SMTP and the job are still done through the web UI; the script ends with that
list in a comment.

## Build

Always tag with the commit as well as with `local`. Two tags, one image: `local`
is what the run commands name, and the commit tag is what makes a rollback
possible.

```bash
# from the repo root — the trailing dot is the build context
TAG=$(git rev-parse --short HEAD)

docker build -f docker/api.Dockerfile \
  --build-arg GIT_COMMIT="$TAG" \
  -t rmit-api:"$TAG" -t rmit-api:local .

docker build -f docker/client.Dockerfile \
  -t rmit-client:"$TAG" -t rmit-client:local .
```

`--build-arg GIT_COMMIT` is what makes `GET /api/version/` report the commit
instead of the `dev` default, so the deployed build can be identified through a
load balancer. `APP_VERSION` works the same way for a release number.

**Building with only `-t rmit-api:local` throws away the previous build.** The
tag moves to the new image and the old one becomes `<none>:<none>` — still on
disk, still runnable by image ID, but nameless and deleted by the next
`docker system prune -a`. With the commit tag, rollback is a `docker run` away:

```bash
docker images rmit-api                       # every build still has a name
docker rm -f rmit-api
docker run -d --name rmit-api -p 80:8000 --env-file api.env \
  --restart unless-stopped rmit-api:a1b2c3d
curl -s http://127.0.0.1/api/version/        # confirms which build is serving
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

## The whole stack on one host

`docker-compose.yml` at the repo root brings up four services — `db`, `migrate`,
`api`, `client` — from these same two images:

Neither compose file has a `build:` section: they run images, they do not
produce them. Build first, then bring the stack up.

```bash
docker build -f docker/api.Dockerfile    --target runtime -t rmit-api:local .
docker build -f docker/client.Dockerfile                  -t rmit-client:local .

docker compose up -d
```

`--target runtime` is not optional. Stage `test` is the last stage in
`api.Dockerfile`, and Docker builds the last stage when no target is given, so
omitting it produces the test image — `CMD` is `pytest`, not gunicorn.

It is a **development and CI stack**, not the production topology: dev settings
and a throwaway Postgres container, no RDS and no S3. What it buys is a stack
that comes up anywhere Docker runs, which is what a CI job needs to run the
integration suite without borrowing the shared database. Production stays as
described above.

`migrate` is a separate service there for the same reason it is absent from the
image: it must run once per release, gated behind the database being healthy and
ahead of the API accepting traffic.

## Media

With `USE_S3=false`, uploads land on the container's writable layer and vanish
with the container. Mount a volume for a single-host run:

```bash
-v rmit-media:/srv/app/media
```

A volume does not survive a second host. Once the API runs on more than one
instance, set `USE_S3=true` and give the instance an IAM role — no code
change, and no AWS keys anywhere.
