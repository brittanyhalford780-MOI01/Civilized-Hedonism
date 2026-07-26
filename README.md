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
├── client/                             ← Local MacBook Workstation Tools
│   └── generate-test-payloads.sh           ← Generates test-500kb.json & test-10mb.json
│
├── vault/                              ← Core Vault Application (AWS EC2 Server)
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
├── scripts/                            ← Server Operations & Tools
│   ├── server-init.sh                      ← One-shot server OS hardening & package setup
│   └── configure.sh                        ← Interactive configuration wizard
│
├── infra/                              ← Infrastructure as Code (OpenTofu / AWS)
│   ├── main.tf                             ← EC2, Security Group (SSH/80/443), Elastic IP
│   ├── variables.tf                        ← Infrastructure parameters
│   ├── outputs.tf                          ← Exported values (Elastic IP)
│   └── terraform.tfvars.example            ← Example tfvars
│
├── docs/                               ← Master Handover Documentation
│   ├── DEPLOYMENT_BLUEPRINT.md             ← Master Deployment Blueprint ("The Book")
│   └── CONFIGURATION_MATRIX.md             ← Line-by-line variable & secret cheat sheet
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
git clone https://github.com/<your-org>/moi01-vault.git MOI01
cd ~/MOI01
```

### 🧙 1. OS-Agnostic Setup Wizard & Support Concierge (Automated Guidance)
Run the smart interactive wizard from your terminal. It automatically detects your operating system (**macOS**, **Linux (Ubuntu/Debian/Fedora/Arch)**, or **Windows WSL/Git Bash**), provides platform-specific installation commands, audits AWS keys & SSH key pairs, provisions OpenTofu infrastructure, polls GoDaddy DNS live until resolution, and formats GitHub Secrets safely.

If an error or missing tool occurs, the wizard generates an instant **Lead Engineer Diagnostic Report (`audit_diagnostics.txt`)** and prompt snippet for immediate resolution:
```bash
cd ~/MOI01
./scripts/configure.sh
```



### 📋 2. Variable Cheat Sheet
For a complete matrix of all variables, line numbers, default values, and GitHub Secrets, see:  
👉 **[Configuration Matrix](docs/CONFIGURATION_MATRIX.md)**

### 🧪 3. Run Vault Tests
```bash
cd ~/MOI01/vault
npm test
```

### 🏗️ 4. Provision AWS Infrastructure (OpenTofu)
```bash
cd ~/MOI01/infra
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu apply
```



### 📘 5. Master Deployment Blueprint
For the complete step-by-step handover guide covering local setup, DNS delegation, Let's Encrypt TLS, systemd sandboxing, and the 3-step live verification protocol, see:  
👉 **[Deployment Blueprint](docs/DEPLOYMENT_BLUEPRINT.md)**


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

