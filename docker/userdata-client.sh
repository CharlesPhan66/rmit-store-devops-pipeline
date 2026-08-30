#!/bin/bash
#
# EC2 user data for the frontend host (Plan D, machine ②).
#
# Paste into the launch wizard under Advanced details -> User data, or:
#     aws ec2 run-instances --user-data file://docker/userdata-client.sh ...
#
# Runs ONCE, on first boot, as root, with the working directory at /. It is
# not a login shell: there is no sudo, and ~ is /root — which is why cloning
# the repo is left to a human afterwards.
#
# NEVER put a secret in here. User data is readable from inside the instance
# by any process, with no privileges required:
#     TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token \
#              -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
#     curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
#          http://169.254.169.254/latest/user-data
#
# Progress and errors land in /var/log/cloud-init-output.log (set -x below).

set -euxo pipefail

# --- Machine name ----------------------------------------------------------
# preserve_hostname is not optional. cloud-init's update_hostname module runs
# on EVERY boot and resets the hostname from instance metadata, so without it
# the name set here is gone after the first stop/start — which on Learner Lab
# means every session.
hostnamectl set-hostname client-server
echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg

# --- The only runtime this host needs --------------------------------------
# No node, no npm, no nginx. Everything the application needs
# lives inside the image; the host runs containers and nothing else.
dnf update -y
dnf install -y docker git

# `enable` so the daemon comes back on its own every time the instance starts.
# Without it, `docker run --restart unless-stopped` has nobody to restart it.
systemctl enable --now docker

# Lets ec2-user run docker without sudo from the very first login, so there is
# no "log out and back in for the group to take effect" step.
usermod -aG docker ec2-user

echo "user-data completed $(date -Is)" > /etc/motd
