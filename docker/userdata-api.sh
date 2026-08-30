#!/bin/bash
#
# EC2 user data for the API host.
#
# Runs ONCE, on first boot, as root, with the working directory at /. It is
# not a login shell: there is no sudo, and ~ is /root — which is why cloning
# the repo is left to a human afterwards.
#
# NEVER put a secret in here. User data is readable from inside the instance
#
# Progress and errors land in /var/log/cloud-init-output.log (set -x below).

set -euxo pipefail

# --- Machine name ----------------------------------------------------------
# preserve_hostname is not optional.
hostnamectl set-hostname api-server
echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg

# --- The only runtime this host needs --------------------------------------
# No python, no nginx, no postgresql client. Everything the application needs
# lives inside the image; the host runs containers and nothing else.
dnf update -y
dnf install -y docker git

systemctl enable --now docker

# Lets ec2-user run docker without sudo from the very first login, so there is
# no "log out and back in for the group to take effect" step.
usermod -aG docker ec2-user

# This is the last line of the script. It writes a message to /etc/motd (message of the day) indicating that the user-data script has completed, along with the current date and time in ISO 8601 format. This message will be displayed to users when they log in to the instance.
# Optional but helpful for debugging
echo "user-data completed $(date -Is)" > /etc/motd
