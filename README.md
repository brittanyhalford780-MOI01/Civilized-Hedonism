# MOI01.VIP — Zero-Knowledge Ephemeral Vault

A military-grade, zero-knowledge payload relay built on Node.js. All incoming data lives exclusively in volatile V8 RAM — nothing touches physical storage (SSD/EBS), ever.

---

## 🏛️ System Architecture

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

---

## 📂 Repository Layout

The repository is organized logically into dedicated layers:

```
~/MOI01/
├── README.md                           ← Master Repository README
│
├── _docs/                              ← Master Handover Documentation (Floats to Top)
│   ├── DEPLOYMENT_BLUEPRINT.md             ← Master Deployment Blueprint ("The Book")
│   └── CONFIGURATION_MATRIX.md             ← Line-by-line variable & secret cheat sheet
│
├── app/                                ← Core Vault Application (AWS EC2 Server)
│   ├── src/
│   │   ├── server.js                       ← Node.js RAM-only payload relay & webhook forwarder
│   │   └── public/
│   │       └── index.html                      ← Secure Intake Web UI (Glassmorphic dark design)
│   ├── config/
│   │   ├── nginx.conf                      ← Nginx edge proxy config (1MB payload cap, no buffering)
│   │   └── moi01.service                   ← systemd sandbox service unit (DynamicUser, zero core dumps)
│   ├── test/
│   │   └── test.js                         ← Native node:test suite (`npm test`)
│   └── package.json                    ← Node.js package manifest
│
├── destination/                        ← Independent Destination Audit Sink
│   └── audit_sink.py                       ← Standalone Python audit server + Live HTML Dashboard
│
├── tools/                              ← Server Operations & Tools
│   ├── configure.sh                        ← Interactive configuration wizard
│   ├── destroy.sh                          ← 1-Click infrastructure teardown script
│   ├── server-init.sh                      ← One-shot server OS hardening & package setup
│   └── test-app.sh                         ← 1-Click Master Audit & Auto-Healing Test Suite
│
├── infra/                              ← Infrastructure as Code (OpenTofu / AWS)
│   ├── main.tf                             ← EC2, Security Group (SSH/80/443), Elastic IP
│   ├── variables.tf                        ← Infrastructure parameters
│   ├── outputs.tf                          ← Exported values (Elastic IP)
│   └── terraform.tfvars.example            ← Example tfvars
│
└── .github/
    └── workflows/
        └── deploy.yml                      ← GitHub Actions CI/CD deployment pipeline
```

---

## ⚡ Quick Start & Operational Flow

### 🚀 0. Clone Repository to Home Directory (`~`)
Open your MacBook terminal, navigate to your home directory (`~`), and clone the repository:
```bash
cd ~
git clone https://github.com/brittanyhalford780-MOI01/Civilized-Hedonism.git MOI01
cd ~/MOI01
```

### 🧙 1. OS-Agnostic Setup Wizard & Support Concierge (Automated Guidance)
Run the smart interactive wizard from your terminal. It automatically detects your operating system (**macOS**, **Linux (Ubuntu/Debian/Fedora/Arch)**, or **Windows WSL/Git Bash**), provides platform-specific installation commands, audits AWS keys & SSH key pairs, provisions OpenTofu infrastructure, polls live DNS propagation until resolution, and formats GitHub Secrets safely.

If an error or missing tool occurs, the wizard generates an instant **Lead Engineer Diagnostic Report (`audit_diagnostics.txt`)** and prompt snippet for immediate resolution:
```bash
cd ~/MOI01
chmod +x ./tools/configure.sh
./tools/configure.sh

# Jump directly to Step 6 (Deployment Launch) at any time:
./tools/configure.sh --step 6
```

### 🚀 2. 1-Click Deployment Launch (Direct SSH or GitHub Encrypted CI/CD)

Once the setup wizard reaches Step 6, choose your preferred deployment method:

#### Option 1: Direct 1-Click Wizard Deployment via SSH (Fastest — Zero GitHub Setup Required)
Select **Option 1** in `./tools/configure.sh`.  
The wizard automatically uses your generated SSH key (`~/.ssh/moi01-vault-key.pem`) to:
1. Connect directly to your EC2 instance (`ubuntu@<YOUR_ELASTIC_IP>`).
2. Sync the codebase to `/var/www/moi01.vip`.
3. Run OS hardening, install Node.js/Nginx, configure TLS, and launch `moi01.service`.
4. **No Git credentials, GitHub accounts, or personal access tokens required!**

#### Option 2: GitHub Encrypted Secrets CI/CD Pipeline (Recommended for Enterprise Security & Teams)
For enterprise production environments, storing sensitive variables (`API_KEY`, `WEBHOOK_URL`, `AWS_SSH_KEY`) inside **GitHub Encrypted Secrets** prevents credentials from being exposed on local workstations:
1. In your browser, go to **GitHub Repository → Settings → Secrets and variables → Actions**.
2. Add the 4 secrets (`SERVER_IP`, `AWS_SSH_KEY`, `WEBHOOK_URL`, `API_KEY`).
3. Push code to `main` branch to trigger automated deployment via `.github/workflows/deploy.yml`.

#### 🌐 3. Direct Web App Access & Transmission
Once deployed, access the live application in your browser:
- **Direct Server IP**: `http://<YOUR_SERVER_IP>`
- **Production Domain**: `https://<YOUR_DOMAIN>`

#### 🎥 3B. Live Video Demonstration & Handover Verification Protocol (3-Node Setup)

```
  ┌──────────────────────────┐    HTTPS Transmit    ┌──────────────────────────┐    HTTP Relay     ┌──────────────────────────┐
  │   MAC CLIENT WORKSTATION │ ───────────────────> │  VAULT EC2 SERVER NODE   │ ────────────────> │ DESTINATION AUDIT SINK   │
  │   (MacBook / Browser)    │                      │  (https://<YOUR_DOMAIN>) │                   │ (http://<DESTINATION_IP>)│
  └──────────────────────────┘                      └──────────────────────────┘                   └──────────────────────────┘
```

##### Node 1: Setup Independent Destination Audit Sink Server
On your Destination Server (`<DESTINATION_IP>` or any Linux VPS):
```bash
# Upload destination/audit_sink.py and run as root on Port 80
sudo python3 audit_sink.py --port 80 --token audit2026
```
Open the Audit Sink Dashboard in your browser: `http://<DESTINATION_IP>/audit2026/` *(Displays TOTAL RECEIVED: 0)*.

##### Node 2: Target Monitoring of Node.js Vault Application Process
SSH into your Vault EC2 Node to monitor the Node.js Vault process (`moi01.service`) specifically:

```bash
# 1. Watch Node.js RAM & CPU Metrics ONLY (Filtered to ignore unrelated OS tasks)
# WHY: Proves Node.js operates cleanly within V8 RAM during intake.
ssh -t -i credentials/moi01-vault-key.pem ubuntu@<YOUR_SERVER_IP> "top -p \$(pgrep -d',' node)"

# 2. Prove 0.00 B Disk Writes for Node.js Process (Physical SSD Audit)
# WHY: Accumulates total disk writes for Node.js to mathematically prove 0 bytes touch SSD storage.
ssh -t -i credentials/moi01-vault-key.pem ubuntu@<YOUR_SERVER_IP> "sudo iotop -o -a -p \$(pgrep -d',' node)"

# 3. Stream Live Volatile Application Status (Stored in Volatile Kernel RAM Only)
# WHY: Streams real-time HTTP 200 relay status without logging any customer payload contents.
ssh -i credentials/moi01-vault-key.pem ubuntu@<YOUR_SERVER_IP> "sudo journalctl -u moi01.service -f"

# 4. Verify Zero Swap Paging (Kernel RAM-Only Enforcement)
# WHY: Confirms swap is disabled (returns empty), guaranteeing memory pages never swap to disk.
ssh -i credentials/moi01-vault-key.pem ubuntu@<YOUR_SERVER_IP> "swapon --show"
```

##### Node 3: Transmit Test Payloads & Run Master Audit Suite
1. Run 1-Click Master Audit & Auto-Healing Test Suite (`tests/` workspace):
   ```bash
   chmod +x ./tools/test-vault.sh
   ./tools/test-vault.sh
   ```
   *(Generates dynamic test payloads in `tests/`, verifies HTTP 200/413, executes load ramp, simulates `kill -9` process sabotage, verifies systemd auto-healing, and saves report to `tests/AUDIT_TEST_REPORT.md`).*

2. Open `https://<YOUR_DOMAIN>` in your web browser for visual UI verification:
   - **Test 1 (Valid Intake)**: Drag & drop `tests/test-500kb.json` → Click **Transmit to Vault**.  
     *Result*: Vault UI displays `✅ Payload processed (500.00 KB). RAM wiped. Relayed to destination.`  
     *Audit Sink Dashboard*: Increments live showing `🔑 Bearer audit2026`.
   - **Test 2 (Edge Protection)**: Drag & drop `tests/test-10mb.json` → Click **Transmit to Vault**.  
     *Result*: Nginx/Vault blocks file with `🛡️ Error 413: Payload exceeds RAM limits. Dropped at edge.`

---

### 💥 4. Total Infrastructure Destruction & Cleanup (`destroy.sh`)
To 100% terminate all AWS resources (EC2 instance, Elastic IP, Security Groups, EBS volumes) and wipe all local credentials/keys:
```bash
cd ~/MOI01
chmod +x ./tools/destroy.sh
./tools/destroy.sh
```
*(When prompted, type `DESTROY` to confirm complete teardown).*

---

### 📋 5. Variable Cheat Sheet
For a complete matrix of all variables, line numbers, default values, and GitHub Secrets, see:  
👉 **[Configuration Matrix](_docs/CONFIGURATION_MATRIX.md)**

### 🧪 6. Run Vault Unit Tests
```bash
cd ~/MOI01/app
npm test
```

### 🏗️ 7. Provision AWS Infrastructure (OpenTofu IaC Manual Reference)
```bash
cd ~/MOI01/infra
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu apply
```

### 📘 8. Master Deployment Blueprint
For the complete step-by-step handover guide covering local setup, DNS delegation, Let's Encrypt TLS, systemd sandboxing, and the 3-step live verification protocol, see:  
👉 **[Deployment Blueprint](_docs/DEPLOYMENT_BLUEPRINT.md)**


---

## 🔒 Threat Model & Containment Matrix (Blast Radius Analysis)

If a bad actor attempts to exploit an application vulnerability or compromise Nginx / Node.js, the system enforces **Zero-Privilege Blast Radius Isolation**:

```
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │                                ATTACK CONTAINMENT MATRIX                                │
 ├──────────────────┬───────────────────────────────┬──────────────────────────────────────┤
 │ Vector           │ Attacker Goal                 │ Defense & Containment Result         │
 ├──────────────────┼───────────────────────────────┼──────────────────────────────────────┤
 │ Node.js Exploit  │ RCE / Shell Execution         │ 💥 CONTAINED: Runs under DynamicUser │
 │                  │                               │ (ephemeral RAM user). ProtectSystem   │
 │                  │                               │ makes filesystem 100% READ-ONLY.     │
 ├──────────────────┼───────────────────────────────┼──────────────────────────────────────┤
 │ Disk Persistence │ Exfiltrate Stored Files       │ 💥 FAILS: Zero payloads touch disk.  │
 │                  │                               │ RAM-only V8 pipeline.                │
 ├──────────────────┼───────────────────────────────┼──────────────────────────────────────┤
 │ Secret Theft     │ Read /etc/myapp/config.env    │ 💥 FAILS: File owned by root:root    │
 │                  │                               │ mode 0600. Node cannot read file.    │
 ├──────────────────┼───────────────────────────────┼──────────────────────────────────────┤
 │ Memory Dump      │ Core Dump / Crash Inspection  │ 💥 FAILS: LimitCORE=0 & suid_dump=0  │
 │                  │                               │ disables crash dump creation.        │
 ├──────────────────┼───────────────────────────────┼──────────────────────────────────────┤
 │ Privilege Escalation │ Elevate to root via sudo  │ 💥 FAILS: NoNewPrivileges=yes &      │
 │                  │                               │ ProtectKernelTunables prevents sudo. │
 └──────────────────┴───────────────────────────────┴──────────────────────────────────────┘
```

---

## 🛡️ Security Guarantees Matrix


| Component | Protection Mechanism | Security Impact |
| :--- | :--- | :--- |
| **OS Kernel** | `swapoff -a` & `vm.swappiness=0` | Prevents RAM pages from swapping to disk |
| **OS Memory** | `LimitCORE=0` & `fs.suid_dumpable=0` | Disables core dumps on process crash |
| **System Logs**| Volatile `journald` in RAM | Keeps request logs out of persistent disk |
| **Nginx Edge** | `client_max_body_size 1m;` | Drops payloads > 1MB at edge parser boundary |
| **Nginx Buffers**| `proxy_buffering off;` | Disables writing proxy body buffers to disk temp files |
| **Node.js** | Ephemeral RAM pipeline | Zero `fs.write*` calls; data garbage-collected |
| **systemd** | `DynamicUser=yes` & `ProtectSystem=strict` | Process runs under transient RAM user; filesystem read-only |

---

## 📜 License

MOI Proprietary — All rights reserved 2026.





