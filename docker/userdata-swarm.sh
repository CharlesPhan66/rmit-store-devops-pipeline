#!/bin/bash
#
# EC2 user data for a Docker Swarm node (manager or worker).
#
# TEMPLATE: fill in NODE_NAME and JENKINS_PUBKEY below before pasting this into
# the launch wizard. It refuses to run with either left at REPLACE-ME.
#
# Everything else is identical for every node in the cluster: manager and worker
# differ only in which `docker swarm` command you run afterwards, not in how the
# host is built.
#
# Runs ONCE, on first boot, as root, with the working directory at /. It is not
# a login shell: there is no sudo, and ~ is /root.
#
# NEVER put a secret in here. User data is readable from inside the instance by
# any process. The public key below is not a secret; the swarm join token is,
# which is why joining the cluster stays a manual step.
#
# Progress and errors land in /var/log/cloud-init-output.log (set -x below).

set -euxo pipefail

# --- Fill these in ---------------------------------------------------------
# One name per node: swarm-mgr, swarm-w1, swarm-w2.
NODE_NAME="REPLACE-ME"

# From `cat ~/.ssh/deploy_rmit.pub` on the Jenkins host. Whole line, including
# the "ssh-ed25519 " prefix and the trailing comment.
JENKINS_PUBKEY="REPLACE-ME"

# Fail on the first boot rather than producing a half-configured node that
# looks fine until it cannot join the cluster.
case "${NODE_NAME}${JENKINS_PUBKEY}" in
  *REPLACE-ME*)
    echo "user-data: placeholders were not filled in" >&2
    exit 1
    ;;
esac

# --- Machine name ----------------------------------------------------------
hostnamectl set-hostname "$NODE_NAME"
echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg

# --- Runtime ---------------------------------------------------------------
dnf update -y
dnf install -y docker git amazon-ecr-credential-helper

# `enable` matters as much as `start`. A node whose Docker did not come back
# after a reboot shows as Down in `docker node ls`, and the cluster quietly
# runs at reduced capacity.
systemctl enable --now docker

usermod -aG docker ec2-user

# --- Let Docker fetch its own ECR token ------------------------------------
# `docker stack deploy --with-registry-auth` copies the manager's registry
# credentials to the workers AT DEPLOY TIME, and an ECR token is valid for 12
# hours. After that, any task Swarm needs to restart — a crashed container, a
# rebooted node — pulls with an expired token and fails with
# `no basic auth credentials`, with no deploy running to blame.
#
# The credential helper removes the expiry entirely: Docker asks for a fresh
# token on every pull, using this instance's IAM profile. No static AWS keys.
install -d -m 700 -o ec2-user -g ec2-user /home/ec2-user/.docker
cat > /home/ec2-user/.docker/config.json <<'JSON'
{
  "credsStore": "ecr-login"
}
JSON
chown ec2-user:ec2-user /home/ec2-user/.docker/config.json
chmod 600 /home/ec2-user/.docker/config.json

# --- Let Jenkins in --------------------------------------------------------
# Jenkins deploys by SSH, not through the Docker API, so every node it touches
# needs this key. Baking it in here beats pasting it into each node by hand.
install -d -m 700 -o ec2-user -g ec2-user /home/ec2-user/.ssh
echo "$JENKINS_PUBKEY" >> /home/ec2-user/.ssh/authorized_keys
chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/authorized_keys

# --- What is deliberately NOT here -----------------------------------------
# `docker swarm init` / `docker swarm join` are manual. The join token is a
# secret — anyone holding it, with a route to port 2377, can join the cluster
# and run containers in it — and user data is world-readable from inside the
# instance. See plan/BUILD.md section 3.2.

echo "user-data completed $(date -Is)" > /etc/motd