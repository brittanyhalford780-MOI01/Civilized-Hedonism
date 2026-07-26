#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — OS-Agnostic Intelligent Setup Wizard (v4.0.0)
#
# PURPOSE:
#   An OS-agnostic, multi-platform interactive CLI wizard for macOS, Linux,
#   and Windows (WSL/Git Bash). Detects OS environment automatically, provides
#   tailored package installation commands, guides AWS setup, polls GoDaddy DNS,
#   and includes an automated "Contact Lead Engineer / Diagnostic Log" escalation helper.
#
# USAGE:
#   cd ~/MOI01
#   ./scripts/configure.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── ANSI Color Tokens ─────────────────────────────────────────────────────────

BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
MAGENTA="\033[0;35m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$REPO_ROOT/.wizard_state.json"
DIAGNOSTIC_FILE="$REPO_ROOT/audit_diagnostics.txt"

# ── OS Detection Logic ────────────────────────────────────────────────────────

DETECTED_OS="unknown"
PACKAGE_MGR="unknown"

detect_operating_system() {
    local os_type="$(uname -s 2>/dev/null || echo "unknown")"
    case "$os_type" in
        Darwin*)
            DETECTED_OS="macOS"
            PACKAGE_MGR="brew"
            ;;
        Linux*)
            DETECTED_OS="Linux"
            if command -v apt-get &>/dev/null; then
                PACKAGE_MGR="apt"
            elif command -v dnf &>/dev/null; then
                PACKAGE_MGR="dnf"
            elif command -v yum &>/dev/null; then
                PACKAGE_MGR="yum"
            elif command -v pacman &>/dev/null; then
                PACKAGE_MGR="pacman"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            DETECTED_OS="Windows (Git Bash/MSYS)"
            PACKAGE_MGR="winget / choco"
            ;;
        *)
            DETECTED_OS="Generic Unix/Linux"
            PACKAGE_MGR="manual"
            ;;
    esac
}

# ── Formatting Helpers ────────────────────────────────────────────────────────

banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo " ╔═════════════════════════════════════════════════════════════════════╗"
    echo " ║                                                                     ║"
    echo " ║   🏛️  MOI01.VIP — Ephemeral Vault Setup Wizard (OS-Agnostic)        ║"
    echo " ║   Zero-Knowledge Architecture · Principal Engineer Edition          ║"
    echo " ║                                                                     ║"
    echo " ╚═════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    local step_num="$1"
    local title="$2"
    echo ""
    echo -e "${MAGENTA}${BOLD}───────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${MAGENTA}${BOLD}  [STEP $step_num of 6] ▸ $title${NC}"
    echo -e "${MAGENTA}${BOLD}───────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

info() { echo -e "${CYAN}ℹ ${NC} $1"; }
success() { echo -e "${GREEN}✔ ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $1"; }
error() { echo -e "${RED}✖ ${NC} $1"; }
tooltip() { echo -e "${DIM}   💡 HELP: $1${NC}"; }

# ── Escalation & Diagnostic Report Generator ──────────────────────────────────

generate_diagnostic_report() {
    local issue_description="$1"
    
    cat > "$DIAGNOSTIC_FILE" <<EOF
================================================================================
MOI01.VIP — SYSTEM DIAGNOSTIC REPORT FOR LEAD ENGINEER ESCALATION
Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
================================================================================

[OPERATING SYSTEM DETAILS]
OS Detected:      $DETECTED_OS
Kernel Version:   $(uname -r 2>/dev/null || echo "N/A")
Package Manager:  $PACKAGE_MGR
Shell:            $SHELL

[TOOLING STATUS]
Git:              $(command -v git &>/dev/null && git --version || echo "MISSING")
Node.js:          $(command -v node &>/dev/null && node --version || echo "MISSING")
OpenTofu/Tform:   $(command -v tofu &>/dev/null && tofu --version | head -n1 || command -v terraform &>/dev/null && terraform --version | head -n1 || echo "MISSING")
AWS CLI:          $(command -v aws &>/dev/null && aws --version | head -n1 || echo "MISSING")
DNS Tool (dig):   $(command -v dig &>/dev/null && echo "AVAILABLE" || echo "MISSING")

[ISSUE DESCRIPTION]
$issue_description

================================================================================
INSTRUCTIONS FOR NON-TECHNICAL USER:
1. Attach or copy the contents of this file ('$DIAGNOSTIC_FILE').
2. Send to your Lead Systems Architect / Security Engineer.
3. Or paste into your AI Assistant for immediate step-by-step resolution.
================================================================================
EOF

    echo ""
    echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}${BOLD}  🆘 NEED HELP? CONTACT LEAD ENGINEER / COPILOT ASSISTANT${NC}"
    echo -e "${RED}${BOLD}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "An automated diagnostic report has been created for you:"
    echo -e "📄 File: ${CYAN}${BOLD}$DIAGNOSTIC_FILE${NC}"
    echo ""
    echo -e "${YELLOW}Copy-paste the prompt below into your AI Chatbot or email to your Lead Architect:${NC}"
    echo -e "${DIM}---------------------------------------------------------------------${NC}"
    echo -e "I'm setting up MOI01.VIP on $DETECTED_OS and encountered an issue:"
    echo -e "  Summary: $issue_description"
    echo -e "Please provide a 1-liner terminal command to fix this."
    echo -e "${DIM}---------------------------------------------------------------------${NC}"
    echo ""
}

# ── Step 1: OS Detection & Dependency Audit ──────────────────────────────────

audit_tools() {
    detect_operating_system
    banner
    print_step "1" "OS Detection & Pre-flight Tooling Audit"

    info "Detected Operating System: ${BOLD}$DETECTED_OS${NC} (Package Manager: ${CYAN}$PACKAGE_MGR${NC})"
    echo ""

    local missing_tools=()

    # Check Git
    if command -v git &>/dev/null; then
        success "Git is installed: $(git --version | head -n1)"
    else
        error "Git is NOT installed"
        missing_tools+=("git")
    fi

    # Check Node.js
    if command -v node &>/dev/null; then
        success "Node.js is installed: $(node --version)"
    else
        error "Node.js is NOT installed"
        missing_tools+=("node")
    fi

    # Check OpenTofu / Terraform
    if command -v tofu &>/dev/null; then
        success "OpenTofu is installed: $(tofu --version | head -n1)"
    elif command -v terraform &>/dev/null; then
        success "Terraform is installed: $(terraform --version | head -n1)"
    else
        warn "Neither OpenTofu nor Terraform is installed"
        missing_tools+=("opentofu")
    fi

    # Check AWS CLI
    if command -v aws &>/dev/null; then
        success "AWS CLI is installed: $(aws --version | head -n1)"
    else
        warn "AWS CLI is NOT installed (Optional, but recommended)"
    fi

    # Check DNS tool
    if command -v dig &>/dev/null; then
        success "DNS Lookup tool (dig) is available"
    else
        warn "dig utility is missing — live DNS poller will use fallback"
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo ""
        error "Missing required dependencies: ${missing_tools[*]}"
        echo ""
        echo -e "${YELLOW}${BOLD}Tailored Installation Instructions for $DETECTED_OS:${NC}"
        
        case "$PACKAGE_MGR" in
            brew)
                echo -e "  Run command: ${CYAN}brew install ${missing_tools[*]}${NC}"
                ;;
            apt)
                echo -e "  Run command: ${CYAN}sudo apt-get update && sudo apt-get install -y ${missing_tools[*]}${NC}"
                ;;
            dnf)
                echo -e "  Run command: ${CYAN}sudo dnf install -y ${missing_tools[*]}${NC}"
                ;;
            yum)
                echo -e "  Run command: ${CYAN}sudo yum install -y ${missing_tools[*]}${NC}"
                ;;
            winget*)
                echo -e "  Run in PowerShell: ${CYAN}winget install OpenTofu.OpenTofu Git.Git OpenJS.NodeJS${NC}"
                ;;
            *)
                echo -e "  Please install ${missing_tools[*]} using your platform's package manager."
                ;;
        esac

        generate_diagnostic_report "Missing required CLI packages: ${missing_tools[*]}"
        
        echo ""
        read -p "Press ENTER to attempt to continue anyway, or Ctrl+C to stop..."
    else
        echo ""
        success "All core dependencies verified successfully for $DETECTED_OS!"
    fi

    sleep 1
}

# ── Step 2: AWS Access Credentials & Key Pair Verification ────────────────────

audit_aws_credentials() {
    banner
    print_step "2" "AWS Access Credentials & SSH Key Pair Verification"

    info "Checking AWS credentials on $DETECTED_OS..."
    echo ""

    local has_aws_vars=false
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        has_aws_vars=true
        success "AWS Environment Variables detected (AWS_ACCESS_KEY_ID is set)"
    elif [ -f "$HOME/.aws/credentials" ]; then
        has_aws_vars=true
        success "AWS Credentials file detected (~/.aws/credentials)"
    else
        warn "No active AWS credentials detected in environment or ~/.aws/credentials"
    fi

    if [ "$has_aws_vars" = false ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}📖 GUIDANCE: How to get your AWS Access Keys:${NC}"
        echo "  1. Log into AWS Console: https://console.aws.amazon.com/"
        echo "  2. Click your account name at top-right → 'Security credentials'"
        echo "  3. Scroll down to 'Access keys' → Click 'Create access key'"
        echo "  4. Select 'Command Line Interface (CLI)' → Click Next → Create"
        echo "  5. Copy your Access Key ID and Secret Access Key"
        echo ""
        read -p "AWS Access Key ID (press ENTER to skip): " INPUT_AWS_KEY
        if [ -n "$INPUT_AWS_KEY" ]; then
            export AWS_ACCESS_KEY_ID="$INPUT_AWS_KEY"
            echo -n "AWS Secret Access Key (hidden input): "
            read -s INPUT_AWS_SECRET
            echo ""
            export AWS_SECRET_ACCESS_KEY="$INPUT_AWS_SECRET"
            success "AWS credentials set in memory for this session."
        else
            warn "Skipping AWS credentials entry."
        fi
    fi

    echo ""
    info "Checking SSH Private Key file (.pem)..."

    local key_name="moi01-vault-key"
    local key_file="$HOME/.ssh/${key_name}.pem"

    if [ -f "$key_file" ]; then
        success "Local SSH Private Key found: $key_file"
    else
        warn "SSH Private Key not found at expected path: $key_file"
        echo ""
        echo -e "${YELLOW}${BOLD}📖 GUIDANCE: How to download AWS SSH Key Pair:${NC}"
        echo "  1. Open AWS EC2 Console: https://console.aws.amazon.com/ec2/"
        echo "  2. Left navigation → 'Network & Security' → 'Key Pairs'"
        echo "  3. Click 'Create key pair' → Name: ${BOLD}moi01-vault-key${NC} → Format: .pem"
        echo "  4. Click Create → Move downloaded file to ~/.ssh/${key_name}.pem:"
        echo -e "     ${CYAN}mkdir -p ~/.ssh && mv ~/Downloads/${key_name}.pem ~/.ssh/ && chmod 400 ~/.ssh/${key_name}.pem${NC}"
        echo ""

        if command -v aws &>/dev/null && [ "$has_aws_vars" = true ]; then
            read -p "Would you like the wizard to auto-generate '${key_name}.pem' now? (y/N): " AUTO_KEY
            if [[ "$AUTO_KEY" =~ ^[Yy]$ ]]; then
                mkdir -p "$HOME/.ssh"
                if aws ec2 create-key-pair --key-name "$key_name" --query 'KeyMaterial' --output text > "$key_file" 2>/dev/null; then
                    chmod 400 "$key_file"
                    success "Automatically generated and saved SSH key to $key_file"
                else
                    error "Failed to generate key pair automatically. Please create it via AWS Console."
                fi
            fi
        fi
    fi

    sleep 1
}

# ── Step 3: Domain & Security Settings ────────────────────────────────────────

configure_settings() {
    banner
    print_step "3" "Domain, AWS Region & Security Parameters"

    info "Configuring application variables..."
    echo ""

    read -p "$(echo -e "${BOLD}Target Domain Name${NC} [default: moi01.vip]: ")" INPUT_DOMAIN
    DOMAIN="${INPUT_DOMAIN:-moi01.vip}"

    read -p "$(echo -e "${BOLD}AWS Region${NC} [default: us-east-1]: ")" INPUT_REGION
    AWS_REGION="${INPUT_REGION:-us-east-1}"

    read -p "$(echo -e "${BOLD}Maximum Payload Limit in MB${NC} [default: 1]: ")" INPUT_LIMIT
    MAX_MB="${INPUT_LIMIT:-1}"

    echo ""
    info "Destination Audit Webhook (Where payloads are forwarded)"
    tooltip "Example: http://<DESTINATION_IP>:8080/audit2026/submit"
    echo -n "Destination Webhook URL (hidden input, press ENTER to skip): "
    read -s WEBHOOK_URL
    echo ""

    echo -n "Destination Bearer Token / API Key (hidden input, press ENTER to skip): "
    read -s API_KEY
    echo ""

    echo -e "${CYAN}▸ Applying configuration choices...${NC}"

    local nginx_conf="$REPO_ROOT/vault/config/nginx.conf"
    if [ -f "$nginx_conf" ]; then
        sed -i -E "s/client_max_body_size [0-9]+m;/client_max_body_size ${MAX_MB}m;/" "$nginx_conf"
        sed -i -E "s/server_name .*/server_name ${DOMAIN};/" "$nginx_conf"
        success "Updated $nginx_conf"
    fi

    local server_js="$REPO_ROOT/vault/src/server.js"
    if [ -f "$server_js" ]; then
        sed -i -E "s/const MAX_PAYLOAD_BYTES = [0-9]+ \* 1024 \* 1024;/const MAX_PAYLOAD_BYTES = ${MAX_MB} \* 1024 \* 1024;/" "$server_js"
        success "Updated $server_js"
    fi

    local tfvars="$REPO_ROOT/infra/terraform.tfvars.example"
    if [ -f "$tfvars" ]; then
        sed -i -E "s/aws_region *= *\".*\"/aws_region    = \"${AWS_REGION}\"/" "$tfvars"
        success "Updated $tfvars"
    fi

    cat > "$STATE_FILE" <<EOF
{
  "os": "$DETECTED_OS",
  "domain": "$DOMAIN",
  "aws_region": "$AWS_REGION",
  "max_mb": "$MAX_MB",
  "webhook_configured": "$([ -n "$WEBHOOK_URL" ] && echo "true" || echo "false")"
}
EOF

    sleep 1
}

# ── Step 4: OpenTofu Infrastructure Provisioning ──────────────────────────────

provision_infrastructure() {
    banner
    print_step "4" "Infrastructure Provisioning (OpenTofu) & Elastic IP"

    info "Ready to spin up AWS infrastructure."
    echo ""
    echo -e "Commands to execute:"
    echo -e "  ${CYAN}cd ~/MOI01/infra && cp terraform.tfvars.example terraform.tfvars && tofu init && tofu apply${NC}"
    echo ""

    read -p "Would you like the wizard to run OpenTofu initialization & plan now? (y/N): " RUN_TOFU

    if [[ "$RUN_TOFU" =~ ^[Yy]$ ]]; then
        cd "$REPO_ROOT/infra"
        if [ ! -f "terraform.tfvars" ]; then
            cp terraform.tfvars.example terraform.tfvars
        fi

        local tofu_bin="tofu"
        command -v tofu &>/dev/null || tofu_bin="terraform"

        info "Initializing $tofu_bin..."
        if ! $tofu_bin init; then
            generate_diagnostic_report "OpenTofu/Terraform init failed on $DETECTED_OS"
            return
        fi

        info "Generating $tofu_bin plan..."
        if ! $tofu_bin plan; then
            generate_diagnostic_report "OpenTofu/Terraform plan failed (check AWS credentials)"
            return
        fi

        echo ""
        read -p "Apply this infrastructure plan to AWS now? (y/N): " APPLY_TOFU
        if [[ "$APPLY_TOFU" =~ ^[Yy]$ ]]; then
            info "Provisioning AWS EC2 & Elastic IP..."
            $tofu_bin apply -auto-approve
            
            ELASTIC_IP=$($tofu_bin output -raw elastic_ip 2>/dev/null || echo "")
            if [ -n "$ELASTIC_IP" ]; then
                success "Elastic IP Provisioned: $ELASTIC_IP"
                local tmp_json=$(cat "$STATE_FILE")
                echo "$tmp_json" | sed "s/}/, \"elastic_ip\": \"$ELASTIC_IP\"}/" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
            fi
        fi
    fi

    sleep 1
}

# ── Step 5: Live DNS Propagation Poller ───────────────────────────────────────

poll_dns() {
    banner
    print_step "5" "GoDaddy DNS Delegation & Live Propagation Poller"

    local domain="moi01.vip"
    local target_ip=""
    if [ -f "$STATE_FILE" ]; then
        domain=$(grep -o '"domain": "[^"]*"' "$STATE_FILE" | cut -d'"' -f4 || echo "moi01.vip")
        target_ip=$(grep -o '"elastic_ip": "[^"]*"' "$STATE_FILE" | cut -d'"' -f4 || echo "")
    fi

    echo -e "${YELLOW}${BOLD}📖 GUIDANCE: GoDaddy DNS Delegation Instructions:${NC}"
    echo "  1. Log into GoDaddy Domain Control Center: https://dcc.godaddy.com/"
    echo "  2. Select domain '${BOLD}$domain${NC}' → Click 'Manage DNS'"
    echo "  3. Add an ${BOLD}A Record${NC}:"
    echo "     • Type:  ${BOLD}A${NC}"
    echo "     • Name:  ${BOLD}@${NC}"
    echo -e "     • Value: ${CYAN}${target_ip:-"<YOUR_ELASTIC_IP>"}${NC}"
    echo "     • TTL:   600 seconds"
    echo ""

    if [ -z "$target_ip" ]; then
        read -p "Enter your Vault Elastic IP to test DNS propagation: " target_ip
    fi

    if [ -n "$target_ip" ]; then
        read -p "Start the Live DNS Propagation Poller now? (y/N): " START_POLL
        if [[ "$START_POLL" =~ ^[Yy]$ ]]; then
            echo ""
            info "Polling DNS resolution for '$domain' (@8.8.8.8)..."
            echo "Press Ctrl+C to interrupt at any time."
            echo ""

            local count=0
            local max_attempts=30
            local resolved_ip=""

            while [ $count -lt $max_attempts ]; do
                count=$((count + 1))
                if command -v dig &>/dev/null; then
                    resolved_ip=$(dig +short "$domain" @8.8.8.8 | tail -n1 || echo "")
                else
                    resolved_ip=$(nslookup "$domain" 8.8.8.8 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' || echo "")
                fi

                if [ "$resolved_ip" = "$target_ip" ]; then
                    echo ""
                    success "🎉 DNS PROPAGATED SUCCESSFULLY! $domain → $resolved_ip"
                    break
                else
                    echo -ne "  Attempt $count/$max_attempts: Resolved '$resolved_ip' (Waiting for '$target_ip')...\r"
                    sleep 10
                fi
            done
        fi
    fi

    sleep 1
}

# ── Step 6: GitHub Secrets & Handover Checklist ───────────────────────────────

github_secrets_summary() {
    banner
    print_step "6" "GitHub Secrets & Handover Checklist"

    info "Final step: Add credentials to GitHub Secrets on $DETECTED_OS."
    echo ""
    echo -e "${YELLOW}${BOLD}📖 GUIDANCE: How to set GitHub Secrets:${NC}"
    echo "  1. Open GitHub Repository in browser"
    echo "  2. Go to: ${BOLD}Settings → Secrets and variables → Actions${NC}"
    echo "  3. Click ${BOLD}'New repository secret'${NC} for each item:"
    echo ""
    echo -e "  • ${BOLD}SERVER_IP${NC}   = Your EC2 Elastic IP"
    echo -e "  • ${BOLD}AWS_SSH_KEY${NC} = Contents of ~/.ssh/moi01-vault-key.pem"
    echo -e "  • ${BOLD}WEBHOOK_URL${NC} = Destination Webhook URL"
    echo -e "  • ${BOLD}API_KEY${NC}     = Bearer Token for destination auth"
    echo ""

    echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  🎉 WIZARD COMPLETE — MOI01.VIP Setup Ready for Handover!${NC}"
    echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ── Main Wizard Entry Point ───────────────────────────────────────────────────

main() {
    audit_tools
    audit_aws_credentials
    configure_settings
    provision_infrastructure
    poll_dns
    github_secrets_summary
}

main "$@"

