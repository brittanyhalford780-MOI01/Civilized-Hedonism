# MOI01.VIP — Configuration & Variable Reference Matrix

**Document Version:** 1.0.0  
**Classification:** Operational Guide & Variable Directory  

This document serves as the single source of truth for **all configurable parameters** across the entire MOI01.VIP codebase. It specifies:
1. **GitHub Secrets (Automated & Zero-Code)** — Injected into the server at deployment; never written in code files.
2. **Manual & System Code Tweaks** — Exact file paths, line numbers, default values, and safe boundaries for manual adjustments.
3. **Interactive Configurator Utility** — How to change parameters automatically without opening code files.

---

## 🚀 Easy Mode: Interactive Configuration Wizard

For non-technical administrators who prefer **NOT** to edit code files manually, run the included terminal wizard from your MacBook or workstation:

```bash
cd ~/MOI01
chmod +x scripts/configure.sh
./scripts/configure.sh
```



### What the Smart Wizard Automatically Handles:
- **OS-Agnostic Environment Detection:** Detects **macOS**, **Linux (Ubuntu/Debian/Fedora/Arch)**, or **Windows (WSL/Git Bash)** and tailors package manager commands (`brew`, `apt`, `dnf`, `winget`).
- **Pre-flight Tool Audit:** Checks `git`, `node`, `tofu`, `aws`, `dig` and provides platform-tailored 1-liner install commands if missing.
- **AWS Credentials & Key Pair Guidance:** Audits AWS access keys and `.pem` SSH key pairs. Offers automated 1-click AWS SSH key generation if missing.
- **Lead Engineer Escalation Helper:** If any tool or credential check fails, automatically writes an `audit_diagnostics.txt` report file and formats a copy-paste prompt snippet to send to the Lead Systems Engineer or AI Copilot.
- **System Customization:** Interactively configures Domain Name, AWS Region, and Payload Size Limit.
- **Live DNS Propagation Poller:** Periodically checks DNS `@8.8.8.8` after OpenTofu provisions the Elastic IP, displaying a live progress counter until GoDaddy DNS resolves!
- **GitHub Secrets Manager:** Formats all required GitHub Secrets (`SERVER_IP`, `AWS_SSH_KEY`, `WEBHOOK_URL`, `API_KEY`) for easy copy-paste or 1-click `gh secret set`.
- **Security Guarantee:** Uses masked inputs (`read -s`) for secrets — credentials are **NEVER** saved to disk or shell history.



---

## 🔑 Category 1: GitHub Secrets Matrix (Zero-Hardcoding Policy)

These values **MUST NEVER** be committed to Git or written in source files.  
Configure them in: **GitHub Repo → Settings → Secrets and variables → Actions → New repository secret**.

| Secret Name | Required / Optional | Example / Format | Purpose | Where Injected at Boot |
| :--- | :--- | :--- | :--- | :--- |
| `SERVER_IP` | **Required** | `54.210.123.45` | Elastic IP of the AWS EC2 instance | `/etc/myapp/config.env` |
| `AWS_SSH_KEY` | **Required** | `-----BEGIN OPENSSH PRIVATE KEY-----...` | Private key matching AWS EC2 Key Pair | Used by SSH runner |
| `WEBHOOK_URL` | **Required** | `http://<DESTINATION_IP>:8080/audit2026/submit` | Forwarding target for audit payloads | `/etc/myapp/config.env` |
| `API_KEY` | **Optional** | `sec_live_9f8a7b6c5d4e3f2a1b` | Bearer token header sent to destination | `/etc/myapp/config.env` |

---

## 🌐 Category 1B: IT & Network Firewall Requirements

The IT / Infrastructure Lead **MUST** configure the AWS Security Group (or corporate firewalls) to allow the following inbound ports:

| Port | Protocol | Source CIDR | Why It Is Mandatory | Can It Be Closed Later? |
| :---: | :---: | :---: | :--- | :--- |
| **80** | TCP | `0.0.0.0/0` | **Let's Encrypt ACME Challenge & HTTP→HTTPS 301 Redirection** | **NO.** Closing Port 80 will break automatic 60-day SSL renewals. |
| **443** | TCP | `0.0.0.0/0` | **Production Encrypted Vault Traffic (HTTPS)** | **NO.** Required for end-user secure intake. |
| **22** | TCP | Admin CIDR / `0.0.0.0/0` | **SSH Administration & GitHub Actions CI/CD Deployments** | **NO.** Required for automated CI/CD code updates. |

---

## 🛠️ Category 2: Manual Code & Configuration Variable Matrix


If you need to customize system limits, ports, or domain settings manually, refer to the exact file paths and line numbers below.

### 1. Edge Proxy & Payload Limits (`vault/config/nginx.conf`)

Target File: [`vault/config/nginx.conf`](file:///srv/MOI01/vault/config/nginx.conf)

| Variable / Directive | Exact Line | Default Value | Operational Purpose | Safe Adjustment Range |
| :--- | :---: | :---: | :--- | :--- |
| `server_name` | **L16** | `moi01.vip` | Domain name for HTTP/S routing | Set to your domain name |
| `client_max_body_size` | **L19** | `1m` | Edge body size limit dropped before Node.js | `1m` to `5m` (Must match `server.js`) |
| `rate` limit | **L13** | `10r/s` | Rate limit per client IP address | `5r/s` to `50r/s` |
| `burst` limit | **L30** | `burst=20` | Maximum burst queue before HTTP 429 | `10` to `50` |

---

### 2. Node.js Application Parameters (`vault/src/server.js`)

Target File: [`vault/src/server.js`](file:///srv/MOI01/vault/src/server.js)

| Variable Name | Exact Line | Default Value | Operational Purpose | Safe Adjustment Range |
| :--- | :---: | :---: | :--- | :--- |
| `PORT` | **L25** | `3000` | Local port Node.js listens on | `3000` to `9000` (Must match Nginx `proxy_pass`) |
| `MAX_PAYLOAD_BYTES` | **L28** | `1 * 1024 * 1024` (1MB) | RAM JSON parser size limit | Must match Nginx `client_max_body_size` |
| `timeout` | **L135** | `10000` (10s) | Webhook forward request timeout in ms | `3000` to `30000` |

---

### 3. OpenTofu / AWS Infrastructure (`infra/variables.tf` & `infra/terraform.tfvars.example`)

Target Files: [`infra/variables.tf`](file:///srv/MOI01/infra/variables.tf) and [`infra/terraform.tfvars.example`](file:///srv/MOI01/infra/terraform.tfvars.example)

| Variable Name | File & Line | Default Value | Operational Purpose | Safe Adjustment Range |
| :--- | :---: | :---: | :--- | :--- |
| `aws_region` | `variables.tf` **L7** | `"us-east-1"` | AWS region for EC2 deployment | Any valid AWS region code |
| `instance_type` | `variables.tf` **L13** | `"t3.micro"` | EC2 compute instance tier | `t3.micro` (free tier) to `t3.small` |
| `ami_id` | `variables.tf` **L19** | `"ami-0b6d9d3d33ba97d99"` | Ubuntu 24.04 LTS AMI ID | Must match selected AWS region |
| `key_name` | `variables.tf` **L25** | Required | Name of your AWS SSH Key Pair | Set to your AWS key pair name |
| `ssh_allowed_cidrs` | `variables.tf` **L30** | `["0.0.0.0/0"]` | Allowed SSH inbound IP blocks | Restrict to your office/admin IP |

---

### 4. Destination Audit Sink Parameters (`destination/audit_sink.py`)

Target File: [`destination/audit_sink.py`](file:///srv/MOI01/destination/audit_sink.py)

| Variable Name | Exact Line | Default Value | Operational Purpose | Safe Adjustment Range |
| :--- | :---: | :---: | :--- | :--- |
| `LISTEN_PORT` | **L21** | `8080` | Port audit sink listens on | Any unprivileged port (`8080`, `9090`) |
| `DEFAULT_TOKEN` | **L22** | `"audit2026"` | URL path segment token | Set to a secret alphanumeric token |
| `MAX_LOG_ENTRIES` | **L23** | `1000` | Max entries held in volatile RAM | `100` to `5000` |
| `PREVIEW_BYTES` | **L24** | `500` | Payload preview byte truncation limit | `100` to `2000` |

---

### 5. systemd Sandbox Supervisor (`vault/config/moi01.service`)

Target File: [`vault/config/moi01.service`](file:///srv/MOI01/vault/config/moi01.service)

| Directive Name | Exact Line | Default Value | Security Impact |
| :--- | :---: | :---: | :--- |
| `RestartSec` | **L19** | `3s` | Seconds to wait before auto-restarting process on panic/crash |
| `EnvironmentFile` | **L22** | `/etc/myapp/config.env` | Location of root-locked environment file |
| `LimitCORE` | **L27** | `0` | Disables core dumps (no crash data to disk) |
| `DynamicUser` | **L30** | `yes` | Creates ephemeral RAM-only process user |
| `ProtectSystem` | **L31** | `strict` | Mounts entire OS file system as read-only |

---

## 📝 Step-by-Step Change Procedure

### To Change Payload Limit (e.g., from 1MB to 2MB):
1. **Option A (Wizard):** Run `./scripts/configure.sh`, enter `2` for payload size limit. Done!
2. **Option B (Manual):**
   - Open [`vault/config/nginx.conf`](file:///srv/MOI01/vault/config/nginx.conf#L19), change `client_max_body_size 1m;` → `client_max_body_size 2m;`.
   - Open [`vault/src/server.js`](file:///srv/MOI01/vault/src/server.js#L28), change `1 * 1024 * 1024` → `2 * 1024 * 1024`.
   - Commit & push to `main` branch.

### To Change Webhook Destination or API Key:
1. Go to **GitHub Repo → Settings → Secrets and variables → Actions**.
2. Click **Edit** next to `WEBHOOK_URL` or `API_KEY`.
3. Paste the new value and click **Update Secret**.
4. Re-run or push to `main` — GitHub Actions will inject the new secret into `/etc/myapp/config.env` on deployment.

