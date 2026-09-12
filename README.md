# [Project Title]

## 1. Project Information

**Course:** COSC2767 - Systems Deployment and Operations

**Assignment:** [Date]

**Student Name(s) (sid):**
- Phan Huynh Ba Khang (s4131861)
- Tu Tuan Hung
- Nguyen Cong Quoc Dat
- 
- 

**Instructor:** Tom Huynh

---

## 2. Reproducing the Pipeline on a Clean AWS Account

Everything below assumes a **blank AWS account** and a clean checkout of this repository. No step requires the AWS Console — every resource is created by CloudFormation, Ansible, or the pipeline itself.

### 2.1 Prerequisites

| What | Notes |
|---|---|
| An AWS account | Built and tested against an **AWS Academy Learner Lab** (`LabRole`, no IAM role creation). Any account with equivalent EC2/RDS/S3/ECR/SSM/IAM-instance-profile permissions works. |
| `aws` CLI v2, configured | `aws sts get-caller-identity` must return a valid `Account`. Learner Lab sessions expire after ~4 hours — re-check this first if a later step fails with a credentials error. |
| `git` | To clone this repo and push to trigger builds. |
| A terminal (`zsh`/`bash`) | Every command below is written for one. |
| An EC2 key pair | `aws ec2 create-key-pair --key-name devops_project_key --query KeyMaterial --output text > ~/.ssh/devops_project_key.pem && chmod 400 ~/.ssh/devops_project_key.pem`. Used only for manual SSH debugging — no component of the pipeline depends on it; Ansible and Jenkins each generate their own operational keys. |
| A Gmail account (Because learner lab doesn't grant access to SES, but if you prefer to use another SMTP provider, just use a different one) | For Jenkins build/deploy alert email and the app's own transactional mail. Needs an [App Password](https://myaccount.google.com/apppasswords), not the account password (This is the case for learner labs). |

Total time: roughly 45–60 minutes, most of it waiting on CloudFormation and the first Jenkins build.

### 2.2 Order of operations

Six EC2 instances, one per role (`ansible`, `jenkins`, `staging`, one Swarm
manager, two Swarm workers), wired together with **no hardcoded addresses**:
CloudFormation writes every address to **SSM Parameter Store**; Ansible and
Jenkins both read from there. Run the steps in this order — later steps
`ImportValue`/look up what earlier steps produced.

```
CloudFormation (4 stacks, in order) ──> Secrets script ──> Ansible ──> Jenkins (manual, once at first setup) ──> git push to trigger or manual "Build Now"
```

**1. CloudFormation — four stacks, this exact order**

Let's say you are standing in the root of this repo:
```bash
cd cloudformation
```
1. network.yml --> stack rmit-network
This creates the VPC, subnets, and security groups. The `AdminCidr` parameter limits SSH to your current IP address (Therefore, if your IP changes, you must re-run this step to update the security group, so that you can still SSH in ansible to debug manually or open Jenkins GUI at port 8080 of Elastic IP of the Jenkins instance). The stack name is `rmit-network`.
```bash
aws cloudformation deploy --template-file network.yml --stack-name rmit-network \
  --parameter-overrides AdminCidr=$(curl -s https://checkip.amazonaws.com)/32
```

2. bootstrap.yml -> stack rmit-bootstrap
This creates 1 EC2 instance, the Ansible control node, in the public subnet. At this point, the stack generates an SSH keypair for Ansible and publishes the public half to SSM at `/rmit/ANSIBLE_PUBKEY`. The next step, `compute.yml`, installs that key on the five other machines, so this MUST finish first. The stack name is `rmit-bootstrap`.
```bash
aws cloudformation deploy --template-file bootstrap.yml --stack-name rmit-bootstrap \
  --parameter-overrides KeyPairName=devops_project_key

until aws ssm get-parameter --name /rmit/ANSIBLE_PUBKEY >/dev/null 2>&1; do sleep 15; done
```
3. data.yml -> stack rmit-data
RDS PostgreSQL, S3 media bucket, ECR repositories. Run once.
There are 2 prompts for these instead of leaving a placeholder in the command, so there is nothing to forget to edit before pasting.
RDS_PASS must be letters and digits only, no @:/#, and it's up to you to choose a unique suffix for the S3 bucket name, the prefix is `rmit-store-media-` and the suffix can be your id or any unique string.
```bash
read -rs "DB_PASS?RDS master password (letters and digits only, no @:/#): "; echo
read "BUCKET_SUFFIX?Unique suffix for the S3 bucket name (e.g. your student id): "

aws cloudformation deploy --template-file data.yml --stack-name rmit-data \
  --parameter-overrides DbPassword="$DB_PASS" \
                         MediaBucketName="rmit-store-media-$BUCKET_SUFFIX"

```
4. compute.yml -> stack rmit-compute
The five remaining EC2 instances and the Application Load Balancer.
It will fetch the Ansible public key from SSM and install it on the five instances, so this MUST run after `bootstrap.yml` finishes.
```bash
aws cloudformation deploy --template-file compute.yml --stack-name rmit-compute \
  --parameter-overrides KeyPairName=devops_project_key
```

Verify: `aws cloudformation describe-stacks --query 'Stacks[].[StackName,StackStatus]' --output table`
— all four `CREATE_COMPLETE`.

**2. Secrets — `scripts/put-secrets.sh`**

Other keys have been published to SSM are `String` types and `StringList` types, which are pushed during the deployment process by CloudFormation, but CloudFormation cannot create `SecureString` SSM parameters, so we have the script to read the keys from the user and push them to SSM as `SecureString` parameters. The script is idempotent — it will not overwrite an existing `SECRET_KEY`, so it is safe to re-run if you need to add or change other secrets.

```bash
./scripts/put-secrets.sh
```

Prompts for the RDS master password (must match `DbPassword` above), the staging/production admin passwords, and the alert email address. Safe to re-run — `SECRET_KEY` is created once and never overwritten.

**3. Ansible — configure all six hosts**

Run belows commands on your local machine to easily have the IP address and scp (copy folder ansible over to the ansible host using ssh) and ssh into the ansible host (OR you can open the AWS console to view the instances to get connection ssh command). Then run the ansible-playbook commands on the ansible host to configure all six hosts.
```bash
IP=$(aws ec2 describe-instances \
       --filters Name=tag:Role,Values=ansible Name=instance-state-name,Values=running \
       --query 'Reservations[].Instances[].PublicIpAddress' --output text)
scp -i ~/.ssh/devops_project_key.pem -r ansible ec2-user@$IP:~/
ssh -i ~/.ssh/devops_project_key.pem ec2-user@$IP
```

On the control node, navigate to the `ansible` folder and run the following commands to check syntax, ping all five targets (exclude itself), and run the playbook twice (the second run should report `changed=0` for idempotency)
This installs Docker + the Compose plugin on all five container hosts, installs Java/AWS CLI/Jenkins on the Jenkins host, initializes the Docker Swarm cluster, creates the production Swarm secrets from SSM, and authorizes the Jenkins host's SSH key on the staging and Swarm hosts.

```bash
cd ~/ansible
ansible-playbook site.yml --syntax-check
ansible 'all:!tag_Role_ansible' -m ping        # all five targets must go green
ansible-playbook site.yml                      # first run
ansible-playbook site.yml                      # second run must report changed=0
```

**4. Jenkins — the one manual step**

Everything above is scriptable; Jenkins' own first-run wizard is not, and needs a Google App Password that only exists after a human visits Google's UI. See **2.4** below for exactly what to configure and **2.3** for the required credential IDs.

**5. Trigger the pipeline** — see **2.5**.

### 2.3 Required Jenkins credentials, by ID

The `Jenkinsfile` and the email configuration expect these two credentials to
exist under exactly these IDs — nothing else needs a credential in the
Jenkins store (deploying to staging/Swarm authenticates over SSH using the
key Ansible generated for the `jenkins` OS user in §2.2 step 3, not a Jenkins
credential).

| ID | Kind | Used for |
|---|---|---|
| `gmail-smtp` | Username with password | SMTP auth for Extended E-mail Notification (build/test/deploy failure alerts, §2.3 step 5). Username = full Gmail address; password = a 16-character Google App Password, no spaces. |
| `github-pat` (HTTPS) **or** `github-ssh` (SSH) | Username with password / SSH Username with private key | `checkout scm` — Jenkins reading this repository. Pick one and match it to the Repository URL scheme in the job (§2.3 step 7). |

> Note: If you use SSH instead of HTTPS for GitHub, you must create a keypair on Jenkins and add the public half to your GitHub account. You don't have to SSH into the Jenkins host to do this, you can take advantage of Ansible, which have the control over the Jenkins host and can run commands on it:
> ```bash
> ansible tag_Role_jenkins -b -m shell -a \
> 'sudo -u jenkins ssh-keygen -t ed25519 -f /var/lib/jenkins/.ssh/id_ed25519_github -N "" -C "jenkins-github-checkout"'
>
> ansible tag_Role_jenkins -b -a 'cat /var/lib/jenkins/.ssh/id_ed25519_github.pub'
> ```

Copy the output of the second command and add it to your GitHub account as a new SSH key. Then use `github-ssh` as the credential ID in Jenkins.

### 2.4 Jenkins setup

1. Get the URL (Both CLI and AWS Console are good, it's your choice): 
```bash
aws ssm get-parameter --name /rmit/JENKINS_PUBLIC_IP --query Parameter.Value --output text
```
It returns the public IP of the Jenkins instance, which you can paste into a browser to reach the Jenkins GUI at `http://<above-returned-ip>:8080/`. The first time you visit, it will ask for the initial admin password.
2. Unlock with the initial admin password, retrieved through Ansible rather than SSH'ing directly to the Jenkins server. On the terminal sshed to the Ansible control node, run:
```bash
  ansible tag_Role_jenkins -b -a 'cat /var/lib/jenkins/secrets/initialAdminPassword'
```
3. **Install suggested plugins** (already covers everything the `Jenkinsfile` needs: Pipeline, `git`, `github`, `junit`, `credentials`, `email-ext`).
4. **Configure timezone and admin password** — Jenkins → Profile → Preferences → Time Zone: *UTC*; Jenkins → Profile → Configure → Password: set a strong password for the `admin` user then login again at `http://<above-returned-ip>:8080/`.
5. **Configure Email Notification**
Because this stack uses Gmail for email notifications, this instruction is for Gmail SMTP configuration:
  5.1 Get App Password from Gmail account (https://myaccount.google.com/apppasswords) and copy it to clipboard (Make sure you have your account set up for 2-step verification, if not, please visit https://myaccount.google.com/security to enable it first).
  5.2 Go to https://myaccount.google.com/apppasswords and generate a new app password
  5.3 Store the return 16-character password to configure Jenkins credential `gmail-smtp` in **2.3**
  > Note: Please remove any spaces in the 16-character password when you copy it to Jenkins credential `gmail-smtp`.
  5.4 In the section of Extended E-mail Notification, configure as below:
  - SMTP server: `smtp.gmail.com`
  - SMTP port: `587`
  - Credential: `gmail-smtp` (the credential you created in **2.3**)
  - TLS/SSL: ☑ **Use TLS** (Do not use SSL)
  - Default Recipients: For markers, you can use your Gmail address to receive the email notification.
  5.5 (Optional) Test the configuration by clicking **Test configuration by sending test e-mail**, then fill in the test email details (The same as above for **Extended E-mail Notification**, however, you cannot choose credential, you have to fill directly the username, which is your Gmail address, and the password, which is the app password you generated with no spaces). If you receive the email, it means the configuration is correct.
6. **Create a new Job item**:
  - Item name: `rmit-store` or any name you like
  - Type: *Pipeline*
  - **OK**
  In the Pipeline configuration page, configure as below:
  | Setting | Value |
  |---|---|
  | Definition | *Pipeline script from SCM* |
  | SCM | *Git* |
  | Repository URL | This repo's URL (Please find it at GitHub.txt from submission zip file) |
  | Credentials | `github-pat` or `github-ssh` (match the scheme of the Repository URL) |
  | Branch Specifier | `*/main` |
  | Script Path | `Jenkinsfile` |
  | Lightweight checkout | ☑ **Lightweight checkout** |

  Then **Save** the job.
7. Webhook setup:
> Thanks to Elastic IP, the Jenkins host is reachable from the public internet over many launches of Learner Lab.
You may find the Elastic IP of the Jenkins host from SSM quickly by:
```bash
aws ssm get-parameter --name /rmit/JENKINS_PUBLIC_IP \
  --query Parameter.Value --output text
```
Then on GitHub, navigate to this repository → **Settings** → **Webhooks** → **Add webhook**:
| Setting | Value |
|---|---|
| Payload URL | `http://<jenkins-elastic-ip>:8080/github-webhook/` (trailing slash required) |
| Content type | `application/json` |
| Event | *Just the push event* |
Left the other options as default, then **Add webhook**.
Navigate to the webhook's page and click **Redeliver** to test whether it returns 200.

### 2.5 Triggering a deploy

You have two ways to trigger the pipeline:
1. Push a new commit to `main`
  1.1 You may push a commit with real changes as normal
  ```bash
  git push origin main
  ```
  1.2 Or, if you just want to trigger a build without changing any files, you can make a dummy commit:
  ```bash
  git commit --allow-empty -m "Trigger Jenkins build"
  git push
  ```

2. To trigger manually without a push: Jenkins → `Your job item` → **Build Now**.

Confirm which build is live from outside the box:

```bash
ALB=$(aws ssm get-parameter --name /rmit/prod/ALB_DNS --query Parameter.Value --output text)
curl -s "http://$ALB/api/version/"
```

### 2.6 Confirming a deploy
In real production, we do not need to open the port for you to visit the staging url, but for the purpose of this assignment, we will open the port for you to visit the staging url to confirm staging is working correctly before the work is published. 
1. Staging
You can find the staging url from SSM by:
```bash
aws ec2 describe-instances \
  --filters Name=tag:Role,Values=staging Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].PublicIpAddress' --output text
```
Then you can visit the staging url in your browser: `http://<staging-public-ip>:8081/`

2. Production
You can find the production url (It's alb dns) from SSM by:
```bash
aws ssm get-parameter --name /rmit/prod/ALB_DNS --query Parameter.Value --output text
```
Then you can visit the production url in your browser: `http://<alb-dns>/

### 2.7 Triggering a rollback
Actually, when a trigger fails to attempt to deploy, the production will not be affected because it will not be deployed to production, and the production is still the latest successful build. However, if you want to rollback to the previous build or any older build, you can do it by the following ways:

**Production (Docker Swarm)** — instant, no rebuild:
1. Rollback to the previous task definition of each service:
```bash
# on the Swarm manager
docker service rollback rmit_api
docker service rollback rmit_client
```

Swarm reverts each service to its previous task definition. Alternatively,
re-run the Jenkins job at an older commit — ECR keeps the last 10 images per
service, tagged by short commit SHA, so any recent release can be redeployed.

```bash
# on the staging host, in ~/deploy
ECR=<registry> IMAGE_TAG=<older-sha> \
  docker compose --env-file compose.env -f docker-compose.prod.yml up -d
```

Either way, confirm the rollback the same way a deploy is confirmed — `curl
.../api/version/` from outside the instance, not the color of the Jenkins
build.

2. Rebuild and redeploy an older commit (You can run from ansible host, no need to SSH into Jenkins host):
```bash
ansible tag_Role_jenkins -b -m shell -a \
  'cd /var/lib/jenkins/workspace/rmit-store && git checkout <older-sha> && git reset --hard && git clean -fdx && git pull origin main'
``` 
Then trigger the build manually from Jenkins GUI

---
