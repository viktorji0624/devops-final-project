# DevSecOps Pipeline — Spring PetClinic

A DevSecOps pipeline for the Spring PetClinic application using Docker, Jenkins, SonarQube, Prometheus, Grafana, Burp Suite, and Ansible.

## Architecture

All pipeline services run as Docker containers on a shared `devsecops-net` bridge network:

| Service | Port | Credentials |
|---------|------|-------------|
| Jenkins | 8080 | admin / admin |
| SonarQube | 9000 | admin / admin |
| Prometheus | 9090 | — |
| Grafana | 3000 | admin / admin |
| Burp Suite CE | 8081 (web), 6080 (noVNC), 5900 (VNC) | — |
| MySQL | 3306 | petclinic / petclinic |
| PostgreSQL | 5432 | petclinic / petclinic |

## Prerequisites

- Docker and Docker Compose
- Vagrant with VirtualBox (or VMware Desktop) for the production VM
- Git repository with a remote origin (used by Jenkins to check out source code)

## Quick Start

Run the startup script from the **host machine** (not inside a devcontainer):

```bash
./scripts/startup.sh
```

This single command will:

1. Start SonarQube and wait for it to be ready
2. Create a SonarQube project and generate an authentication token via API
3. Build the Jenkins image with pre-installed plugins (Blue Ocean, SonarQube Scanner, Prometheus, etc.)
4. Start all Docker services with the token injected into Jenkins via JCasC
5. Start the Vagrant VM (default provider: `virtualbox`)
6. Wait for Jenkins to be ready and trigger the first pipeline build

To use VMware Desktop instead of VirtualBox:

```bash
./scripts/startup.sh vmware_desktop
```

> **Note:** The startup script must be run on the host, not inside a devcontainer. Vagrant requires a hypervisor which is not available in container environments.

### Verify services

| Service | URL |
|---------|-----|
| Jenkins | http://localhost:8080 |
| SonarQube | http://localhost:9000 |
| Prometheus | http://localhost:9090 |
| Grafana | http://localhost:3000 |
| Burp Suite | http://localhost:6080 (noVNC, recommended) or VNC client at localhost:5900 |
| PetClinic App | http://localhost:8082 |

## Project Structure

```
devops-final-project/
├── ansible/
│   ├── ansible.cfg          # Local Ansible defaults
│   ├── deploy.yml           # Deployment playbook for the production VM
│   └── inventory.ini        # SSH target for the Vagrant VM
├── docker-compose.yml        # All services (databases + pipeline tools)
├── jenkins/
│   ├── Dockerfile            # Jenkins image with Ansible, plugins, and JCasC
│   ├── plugins.txt           # Pre-installed Jenkins plugins
│   └── casc.yaml             # Jenkins Configuration as Code
├── burpsuite/
│   ├── Dockerfile            # Custom Burp Suite CE image
│   └── entrypoint.sh         # Starts Xvfb + VNC + Burp Suite
├── grafana/
│   ├── dashboards/           # Provisioned Grafana dashboards
│   └── provisioning/         # Datasource and dashboard providers
├── prometheus/
│   └── prometheus.yml        # Scrape config for Jenkins metrics
├── scripts/
│   ├── startup.sh            # One-click setup and launch
│   ├── teardown.sh           # Stop all services and destroy VM
│   └── run_burp_report.sh    # Generate Burp baseline security report
├── src/                      # Spring PetClinic application source
├── pom.xml                   # Maven build
└── README-petclinic.md       # Original PetClinic documentation
```

## Pipeline Setup

### Jenkins (fully automated)

Jenkins is configured automatically via [JCasC](https://www.jenkins.io/projects/jcasc/) — no manual UI setup required.

The startup script handles:

- Skipping the setup wizard and creating the admin user
- Installing all required plugins (Blue Ocean, SonarQube Scanner, Prometheus Metrics, etc.)
- Configuring the SonarQube server connection and credentials
- Creating the `petclinic-pipeline` job pointing to this repository
- Triggering the first build

Configuration files:

| File | Purpose |
|------|---------|
| `jenkins/plugins.txt` | List of plugins to pre-install |
| `jenkins/casc.yaml` | JCasC configuration (credentials, SonarQube server, job definition) |
| `jenkins/Dockerfile` | Builds the Jenkins image with Ansible, plugins, and JCasC |

### SonarQube Integration (fully automated)

SonarQube setup is handled by `scripts/startup.sh`:

1. Waits for SonarQube to be ready
2. Creates the `spring-petclinic` project via API
3. Generates an authentication token via API
4. Passes the token to Jenkins as an environment variable (read by JCasC)

SonarQube is reachable from Jenkins at `http://sonarqube:9000` (container name resolution).

### Burp Suite Security Scan

#### Start Burp and the target application

Burp in this project runs inside the `burpsuite` Docker container. The container starts:

- `Burp Suite Community Edition`
- `x11vnc` on port `5900`
- `noVNC` on port `6080` (recommended)

Open the Burp browser UI (manual interaction required):

- noVNC: `http://localhost:6080` (recommended)
- Raw VNC client: `localhost:5900`

Confirm the target application is reachable:

- Host forwarded URL: `http://localhost:8082`
- VM private network URL: `http://192.168.56.10:8080`

#### Burp report generation

This repository includes a scripted Burp baseline report generator:

```bash
bash scripts/run_burp_report.sh
```

Default target:

```text
http://host.docker.internal:8082
```

This means the `burpsuite` container sends requests to the host's forwarded port `8082`, which maps to the PetClinic application running inside the VM.

You can also scan another target explicitly:

```bash
bash scripts/run_burp_report.sh http://192.168.56.10:8080
```

Generated report: `burpsuite/report/index.html`

#### Burp traffic flow

1. You open Burp through `http://localhost:6080`
2. The `burpsuite` container runs Burp and listens with its proxy on `127.0.0.1:8080` inside the container
3. The report script runs inside the same container and sends HTTP requests through that proxy
4. The proxy forwards traffic to `http://host.docker.internal:8082`
5. Port `8082` on the host forwards to the PetClinic application running in the VM
6. The response comes back through Burp, and the script writes the HTML report to `burpsuite/report/index.html`

#### What the scripted report checks

The bundled Burp baseline report is not a full active vulnerability scan. It currently checks:

- Endpoint reachability and response times
- Burp process and proxy readiness
- Basic security headers
- Cookie flags such as `HttpOnly`, `SameSite`, and `Secure` on HTTPS
- CORS behavior
- Allowed HTTP methods and `TRACE`
- Sensitive endpoint exposure such as `/actuator/*`, `/swagger-ui`, `/.env`, and `/.git/config`

### Prometheus and Grafana Monitoring

All monitoring is pre-configured — no manual plugin installation required.

- The Prometheus Metrics plugin is pre-installed via `jenkins/plugins.txt`
- Prometheus is pre-configured to scrape Jenkins at `jenkins:8080/prometheus`
- Verify at http://localhost:9090/targets — Jenkins target should show as UP
- In Grafana (http://localhost:3000):
  - Prometheus is provisioned automatically as the default data source
  - The `Jenkins Monitoring Overview` dashboard is provisioned automatically at startup

### Ansible Deployment to Production VM

The repository includes deployment automation under `ansible/` for the Vagrant-based production VM.

Files:
- `ansible/inventory.ini`: SSH target definition (uses `host.docker.internal` so Jenkins inside Docker can reach the VM)
- `ansible/ansible.cfg`: local Ansible defaults
- `ansible/deploy.yml`: copies the packaged jar to the VM and runs it as a `systemd` service

The Deploy stage in the Jenkinsfile automatically detects the Vagrant private key regardless of the provider (VirtualBox or VMware Desktop).

Manual deployment (if needed):

1. Package the application:

   ```bash
   ./mvnw clean package -DskipTests
   ```

2. Deploy the packaged jar:

   ```bash
   VAGRANT_KEY=$(find .vagrant/machines/default -name private_key -print -quit)
   ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
     --private-key "$VAGRANT_KEY" \
     -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
   ```

3. Verify the deployed application:

   - Host forwarded port: `http://localhost:8082`
   - Vagrant private IP: `http://192.168.56.10:8080`

## Verifying the Full Pipeline

1. Make a code change (e.g., modify a page title in `src/`)
2. Push to the repository
3. Jenkins detects the change via SCM polling
4. Pipeline runs: build → SonarQube analysis → Burp Suite scan → Ansible deploy
5. Verify the change is reflected on the production VM

## Stopping Services

```bash
./scripts/teardown.sh
```

This stops the Docker services and destroys the Vagrant VM.

To do a full clean reset (including all data volumes):

```bash
docker compose down -v
vagrant destroy -f
rm -f .env
./scripts/startup.sh
```
