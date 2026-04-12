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
| Burp Suite CE | 8081 (web), 6080 (noVNC), 5900 (VNC) | — |
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
./scripts/startup.sh vmware_desktop
```

This starts the Docker services and the Vagrant production VM together. If you only need the Docker stack, you can still run `docker compose up -d` manually.

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
| Burp Suite | http://localhost:6080 (Recommended) or Connect VNC client to localhost:5900 |

## Project Structure

```
devops-final-project/
├── ansible/
│   ├── ansible.cfg          # Local Ansible defaults
│   ├── deploy.yml           # Deployment playbook for the production VM
│   └── inventory.ini        # SSH target for the Vagrant VM
├── docker-compose.yml        # All services (databases + pipeline tools)
├── burpsuite/
│   ├── Dockerfile            # Custom Burp Suite CE image
│   └── entrypoint.sh         # Starts Xvfb + VNC + Burp Suite
├── grafana/
│   ├── dashboards/           # Provisioned Grafana dashboards
│   └── provisioning/         # Datasource and dashboard providers
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

1. Log into SonarQube at http://localhost:9000 (admin/1234)
2. Create a project and generate an authentication token
3. Add the SonarQube stage to the Jenkinsfile with the token
4. SonarQube is reachable from Jenkins at `http://sonarqube:9000` (container name)

### Burp Suite Security Scan

#### Start Burp and the target application

Burp in this project runs inside the `burpsuite` Docker container. The container starts:

- `Burp Suite Community Edition`
- `x11vnc` on port `5900` 
- `noVNC` on port `6080` (Recommended)

Recommended startup flow:

1. Start the full Docker stack:

   ```bash
   docker compose up -d
   ```

2. If you also need the Vagrant VM that hosts the deployed PetClinic application, start it separately:

   ```bash
   vagrant up
   ```

   Or use the project helper script if `vagrant` is installed:

   ```bash
   bash scripts/startup.sh
   ```

3. Open Burp's browser UI (This step require manual click in UI):

   - noVNC: `http://localhost:6080` (Recommended)
   - Raw VNC client: `localhost:5900`

4. Confirm the target application is reachable:

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

This means the `burpsuite` container sends requests to the host's forwarded port `8082`, which should map to the PetClinic application running inside the VM.

You can also scan another target explicitly:

```bash
bash scripts/run_burp_report.sh http://192.168.56.10:8080
```

Generated report:

- `burpsuite/report/index.html`

#### Burp traffic flow

The interaction between the components is:

1. You open Burp through `http://localhost:6080`
2. The `burpsuite` container runs Burp and listens with its proxy on `127.0.0.1:8080` inside the container
3. The report script runs inside the same container and sends HTTP requests through that proxy
4. The proxy forwards traffic to `http://host.docker.internal:8082`
5. Port `8082` on the host is expected to forward to the PetClinic application running in the VM
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

1. Install the Prometheus Metrics plugin in Jenkins
2. Prometheus is pre-configured to scrape Jenkins at `jenkins:8080/prometheus`
3. Verify at http://localhost:9090/targets — Jenkins target should show as UP
4. In Grafana (http://localhost:3000):
   - Prometheus is provisioned automatically as the default data source
   - The `Jenkins Monitoring Overview` dashboard is provisioned automatically at startup

### Ansible Deployment to Production VM

The repository includes deployment automation under `ansible/` for the Vagrant-based production VM.

Files:
- `ansible/inventory.ini`: Vagrant SSH target definition
- `ansible/ansible.cfg`: local Ansible defaults
- `ansible/deploy.yml`: copies the packaged jar to the VM and runs it as a `systemd` service

Assumptions:
- The shared local environment has already been started
- The application has already been built by Jenkins or locally
- The packaged jar exists at `target/*.jar`
- The VM is reached through Vagrant SSH forwarding on `127.0.0.1:2222`
- SSH user is `vagrant`

Local deployment flow:

1. Package the application:

   ```bash
   ./mvnw clean package -DskipTests
   ```

2. Deploy the packaged jar:

   ```bash
   ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
     --private-key .vagrant/machines/default/vmware_desktop/private_key \
     -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
   ```

3. Verify the deployed application:

   - Host forwarded port: `localhost:8082`
   - Vagrant private IP inside the VM network: `192.168.56.10:8080`

Jenkins handoff:

Once Jenkins has already run the build and tests, the deploy stage can call the same command:

```bash
ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
  --private-key .vagrant/machines/default/vmware_desktop/private_key \
  -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
```

If your Vagrant provider is not VMware Desktop, update the private key path to match the provider-specific directory under `.vagrant/machines/default/`.

## Verifying the Full Pipeline

1. Make a code change (e.g., modify a page title in `src/`)
2. Push to the repository
3. Jenkins detects the change via SCM polling
4. Pipeline runs: build → test → SonarQube analysis → Burp Suite scan → Ansible deploy
5. Verify the change is reflected on the production VM

## Stopping Services

```bash
./scripts/teardown.sh
```

This stops the Docker services and destroys the Vagrant VM. If you only need to stop the Docker stack, you can still use `docker compose down` manually.
