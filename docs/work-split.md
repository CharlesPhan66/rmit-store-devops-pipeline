# Pipeline work split — 5 people, 1 shared AWS account

Every task below is traced to a line range in **`app/README.md`**. That file, not
this one, is the authority: if the two disagree, the README wins and this document
gets fixed.

**Criticality markers**

| | Meaning |
|---|---|
| 🔴 | One of the nine assessed requirements fails without it |
| 🟠 | The requirement still passes, but the demo looks thin |
| 🟢 | Bonus marks only |

---

## 1. Task inventory

Organised by the work itself, not by the README's Plan A–F. Plans A–F are six
*alternative deployment targets*; the pipeline is one thing built out of the tasks
below.

### 1.1 Containers and build artifacts

| # | Task | README | |
|---|---|---|---|
| C1 | API `Dockerfile` — decide whether `migrate` and `collectstatic` belong in the image build or the entrypoint | 377–378 | 🔴 |
| C2 | Client `Dockerfile`, multi-stage — Node compiles, result copied into a web server image. **Final image must not contain Node** | 379–381 | 🔴 |
| C3 | Decide how `config.js` reaches the frontend container at run time | 382, 291–296 | 🔴 |
| C4 | `docker-compose.yml` describing database, API, frontend | 387–388 | 🔴 |
| C5 | Healthcheck against `/readyz/` so the API waits for the database instead of crash-looping | 389–390 | 🔴 |
| C6 | Work out where migrations run when three containers start at once | 391, 298–301 | 🔴 |
| C7 | Stamp `APP_VERSION` / `GIT_COMMIT` at build time so `/api/version/` identifies the running build | 205–206, 413–415 | 🟠 |
| C8 | Push images to a registry (ECR) with immutable tags | 402–403 | 🟠 |

### 1.2 AWS infrastructure

| # | Task | README | |
|---|---|---|---|
| I1 | CloudFormation for the EC2 instances, the RDS database, the S3 bucket and the IAM roles | 402–403 | 🔴 |
| I2 | S3 bucket for product images + decide **how the browser is allowed to read from it** | 1180–1183 | 🔴 |
| I3 | Give the instance an identity that can write to the bucket **without long-lived access keys in a `.env`** | 1181–1183, 212–214 | 🔴 |
| I4 | Security groups: open the right ports and only those. Database not reachable from the internet | 372–373 | 🔴 |
| I5 | ELB in front of two API instances, `/healthz/` as the target group health check | 410–412 | 🟠 |
| I6 | `DisallowedHost`: the health check arrives with the instance's **private IP** in `Host`. Fix `ALLOWED_HOSTS` or the check's `Host` header | 1343–1349 | 🔴 |
| I7 | Keep mail and database credentials out of the repository | 1236–1238 | 🔴 |

> I6 is the one the README singles out: *"the single most common way to lose an
> afternoon on it."* It only appears once an ELB exists, which is why it belongs
> with I5 and not with whoever wrote `ALLOWED_HOSTS` first.

### 1.3 Configuration management

| # | Task | README | |
|---|---|---|---|
| M1 | Ansible to manage server configuration instead of running commands by hand | 400–401 | 🔴 |
| M2 | nginx in front of gunicorn — **must not rewrite `Host`**, or `image_url` sends browsers to the wrong machine | 1356–1377 | 🔴 |
| M3 | gunicorn + WhiteNoise; `collectstatic` or `/admin/` loses its styling | 219–220, 1382–1383 | 🟠 |
| M4 | Point email at real delivery (SES or any SMTP) through environment variables only | 1236–1238, 215–218 | 🟠 |

> M4 has a trap worth reading before testing it: delivery failures are logged,
> never raised, so **a broken mail configuration is silent** — the UI says "check
> your email" either way (1240–1243).

### 1.4 Orchestration and scaling

| # | Task | README | |
|---|---|---|---|
| O1 | Deploy to Kubernetes or Docker Swarm and scale the API to more than one replica | 404–405 | 🔴 |
| O2 | **The moment you scale, uploaded images break.** Flip `USE_S3`. "That is not a bug; it is the lesson" | 405–407, 1164–1178, 1379–1380 | 🔴 |
| O3 | Zero-downtime deployment — blue/green or canary, confirmed from outside via `/api/version/` | 413–415 | 🟠 |

### 1.5 Testing

The README is unusually specific about where the bugs worth catching live
(1267–1269), and states plainly that the repo ships no tests at all (1260).

| # | Task | README | |
|---|---|---|---|
| T1 | Test tooling, kept out of the production image | 1258–1265 | 🔴 |
| T2 | Unit: authorisation — who may call what | 1267 | 🔴 |
| T3 | Unit: server-side pricing and tax (5% on taxable lines only) | 1267–1268, 1297–1299 | 🔴 |
| T4 | Unit/integration: the stock decrement on checkout | 1268 | 🔴 |
| T5 | Integration: what a declined card leaves behind — **no order, no stock movement** | 1268–1269, 1212–1218 | 🔴 |
| T6 | Frontend unit tests | 416–418 | 🟠 |
| T7 | End-to-end from journeys A–F — "a ready-made backlog … each one converts into an end-to-end test" | 1271–1272, 1274–1330 | 🔴 |
| T8 | Smoke tests against `/healthz/`, `/readyz/`, `/api/version/` | 1245–1256 | 🔴 |
| T9 | Suites emit **machine-readable reports** so Jenkins can publish them and fail the build | 397–399 | 🔴 |

Test cards are safe to automate: no payment provider, no API key, no outbound
network call (1187–1190). `4242 4242 4242 4242` approves, `4000 0000 0000 0002`
declines.

### 1.6 CI/CD

| # | Task | README | |
|---|---|---|---|
| P1 | Jenkins builds, tests and deploys automatically | 397–399 | 🔴 |
| P2 | Trigger on push (webhook) | 397 | 🔴 |
| P3 | Publish test reports; **fail the build when they fail** | 398–399 | 🔴 |
| P4 | Build in CI and ship only `dist/` — a `t3.micro` OOMs on `npm run build`, and shipping the artifact "is the point of having a build stage" | 1351–1354 | 🔴 |
| P5 | Deploy to staging automatically; promote to production on green | assignment req 4 | 🔴 |
| P6 | Notify on failure and leave production untouched | assignment req 8 | 🔴 |
| P7 | Rollback path | 413–415 | 🟠 |

### 1.7 Deploy-time steps and the config contract

These fall between groups if nobody names them. Each one is a *decision* somebody
has to own, not just a file somebody has to write.

| # | Task | README | |
|---|---|---|---|
| X1 | Agree the environment-variable contract per tier — `DJANGO_SETTINGS_MODULE`, `DATABASE_URL`, `SECRET_KEY`, `ALLOWED_HOSTS`, `CLIENT_URL`, `USE_S3` + `AWS_*`, `EMAIL_*` — and who supplies each one | 209–211 | 🔴 |
| X2 | Decide the topology's CORS answer. One origin behind the load balancer and it "never enters the picture"; two origins and `CORS_ALLOWED_ORIGINS` + `CSRF_TRUSTED_ORIGINS` become mandatory | 370–371, 888 | 🔴 |
| X3 | `create_admin` in the container entrypoint and the Ansible task — the README says it exists "for container entrypoints and Ansible tasks" | 232–234 | 🟠 |
| X4 | Decide where `seed_demo` runs. Idempotent, so safe to re-run — but safe is not the same as wanted. Staging yes, production no | 228–231 | 🟠 |
| X5 | Decide where container logs go once the orchestrator replaces a container (`LOG_LEVEL`) | 226–227 | 🟢 |

> X2 is the one to settle **first**, because it is G1's topology choice that
> decides whether it is work at all — and G3 and G5 cannot write the environment
> file until they know the answer.

**Already working, no pipeline task required:** `/api/config/` serving tax rate and
currency (207–208), `/api/schema/` + `/api/docs/` (221–222), the consistent error
envelope (223–225). Listed here so nobody spends an afternoon looking for the work.

### 1.8 Monitoring — stretch, see §6

| # | Task | README | |
|---|---|---|---|
| S1 | Prometheus and Grafana. "`/healthz/` and `/readyz/` are already there for probes; adding a metrics endpoint is your job" | 408–409 | 🟢 |

---

## 2. Ownership

Four people. One takes G1 and G4 together; the other three take one group each.

| Group | Owner | Weight |
|---|---|---|
| G1 — Infrastructure as Code | **Charles** + **Trung** | ~6.75 |
| G4 — Testing | **Charles** + **Trung** | ~6.5 |
| G2 — Containers and artifacts | **Dat** | ~6.25 |
| G3 — Configuration management and orchestration | **Hung** | ~6.0 |
| G5 — Jenkins CI/CD and alerting | **Khoa** | ~6.25 |

The three single-owner groups sit at 6.0–6.25 — even within **±2.7%**. They are
already cut along the natural seams (build the images / configure and run the
servers / drive the pipeline), so the balancing was done by removing two handoffs
rather than by shuffling tasks for the sake of the arithmetic:

- **G5 provisions its own Jenkins host** instead of receiving a half-built server
  from G3. Handing over a partly-configured machine between two people is exactly
  where a day disappears — and G5 writing that Ansible role gives it a share of
  requirement 7's evidence too.
- **G2 owns the Jenkins stage that builds and pushes images**, because G2 wrote
  both Dockerfiles and named the ECR repositories. Thirty lines of `Jenkinsfile`
  belong with the person who knows what they are calling.

The lead carries ~13.25 days, roughly double a single-owner group. That is a
deliberate choice, but it makes the lead a **single point of dependency for two of
the three others** — see §4.

Weights are estimated person-days.

### G1 — Infrastructure as Code · ~6.75 days · 🔴 Critical

Blocks G3 and G5. Nothing else can land until there is somewhere to land.

| Task | |
|---|---|
| CloudFormation: VPC, subnets, security groups (I4) | 🔴 |
| CloudFormation: RDS PostgreSQL, not publicly accessible (I1, I4) | 🔴 |
| CloudFormation: S3 bucket + browser read policy (I1, I2) | 🔴 |
| CloudFormation: IAM instance role — **no long-lived keys anywhere** (I3) | 🔴 |
| CloudFormation: ECR repositories (C8) | 🟠 |
| CloudFormation: EC2 fleet + ALB + target group on `/healthz/` (I5) | 🟠 |
| Fix `DisallowedHost` from the ALB's private-IP `Host` header (I6) | 🔴 |
| Secret store for `SECRET_KEY`, `DATABASE_URL`, SES credentials (I7) | 🔴 |
| Own the environment-variable contract — publish the list, say who supplies each (X1) | 🔴 |
| Settle the CORS question by choosing the topology, and tell G3 and G5 (X2) | 🔴 |

**Done when** a single `create-stack` produces a working RDS instance, an empty
bucket, an instance role that can write to it, and a load balancer reporting
healthy targets — and `git grep AWS_SECRET_ACCESS_KEY` finds nothing.

### G2 — Containers and artifacts · ~6.25 days · 🔴 Critical

Blocks G3 and G5. **Needs no AWS access** until the ECR push at the end.

| Task | |
|---|---|
| API `Dockerfile`, with the `migrate`/`collectstatic` placement decision written down (C1) | 🔴 |
| Client `Dockerfile`, multi-stage, **verified to contain no Node** (C2) | 🔴 |
| Runtime `config.js` injection — entrypoint `envsubst`, bind mount or ConfigMap (C3) | 🔴 |
| `docker-compose.yml` for all three tiers (C4) | 🔴 |
| `/readyz/` healthcheck gating API startup (C5) | 🔴 |
| Migration ordering with three containers starting at once (C6) | 🔴 |
| `create_admin` in the entrypoint, from `DJANGO_SUPERUSER_*` (X3) | 🟠 |
| `APP_VERSION` / `GIT_COMMIT` build args feeding `/api/version/` (C7) | 🟠 |
| Push to ECR with immutable tags (C8) | 🟠 |
| The `Jenkinsfile` stage that builds and pushes both images (C8, P4) | 🔴 |

**Done when** `docker compose up` on a clean machine serves the storefront with
images, `docker run --rm <client-image> which node` finds nothing, and
`/api/version/` reports the real commit rather than the `dev` default.

### G3 — Configuration management and orchestration · ~6.0 days · 🔴 Critical

Owns requirements 7 and 9 — two requirements in one group, which is why it holds
no Jenkins work at all.

**Blocked longest**, because both halves need somewhere to land. Do not wait: write
and test every Ansible role against a **local VM or a systemd-enabled container**
first, so the day G1's instances appear the roles only need an inventory change.
An idle week here is the most likely way this project runs late.

| Task | |
|---|---|
| Ansible roles: runtimes, PostgreSQL client, Docker (M1) | 🔴 |
| Ansible role: nginx with `proxy_set_header Host $host` (M2) | 🔴 |
| Ansible role: gunicorn under systemd + `collectstatic` (M3) | 🟠 |
| Idempotency — a second run reports zero changes (M1) | 🔴 |
| Swarm cluster init + `stack.yml` (O1) | 🔴 |
| Scale the API to ≥2 replicas (O1) | 🔴 |
| **Flip `USE_S3` and prove the image breakage disappears** (O2) | 🔴 |
| Migrations as a one-shot job, not once per replica (C6, 298–301) | 🔴 |
| Rolling update + `service rollback` demo (O3) | 🟠 |
| SES via environment variables only (M4) | 🟠 |

**Done when** a second `ansible-playbook` run is all green with zero changes, two
API replicas serve the same product image, and a rolling update is visible through
`/api/version/` without a dropped request.

> Capture O2 as **before and after**: scale to two replicas with `USE_S3=False`
> first, screenshot the intermittent 404s, then flip it. That contrast is the
> single best piece of evidence in the whole assignment.

### G4 — Testing · ~6.5 days · 🔴 Critical

Owns requirement 5. G5 has nothing to run without it. **Needs no AWS access at
all** — starts day 1.

| Task | |
|---|---|
| pytest-django + `requirements-dev.txt`, separate from runtime deps (T1) | 🔴 |
| Unit: authorisation matrix — anon / member / merchant / admin (T2) | 🔴 |
| Unit: card validation, brand detection, expiry, decline codes (T3) | 🔴 |
| Unit: 5% tax on taxable lines only; totals computed server-side (T3) | 🔴 |
| Integration: checkout decrements stock exactly once (T4) | 🔴 |
| Integration: declined card leaves **no order and no stock movement** (T5) | 🔴 |
| Integration: a merchant hitting another merchant's id gets 404, not 403 (T2) | 🟠 |
| Frontend unit: cart store, card-input formatting (T6) | 🟠 |
| E2E: journeys A and B — browse, register, buy, check the arithmetic (T7) | 🔴 |
| E2E: journey E, the seller lifecycle (T7) | 🟠 |
| E2E: journeys C, D and F — fulfilment, reviews/wishlist, administration (T7) | 🟢 |
| Smoke: `/healthz/`, `/readyz/`, `/api/version/` (T8) | 🔴 |
| JUnit XML output + coverage report from every suite (T9) | 🔴 |

**Done when** four distinct kinds of test exist, all emit JUnit XML, and a
deliberately broken tax calculation turns the suite red.

> Journey B is the highest-value e2e because it asserts arithmetic the server
> owns: subtotal `$72.90`, tax `$2.25` — five per cent of the taxable line alone,
> not of the subtotal — total `$75.15` (1297–1301).

### G5 — Jenkins CI/CD and alerting · ~6.25 days · 🔴 Critical

Owns requirements 3, 4, 6 and 8. Waits on G2 (images) and G4 (suites), so starts
by standing up Jenkins and a skeleton pipeline with stubbed stages.

| Task | |
|---|---|
| Jenkins on its own EC2, **provisioned by an Ansible role you write** (P1, M1) | 🔴 |
| Credentials: registry, SSH, AWS, SES (I7) | 🔴 |
| Webhook trigger on push (P2) | 🔴 |
| Stage: build both tiers — client bundle built in CI, not on the server (P4) | 🔴 |
| Stage: run every suite from G4 (P1) | 🔴 |
| Stage: publish reports and **fail red** (P3) | 🔴 |
| Stage: migrate once, then deploy to staging (P5) | 🔴 |
| Stage: `seed_demo` on staging only, never on production (X4) | 🟠 |
| Stage: promote to production on green (P5) | 🔴 |
| Failure email; production left untouched on red (P6) | 🔴 |
| Rollback stage (P7) | 🟠 |

**Done when** one `git push` produces a green run that reaches production, and one
push with a deliberately failing test produces a red run, an email in the team's
inbox, and a production `/api/version/` still reporting the previous commit.

---

## 3. Requirement traceability

| # | Requirement | Group | Primary evidence |
|---|---|---|---|
| 1 | Cloud integration | **G1** | CloudFormation stacks; RDS, S3, ECR, ALB, IAM in console |
| 2 | Containerized services | **G2** | Two Dockerfiles; final client image has no Node |
| 3 | Continuous Integration | **G5** | Push builds both tiers, runs all suites, publishes results |
| 4 | Continuous Deployment | **G5** | Auto staging → green → auto production; red → notify, production untouched |
| 5 | Testing, ≥4 kinds | **G4** | unit / integration / e2e / smoke, all emitting JUnit XML |
| 6 | Automation tool | **G5** | `Jenkinsfile`, webhook-triggered job, published reports |
| 7 | Configuration management | **G3** | Idempotent Ansible roles; second run zero changes |
| 8 | Automated alerting | **G5** | Failure email received, inbox screenshot |
| 9 | Orchestration | **G3** | ≥2 API replicas, rolling update, rollback demo |

Every requirement has exactly one owning group. Where a second group contributes
(G3 provisions G5's Jenkins host; G1's bucket is what makes G3's `USE_S3` flip
work), the owner is still accountable for the evidence.

---

## 4. Dependencies and start order

```
Day 1, in parallel, no contention:

  LEAD ┬─ G1 Infrastructure ──┬──> G3 Config mgmt + Orchestration ──┐
       │                      │                                     │
       └─ G4 Testing ─────────┼─────────────────────────────────────┼──> G5 Jenkins
                              │                                     │
          G2 Containers ──────┴─────────────────────────────────────┘
```

**G2 and G4 need no AWS account at all.** Docker builds and test suites run on a
laptop. Half the team therefore never touches the shared account in week one. Say
this out loud at the first stand-up — the instinct is to have everyone log into AWS
on day 1, and that is the worst possible start.

Hard ordering rules:

- **G4 before G5's test stages.** CI with nothing to run is not CI. (Jenkins depends on Testing)
- **G2 before G3's orchestration.** You cannot orchestrate images that do not exist. (Ansible Swarm depend on Container)
- **G1 before G3.** Ansible and Swarm both need somewhere to land. (Container depends on Cloudformation)
- **G3's `USE_S3` flip needs G1's bucket and instance role.** Agree the bucket name
  on day 1 so G3 is not blocked at the end.
- **G5 can start immediately** with its own Jenkins host and stubbed stages; wire
  the real stages in as G2 and G4 land.

### The one scheduling risk worth naming

The lead owns **both** G1 and G4, and those two are upstream of G3 and G5
respectively. If the lead falls behind, two of the other three stall — and G2,
the one that would keep going, is also the one that finishes earliest.

Two cheap mitigations, both worth doing in week one:

1. **Publish G1's contracts before G1 is finished.** Bucket name, ECR repository
   names, the environment-variable list (X1) and the CORS decision (X2) are all
   just *decisions* — they can be written down on day 1 and honoured later. G3 and
   G5 can build against agreed names long before the stacks exist.
2. **Land G4's smoke suite (T8) first.** It is the smallest of the five test kinds
   and the one G5 needs earliest, so it unblocks the CI stage while the unit and
   e2e suites are still being written.

When G2 finishes early, that person picks up whichever of the lead's two groups is
further behind — most likely G4's e2e specs, which parallelise cleanly by journey.

---

## 5. Shared-account rules

One Learner Lab account, four people. These are not suggestions.

**Prefix every resource with your group.** `g1-`, `g2-`, `g3-`, `g5-` on stack
names, security groups, ECR repos and EC2 name tags. The lead uses `g1-` for
infrastructure; G4 creates no AWS resources at all. **S3 bucket names are globally
unique across all of AWS** — a collision fails with an error that does not explain
itself.

**G1 owns the network.** Nobody else creates or deletes a VPC, subnet or security
group. If you need a rule added, ask G1.

**Never delete what you did not create.** `delete-stack` on someone else's stack
destroys their afternoon and possibly their evidence. Ask in the group chat first,
every time.

**Every lab session end stops all EC2 and reassigns public IPs.** What survives:
RDS endpoints, S3 bucket names and URLs. What does not: every EC2 public IP. This
is precisely why G1's load balancer and G3's Swarm service names matter — they are
what lets the pipeline survive a session boundary without five people editing
config files every morning.

**Capture evidence as you go.** Screenshots recreated at the end always look
recreated. The moment something works, photograph it.

---

## 6. Stretch goals — deliberately not in the split

**S1 — Prometheus and Grafana** (README 408–409). The README lists monitoring as
one of eight optional "directions worth taking" for Plan F, and it is **not one of
the nine assessed requirements** — only *automated alerting* is, and that lives in
G5 as P6.

Adding it to any group would put that group ~2 days ahead of the rest for marks
that are not on the sheet. Assign it to whichever group finishes first.

**X5 — log destination once containers are disposable.** `LOG_LEVEL` and a single
console handler already exist (226–227); shipping those logs somewhere that
survives a replaced container is the extra work. Natural companion to S1.

Same treatment for a canary release beyond the basic rolling update (O3 covers the
requirement), and for TLS termination — worth mentioning in the report as known
future work, not worth a group's time now.

---

## 7. What every group hands to the report

Each group writes its own section, and each section answers the same four
questions:

1. **What the README asked for** — quote the line range.
2. **What we built** — the file, the stack, the job.
3. **How we proved it** — the command output or screenshot.
4. **What we traded away** — the shortcut we took and what production would do
   instead.

Question 4 is where the marks that separate groups usually are. Examples already
known: RDS master user reused as the application user; `Public access` handled by
one checkbox rather than a private subnet with a bastion; product images public in
S3 rather than served through signed URLs.
