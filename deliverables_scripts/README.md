# Deliverables — Provisioning Scripts & Config

Docker commands, configuration files, and provisioning scripts for each tool, organized by tool name.

## Root-level shared files

- `docker-compose.yml` — Orchestrates all services (Jenkins / Prometheus / Grafana / Burp Suite / SonarQube / MySQL / Postgres).
- `Vagrantfile` — Provisions a target VM used by Ansible for deployment.
- `startup.sh` — One-shot script to bring the whole stack up.
- `teardown.sh` — One-shot script to stop and clean up the stack.

## Jenkins

- `Dockerfile` — Custom Jenkins image (pre-installs plugins and JCasC).
- `plugins.txt` — Jenkins plugin install list.
- `casc.yaml` — Jenkins Configuration as Code settings.
- `Jenkinsfile` — CI/CD pipeline (Groovy).

## Prometheus

- `prometheus.yml` — Prometheus scrape targets configuration.

## Grafana

- `provisioning/datasources/prometheus.yml` — Auto-registers Prometheus as a datasource.
- `provisioning/dashboards/jenkins.yml` — Dashboard provider configuration.
- `dashboards/jenkins-dashboard.json` — Jenkins monitoring dashboard definition.

## Burp Suite

- `Dockerfile` — Burp Suite container image.
- `entrypoint.sh` — Container startup script.
- `scan_target.sh` — Triggers scans against the target application.
- `run_burp_report.sh` — Generates the scan report.
- `index.html` — Report landing page.

## Ansible

- `ansible.cfg` — Ansible runtime configuration.
- `inventory.ini` — Target host inventory.
- `deploy.yml` — Deployment playbook.
