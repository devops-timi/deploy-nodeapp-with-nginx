# Deploy Node.js App with Nginx on AWS EC2

A fully automated CI/CD pipeline that builds, containerizes, and deploys a Node.js application to an AWS EC2 instance, served behind an Nginx reverse proxy. The pipeline is powered by **GitHub Actions**, **Ansible**, **Docker**, and **Amazon ECR**.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Application](#application)
- [Prerequisites](#prerequisites)
- [Infrastructure Setup](#infrastructure-setup)
- [Configuration](#configuration)
- [CI/CD Pipeline](#cicd-pipeline)
- [Ansible Provisioning](#ansible-provisioning)
- [Nginx Reverse Proxy](#nginx-reverse-proxy)
- [Local Development](#local-development)
- [Deployment Flow](#deployment-flow)
- [Secrets Reference](#secrets-reference)

---

## Architecture Overview

```
Internet
   │
   ▼
EC2 Instance (Ubuntu)
   │
   ├── Nginx (Port 80)  ──reverse proxy──►  Node.js App (Port 3000)
   │                                              │
   │                                         Docker Container
   │                                              │
   │                                    Image pulled from AWS ECR
   │
   └── Provisioned & configured via Ansible (run from GitHub Actions)
```

When a push is made to the `main` branch, GitHub Actions:
1. Uses **Ansible** to provision the EC2 instance (install Nginx, Docker, AWS CLI, configure reverse proxy).
2. Builds the Docker image and pushes it to **AWS ECR**.
3. SSHs into the EC2 instance, pulls the latest image, and restarts the container.

---

## Project Structure

```
deploy-nodeapp-with-nginx/
├── .github/
│   └── workflows/
│       └── infrastructure.yml     # GitHub Actions CI/CD pipeline
├── ansible/
│   ├── ansible.sh                 # Script to install Ansible on the runner
│   ├── inventory.ini              # Ansible inventory (EC2 host + SSH config)
│   └── setup-server.yml           # Ansible playbook: installs Nginx, Docker, AWS CLI
└── node-ec2-app/
    ├── Dockerfile                 # Containerizes the Node.js app
    ├── index.js                   # Express server entry point
    ├── package.json               # App dependencies
    └── public/
        ├── index.html             # Served HTML page
        └── style.css              # Stylesheet
```

---

## Application

The Node.js application is a minimal **Express** server that serves a static HTML page.

- **Framework:** Express 4.x
- **Port:** `3000`
- **Entry point:** `index.js`
- **Static files:** served from the `public/` directory

The app responds to all requests at `/` by serving `public/index.html`.

---

## Prerequisites

Before using this project, ensure you have the following:

- An **AWS account** with:
  - An EC2 instance running **Ubuntu** (the pipeline targets `98.81.204.204` — update this to your IP)
  - An **ECR repository** to store the Docker image
  - An **IAM user** with permissions for ECR (push/pull) and EC2 access
- A **GitHub repository** with Actions enabled
- An **SSH key pair** for connecting to your EC2 instance
- The EC2 instance's **security group** must allow inbound traffic on ports `22` (SSH) and `80` (HTTP)

---

## Infrastructure Setup

### 1. Create an ECR Repository

```bash
aws ecr create-repository --repository-name node-nginx-app --region us-east-1
```

Note the repository URI (e.g., `<account-id>.dkr.ecr.us-east-1.amazonaws.com/node-nginx-app`) and update it in `.github/workflows/infrastructure.yml`.

### 2. Launch an EC2 Instance

- AMI: Ubuntu 22.04 LTS (or similar)
- Instance type: `t2.micro` or larger
- Assign an Elastic IP or note the public IP
- Download or create an SSH key pair (`.pem` file)

### 3. Update Configuration Files

Update the EC2 public IP address in two places:

**`ansible/inventory.ini`**
```ini
<YOUR_EC2_IP>  ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/us-connect.pem
```

**`.github/workflows/infrastructure.yml`** — in the `Deploy Container via SSH` step:
```yaml
host: <YOUR_EC2_IP>
```

Also replace the ECR registry URI (`596387592424.dkr.ecr.us-east-1.amazonaws.com`) with your own account's URI throughout the workflow file.

---

## Configuration

### GitHub Secrets

Navigate to your repository's **Settings → Secrets and variables → Actions** and add the following secrets:

| Secret Name           | Description                                              |
|-----------------------|----------------------------------------------------------|
| `SSH_PRIVATE_KEY`     | Contents of your EC2 SSH private key (`.pem` file)       |
| `AWS_ACCESS_KEY_ID`   | AWS IAM user access key ID                               |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM user secret access key                         |

---

## CI/CD Pipeline

The pipeline is defined in `.github/workflows/infrastructure.yml` and triggers on every push to the `main` branch.

It consists of two sequential jobs:

### Job 1: `configure` — Provision EC2 with Ansible

Runs on `ubuntu-latest` from the `ansible/` directory.

| Step | Description |
|------|-------------|
| Checkout Code | Checks out the repository |
| Install Ansible | Runs `ansible.sh` to install Ansible on the runner |
| Setup SSH Key | Writes `SSH_PRIVATE_KEY` secret to `~/.ssh/us-connect.pem` with `600` permissions |
| Run Ansible Playbook | Executes `setup-server.yml` against the inventory with host key checking disabled |

### Job 2: `build-and-deploy` — Build Image & Deploy Container

Runs after `configure` completes, from the `node-ec2-app/` directory.

| Step | Description |
|------|-------------|
| Checkout Code | Checks out the repository |
| Configure AWS Credentials | Authenticates with AWS using IAM secrets |
| Build and Push to ECR | Authenticates with ECR, builds the Docker image, and pushes it |
| Deploy Container via SSH | SSHs into EC2, stops/removes the old container, pulls the new image, and starts a fresh container |

---

## Ansible Provisioning

The playbook `ansible/setup-server.yml` configures the EC2 instance with everything needed to run the app.

### Tasks Performed

1. **Update apt cache** — Refreshes package lists (skips if updated within the last hour)
2. **Install packages** — Installs `nginx`, `docker.io`, `unzip`, and `curl`
3. **Install AWS CLI v2** — Downloads and installs the AWS CLI if not already present
4. **Start & enable Docker** — Ensures the Docker systemd service is running and enabled on boot
5. **Add `ubuntu` to docker group** — Allows the `ubuntu` user to run Docker without `sudo`
6. **Reset SSH connection** — Applies the group change by resetting the Ansible connection
7. **Create Nginx config** — Writes the reverse proxy config to `/etc/nginx/sites-available/nodeapp`
8. **Enable Nginx config** — Symlinks the config into `/etc/nginx/sites-enabled/`
9. **Test Nginx config** — Runs `nginx -t` to validate the configuration
10. **Remove default Nginx config** — Deletes the default site to avoid conflicts
11. **Start & enable Nginx** — Ensures Nginx is running and enabled on boot

---

## Nginx Reverse Proxy

Ansible writes the following Nginx configuration to `/etc/nginx/sites-available/nodeapp`:

```nginx
server {
  listen 80;
  server_name _;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

This forwards all HTTP traffic on port `80` to the Node.js container on port `3000`, passing along client IP and protocol headers.

---

## Local Development

### Run Without Docker

```bash
cd node-ec2-app
npm install
npm start
```

The app will be available at `http://localhost:3000`.

### Run With Docker

```bash
cd node-ec2-app
docker build -t node-nginx-app .
docker run -p 3000:3000 node-nginx-app
```

The app will be available at `http://localhost:3000`.

---

## Deployment Flow

The following diagram shows the end-to-end flow triggered by a `git push` to `main`:

```
git push → main branch
        │
        ▼
GitHub Actions triggered
        │
        ├─── Job 1: configure
        │         │
        │         ├── Install Ansible on runner
        │         ├── Write SSH key from secret
        │         └── Run Ansible playbook on EC2
        │               ├── Install Nginx, Docker, AWS CLI
        │               └── Configure Nginx reverse proxy
        │
        └─── Job 2: build-and-deploy (runs after Job 1)
                  │
                  ├── Authenticate with AWS
                  ├── Build Docker image
                  ├── Push image to ECR
                  └── SSH into EC2
                        ├── Stop & remove old container
                        ├── Pull latest image from ECR
                        └── Start new container on port 3000
```

---

## Secrets Reference

| Secret | Where It's Used |
|--------|----------------|
| `SSH_PRIVATE_KEY` | Written to `~/.ssh/us-connect.pem` by the runner for Ansible SSH; also used by `appleboy/ssh-action` to deploy the container |
| `AWS_ACCESS_KEY_ID` | Used by `aws-actions/configure-aws-credentials` to authenticate AWS CLI |
| `AWS_SECRET_ACCESS_KEY` | Used by `aws-actions/configure-aws-credentials` to authenticate AWS CLI |