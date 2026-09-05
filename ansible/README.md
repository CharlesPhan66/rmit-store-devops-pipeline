# G3 Ansible and Docker Swarm

## Purpose

This directory contains the Ansible configuration for the G3 deployment work.

Ansible uses SSH to connect to the EC2 instances defined in the inventory and
allows the team to manage their configuration from one control machine.

## Current status

Completed:

- Ansible structure, safe inventory and EC2 preflight playbook.
- Reusable Docker and application-runtime roles with configurable variables.
- Personal Amazon Linux 2023 testing with `changed=0` on second runs.
- Single-node Docker Swarm rehearsal using a public Nginx image.

Pending production integration:

- Use G1 outputs to configure the production manager and workers.
- Deploy G2 images using the agreed runtime contract.
- Configure Nginx/Gunicorn, migrations, RDS and S3 as required.
- Demonstrate health checks, rolling update, rollback and evidence.

> The single-node Swarm test is a rehearsal, not the production deployment.

## Requirements

- Python 3 and Ansible Core on the control machine.
- SSH access and the correct private key for each target EC2 instance.
- Amazon Linux 2023 target instances.
- Security-group rules that allow SSH from the control machine.

Activate the Ansible virtual environment when required:

```bash
source <PATH_TO_ANSIBLE_VENV>/bin/activate
ansible --version
```

## Development inventory

```bash
cp ansible/inventory/dev.example.ini ansible/inventory/dev.ini
```

Set the target address in `ansible/inventory/dev.ini`:

```ini
[g3_targets]
g3_target ansible_host=<EC2_PUBLIC_IP_OR_DNS> ansible_user=ec2-user ansible_python_interpreter=/usr/bin/python3
```

Never commit `dev.ini`, PEM keys, passwords, AWS credentials or Swarm tokens.

## Run the baseline configuration

Run the connectivity check:

```bash
ansible-playbook -i ansible/inventory/dev.ini \
  ansible/playbooks/preflight.yml \
  --private-key <PATH_TO_PEM_KEY>
```

Expected recap: `unreachable=0` and `failed=0`.

The preflight result confirms that Ansible connected to the target EC2 instance
successfully and that no tasks failed.

Install and configure Docker:

```bash
ansible-playbook -i ansible/inventory/dev.ini \
  ansible/playbooks/docker.yml \
  --private-key <PATH_TO_PEM_KEY>
```

Install the application runtime and PostgreSQL client:

```bash
ansible-playbook -i ansible/inventory/dev.ini \
  ansible/playbooks/runtime.yml \
  --private-key <PATH_TO_PEM_KEY>
```

The PostgreSQL server created on the personal EC2 instance was only for practice.
Production must use the RDS database supplied by G1.

## Idempotency

Run both configuration playbooks a second time. The expected recap is:

```text
changed=0
unreachable=0
failed=0
```

The first playbook run changes the EC2 instance by installing and applying the
required configuration. The second run makes no changes because the instance
already matches the desired state, which keeps the EC2 configuration consistent.

## Docker Swarm rehearsal

The personal EC2 rehearsal initialized one Swarm manager, published Nginx on port
`8080`, and scaled the service between two and three replicas.

A replica is one running instance of a service. Replicas running on the same EC2
instance are not highly available because they all stop if that instance fails.

## Production inputs

G1 must provide manager and worker addresses, SSH access, security-group rules,
RDS details, the S3 bucket and region, IAM details, ECR names and ALB health data.

G2 must provide immutable API and client image tags, container ports, health
endpoints, required environment variables, migration commands and entrypoints.

```text
G1 infrastructure -> Ansible inventory -> Docker/Swarm configuration
G2 images and runtime contract -> migrations -> Swarm stack deployment
Swarm services -> health checks -> rolling update or rollback
```

G1 provides infrastructure such as the EC2 instances and supporting AWS
resources. G2 provides the container images and runtime contract. G3 uses these
outputs with Ansible to configure the EC2 instances, create the Docker Swarm and
deploy the application services to its worker nodes.

## Evidence checklist

- [ ] Preflight succeeds on production targets.
- [ ] Docker and runtime playbooks succeed.
- [ ] Second playbook runs show `changed=0`.
- [ ] Manager and worker nodes appear in the Swarm.
- [ ] The API runs with at least two replicas.
- [ ] Migration and application health checks succeed.
- [ ] RDS and S3 integration is demonstrated.
- [ ] Rolling update and rollback are demonstrated.

## Security

Use private network addresses between Swarm nodes where possible. Store secrets
in the approved AWS secret service or Jenkins credentials, never in Git.
