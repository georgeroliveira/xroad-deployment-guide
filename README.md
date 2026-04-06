# X-Road Install Scripts

Bash scripts for installing and managing X-Road components on Ubuntu 24.04 (x86_64).

Maintained by [George Rodrigues de Oliveira](https://github.com/georgeroliveira) — Ignitek Digital / X-Via Tecnologia LTDA.

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

## Recommended Execution Order

```
1. install-xroad-centralserver.sh   # on the Central Server host
2. install-xroad-securityserver.sh  # on the Security Server host
3. install-xroad-autologin.sh       # on the Security Server host (optional)
```

The Central Server must be running and reachable before configuring the Security Server.

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

## Standards

All scripts follow the conventions defined in [`xroad-bash-standards.md`](./xroad-bash-standards.md).

---

## License

MIT — see individual script headers.