# DevSecOps Pipeline - Spring PetClinic

## 1. Project Overview

This repository implements a DevSecOps pipeline for the Spring PetClinic application using:

- Docker Compose for infrastructure services
- Jenkins for CI/CD orchestration
- SonarQube for code quality analysis
- Prometheus + Grafana for monitoring
- Burp Suite Community Edition for baseline security scanning
- Ansible for deployment to a Vagrant-based VM

## 2. Architecture / Components

Services run in Docker containers on a shared bridge network (`devsecops-net`), while the deployment target runs in a Vagrant VM.

| Component | Role | Access |
|---|---|---|
| Jenkins | CI/CD pipeline orchestration | http://localhost:8080 (`admin/admin`) |
| SonarQube | Static/code quality analysis | http://localhost:9000 (`admin/admin`) |
| Prometheus | Metrics scraping | http://localhost:9090 |
| Grafana | Dashboards and visualization | http://localhost:3000 (`admin/admin`) |
| Burp Suite CE | Security testing UI + proxy | http://localhost:6080 (noVNC), VNC on `localhost:5900` |
| MySQL | Optional app database container | `localhost:3306` |
| PostgreSQL | Optional app database container | `localhost:5432` |
| Vagrant VM (`petclinic-prod`) | Deployment target for Ansible | App forwarded at http://localhost:8082 |

High-level flow:

1. `scripts/startup.sh` starts SonarQube, generates token/project, starts VM, then builds/starts Docker services.
2. Jenkins is auto-configured from JCasC and creates `petclinic-pipeline`.
3. Pipeline executes stages from `Jenkinsfile` (build, SonarQube analysis, security-report publish check, deploy).
4. Ansible deploys built JAR to the Vagrant VM and manages a `systemd` service.

## 3. Prerequisites

- Docker and Docker Compose
- Vagrant
- A Vagrant provider:
  - VirtualBox (default), or
  - VMware Desktop (optional)
- Git repository with configured remote origin (used by Jenkins job creation)

Notes:

- Run setup from the host machine (not inside a devcontainer) because Vagrant requires host virtualization.
- Default VM private IP in this repo: `192.168.56.10` (see `Vagrantfile`).

## 4. Step-by-Step Setup Instructions

### Step 1: Clone and enter repository

```bash
git clone <your-repo-url>
cd devops-final-project
```

### Step 2: Start containers and VM

Default provider (VirtualBox):

```bash
./scripts/startup.sh
```

VMware Desktop provider:

```bash
./scripts/startup.sh vmware_desktop
```

What this script does (implemented in `scripts/startup.sh`):

1. Starts SonarQube container and waits for readiness
2. Creates SonarQube project `spring-petclinic` and token via API
3. Writes `.env` with `SONAR_TOKEN` and `GIT_REPO_URL`
4. Starts Vagrant VM (`vagrant up --provider=...`)
5. Builds Jenkins image and starts all Compose services
6. Waits for Jenkins, validates `petclinic-pipeline` job, and triggers first build

### Step 3: Initial Jenkins setup (automated)

Jenkins initial setup is provisioned automatically, no setup wizard steps required.

Verify:

1. Open http://localhost:8080
2. Login with `admin/admin`
3. Confirm job `petclinic-pipeline` exists

Jenkins dashboard / job trigger screenshot:

![Jenkins pipeline trigger](./Project%20Screenshots/Jenkins%20Pipeline/demo%20triggered%20pipeline.png)

Configured by:

- `jenkins/Dockerfile` (plugin installation, JCasC wiring, Ansible tooling)
- `jenkins/plugins.txt` (preinstalled plugins)
- `jenkins/casc.yaml` (admin user, SonarQube server/credentials, pipeline job definition)

### Step 4: SonarQube setup (automated)

SonarQube setup is done by `scripts/startup.sh`.

Verification:

1. Open http://localhost:9000
2. Login with `admin/admin`
3. Confirm project `spring-petclinic` exists

SonarQube dashboard screenshots:

![SonarQube analysis overview](./Project%20Screenshots/SonarQube/SonarQube%20Analysis%20overview.png)

![SonarQube code smell analysis](./Project%20Screenshots/SonarQube/SonarQube%20Analysis%20on%20code%20smell.png)

Integration details:

- Token is generated through SonarQube API in `scripts/startup.sh`
- Token is injected into Jenkins via `.env` and consumed in `jenkins/casc.yaml`
- Pipeline uses `withSonarQubeEnv('sonarqube')` in `Jenkinsfile`

### Step 5: Pipeline setup

Pipeline job and stages are defined by repository files:

- `jenkins/casc.yaml`: creates `petclinic-pipeline` job from SCM
- `Jenkinsfile`: defines pipeline stages and post actions

Default stage sequence in `Jenkinsfile`:

1. Checkout
2. Build (`./mvnw clean package -DskipTests`)
3. SonarQube Analysis
4. Security Scan report presence check + HTML publish
5. Deploy via Ansible playbook (if Vagrant key/Ansible are available in Jenkins container)

Trigger model:

- SCM polling every 2 minutes (`pollSCM('H/2 * * * *')`)
- First build is auto-triggered by `scripts/startup.sh`

Pipeline screenshots:

![Blue Ocean pipeline stage visualization](./Project%20Screenshots/Jenkins%20Pipeline/ocean%20blue%20pipeline%20stage%20visualization.png)

![Jenkins pipeline console output](./Project%20Screenshots/Jenkins%20Pipeline/jenkins%20pipeline%20console%20output.png)

### Step 6: Monitoring setup (Prometheus + Grafana)

Monitoring is pre-provisioned.

Verify Prometheus:

1. Open http://localhost:9090/targets
2. Confirm Jenkins target is `UP`

Verify Grafana:

1. Open http://localhost:3000 (`admin/admin`)
2. Confirm Prometheus datasource exists
3. Confirm `Jenkins Monitoring Overview` dashboard is available

Configured by:

- `prometheus/prometheus.yml` (scrape `jenkins:8080/prometheus`)
- `grafana/provisioning/datasources/prometheus.yml` (datasource provisioning)
- `grafana/provisioning/dashboards/jenkins.yml` (dashboard provider config)
- `grafana/dashboards/jenkins-dashboard.json` (dashboard content)

Monitoring screenshots:

![Prometheus or Grafana monitoring screenshot 1](./Project%20Screenshots/Grafana%20and%20Prometheus/%E6%88%AA%E5%9C%96%202026-04-16%20%E4%B8%8B%E5%8D%884.25.37.png)

![Prometheus or Grafana monitoring screenshot 2](./Project%20Screenshots/Grafana%20and%20Prometheus/%E6%88%AA%E5%9C%96%202026-04-16%20%E4%B8%8B%E5%8D%884.26.02.png)

### Step 7: Security scan setup (Burp Suite baseline workflow)

Burp service is containerized and started by Compose.

Access Burp UI:

- noVNC: http://localhost:6080
- VNC: `localhost:5900`

Generate baseline report (host command):

```bash
bash scripts/run_burp_report.sh
```

Optional explicit target:

```bash
bash scripts/run_burp_report.sh http://192.168.56.10:8080
```

Generated artifact:

- `burpsuite/report/index.html`

Important accuracy note:

- In current repo behavior, Jenkins `Security Scan` stage validates/publishes an existing Burp report file.
- The Jenkinsfile does not invoke Burp crawling itself; report generation is performed via `scripts/run_burp_report.sh`.

Burp Suite screenshots:

![Burp report webpage](./Project%20Screenshots/Burp%20Suite/burp%20suite%20report%20webpage.png)

![run_burp_report.sh result](./Project%20Screenshots/Burp%20Suite/run_burp_report.sh%20result.png)

### Step 8: Deployment setup (Ansible to VM)

Deployment automation files:

- `ansible/inventory.ini`
- `ansible/ansible.cfg`
- `ansible/deploy.yml`

Pipeline deploy stage calls:

```bash
ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
  --private-key <vagrant_private_key> \
  -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
```

Manual deploy (if needed):

```bash
./mvnw clean package -DskipTests
VAGRANT_KEY=$(find .vagrant/machines/default -name private_key -print -quit)
ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
  --private-key "$VAGRANT_KEY" \
  -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
```

Verify deployed app:

- Host forwarded port: http://localhost:8082
- VM private network: http://192.168.56.10:8080

Deployment screenshots:

![Ansible playbook completed successfully](./Project%20Screenshots/Ansible/ansible%20playbook%20completed%20successfully.png)

![Jenkins deployment successful](./Project%20Screenshots/Jenkins%20Pipeline/deployment%20successful.png)

Before/after deployment proof:

![Production VM app before change](./Project%20Screenshots/Ansible/web-before-change.png)

![Production VM app after change](./Project%20Screenshots/Ansible/web-after-change.png)

### Step 9: Verification flow (end-to-end)

1. Ensure services are up from Steps 2-8.
2. Make and push a small code change.
3. Confirm Jenkins job triggers (SCM polling).
4. Confirm successful pipeline stages (build, SonarQube, security-report publish check, deploy).
5. Confirm app is reachable on `http://localhost:8082`.
6. Confirm monitoring data appears in Prometheus/Grafana.

Stop environment:

```bash
./scripts/teardown.sh
```

Full reset:

```bash
docker compose down -v
vagrant destroy -f
rm -f .env
./scripts/startup.sh
```

## 5. Provisioning Scripts and Configuration Files

This section is the explicit submission index for deliverable (2).

### Core orchestration

- `docker-compose.yml`
  - Defines all primary services, ports, volumes, networks, and build contexts.
- `scripts/startup.sh`
  - End-to-end bootstrap script (SonarQube init, `.env` creation, VM startup, service startup, Jenkins readiness/trigger).
- `scripts/teardown.sh`
  - Stops Docker services and destroys Vagrant VM.
- `Vagrantfile`
  - Defines VM box/version, networking, provider resources, and Java runtime provisioning.

### Jenkins provisioning/config

- `jenkins/Dockerfile`
  - Builds custom Jenkins image, installs Ansible/SSH tooling, installs plugins, and loads JCasC.
- `jenkins/plugins.txt`
  - Plugin list (pipeline, git, blueocean, sonar, prometheus, htmlpublisher, JCasC, etc.).
- `jenkins/casc.yaml`
  - Jenkins Configuration as Code: admin auth, SonarQube server, credentials, and pipeline job creation.
- `Jenkinsfile`
  - CI/CD pipeline definition (checkout/build/analyze/security-report publish/deploy).

### SonarQube integration

- `scripts/startup.sh`
  - Uses SonarQube APIs to create project and generate token.
- `jenkins/casc.yaml`
  - Injects Sonar token as Jenkins credential and configures server installation.
- `Jenkinsfile`
  - Executes Maven Sonar analysis stage.

### Prometheus provisioning/config

- `prometheus/prometheus.yml`
  - Scrape config for Jenkins metrics endpoint.

### Grafana provisioning/config

- `grafana/provisioning/datasources/prometheus.yml`
  - Auto-provisions Prometheus datasource.
- `grafana/provisioning/dashboards/jenkins.yml`
  - Dashboard provider config.
- `grafana/dashboards/jenkins-dashboard.json`
  - Dashboard definition imported at startup.

### Burp Suite provisioning/config

- `burpsuite/Dockerfile`
  - Builds Burp Suite CE container with Xvfb, VNC, and noVNC dependencies.
- `burpsuite/entrypoint.sh`
  - Starts virtual display, VNC/noVNC services, then Burp.
- `burpsuite/scan_target.sh`
  - Baseline scan/report logic executed in container.
- `scripts/run_burp_report.sh`
  - Host-side wrapper that calls Burp scan script in container and writes HTML report.

### Ansible deployment provisioning/config

- `ansible/ansible.cfg`
  - Local Ansible defaults.
- `ansible/inventory.ini`
  - VM target definition (SSH host/port/user/options).
- `ansible/deploy.yml`
  - Deployment playbook for JAR copy, systemd unit install, restart, and health verification.


## 6. Known limitations / notes

- Burp scan execution is currently initiated by `scripts/run_burp_report.sh`; Jenkins validates and publishes the generated report rather than running Burp crawl itself.
- `docker-compose.yml` uses `latest` tags for Prometheus/Grafana images, so exact versions can vary across runs.
- Deployment stage in Jenkins is conditional on Vagrant SSH key availability and `ansible-playbook` presence inside Jenkins container.
- Setup should be run on a host with virtualization support; running `scripts/startup.sh` from a devcontainer is not supported.
