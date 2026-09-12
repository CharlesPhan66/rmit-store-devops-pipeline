<!--
  RMIT University Vietnam
  Course: COSC2767|COSC2805 Systems Deployment and Operations
  Semester: 2026B
  Assessment: Assignment 2
  Author: Tu Tuan Hung - 4130499
  Created date: 06/09/2026
  Last modified: 08/09/2026
  Acknowledgement: None
-->

# Ansible Configuration and Docker Swarm

## Scope

This directory implements two assignment requirements:

- Requirement 7: configure EC2 hosts with idempotent Ansible roles.
- Requirement 9: create Docker Swarm, run at least two API replicas, and prove rolling update and rollback.

The Ansible work does not build images or configure Jenkins. G2 supplies the deployment contract; G5 runs CI/CD.

```text
G1 infrastructure -> Ansible inventory -> configure EC2 -> Docker Swarm
G2 images + runtime contract -----------------------------^        |
G5 Jenkins --------------------------------------------------------+-> deploy
```

## What is implemented

- Dynamic EC2 inventory based on G1 `Role` or `Name` tags.
- Preflight validation and SSH connectivity checks.
- Reusable Docker installation and configuration role.
- Staging runtime role for Python 3.11, pip and PostgreSQL client.
- Staging environment file rendered from SSM Parameter Store.
- Automatic Swarm manager initialization and worker joining.
- Swarm secrets created from SSM without committing secret values.
- Production stack for two API replicas and two client replicas.
- One-shot database migration before each production deployment.
- S3-backed shared media and rolling-update/rollback policies.
- Verification playbook for Docker, staging files, nodes and secret names.

The roles are idempotent. The second unchanged run should report `changed=0`.

## Inputs from teammates

G1 must provide:

- Running staging, Swarm manager and Swarm worker EC2 instances.
- Stable `Role` or `Name` tags matching the inventory groups.
- SSH access from the Ansible controller and the correct private key.
- Security-group rules for SSH and Swarm ports.
- IAM permission for EC2 discovery and SSM reads.
- RDS, S3 and the required SSM parameters.

G2 must provide:

- Immutable API and client image names/tags.
- The Compose/runtime contract that the Ansible deployment adapts into `swarm/stack.yml`.
- Health endpoints and the one-shot migration command.

## Layout

```text
ansible/
├── ansible.cfg, requirements.yml, inventory/, group_vars/
├── preflight.yml, site.yml, verify.yml
└── roles/{docker,app,swarm}/
```

## Controller setup

Run these commands on the Ansible controller, not on a managed target:

```bash
cd ansible
python3 -m pip install --user ansible-core boto3 botocore
ansible-galaxy collection install -r requirements.yml
aws sts get-caller-identity
```

`ansible.cfg` expects the SSH key at `~/.ssh/ansible_rmit` and connects as
`ec2-user`. Change those settings only if G1 supplies a different contract.

Never commit PEM keys, passwords, AWS credentials, SSM values or Swarm tokens.

## Discover and test the hosts

```bash
ansible-inventory --graph
ansible-playbook preflight.yml
```

Required groups are `tag_Role_staging`, `tag_Role_swarm_manager` and
`tag_Role_swarm_worker`. Continue only when preflight reports
`unreachable=0` and `failed=0`.

## Requirement 7 — configuration management

Configure Docker, the staging runtime and the Swarm hosts:

```bash
ansible-playbook site.yml
ansible-playbook site.yml
```

The first run may change the new machines. Save the recap from the second run;
it should show `changed=0`, proving that Ansible preserves the desired state.

## Requirement 9 — orchestration

`site.yml` automatically initializes the manager, retrieves the worker join
token securely and joins every worker. Confirm the result with:

```bash
ansible-playbook verify.yml
```

Validate the integrated G1/G2 contract before changing production:

```bash
ansible-playbook contract.yml
```

The command confirms the production topology, reads the required SSM
parameters without printing secrets, and lists the newest API/client image
tags in ECR. Select the same immutable tag that G2/G5 built for both images.

Deploy with that exact tag:

```bash
ansible-playbook deploy.yml -e image_tag=<GIT_SHA>
```

`deploy.yml` validates the images, runs `python manage.py migrate` in one
temporary service, deploys the stack, waits for every replica, and checks
`/readyz/` and `/api/version/`. The deployment evidence then proves:

- Every expected node is `Ready` in `docker node ls`.
- The API service has at least two replicas.
- Both replicas serve the same product images with S3 enabled.
- A rolling update changes the application version without dropped requests.
- `docker service rollback` restores the previous working version.
- Database migration runs once, not once per API replica.

## Required SSM parameters

```text
/rmit/ECR_REGISTRY
/rmit/staging/{SECRET_KEY,DATABASE_URL,MEDIA_BUCKET}
/rmit/prod/{ALB_DNS,MEDIA_BUCKET}
/rmit/prod/{SECRET_KEY,DATABASE_URL}
```

## Remaining integration work

- Run all playbooks against the final G1 infrastructure.
- Confirm the deployed G1 tags and SSM contract with `contract.yml`.
- Select one image tag that exists in both G2 ECR repositories.
- Deploy at least two API replicas with `USE_S3=True`.
- Capture idempotency, rolling-update and rollback evidence.

## Evidence checklist

- Inventory graph and successful preflight recap.
- First and second Ansible recaps; second run has `changed=0`.
- Docker running on staging, manager and workers.
- `docker node ls` showing one manager and all workers `Ready`.
- `docker service ls` showing at least two API replicas.
- Before/after `/api/version/` output during a rolling update.
- Successful rollback output and restored version.
- No secrets, private keys or join tokens visible in Git or screenshots.
