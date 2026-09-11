# Master plan — COSC2767 A2, Team 13

Entry point for the whole build. Read this first, then work the phase files in
order. Every path here is written **from the repo root**.

---

## Start here

**Two folders, two different jobs. Do not confuse them.**

| | `plan/NN-*.md` (phases) | `plan/app-plans/` |
|---|---|---|
| What it is | **What we build.** The assignment | Tom's README, condensed |
| Who wrote the content | Us | Tom (we only summarised it) |
| Use it as | Your **task list** — work top to bottom | **Reference** — read the one a phase points you at |
| If you skip it | You have no deliverable | You will rediscover his gotchas the hard way |

`app-plans/` alone builds nothing. Plans C–F in it are summaries of *directions*
Tom suggests, not steps — the actual Dockerfiles, Jenkinsfile, CloudFormation
templates, Ansible roles and Swarm stack are specified in the phase files.

### The order to actually work in

| Do this | Read alongside it |
|---|---|
| 1. `01-local-baseline.md` | **`app-plans/plan-a-local-macos.md`** ← on macOS, follow this one directly |
| 2. `02-testing.md` | `app/README.md` § journeys A–F |
| 3. `03-containerisation.md` | `app-plans/plan-d-docker.md`, `plan-e-compose.md` |
| 4. `04-aws-infrastructure.md` | `app-plans/plan-c-split-ec2.md`; run `aws-capability-check.sh` first |
| 5. `05-configuration-management.md` | **`app-plans/plan-b-single-ec2.md`** ← do it by hand once, then automate |
| 6. `06-orchestration.md` | — |
| 7. `07-jenkins-cicd.md` | `app-plans/plan-f-pipeline.md` |
| 8. `08-alerting-monitoring.md` | — |
| Throughout | `09-verification-and-demo.md` — capture evidence *as you go* |

Phase 01 is the only one where the `app-plans/` file replaces the phase file
rather than supplementing it, because getting the app running locally is
entirely Tom's territory. Everywhere else, the phase file is the spine.

---

## How to use this folder

**Each file is a `phase` — a stage of work, not an alternative option.** You do
all of them, roughly in numeric order. They are numbered because of what blocks
what, not because you pick one.

> Do not confuse these with **Plan A–F in `app/README.md`**. Those are six
> *alternative deployment targets* of increasing difficulty (laptop → one EC2 →
> split EC2 → Docker → Compose → full pipeline), and you only ever end at one of
> them. Our phases are the *route* that walks from Plan A to Plan F. Phase 01 is
> the app README's Plan A. Phase 03 covers its Plans D and E. Phases 04–08 are
> its Plan F broken into deliverable pieces.

Working rhythm for a phase file:

1. Read the **header** — `Goal`, `Depends on`, `Blocks`. If its dependency is
   not finished, stop and go do that phase instead.
2. Work the steps top to bottom. The order inside a file is also dependency
   order.
3. Capture the evidence that `09-verification-and-demo.md` asks for **while you
   are in the phase**. Some of it cannot be recreated later.
4. Tick the `Done when` checklist at the bottom. That checklist is the handover
   contract — the next phase assumes every box is ticked.

Phases can run in parallel where the map below shows no arrow between them.
With a team, the natural split is: one person on 02 (testing), one on 03
(containers), one on 04+05 (AWS + Ansible), and the rest converge on 06–07 once
those land.

`plan/app-plans/` is a condensed rewrite of `app/README.md` — see the mapping
table below for which phase points at which of its Plans.

The files are working notes, deliberately git-ignored. They are not the
deliverable — `README.md` at the repo root is. `09` describes how to turn these
notes into that report.

---

## The job

Tom has a working three-tier app (`app/`) and no pipeline. We are the DevOps
consultancy. We do not restructure his app; we build everything around it so
that deploying, testing, scaling, observing and rolling back become boring.

**We never create or edit a single file under `app/`. Not one — not even a
test.** Tom's app is vendored upstream source. Every artifact we produce sits at
the repo root beside it: `requirements-dev.txt`, `pytest.ini`, `conftest.py`,
`tests/`, `Jenkinsfile`, `ansible/`, `cloudformation/`, `docker/`, `swarm/`.

The test of whether the rule is being kept: `rm -rf app/`, re-vendor a newer
version of Tom's app, and **nothing of ours is lost**. That is the whole reason
the rule exists, and it is also what makes `git diff app/` a one-line proof for
the report that we changed none of his code.

---

## Requirement → phase traceability

Marker to keep the final report honest. Every one of the nine must be
demonstrable, and the grader will look for exactly these.

| # | Requirement | Phase | Primary evidence |
|---|---|---|---|
| 1 | Cloud integration (heavy AWS use) | 04 | CloudFormation stacks; RDS, S3, ECR, ALB, IAM, Secrets Manager live in console |
| 2 | Containerized services | 03 | Two Dockerfiles + compose; final client image has no Node |
| 3 | Continuous Integration | 07 | Push triggers build of both tiers + all suites, results published |
| 4 | Continuous Deployment | 07 | Auto-deploy staging → green → auto-promote prod; red → notify, prod untouched |
| 5 | Testing (≥4 distinct kinds) | 02 | unit / integration / e2e / smoke, all emitting JUnit XML |
| 6 | Automation tool (Jenkins) | 07 | `Jenkinsfile`, multibranch job, published reports |
| 7 | Configuration management (Ansible) | 05 | Idempotent roles; second run reports zero changes |
| 8 | Automated alerting | 08 | Failure email received, with screenshot of inbox |
| 9 | Orchestration (Docker Swarm) | 06 | ≥2 API replicas, rolling update, `docker service rollback` demo |

---

## Phase ↔ the app README's Plan A–F

`app/README.md` describes six **alternative deployment targets**, easy to hard.
You only ever *end* at one — for this assignment, Plan F. Our phases are the
**route** that walks from Plan A to Plan F. Different meaning of the word
"plan"; do not conflate them.

| App README | Our phase | What we do with it |
|---|---|---|
| **Plan A** — run locally | **01** | Do it. Prerequisite for everything |
| **Plan B** — one EC2 instance | **05** | Do it **once by hand**, then automate it in Ansible |
| **Plan C** — split EC2 | **04** | Not built as such; its CORS + `config.js` lesson is required |
| **Plan D** — Docker | **03** | Do it |
| **Plan E** — Docker Compose | **03** | Do it |
| **Plan F** — a real pipeline | **02, 04, 06, 07, 08** | This *is* the assignment |

Plan F's eight sub-directions: CI/CD→07, Ansible→05, IaC→04, orchestration→06,
monitoring→08, load balancing→04, zero-downtime→06, testing→02.

**`plan/app-plans/` holds all six rewritten and condensed** (1417 lines → ~750),
adapted for macOS and for our `app/` subdirectory layout. Read those instead of
scrolling the original, but treat the original as the authority.

---

## Phase map and dependencies

```
01 Local baseline  ──┐
                     ├──> 02 Testing ──┐
                     │                 │
                     └──> 03 Containers├──> 07 Jenkins CI/CD ──> 08 Alerting
                                │      │            ▲
                                │      │            │
          04 AWS infrastructure ┴──────┴──> 05 Ansible
                                │
                                └──> 06 Orchestration ──────────┘

                                             09 Verification & demo (last)
```

Hard ordering rules:

- **02 before 07.** CI with nothing to run is not CI. Tests exist first.
- **03 before 06.** You cannot orchestrate images that do not exist.
- **04 before 05 and 06.** Ansible and Swarm both need somewhere to land.
- **06 forces `USE_S3=True`.** The second replica breaks product images. That
  is the assignment's planted lesson — see 06.
- **09 last**, but read it at the start: it lists the screenshots and logs to
  capture *as you go*. Evidence recreated at the end always looks recreated.

---

## Decisions — all settled

| # | Decision | Answer |
|---|---|---|
| 1 | AWS account type | AWS Academy **Learner Lab** |
| 2 | Orchestrator | **Docker Swarm on EC2.** EKS rejected — see below |
| 3 | IaC tool | **CloudFormation** (AWS-native, no state backend to babysit) |
| 4 | Jenkins location | **Its own EC2 instance**, provisioned by Ansible (Phase 05) |
| 5 | Secret store | **SSM Parameter Store** (app config) + **Jenkins credentials** (pipeline tokens) |

Nothing is blocked. Start Phase 01.

### Why Swarm and not EKS

Requirement 9 accepts "Docker Swarm or Kubernetes" — **they are worth the same
marks**. The deciding factor was cost against a fixed Learner Lab budget: an EKS
control plane bills **$0.10/hour continuously**, because it is AWS-managed and
keeps running while the lab session is closed and the EC2 instances are stopped.
That is ~$2.40/day for the life of the project, and it would have been the
single largest line item. Swarm runs on the EC2 we already need, stops with the
session, and costs nothing idle.

Secondary reasons, all pointing the same way: `LabRole` blocks the IAM and OIDC
provider creation that IRSA needs, so pods would have fallen back to node-role
S3 access anyway; `eksctl` wants to create IAM roles it cannot; and the AWS Load
Balancer Controller hits the same wall.

**Write this up as a deliberate decision, not an omission.** Engineering under a
constrained environment is a legitimate trade-off and reads far better than a
half-finished EKS cluster.

---

## Where each phase runs

Only Phase 01 happens on a laptop. **Everything else runs on Amazon Linux 2023
EC2 instances.**

| Phase | Runs on |
|---|---|
| 01 Local baseline | Your Mac (`app-plans/plan-a-local-macos.md`) |
| 02 Testing | Written on the Mac, **executed by Jenkins on AL2023** |
| 03 Containers | Images **built on AL2023**, not on the Mac — see below |
| 04 AWS infrastructure | CloudFormation from the Mac; resources are AL2023 |
| 05 Ansible | Controller on the Jenkins box; targets are AL2023 |
| 06 Swarm | 3 × AL2023 (1 manager, 2 workers) |
| 07 Jenkins | Dedicated AL2023 instance |
| 08 Alerting | Jenkins + SES |

### The architecture trap this creates

**Your Mac is Apple Silicon (arm64). AL2023 on `t3.*` is x86_64.** A
`docker build` on the Mac produces an **arm64 image that will not run on the
EC2 nodes** — it fails with `exec format error`, which reads like a corrupt
image rather than a wrong architecture.

Rules that avoid it:

- **Real images are built by Jenkins on AL2023.** That is the pipeline's job
  anyway, and it removes the problem entirely.
- Building on the Mac for a quick local test is fine — Compose runs it natively.
- If you must push a Mac-built image to ECR, force the target architecture:
  `docker build --platform linux/amd64 ...` (slow, emulated).
- Check any suspect image: `docker image inspect <img> --format '{{.Architecture}}'`

Instance sizing: **`t3.small` minimum** for anything that builds the frontend.
`npm run build` gets OOM-killed on `t3.micro` — the README says so, and the
right answer is to build in CI and ship only the resulting image.

---

## Target repo layout when all phases are done

```
.
├── app/                     # Tom's app — vendored upstream, we add nothing
├── tests/
│   ├── e2e/                 # Playwright specs (journeys A–F)
│   └── smoke/               # post-deploy probe checks
├── docker/
│   ├── api.Dockerfile
│   ├── client.Dockerfile
│   ├── nginx.conf
│   └── entrypoint-config.sh
├── docker-compose.yml
├── ansible/
│   ├── inventory/
│   ├── roles/
│   └── site.yml
├── cloudformation/          # AWS-native IaC (decision 3)
│   ├── 01-network.yml
│   ├── 02-data.yml
│   └── 03-compute.yml
├── swarm/                   # stack.yml (decision 2)
├── Jenkinsfile
├── plan/                    # this folder — git-ignored, working notes only
└── README.md                # the deliverable write-up
```

---

## Standing gotcha index

**This is a debugging lookup table, not a reading list.** When something breaks,
match the symptom in the left column *before* you start investigating — every
entry is a failure whose symptom points somewhere other than its cause, which
is exactly the kind that burns an afternoon.

They are collected here because they are the app's *planted teaching devices*:
`app/README.md` states outright that several are deliberate lessons rather than
bugs. If you find yourself about to "fix" one inside `app/`, stop — the fix
almost always belongs in our infrastructure, not in Tom's code.

Add a row whenever the team loses more than thirty minutes to something. By
submission this table is also the raw material for the report section that
actually earns marks (see `09`, "The planted lessons").

| Symptom | Cause | Phase |
|---|---|---|
| Container exits instantly on first deploy | `config.settings.prod` fail-fast: `SECRET_KEY` or `ALLOWED_HOSTS` unset | 03 |
| `DisallowedHost` / 400 from the load balancer health check | ALB probes with the instance's **private IP** as `Host`; add it or `.compute.internal` to `ALLOWED_HOSTS` | 04 |
| Every product image 404s after scaling to 2 replicas | Media on local disk. `USE_S3=True` | 06 |
| Product images point at `localhost:8000` | Something rewrote the `Host` header. `changeOrigin: false`, `proxy_set_header Host $host;` | 03, 05 |
| Static files missing under gunicorn | `collectstatic` not run at image build; whitenoise manifest storage raises | 03 |
| Migrations race / deadlock on rollout | `migrate` running once per replica. Run it once per release, as a Job | 06, 07 |
| `/api/version/` reports `dev` | Pipeline never stamped `GIT_COMMIT` at build time | 07 |
| `npm run build` killed on t3.micro | Out of memory. Build in CI, ship `dist/` only | 03, 07 |
| nginx `alias` paths 404 | Our app sits one level deeper than the README assumes — paths need the `app/` prefix | 05 |
| Password reset "sent" but nothing arrives | Mail failures are logged, never raised. A broken mail config is silent | 08 |

---

## Definition of done for the assignment

The pipeline is finished when a team member can, without touching a console:

1. Push a commit to a feature branch → Jenkins builds both tiers, runs four
   kinds of tests, and publishes the results.
2. Merge to `main` → staging deploys automatically, smoke tests pass, and
   production is promoted automatically.
3. Deliberately break a test, push → the build goes red, an email arrives, and
   **production is still serving the previous build** (prove it with
   `/api/version/`).
4. Run one command to roll production back, and confirm the rollback with
   `/api/version/` from outside the box.
5. Scale the API to three replicas and have product images keep working.
