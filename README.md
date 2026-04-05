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
├── ansible/
│   ├── ansible.cfg          # Local Ansible defaults
│   ├── deploy.yml           # Deployment playbook for the production VM
│   └── inventory.ini        # SSH target for the Vagrant VM
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

The repository includes deployment automation under `ansible/` for the Vagrant-based production VM.

Files:
- `ansible/inventory.ini`: Vagrant SSH target definition
- `ansible/ansible.cfg`: local Ansible defaults
- `ansible/deploy.yml`: copies the packaged jar to the VM and runs it as a `systemd` service

Assumptions:
- The VM is already running from `Vagrantfile`
- The application has already been built by Jenkins or locally
- The packaged jar exists at `target/*.jar`
- The VM is reached through Vagrant SSH forwarding on `127.0.0.1:2222`
- SSH user is `vagrant`

Local deployment flow:

1. Start the VM:

   ```bash
   vagrant up --provider=vmware_desktop
   ```

2. Package the application:

   ```bash
   ./mvnw clean package -DskipTests
   ```

3. Deploy the packaged jar:

   ```bash
   ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
     --private-key .vagrant/machines/default/vmware_desktop/private_key \
     -e jar_path=target/spring-petclinic-4.0.0-SNAPSHOT.jar
   ```

4. Verify the deployed application:

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
docker compose down
```

To also remove volumes (all data):

```bash
docker compose down -v
```
