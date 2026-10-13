# Code-OSS on EC2 behind CloudFront

A single CloudFormation template that stands up a browser-based
**Code-OSS / code-server** development environment on an EC2 instance, fronted
by **Amazon CloudFront** (HTTPS in the browser), and pre-loaded with a common
developer toolchain: **Docker, kubectl, eksctl, Helm, AWS CLI v2**, and
**Python 3** (`python3`, with a `python` alias).

It gives you a full VS Code-style IDE and terminal in the browser, backed by a
real Linux machine in your AWS account — useful whenever you want a consistent,
disposable cloud dev environment you can reach from any browser without
installing anything locally. Typical uses:

- A cloud workstation you can open from a laptop, tablet, or borrowed machine.
- A throwaway sandbox for experimenting with Docker, Kubernetes, or the AWS CLI.
- A shared, reproducible environment for workshops, demos, or onboarding.
- A pre-configured box so you don't have to set up tooling on every new machine.

Deploy the stack, open the URL, log in with a generated password, and you have
a full terminal with everything installed — no local setup required.

---

## Architecture

```
          HTTPS                         HTTP :8080
Browser ─────────────► CloudFront ──────────────────► EC2 (code-server)
        (*.cloudfront.net cert)   (origin-facing          Amazon Linux 2023
                                   prefix list only)       Docker / kubectl /
                                                           eksctl / Helm / AWS CLI
                                                           Python 3
```

- **CloudFront** terminates TLS for the browser using its default
  `*.cloudfront.net` certificate and proxies to the instance over HTTP on port
  8080. WebSockets (needed by the editor's terminal and file sync) are
  supported via the `CachingDisabled` + `AllViewer` managed policies.
- **The instance is not open to the internet.** Its security group only allows
  port 8080 from CloudFront's **origin-facing managed prefix list**. Shell
  access is via **SSM Session Manager** — no SSH, no port 22, no key pair.
- A small **Lambda-backed custom resource** resolves the CloudFront prefix-list
  ID at deploy time (it differs per partition).
- The code-server **login password** is generated on the instance and stored in
  **SSM Parameter Store** (SecureString) — never baked into the template.
- A **`CreationPolicy` + `cfn-signal`** gate means the stack only reaches
  `CREATE_COMPLETE` once code-server is actually serving — a failed bootstrap
  fails the stack instead of silently returning errors.

---

## What's installed

| Tool | Notes |
|------|-------|
| Code-OSS (code-server) | Browser IDE, runs as a systemd service for the `coder` user |
| Docker | Daemon enabled; `coder` is in the `docker` group |
| kubectl | Latest stable, with bash auto-completion + `k` alias |
| eksctl | Latest release, with bash auto-completion |
| Helm | v3, with bash auto-completion |
| AWS CLI | v2 |
| Python 3 | AL2023 system `python3` (3.9), with a convenient `python` alias |

Bash auto-completion for kubectl, eksctl, helm, and docker is configured for
both the `coder` user (editor terminal) and `root` (SSM shell).

---

## Prerequisites

- An AWS account and the **AWS CLI v2** configured with credentials.
- A **VPC** with a **public subnet** (route to an internet gateway and
  auto-assign public IP enabled) — CloudFront reaches the instance via its
  public DNS name.
- Permission to create IAM roles, Lambda, EC2, CloudFront, and SSM resources.

---

## Quick start

### Option A — helper script

```bash
./deploy.sh <vpc-id> <subnet-id> [stack-name] [region]

# example
./deploy.sh vpc-0a03b5275331952f5 subnet-00556ca730a258128 code-oss us-west-2
```

The script creates the stack, waits for `CREATE_COMPLETE`, and prints the
outputs (URL, password command, shell command).

### Option B — raw AWS CLI

```bash
aws cloudformation create-stack \
    --stack-name code-oss \
    --template-body file://code-oss-cloudfront.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=VpcId,ParameterValue=vpc-0a03b5275331952f5 \
        ParameterKey=SubnetId,ParameterValue=subnet-00556ca730a258128 \
    --region us-west-2
```

> **Note:** First creation takes ~10–15 minutes, most of it CloudFront
> propagation. If you open the URL before the instance bootstrap finishes you
> may see a CloudFront **502/504** — wait and retry.

---

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `VpcId` | `AWS::EC2::VPC::Id` | — (required) | VPC to launch into; must have a public subnet with internet access. |
| `SubnetId` | `AWS::EC2::Subnet::Id` | — (required) | Public subnet (IGW route, auto-assign public IP). |
| `InstanceType` | String | `t3.large` | One of `t3.medium`, `t3.large`, `t3.xlarge`, `m5.large`, `m5.xlarge`. |
| `LatestAmiId` | SSM parameter | latest AL2023 | SSM-resolved latest Amazon Linux 2023 AMI. Leave as default. |
| `VolumeSize` | Number | `50` | Root EBS volume size in GiB (20–500). |

---

## Outputs

After `CREATE_COMPLETE`, the stack exposes:

| Output | What it gives you |
|--------|-------------------|
| `CodeOssUrl` | The HTTPS URL to open Code-OSS in the browser. |
| `GetPasswordCommand` | A ready-to-run command to fetch the login password from SSM. |
| `SessionManagerCommand` | A ready-to-run command to open a shell on the instance (no SSH). |
| `InstanceId` | The EC2 instance ID. |

Retrieve them anytime:

```bash
aws cloudformation describe-stacks \
  --stack-name code-oss --region us-west-2 \
  --query 'Stacks[0].Outputs' --output table
```

### Logging in

1. Open the `CodeOssUrl` value in your browser.
2. Get the password:
   ```bash
   aws ssm get-parameter \
     --name /code-oss/code-server/password \
     --with-decryption --query Parameter.Value --output text \
     --region us-west-2
   ```
   (Replace `code-oss` with your stack name if you changed it.)
3. Open a shell on the box without SSH:
   ```bash
   aws ssm start-session --target <instance-id> --region us-west-2
   ```

---

## Tearing down

### Option A — helper script

```bash
./delete.sh [stack-name] [region]

# example
./delete.sh code-oss us-west-2
```

### Option B — raw AWS CLI

```bash
aws cloudformation delete-stack \
    --stack-name code-oss \
    --region us-west-2

aws cloudformation wait stack-delete-complete \
    --stack-name code-oss \
    --region us-west-2 && echo "DELETE_COMPLETE" || echo "wait returned non-zero"
```

The stack holds nothing stateful — the SSM password parameter is regenerated on
each deploy, so deleting and recreating is safe.

---

## Repository contents

```
.
├── code-oss-cloudfront.yaml   # the CloudFormation template
├── deploy.sh                  # create the stack and print outputs
├── delete.sh                  # delete the stack and wait
└── README.md
```

---

## Security notes

- The instance has **no public ingress** except CloudFront's prefix list on
  8080; there is no SSH access (use SSM Session Manager).
- Browser traffic is HTTPS (CloudFront default cert); the CloudFront→origin hop
  is HTTP over the private path allowed by the prefix list.
- The login password is a generated SecureString in SSM Parameter Store.
- This is a convenient **single-user dev environment** with sensible defaults.
  For longer-lived or production-adjacent use, consider: a custom domain + ACM
  certificate instead of the default CloudFront cert, restricting who can read
  the SSM password parameter, running the instance in a private subnet with a
  CloudFront VPC origin, and stopping or deleting the stack when idle to save
  cost.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| CloudFront returns **502/504** right after deploy | Bootstrap still running (Python compile takes a while). Wait a few minutes and retry. |
| Stack stuck in `CREATE_IN_PROGRESS` on the instance, then fails | `cfn-signal` never arrived — bootstrap error. Check `/var/log/user-data.log` via SSM. |
| Can't fetch the password | Bootstrap hasn't reached the SSM step yet, or wrong stack name in the parameter path. |
| A tool has no auto-completion | Open a **new** shell (completion is sourced from `.bashrc`). |

To inspect the instance:

```bash
aws ssm start-session --target <instance-id> --region us-west-2
sudo cat /var/log/user-data.log        # bootstrap log
systemctl status code-server@coder     # editor service
```
