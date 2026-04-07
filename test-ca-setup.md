# X-Road Test CA Setup Guide

> **Important:** The Test CA is for **development and POC environments only**. It is not a secure certification authority and must not be used in production. For production deployments, use EJBCA or another production-grade CA.

---

## Overview

The X-Road Test CA provides a complete trust services stack for a development environment:

| Service | Port | Purpose |
|---------|------|---------|
| CA | 8888 | Signs authentication and signing certificates |
| OCSP | 8888 | Provides certificate status (Online Certificate Status Protocol) |
| TSA | 8899 | Provides timestamping (Time Stamping Authority) |

All services run behind nginx as a reverse proxy.

---

## Prerequisites

- Ubuntu 20.04, 22.04, or 24.04 (x86_64) on the CA host
- Root or sudo access

---

## Step 1 — Install Ansible

```bash
sudo apt update
sudo apt install -y ansible
```

Verify the installation:

```bash
ansible --version
```

---

## Step 2 — Clone the X-Road Repository

Clone directly at version 7.8.0:

```bash
git clone --branch 7.8.0 --depth 1 https://github.com/nordic-institute/X-Road.git
cd X-Road
```

Verify the version:

```bash
git describe --tags
```

Create a working branch:

```bash
git checkout -b feature/7.8.0
```

Navigate to the Ansible directory:

```bash
cd ansible
```

---

## Step 3 — Configure the Inventory

```bash
vim hosts/local_ca.txt
```

Expected content:

```ini
[ca_servers]
localhost ansible_connection=local
```

---

## Step 4 — Configure CA Parameters

Edit `roles/xroad-ca/defaults/main.yml` with the DN values for your organization:

```yaml
xroad_ca_o: "X-Road Test CA"
xroad_ca_cn: "Test CA"
xroad_ca_ocsp_o: "{{ xroad_ca_o }}"
xroad_ca_ocsp_cn: "Test OCSP"
xroad_ca_tsa_o: "{{ xroad_ca_o }}"
xroad_ca_tsa_cn: "Test TSA"
a2c_ver: "0.35"
```

Fields to adjust according to your organization:

- `xroad_ca_o` — organization name, used as base value for OCSP and TSA via `{{ xroad_ca_o }}`
- `xroad_ca_cn` — CA common name
- `xroad_ca_ocsp_cn` — OCSP common name
- `xroad_ca_tsa_cn` — TSA common name

---

## Step 5 — Run the Ansible Playbook

```bash
ansible-playbook -i hosts/local_ca.txt xroad_test_ca.yml
```

The playbook will:
- Install all required system packages
- Create the `ca` and `ocsp` users
- Deploy and configure the CA, OCSP and TSA services
- Configure nginx as a reverse proxy
- Initialize the CA environment and generate all certificates
- Start and enable all services

---

## Step 6 — Verify the Services

```bash
sudo systemctl status ca ocsp tsa nginx
```

All four services should be **active (running)**.

To confirm the CA is accessible, open a browser and navigate to the CA endpoint using the server IP or DNS name:

```
http://<ip-or-hostname>:8888/testca/
```

---

## Signing Certificates

To sign CSRs from Security Servers, open a browser and access the Test CA web interface using the server IP or DNS name:

```
http://<ip-or-hostname>:8888/testca/
```

The interface presents the following fields:

- **CSR** — upload the CSR file downloaded from the Security Server
- **Type** — select `Sign`, `Auth`, or leave as `Autodetect from file name`
- Click **Sign** to generate the signed certificate and download it

> **Note:** The Test CA only accepts CSR files in **DER format**. When generating CSRs on the Security Server, make sure to select DER as the CSR format.

---

## Certificate Locations

| Certificate | Path |
|-------------|------|
| CA certificate | `/home/ca/CA/certs/ca.cert.pem` |
| OCSP certificate | `/home/ca/CA/certs/ocsp.cert.pem` |
| TSA certificate | `/home/ca/CA/certs/tsa.cert.pem` |
| Signed certificates | `/home/ca/CA/newcerts/<serial>.pem` |

---

## Troubleshooting

### Service logs

```bash
journalctl -u ca
journalctl -u ocsp
journalctl -u tsa
```

### nginx logs

```bash
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/access.log
```

### OCSP log

```bash
tail -f /var/log/ocsp.log
```

### Common issues

**Services not starting after playbook**
- Run with verbose output: `ansible-playbook -i hosts/local_ca.txt xroad_test_ca.yml -vvv`
- Ensure Ansible version is 2.9 or later: `ansible --version`

**CA endpoint not responding**
- Check nginx is running: `systemctl status nginx`
- Check CA service is running: `systemctl status ca`

**TSA not responding**
- Confirm the TSA service is running: `systemctl status tsa`