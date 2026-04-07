# X-Road Install Scripts

Bash scripts for installing and managing X-Road components on Ubuntu 24.04 (x86_64).

Maintained by [George Rodrigues de Oliveira](https://github.com/georgeroliveira) — Ignitek Digital.

> All scripts, configurations and documentation in this repository are 100% aligned with the official X-Road documentation from NIIS, following best practices based on the Estonia/Finland X-Road deployment model.

---

## Overview

| Script | Purpose |
|--------|---------|
| `install-xroad-centralserver.sh` | Installs and configures the X-Road Central Server |
| `install-xroad-securityserver.sh` | Installs and configures the X-Road Security Server (BR profile) |
| `install-xroad-autologin.sh` | Installs the xroad-autologin add-on on an existing Security Server |
| `xroad-remove.sh` | Performs a full removal of X-Road from a dedicated VM |

---

## Prerequisites

- Ubuntu 24.04 LTS (x86_64)
- Root access (`sudo`)
- Network connectivity to `artifactory.niis.org`
- Interactive terminal (TTY required)

---

## Installation Sequence

The full X-Road environment must be set up in the following order:

### Step 1 — Test CA (POC/development environments only)

Install the Test CA using the Ansible playbook from the official X-Road repository. The Test CA provides the CA, OCSP and TSA services required for certificate signing and validation.

- Local guide: [`test-ca-setup.md`](./test-ca-setup.md)
- Official reference: [TESTCA.md](https://github.com/nordic-institute/X-Road/blob/develop/ansible/TESTCA.md)

> For production environments, replace the Test CA with EJBCA or another production-grade CA.

### Step 2 — Central Server Installation

```bash
sudo ./install-xroad-centralserver.sh
```

- Official reference: [Central Server Installation Guide](https://github.com/nordic-institute/X-Road/blob/develop/doc/Manuals/ig-cs_x-road_6_central_server_installation_guide.md)

### Step 3 — Central Server Configuration

After installation, configure the Central Server through the admin UI at `https://<central-server>:4000/`. The following steps must be completed in order:

- **Section 1.1** — Log in and complete initial configuration (instance identifier, address, PIN)
- **Section 1.2** — Add member classes
- **Section 1.3** — Add certification service (CA) — upload `ca.pem`, set certificate profile, add OCSP responder
- **Section 1.4** — Add timestamping service (TSA) — upload `tsa.pem`, set TSA URL
- **Section 1.5** — Add the administrative organization and subsystem
- **Section 1.6** — Configure management services
- **Section 1.7** — Add internal and external signing keys

- Official reference: [How to Configure Central Server (>= 7.3.0)](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/215875585/)

### Step 4 — Security Server Installation

```bash
sudo ./install-xroad-securityserver.sh
```

- Official reference: [Security Server Installation Guide](https://github.com/nordic-institute/X-Road/blob/develop/doc/Manuals/ig-ss_x-road_v6_security_server_installation_guide.md)

### Step 5 — Security Server Configuration (Management Services)

After installation, configure the Security Server through the admin UI at `https://<security-server>:4000/`. This Security Server also acts as the management services host:

- **Section 3.1** — Import the configuration anchor downloaded from the Central Server
- **Section 3.2** — Log in to the software token (SOFTTOKEN-0) with the PIN
- **Section 3.3** — Configure the timestamping service
- **Section 3.4** — Generate authentication and signing key pairs and CSRs — **use DER format**
- **Section 3.5** — Sign the CSRs using the Test CA web interface (`http://<ca-host>:8888/testca/`), then import and activate the signed certificates
- **Section 3.6** — Register the authentication certificate and approve the request in the Central Server (Management Requests)
- **Section 3.7** — Add the management services subsystem
- **Section 3.8** — Configure the management services

- Official reference: [How to Configure Central Server (>= 7.3.0) — Section 3](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/215875585/#3.-Configuring-the-Security-Server-for-management-services)

### Step 6 — Autologin (optional)

```bash
sudo ./install-xroad-autologin.sh
```

- Official reference: [Autologin User Guide](https://docs.x-road.global/7.6.3/Manuals/Utils/ug-autologin_x-road_v6_autologin_user_guide.html)

### Step 7 — Register and Publish APIs

After the environment is fully configured, register subsystems and publish REST or SOAP services to X-Road.

- Official reference: [How to Publish a REST API to X-Road](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/1153957893/How+to+Publish+a+REST+API+to+X-Road)

> The Central Server must be fully configured before the Security Server can connect to it.

---

## Scripts

### install-xroad-centralserver.sh

Installs the X-Road Central Server (`xroad-centralserver` package) interactively.

Handles the full installation flow including: system preparation, locale and NTP configuration, official NIIS repository setup, admin user creation, PostgreSQL readiness check, and post-installation validation.

**Known environment considerations handled automatically:**
- If Docker is occupying port 5432, Docker is stopped before installation and must be restarted manually after.
- If the PostgreSQL installation fails during the debconf phase, the script retries after ensuring the PostgreSQL service is active.

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ_NAME` | _(none)_ | System timezone (e.g. `America/Cuiaba`). If not set, timezone is not changed. |

**Usage:**

```bash
sudo ./install-xroad-centralserver.sh
```

**Log:** `/var/log/xroad-centralserver-install.log`

**Access after installation:** `https://<hostname>:4000/`

**Official documentation:** [Central Server Installation Guide](https://github.com/nordic-institute/X-Road/blob/develop/doc/Manuals/ig-cs_x-road_6_central_server_installation_guide.md)

---

### install-xroad-securityserver.sh

Installs the X-Road Security Server (`xroad-securityserver` package) interactively with Brazil-specific configuration.

Includes: operational monitoring add-on (`xroad-addon-opmonitoring`), BR override configuration (`override-securityserver-br.ini`), mail stub, and auxiliary directory permission fixes.

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ_NAME` | _(none)_ | System timezone (e.g. `America/Cuiaba`). If not set, timezone is not changed. |
| `ENABLE_OPMONITORING` | `true` | Set to `false` to skip operational monitoring installation. |
| `APPLY_BR_OVERRIDE` | `true` | Set to `false` to skip the BR-specific configuration override. |

**Usage:**

```bash
# Default (with opmonitoring and BR override)
sudo ./install-xroad-securityserver.sh

# Without opmonitoring
ENABLE_OPMONITORING=false sudo ./install-xroad-securityserver.sh

# Without BR override
APPLY_BR_OVERRIDE=false sudo ./install-xroad-securityserver.sh
```

**Log:** `/var/log/xroad-securityserver-install.log`

**Access after installation:** `https://<hostname>:4000/`

**Official documentation:** [Security Server Installation Guide](https://github.com/nordic-institute/X-Road/blob/develop/doc/Manuals/ig-ss_x-road_v6_security_server_installation_guide.md)

---

### install-xroad-autologin.sh

Installs the `xroad-autologin` add-on on a host where the X-Road Security Server or Central Server is already installed. Prompts for the software token PIN, saves it securely, and enables the autologin service.

**Prerequisites:** X-Road Security Server or Central Server must already be installed on the same host.

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `ARQUIVO_PIN` | `/etc/xroad/autologin` | Path where the PIN file will be stored. |
| `SERVICO` | `xroad-autologin.service` | systemd service name for the autologin add-on. |

**Usage:**

```bash
sudo ./install-xroad-autologin.sh
```

**Log:** `/var/log/xroad-autologin-install.log`

**Official documentation:** [Autologin User Guide](https://docs.x-road.global/7.6.3/Manuals/Utils/ug-autologin_x-road_v6_autologin_user_guide.html)

---

### xroad-remove.sh

Performs a full removal of X-Road from a dedicated VM. Stops all services, drops PostgreSQL databases and users, purges all X-Road, nginx and PostgreSQL packages, and removes configuration directories.

> **Warning:** This is a destructive operation. Use only on dedicated VMs. All data will be lost.

**Modes:**

| Mode | Command |
|------|---------|
| Interactive (default) | `sudo ./xroad-remove.sh` |
| Non-interactive | `sudo ./xroad-remove.sh --yes` |

In interactive mode, each step requires explicit confirmation before proceeding.

**Log:** `/var/log/xroad-remove.log`

**Official documentation:** [How to Manually Remove Security Server Installation](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/4915748/How+to+Manually+Remove+Security+Server+Installation)

---

## Registering and Publishing APIs

After the Security Server is configured and connected to the Central Server, services can be registered and published to X-Road.

For step-by-step instructions on how to publish a REST API to X-Road, refer to the official guide:

[How to Publish a REST API to X-Road](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/1153957893/How+to+Publish+a+REST+API+to+X-Road)

---

## Troubleshooting

### Port 5432 occupied by Docker

The Central Server installer requires PostgreSQL on port 5432. If Docker is binding to that port, the script detects and stops Docker automatically. Restart Docker manually after installation:

```bash
sudo systemctl start docker
```

### PostgreSQL cluster created on wrong port

Ubuntu's `postgresql-common` may create the PostgreSQL cluster on port 5433 if 5432 was occupied during package installation. The script handles this automatically by adjusting the cluster port before retrying.

### Orphaned failed units in systemd

After removing a previously installed Security Server from the same host, systemd may report ghost units (e.g. `xroad-proxy-ui-api.service`) as failed. The post-installation check clears these automatically using `systemctl reset-failed`.

### Log locations

| Component | Log file |
|-----------|----------|
| Central Server installation | `/var/log/xroad-centralserver-install.log` |
| Security Server installation | `/var/log/xroad-securityserver-install.log` |
| Autologin installation | `/var/log/xroad-autologin-install.log` |
| Removal | `/var/log/xroad-remove.log` |
| X-Road services | `/var/log/xroad/` |

---

## Official References

| Resource | Link |
|----------|------|
| X-Road Knowledge Base | [NIIS KB](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/overview?homepageId=4915263) |
| Central Server Installation Guide | [ig-cs](https://github.com/nordic-institute/X-Road/blob/develop/doc/Manuals/ig-cs_x-road_6_central_server_installation_guide.md) |
| Security Server Installation Guide | [ig-ss](https://github.com/nordic-institute/X-Road/blob/develop/doc/Manuals/ig-ss_x-road_v6_security_server_installation_guide.md) |
| How to Configure Central Server (>= 7.3.0) | [NIIS KB](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/215875585/) |
| Autologin User Guide | [ug-autologin](https://docs.x-road.global/7.6.3/Manuals/Utils/ug-autologin_x-road_v6_autologin_user_guide.html) |
| How to Publish a REST API to X-Road | [NIIS KB](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/1153957893/How+to+Publish+a+REST+API+to+X-Road) |
| How to Manually Remove Security Server | [NIIS KB](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/pages/4915748/How+to+Manually+Remove+Security+Server+Installation) |
| X-Road Test CA Setup | [TESTCA.md](https://github.com/nordic-institute/X-Road/blob/develop/ansible/TESTCA.md) |
| X-Road Bug Bounty Program | [NIIS Bug Bounty](https://nordic-institute.atlassian.net/wiki/spaces/XRDBUGBOUNTY/overview?src=contextnavpagetreemode) |

---

## X-Road Knowledge Base

The official X-Road Knowledge Base maintained by NIIS contains how-to articles, troubleshooting guides, migration instructions, and best practices for all X-Road components.

[X-Road Knowledge Base](https://nordic-institute.atlassian.net/wiki/spaces/XRDKB/overview?homepageId=4915263)

---

## X-Road Bug Bounty Program

NIIS maintains an active Bug Bounty Program for X-Road. Security researchers and community members are encouraged to report vulnerabilities and security issues found in X-Road components.

The program covers the X-Road core components and rewards valid security findings. All reports are reviewed by the NIIS security team.

- [Bug Bounty Program Overview](https://nordic-institute.atlassian.net/wiki/spaces/XRDBUGBOUNTY/overview?src=contextnavpagetreemode)
- [Getting Started](https://nordic-institute.atlassian.net/wiki/spaces/XRDBUGBOUNTY/pages/188121174/Getting+Started)

---

## License

MIT — see individual script headers.