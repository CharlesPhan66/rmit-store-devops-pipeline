#!/bin/bash
#
# Author: @CharlesPhan66 (Charles Phan)
# EC2 user data for the Jenkins server.
#
# Runs ONCE, on first boot, as root, with the working directory at /. It is
# not a login shell: there is no sudo, and ~ is /root.
#
# Progress and errors land in /var/log/cloud-init-output.log (set -x below).
#
# Instance sizing: t3.small or larger. t3.micro runs out of memory during the
# frontend image build, and its /tmp (see below) is only 475M.

set -euxo pipefail

# --- Machine name ----------------------------------------------------------
hostnamectl set-hostname jenkins-server
echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg

# --- /tmp must be large enough BEFORE Jenkins starts -----------------------
echo "tmpfs /tmp tmpfs defaults,size=3G 0 0" >> /etc/fstab
mount -o remount /tmp

# --- Runtimes --------------------------------------------------------------
dnf update -y
dnf install -y git docker java-21-amazon-corretto

systemctl enable --now docker

# --- Jenkins ---------------------------------------------------------------
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

# The pipeline shells out to the docker CLI as the `jenkins` user. Group
# membership only takes effect for processes started afterwards, which is why
# this line comes before `systemctl enable --now jenkins` below.
usermod -aG docker jenkins

systemctl enable --now jenkins

# --- What still has to be done by hand -------------------------------------
# This script gets the host ready; it does not configure Jenkins itself.
# Remaining steps, all through the web UI on port 8080:
#
#   1. Unlock:  cat /var/lib/jenkins/secrets/initialAdminPassword
#   2. Install suggested plugins, then add: Docker Pipeline, Email Extension,
#      SSH Agent, Pipeline Stage View, Timestamper
#   3. Create credentials: dockerhub, app-host-key, github-key, smpt-username
#   4. SMTP in BOTH mail blocks, plus System Admin e-mail address
#   5. Create the Multibranch Pipeline job
#

echo "user-data completed $(date -Is)" > /etc/motd
