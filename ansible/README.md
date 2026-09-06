# G3 Ansible and Docker Swarm

## Purpose

This directory contains G3 configuration-management and orchestration work.
Ansible connects to EC2 over SSH and makes every target match the configuration
stored in this repository.

## Status

Completed on a personal Amazon Linux 2023 EC2 instance:
- Safe inventory example and connectivity preflight.
- Reusable roles for Docker, application runtime and Nginx.
- Docker and runtime idempotency: the second run reported `changed=0`.
- Single-node Swarm rehearsal with a public Nginx image.

Prepared but not production-tested:
- Manager/worker inventory and idempotent Swarm join workflow.
- Two-replica rehearsal stack with rolling-update and rollback policies.
- Nginx reverse proxy for Django on port `8000`.

Production integration still needs the G1 infrastructure and G2 images/runtime
contract. The personal single-node rehearsal is not production evidence.

## Requirements

- Python 3 and Ansible Core on the control machine.
- Amazon Linux 2023 targets, the SSH key and SSH access from the controller.
- Private network access between production Swarm nodes.

```bash
source <PATH_TO_ANSIBLE_VENV>/bin/activate
ansible --version
```

## Personal development inventory

```bash
cp ansible/inventory/dev.example.ini ansible/inventory/dev.ini
```

Replace the documentation address in `dev.ini` with the EC2 public IP or DNS.
The real `dev.ini` is ignored by Git.

```ini
[g3_targets]
g3_target ansible_host=<EC2_ADDRESS> ansible_user=ec2-user ansible_python_interpreter=/usr/bin/python3
```

## Run Requirement 7 baseline

Use the same command pattern for every playbook:

```bash
ansible-playbook -i ansible/inventory/dev.ini \
  ansible/playbooks/<PLAYBOOK>.yml \
  --private-key <PATH_TO_PEM_KEY>
```

| Playbook | Purpose |
| --- | --- |
| `preflight.yml` | Test SSH and display target facts |
| `docker.yml` | Install, start and enable Docker |
| `runtime.yml` | Install Git, Python, pip and PostgreSQL client |
| `nginx.yml` | Install Nginx and its Django proxy configuration |
| `site.yml` | Apply Docker, runtime and Nginx together |
| `verify.yml` | Verify services, runtimes, Nginx and HTTP |

Run the combined configuration with `<PLAYBOOK>` set to `site`. The Nginx root
page is a standalone rehearsal check. API proxy routes may return `502` until G2
provides the Django service on port `8000`.

The proxy preserves the original host with `proxy_set_header Host $host`, which
prevents Django from generating URLs for the wrong host.

## Idempotency

Run `site.yml` twice against the same target. The second recap should contain:

```text
changed=0
unreachable=0
failed=0
```

The first run installs missing configuration; the second changes nothing because
the target already matches the declared state.

## Prepare a production-like Swarm

```bash
cp ansible/inventory/swarm.example.ini ansible/inventory/swarm.ini
```

Replace all example public addresses with G1 outputs. Ansible automatically uses
each manager's private default address as its Swarm advertise address.

Required security-group traffic between Swarm nodes:

- TCP `2377` for cluster management.
- TCP/UDP `7946` for node communication.
- UDP `4789` for overlay networking.

Check the inventory and create the cluster:

```bash
ansible-inventory -i ansible/inventory/swarm.ini --graph
ansible-playbook -i ansible/inventory/swarm.ini \
  ansible/playbooks/swarm.yml --syntax-check
ansible-playbook -i ansible/inventory/swarm.ini \
  ansible/playbooks/swarm.yml --private-key <PATH_TO_PEM_KEY>
```

The manager creates the worker token at runtime. Ansible masks it with `no_log`
and never writes it into Git. The optional public-image rehearsal runs two Nginx
replicas on port `8080`:

```bash
ansible-playbook -i ansible/inventory/swarm.ini \
  ansible/playbooks/swarm_rehearsal.yml \
  --private-key <PATH_TO_PEM_KEY>
```

## Production inputs

G1 must provide manager/worker addresses, SSH access, security-group rules, RDS
endpoint, S3 bucket/region, IAM access, ECR names and load-balancer health data.

G2 must provide immutable API/client image tags, ports, health endpoints,
environment-variable names, entrypoints and the one-shot migration command.

```text
G1 infrastructure -> Ansible inventory -> Docker/Swarm configuration
G2 images + runtime contract -> migration -> application stack deployment
Swarm services -> health checks -> rolling update -> rollback
```

## Evidence checklist

- [ ] Production preflight has `unreachable=0` and `failed=0`.
- [ ] Second configuration run has `changed=0`.
- [ ] One manager and all workers are `Ready`.
- [ ] API runs with at least two replicas.
- [ ] One-shot migration and application health checks succeed.
- [ ] Both replicas serve the same product image with `USE_S3=True`.
- [ ] A rolling update and rollback are demonstrated.

## Security

Never commit real inventories, PEM keys, passwords, AWS credentials, database URLs or Swarm tokens. Use approved AWS secret storage or Jenkins credentials.
