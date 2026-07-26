# MOI01.VIP — Zero-Knowledge Vault: Master Deployment Blueprint

**Document Version:** 1.0.0  
**Author:** Principal Systems Architect  
**Classification:** Confidential — System Infrastructure & Operational Blueprint  

---

## Executive Summary & Architectural Pyramid

The **MOI01.VIP Zero-Knowledge Ephemeral Vault** is a high-security, RAM-only payload relay designed for untrusted or sensitive audit file ingest. The primary architectural requirement is **Zero Disk Persistence**: under no circumstances may application payloads, decrypted buffers, or intermediate parsing structures touch physical persistent media (NVMe/SSD/EBS).

### System Topology Pyramid

```
                      ┌───────────────────────────────────────────────┐
                      │            YOUR MACBOOK WORKSTATION           │
                      │  • Local test traffic generator (client/)     │
                      │  • Deployment CLI & GitOps control            │
                      └───────────────────────┬───────────────────────┘
                                              │
                                              │ HTTPS (Port 443)
                                              ▼
                      ┌───────────────────────────────────────────────┐
                      │              THE VAULT SERVER                 │
                      │           (AWS EC2 / Ubuntu 24.04)            │
                      │  • Nginx edge guard (1MB payload cap)         │
                      │  • Node.js Vault ingest (RAM-only relay)      │
                      │  • systemd sandbox (DynamicUser, zero swap)   │
                      │                                               │
                      │   [MONITORING THREADS]                        │
                      │   - iotop (Disk I/O = 0.00 B)                 │
                      │   - htop  (RAM & PID supervisor)              │
                      └───────────────────────┬───────────────────────┘
                                              │
                                              │ Bearer Auth (HTTP/S)
                                              ▼
                      ┌───────────────────────────────────────────────┐
                      │           DESTINATION AUDIT SINK              │
                      │     (Oracle Cloud / AWS / Third-Party)        │
                      │  • Independent request verification server    │
                      │  • Live HTML audit log & header dashboard     │
                      └───────────────────────────────────────────────┘
```

| Component Layer | Implemented Control | Risk Mitigated / Operational Guarantee |
| :--- | :--- | :--- |
| **Edge Proxy** | Nginx `client_max_body_size 1m;` | Dropped at HTTP parser boundary before Node.js event loop processing. |
| **OS Memory** | `swapoff -a` & `vm.swappiness=0` | Mathematical guarantee RAM pages are never swapped to persistent swap space. |
| **Crash Safety** | `LimitCORE=0` & `fs.suid_dumpable=0` | Prevents core dump memory dumps to disk on application segmentation fault or panic. |
| **Audit Logs** | Systemd `Storage=volatile` & Nginx silent body | Prevents request body payloads from leaking into system logs or syslog. |
| **Process Isolation** | Systemd `DynamicUser=yes` & `ProtectSystem=strict` | Node runs under an ephemeral user existing strictly in kernel RAM; filesystem read-only. |
| **Secret Management** | Root-locked `/etc/myapp/config.env` (0600) | Secrets injected by CI/CD at boot, inaccessible to unprivileged processes. |

---

## Chapter 0: Prerequisites & Tooling Checklist

Before executing this blueprint, ensure you have access to the following accounts, domains, and local CLI utilities.

### 1. External Services & Accounts
- **AWS Account:** IAM user with permissions to manage EC2, Elastic IPs, and Security Groups.
- **GoDaddy Account:** Access to Manage DNS for domain `moi01.vip`.
- **GitHub Account / Org:** Admin access to the repository `moi01-vault` under your organization.
- **Destination Compute Host:** (Oracle Cloud Infrastructure, AWS, GCP, or any Linux VPS) for hosting the independent audit sink destination.

### 2. Local Workstation Requirements (MacBook / Linux CLI)
Install the required tools locally:
```bash
# macOS via Homebrew
brew install opentofu node git awscli

# Verify versions
tofu --version      # OpenTofu v1.6.0+
node --version      # Node.js v20.x.x
git --version       # Git 2.40+
aws --version       # AWS CLI v2+
```

---

## Chapter 1: GitOps Strategy & Repository Structure

### 0. Initial Repository Setup (Local MacBook Workstation)
Open your terminal, navigate to your home directory (`~`), and clone the repository:
```bash
cd ~
git clone https://github.com/<your-org>/moi01-vault.git MOI01
cd ~/MOI01
```

### 1. Clean Pyramid Directory Layout

```
/srv/MOI01/
├── client/                            ← Local MacBook Workstation Tools
│   └── generate-test-payloads.sh
├── vault/                             ← Core Vault Application (Node.js + Frontend UI)
│   ├── src/
│   │   ├── server.js                  ← Express server (RAM-only payload relay)
│   │   └── public/index.html          ← Frontend file-upload UI
│   ├── config/
│   │   ├── nginx.conf                 ← Nginx reverse proxy config
│   │   └── moi01.service              ← systemd service unit
│   ├── test/test.js                   ← Unit & integration test suite (`npm test`)
│   └── package.json
├── destination/                       ← Independent Destination Audit Sink
│   └── audit_sink.py                  ← Python audit server + Live HTML Dashboard
├── scripts/
│   └── server-init.sh                 ← One-shot server OS hardening & bootstrap
├── infra/                             ← OpenTofu IaC
└── docs/
    └── DEPLOYMENT_BLUEPRINT.md        ← Master Handover Guide ("The Book")
```

### 2. GitHub Secrets & Variable Reference Matrix
- For a complete line-by-line directory of all configurable variables, file locations, line numbers, and GitHub Secrets, see **[`docs/CONFIGURATION_MATRIX.md`](docs/CONFIGURATION_MATRIX.md)**.
- To configure parameters interactively without editing code files, run: `./scripts/configure.sh`.

Navigate to **GitHub Repository → Settings → Secrets and variables → Actions → New repository secret** and configure:


| Secret Name | Example Value | Description |
| :--- | :--- | :--- |
| `AWS_SSH_KEY` | `-----BEGIN OPENSSH PRIVATE KEY-----...` | Private SSH key (`.pem`) matching the AWS EC2 Key Pair. |
| `SERVER_IP` | `54.210.x.x` | Elastic IP assigned to the AWS EC2 Vault server. |
| `WEBHOOK_URL` | `http://<DESTINATION_IP>:8080/audit2026/submit` | Destination endpoint for payload forwarding. |
| `API_KEY` | `sec_live_9f8a7b6c5d4e3f2a1b` | Bearer token injected into request headers. |

---

## Chapter 2: Infrastructure as Code (OpenTofu)

We use **OpenTofu** (open-source Terraform fork) to provision identical AWS resources programmatically.

```bash
# Navigate to the infrastructure directory
cd ~/MOI01/infra


# Initialize OpenTofu providers
tofu init

# Copy example variables and edit key_name
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Set key_name = "moi01-vault-key"

# Review execution plan & apply
tofu plan
tofu apply -auto-approve
```


Retrieve the static Elastic IP from the output:
```
Outputs:
elastic_ip = "54.210.123.45"
```
Use this `elastic_ip` for GoDaddy DNS and the GitHub Secret `SERVER_IP`.

> [!IMPORTANT]
> **IT / Network Administrator Requirement — Inbound Firewall Ports:**
> The AWS Security Group (and any corporate network firewalls) **MUST** allow inbound traffic on:
> - **Port 80 (HTTP):** **REQUIRED** for Let's Encrypt TLS ACME challenge verification & HTTP-to-HTTPS 301 redirection.
> - **Port 443 (HTTPS):** **REQUIRED** for encrypted production Vault traffic.
> - **Port 22 (SSH):** **REQUIRED** for administration & CI/CD deployment.
> 
> *Note: Port 80 must NOT be closed after TLS setup because Let's Encrypt auto-renews certificates every 60 days via Port 80.*


---

## Chapter 3: GoDaddy DNS & Domain Delegation

1. Log in to **GoDaddy Domain Control Center**.
2. Select `moi01.vip` and navigate to **DNS Management**.
3. Under **Records**, add an **A Record**:
   - **Type:** `A`
   - **Name:** `@`
   - **Value:** `<YOUR_ELASTIC_IP>` (e.g., `54.210.123.45`)
   - **TTL:** `600 seconds`
4. Verify propagation from your local terminal:
   ```bash
   dig +short moi01.vip @8.8.8.8
   ```

---

## Chapter 4: Initial AWS EC2 Bootstrap & OS Hardening

SSH into the server for one-time initialization:
```bash
ssh -i /path/to/moi01-vault-key.pem ubuntu@<YOUR_ELASTIC_IP>
```

Clone the repository and run the bootstrap script:
```bash
sudo mkdir -p /var/www/moi01.vip
sudo chown -R ubuntu:ubuntu /var/www/moi01.vip
git clone https://github.com/<your-org>/moi01-vault.git /var/www/moi01.vip

cd /var/www/moi01.vip
chmod +x scripts/server-init.sh
sudo ./scripts/server-init.sh
```

---

## Chapter 5: Automated TLS / SSL Setup (Let's Encrypt & Nginx)

Once DNS propagation is confirmed, issue the Let's Encrypt TLS certificate:
```bash
sudo certbot --nginx -d moi01.vip --non-interactive --agree-tos -m admin@moi01.vip
```

Verify auto-renewal:
```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
```

---

## Chapter 6: Ephemeral Application Supervisor (`moi01.service`)

The application runs under systemd with strict sandbox isolation.

### Service Unit Location: `/etc/systemd/system/moi01.service`
```ini
[Unit]
Description=MOI01.VIP Zero-Knowledge Vault Service
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/node /var/www/moi01.vip/vault/src/server.js
WorkingDirectory=/var/www/moi01.vip/vault
Restart=always
RestartSec=3s

EnvironmentFile=/etc/myapp/config.env

StandardOutput=null
StandardError=null
LimitCORE=0

DynamicUser=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
NoNewPrivileges=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictNamespaces=yes
RestrictSUIDSGID=yes
ReadOnlyPaths=/var/www/moi01.vip

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now moi01.service
sudo systemctl status moi01.service
```

---

## Chapter 7: The CI/CD Automated Deployment Pipeline

Automated push deployment via `.github/workflows/deploy.yml`:

```yaml
name: Deploy Zero-Knowledge Vault

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.SERVER_IP }}
          username: ubuntu
          key: ${{ secrets.AWS_SSH_KEY }}
          script: |
            sudo mkdir -p /etc/myapp
            sudo bash -c 'cat > /etc/myapp/config.env << ENVEOF
            PORT=3000
            WEBHOOK_URL=${{ secrets.WEBHOOK_URL }}
            API_KEY=${{ secrets.API_KEY }}
            ENVEOF'
            sudo chown root:root /etc/myapp/config.env
            sudo chmod 600 /etc/myapp/config.env

            cd /var/www/moi01.vip
            sudo git fetch origin main
            sudo git reset --hard origin/main

            cd /var/www/moi01.vip/vault
            sudo npm install --production --no-audit --no-fund

            sudo systemctl daemon-reload
            sudo systemctl restart moi01.service
```

---

## Chapter 8: Independent Destination Audit Sink

Deploy `destination/audit_sink.py` on your destination server (Oracle Cloud, AWS, GCP, or VPS):

```bash
# Open TCP port 8080 on firewall
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# Launch destination audit sink
python3 destination/audit_sink.py --port 8080 --token audit2026
```

Access the Live Dashboard in your browser at:  
`http://<DESTINATION_SERVER_IP>:8080/audit2026/`

---

## Chapter 9: Live Testing & Compliance Verification Protocol

Execute this 3-step test protocol to visually demonstrate zero-knowledge compliance for video recording or audits.

### Step 1: Generate Local Test Payloads
On your MacBook:
```bash
chmod +x client/generate-test-payloads.sh
./client/generate-test-payloads.sh
```

### Step 2: Protocol Matrix

| Test Case | Action | Expected Result |
| :--- | :--- | :--- |
| **1. 500KB Transfer** | Upload `test-500kb.json` via Vault UI | `HTTP 200 OK`; Destination Dashboard flashes green; `iotop` writes `0.00 B` |
| **2. 10MB Overflow** | Upload `test-10mb.json` via Vault UI | `HTTP 413` dropped at Nginx edge; Node.js never sees request |
| **3. Process Sabotage**| Run `sudo kill -SEGV <PID>` on Vault | Systemd auto-revives process in <3s; 0 core dumps written |

---

## Chapter 10: Threat Model & Blast Radius Analysis

In a enterprise deployment where Nginx and Node.js reside on the same EC2 instance, the architecture strictly enforces **Zero-Privilege Blast Radius Isolation**:

### 1. Attacker Scenario A: Remote Code Execution (RCE) in Node.js
Suppose a bad actor discovers an unpatched vulnerability in an npm package and executes arbitrary code within the Node.js process:
- **Phantom User (`DynamicUser=yes`):** The process runs under an ephemeral user ID that exists strictly in kernel RAM during runtime. It has no entry in `/etc/passwd` or `/etc/shadow`.
- **Filesystem Read-Only (`ProtectSystem=strict`):** The entire Linux filesystem (`/`, `/etc`, `/usr`, `/var`, `/home`) is mounted as **READ-ONLY**. The attacker **cannot modify any application file, write persistent backdoors, or tamper with binaries**.
- **No Access to Secrets File:** Environment secrets (`API_KEY`, `WEBHOOK_URL`) are injected into process memory by systemd from `/etc/myapp/config.env` (`owned by root:root, mode 0600`). Unprivileged Node.js **cannot read `/etc/myapp/config.env` from disk**.
- **Zero Disk Payload Data:** Even if code execution occurs, **there are zero customer payload files on disk to exfiltrate**, because all incoming payloads reside strictly in volatile V8 RAM and are garbage collected upon forwarding.

### 2. Attacker Scenario B: Nginx Reverse Proxy Compromise
- Nginx runs under unprivileged `www-data`.
- `proxy_buffering off;` and `proxy_request_buffering off;` ensure request streams pass directly through RAM without writing body buffer files to `/var/lib/nginx/body`.
- `client_max_body_size 1m;` drops oversized payloads at the socket layer before reaching Node.js.

### 3. Attacker Scenario C: Crash Panic & Core Dump Theft
- `LimitCORE=0` and `fs.suid_dumpable=0` disable kernel core dumps.
- If an attacker triggers a crash or panic, **zero memory dump files are written to disk** (`/var/crash/` remains 0 files).

---

## Sign-Off & Verification

This blueprint represents the definitive operational specification for **MOI01.VIP**.


**Architect:** Principal Systems Architect  
**Approved for Production:** Yes  

