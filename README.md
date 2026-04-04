# DevSecOps Pipeline — Spring PetClinic

A DevSecOps pipeline for the Spring PetClinic application using Docker, Jenkins, SonarQube, Prometheus, Grafana, Burp Suite, and Ansible.

## Architecture

All pipeline services run as Docker containers on a shared `devsecops-net` bridge network:

| Service | Port | Credentials |
|---------|------|-------------|
| Jenkins | 8080 | See initial setup below |
| SonarQube | 9000 | admin / admin |
| Prometheus | 9090 | — |
| Grafana | 3000 | admin / admin |
| Burp Suite CE | 8081 (web), 5900 (VNC) | — |
| MySQL | 3306 | petclinic / petclinic |
| PostgreSQL | 5432 | petclinic / petclinic |

## Prerequisites

- Docker and Docker Compose
- A VNC client (for Burp Suite access)
- A VM for production deployment (Vagrant or cloud)
- Ansible installed on the Jenkins build server

## Quick Start

### 1. Start all services

```bash
docker compose up -d
```

### 2. Unlock Jenkins

Get the initial admin password:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Open http://localhost:8080, paste the password, and install suggested plugins.

### 3. Verify services

| Service | URL |
|---------|-----|
| Jenkins | http://localhost:8080 |
| SonarQube | http://localhost:9000 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 |
| Burp Suite | Connect VNC client to localhost:5900 |

## Project Structure

```
devops-final-project/
├── docker-compose.yml        # All services (databases + pipeline tools)
├── burpsuite/
│   ├── Dockerfile            # Custom Burp Suite CE image
│   └── entrypoint.sh         # Starts Xvfb + VNC + Burp Suite
├── prometheus/
│   └── prometheus.yml        # Scrape config for Jenkins metrics
├── src/                      # Spring PetClinic application source
├── pom.xml                   # Maven build
└── README-petclinic.md       # Original PetClinic documentation
```

## Pipeline Setup

### Jenkins Pipeline

1. Create a new Pipeline job in Jenkins
2. Point it to this repository
3. Set up SCM polling as the build trigger
4. Install the Blue Ocean plugin for pipeline visualization

### SonarQube Integration

1. Log into SonarQube at http://localhost:9000 (admin/admin)
2. Create a project and generate an authentication token
3. Add the SonarQube stage to the Jenkinsfile with the token
4. SonarQube is reachable from Jenkins at `http://sonarqube:9000` (container name)

### Burp Suite Security Scan

1. Connect to Burp Suite via VNC client at `localhost:5900`
2. Configure Burp Suite to scan the running PetClinic application
3. Export scan reports as HTML
4. Add post-build action in Jenkins to publish HTML reports

### Prometheus and Grafana Monitoring

1. Install the Prometheus Metrics plugin in Jenkins
2. Prometheus is pre-configured to scrape Jenkins at `jenkins:8080/prometheus`
3. Verify at http://localhost:9090/targets — Jenkins target should show as UP
4. In Grafana (http://localhost:3000):
   - Add Prometheus as a data source: URL = `http://prometheus:9090`
   - Import or create dashboards for Jenkins metrics

### Ansible Deployment to Production VM

1. Set up a VM (Vagrant or cloud) with SSH access
2. Install Ansible on the Jenkins container
3. Create an Ansible inventory file with the VM's IP/hostname
4. Create a playbook that deploys the built `.jar` and starts the application
5. Add a deploy stage to the Jenkinsfile that runs the Ansible playbook
6. Verify the PetClinic welcome screen is accessible on the VM

## Verifying the Full Pipeline

1. Make a code change (e.g., modify a page title in `src/`)
2. Push to the repository
3. Jenkins detects the change via SCM polling
4. Pipeline runs: build → test → SonarQube analysis → Burp Suite scan → Ansible deploy
5. Verify the change is reflected on the production VM

## Stopping Services

```bash
docker compose down
```

To also remove volumes (all data):

```bash
docker compose down -v
```
