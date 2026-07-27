#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — OS-Agnostic Intelligent Setup Wizard (v4.0.0)
#
# PURPOSE:
#   An OS-agnostic, multi-platform interactive CLI wizard for macOS, Linux,
#   and Windows (WSL/Git Bash). Detects OS environment automatically, provides
#   tailored package installation commands, guides AWS setup, polls live DNS,
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
CREDENTIALS_DIR="$REPO_ROOT/credentials"
STATE_FILE="$REPO_ROOT/.wizard_state.json"
DIAGNOSTIC_FILE="$REPO_ROOT/audit_diagnostics.txt"
LOCAL_AWS_CREDENTIALS="$CREDENTIALS_DIR/aws_credentials"

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
    
    local git_ver="MISSING"
    local node_ver="MISSING"
    local tofu_ver="MISSING"
    local aws_ver="MISSING"
    local dig_ver="MISSING"

    command -v git &>/dev/null && git_ver="$(git --version 2>/dev/null | head -n1)" || true
    command -v node &>/dev/null && node_ver="$(node --version 2>/dev/null | head -n1)" || true
    if command -v tofu &>/dev/null; then
        tofu_ver="$(tofu --version 2>/dev/null | head -n1)"
    elif command -v terraform &>/dev/null; then
        tofu_ver="$(terraform --version 2>/dev/null | head -n1)"
    fi
    command -v aws &>/dev/null && aws_ver="$(aws --version 2>/dev/null | head -n1)" || true
    command -v dig &>/dev/null && dig_ver="AVAILABLE" || true

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
Git:              $git_ver
Node.js:          $node_ver
OpenTofu/Tform:   $tofu_ver
AWS CLI:          $aws_ver
DNS Tool (dig):   $dig_ver

[ISSUE DESCRIPTION]
$issue_description

================================================================================
INSTRUCTIONS FOR NON-TECHNICAL USER:
1. Attach or copy the contents of this file ('$DIAGNOSTIC_FILE').
2. Send to your Lead Systems Architect / Security Engineer.
3. Or paste into your AI Assistant for immediate step-by-step resolution.
================================================================================
EOF
}

fatal_step_error() {
    local step_num="$1"
    local step_title="$2"
    local error_details="$3"

    generate_diagnostic_report "FATAL ERROR in STEP $step_num ($step_title): $error_details"

    echo ""
    echo -e "${RED}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}${BOLD}  ❌ FATAL ERROR IN STEP $step_num: $step_title${NC}"
    echo -e "${RED}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}${BOLD}Error Summary:${NC} $error_details"
    echo ""
    echo -e "📄 Diagnostic Report Saved: ${CYAN}${BOLD}$DIAGNOSTIC_FILE${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}⚠️  WIZARD EXECUTION ABORTED.${NC}"
    echo -e "Because the setup process is strictly serial, you cannot proceed to Step $((step_num + 1))"
    echo -e "until Step $step_num completes successfully."
    echo -e ""
    echo -e "To resolve this issue:"
    echo -e "  1. Check the error message printed above."
    echo -e "  2. Ensure your AWS credentials are valid or saved in ${CYAN}.aws_credentials${NC}"
    echo -e "  3. Re-run the setup wizard: ${CYAN}${BOLD}./scripts/configure.sh${NC}"
    echo -e "${RED}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    exit 1
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

        fatal_step_error "1" "OS Detection & Pre-flight Tooling Audit" "Missing required CLI dependencies: ${missing_tools[*]}"
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

    if [ -f "$LOCAL_AWS_CREDENTIALS" ]; then
        local sec_val="$(grep -i 'aws_secret_access_key' "$LOCAL_AWS_CREDENTIALS" 2>/dev/null | cut -d'=' -f2- | xargs 2>/dev/null || echo "")"
        if [ -n "$sec_val" ]; then
            export AWS_SHARED_CREDENTIALS_FILE="$LOCAL_AWS_CREDENTIALS"
            has_aws_vars=true
            success "Repository-isolated AWS credentials loaded ($LOCAL_AWS_CREDENTIALS)"
        else
            warn "Existing local file $LOCAL_AWS_CREDENTIALS is missing a Secret Access Key. Removing invalid credentials file..."
            rm -f "$LOCAL_AWS_CREDENTIALS"
        fi
    fi

    if [ "$has_aws_vars" = false ]; then
        if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
            has_aws_vars=true
            success "AWS Environment Variables detected (AWS_ACCESS_KEY_ID is set)"
        elif [ -f "$HOME/.aws/credentials" ]; then
            has_aws_vars=true
            success "Global AWS Credentials detected (~/.aws/credentials)"
        else
            warn "No active AWS credentials detected in environment, repo, or ~/.aws/credentials"
        fi
    fi

    local aws_authenticated=false
    if command -v aws &>/dev/null; then
        if aws sts get-caller-identity &>/dev/null; then
            aws_authenticated=true
            local caller_arn=$(aws sts get-caller-identity --query "Arn" --output text 2>/dev/null || echo "Authenticated")
            success "AWS CLI authenticated as: $caller_arn"
        else
            warn "AWS CLI installed, but authentication check failed (credentials missing or invalid)."
        fi
    fi

    local prompt_creds=false
    if [ "$has_aws_vars" = false ] || [ "$aws_authenticated" = false ]; then
        prompt_creds=true
    else
        read -p "AWS credentials detected. Would you like to update / re-enter your AWS Access Keys? (y/N): " UPDATE_KEYS
        if [[ "$UPDATE_KEYS" =~ ^[Yy]$ ]]; then
            prompt_creds=true
        fi
    fi

    if [ "$prompt_creds" = true ]; then
        echo ""
        echo -e "${YELLOW}${BOLD}📖 GUIDANCE: How to get your AWS Access Keys:${NC}"
        echo -e "  1. Log into AWS Console: https://console.aws.amazon.com/"
        echo -e "  2. Click your account name at top-right → 'Security credentials'"
        echo -e "  3. Scroll down to 'Access keys' → Click 'Create access key'"
        echo -e "  4. Select 'Command Line Interface (CLI)' → Click Next → Create"
        echo -e "  5. Copy your Access Key ID and Secret Access Key"
        echo ""
        read -r -p "AWS Access Key ID (press ENTER to skip): " INPUT_AWS_KEY
        INPUT_AWS_KEY="$(echo "$INPUT_AWS_KEY" | tr -d '\r' | xargs 2>/dev/null || echo "$INPUT_AWS_KEY")"
        if [ -n "$INPUT_AWS_KEY" ]; then
            read -r -p "AWS Secret Access Key: " INPUT_AWS_SECRET
            INPUT_AWS_SECRET="$(echo "$INPUT_AWS_SECRET" | tr -d '\r' | xargs 2>/dev/null || echo "$INPUT_AWS_SECRET")"

            if [ -z "$INPUT_AWS_SECRET" ]; then
                error "AWS Secret Access Key cannot be empty."
                warn "Skipping AWS credentials entry. Infrastructure provisioning (Step 4) requires valid AWS credentials."
            else
                export AWS_ACCESS_KEY_ID="$INPUT_AWS_KEY"
                export AWS_SECRET_ACCESS_KEY="$INPUT_AWS_SECRET"

                mkdir -p "$CREDENTIALS_DIR"
                cat > "$LOCAL_AWS_CREDENTIALS" <<EOF
[default]
aws_access_key_id = $INPUT_AWS_KEY
aws_secret_access_key = $INPUT_AWS_SECRET
EOF
                chmod 600 "$LOCAL_AWS_CREDENTIALS"
                export AWS_SHARED_CREDENTIALS_FILE="$LOCAL_AWS_CREDENTIALS"
                success "AWS Secret Access Key captured (${#INPUT_AWS_SECRET} characters)."
                success "Saved repository-isolated credentials to $LOCAL_AWS_CREDENTIALS (gitignored)."

                if command -v aws &>/dev/null; then
                    if aws sts get-caller-identity &>/dev/null; then
                        success "AWS authentication verified successfully!"
                    else
                        warn "Credentials set. OpenTofu will use these repository-isolated credentials."
                    fi
                fi
            fi
        else
            warn "Skipping AWS credentials entry."
        fi
    fi

    echo ""
    info "Checking SSH Private Key file (.pem)..."

    mkdir -p "$CREDENTIALS_DIR"
    local key_name="moi01-vault-key"
    local key_file="$CREDENTIALS_DIR/${key_name}.pem"

    if [ ! -f "$key_file" ] && [ -f "$HOME/.ssh/${key_name}.pem" ]; then
        cp "$HOME/.ssh/${key_name}.pem" "$key_file" 2>/dev/null || true
        chmod 400 "$key_file" 2>/dev/null || true
    fi

    if [ -f "$key_file" ]; then
        success "SSH Private Key found in credentials folder: $key_file"
    else
        warn "SSH Private Key not found at expected path: $key_file"
        echo ""
        echo -e "${YELLOW}${BOLD}📖 GUIDANCE: AWS SSH Key Pair Setup:${NC}"
        echo -e "OpenTofu will automatically generate '${key_name}.pem' and save it to:"
        echo -e "  ${CYAN}$key_file${NC} (gitignored inside credentials/)"
        echo ""
    fi

    sleep 1
}

# ── Step 3: Domain & Security Settings ────────────────────────────────────────

configure_settings() {
    banner
    print_step "3" "Domain, AWS Region & Security Parameters"

    info "Configuring application variables..."
    echo ""

    local current_domain=$(get_target_domain)
    local current_webhook=$(get_webhook_url)
    local current_api_key=$(get_api_key)

    local domain_prompt="Target Domain Name"
    if [ -n "$current_domain" ]; then
        domain_prompt="Target Domain Name [default: ${current_domain}]"
    else
        domain_prompt="Target Domain Name (e.g. vault.example.com)"
    fi
    read -p "$(echo -e "${BOLD}${domain_prompt}${NC}: ")" INPUT_DOMAIN
    DOMAIN="${INPUT_DOMAIN:-$current_domain}"
    mkdir -p "$CREDENTIALS_DIR"
    echo "$DOMAIN" > "$CREDENTIALS_DIR/domain.txt"

    read -p "$(echo -e "${BOLD}AWS Region${NC} [default: us-east-1]: ")" INPUT_REGION
    AWS_REGION="${INPUT_REGION:-us-east-1}"

    read -p "$(echo -e "${BOLD}Maximum Payload Limit in MB${NC} [default: 1]: ")" INPUT_LIMIT
    MAX_MB="${INPUT_LIMIT:-1}"

    echo ""
    info "Destination Audit Webhook (Where payloads are forwarded)"
    tooltip "Example: http://<DESTINATION_IP>:8080/audit2026/submit"

    if [ -n "$current_webhook" ]; then
        read -r -p "$(echo -e "${BOLD}Destination Webhook URL${NC} [default: ${current_webhook}]: ")" INPUT_WEBHOOK
        WEBHOOK_URL="${INPUT_WEBHOOK:-$current_webhook}"
    else
        read -r -p "Destination Webhook URL (press ENTER to skip): " INPUT_WEBHOOK
        WEBHOOK_URL="$INPUT_WEBHOOK"
    fi
    WEBHOOK_URL="$(echo "$WEBHOOK_URL" | tr -d '\r' | xargs 2>/dev/null || echo "$WEBHOOK_URL")"
    echo "$WEBHOOK_URL" > "$CREDENTIALS_DIR/webhook_url.txt"

    if [ -n "$current_api_key" ]; then
        read -r -p "$(echo -e "${BOLD}Destination Bearer Token / API Key${NC} [default: ${current_api_key}]: ")" INPUT_KEY
        API_KEY="${INPUT_KEY:-$current_api_key}"
    else
        read -r -p "Destination Bearer Token / API Key (press ENTER to skip): " INPUT_KEY
        API_KEY="$INPUT_KEY"
    fi
    API_KEY="$(echo "$API_KEY" | tr -d '\r' | xargs 2>/dev/null || echo "$API_KEY")"
    echo "$API_KEY" > "$CREDENTIALS_DIR/api_key.txt"

    echo -e "${CYAN}▸ Applying configuration choices...${NC}"

    local nginx_conf="$REPO_ROOT/vault/config/nginx.conf"
    if [ -f "$nginx_conf" ]; then
        sed -i -E "s/client_max_body_size [0-9]+m;/client_max_body_size ${MAX_MB}m;/" "$nginx_conf"
        sed -i -E "s/server_name .*/server_name ${DOMAIN} _;/" "$nginx_conf"
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
        if ! command -v tofu &>/dev/null; then
            if command -v terraform &>/dev/null; then
                tofu_bin="terraform"
            else
                fatal_step_error "4" "Infrastructure Provisioning (OpenTofu)" "Neither OpenTofu ('tofu') nor Terraform ('terraform') CLI is installed."
            fi
        fi

        info "Initializing $tofu_bin..."
        if ! $tofu_bin init; then
            fatal_step_error "4" "Infrastructure Provisioning (OpenTofu)" "$tofu_bin init failed. Check module configuration."
        fi

        info "Generating $tofu_bin plan..."
        if ! $tofu_bin plan; then
            fatal_step_error "4" "Infrastructure Provisioning (OpenTofu)" "$tofu_bin plan failed. OpenTofu encountered an authentication or provider error (e.g., missing AWS credentials)."
        fi

        echo ""
        read -p "Apply this infrastructure plan to AWS now? (y/N): " APPLY_TOFU
        if [[ "$APPLY_TOFU" =~ ^[Yy]$ ]]; then
            info "Provisioning AWS EC2 & Elastic IP..."
            if ! $tofu_bin apply -auto-approve; then
                fatal_step_error "4" "Infrastructure Provisioning (OpenTofu)" "$tofu_bin apply failed during AWS resource creation."
            fi

            ELASTIC_IP=$($tofu_bin output -raw elastic_ip 2>/dev/null || echo "")
            if [ -z "$ELASTIC_IP" ]; then
                fatal_step_error "4" "Infrastructure Provisioning (OpenTofu)" "$tofu_bin apply completed but failed to return an elastic_ip output."
            fi

            mkdir -p "$CREDENTIALS_DIR"
            echo "$ELASTIC_IP" > "$CREDENTIALS_DIR/server_ip"
            success "Elastic IP Provisioned & Saved to credentials/server_ip: $ELASTIC_IP"
            local tmp_json=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")
            echo "$tmp_json" | sed "s/}/, \"elastic_ip\": \"$ELASTIC_IP\"}/" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
            return 0
        else
            fatal_step_error "4" "Infrastructure Provisioning (OpenTofu)" "OpenTofu plan was generated but apply was declined. Infrastructure not created."
        fi
    fi

    # Check if elastic_ip already exists in credentials/server_ip or state file
    local state_ip=$(get_target_ip)

    if [ -n "$state_ip" ]; then
        success "Using existing Elastic IP: $state_ip"
        return 0
    fi

    echo ""
    warn "No Elastic IP has been provisioned or recorded."
    read -p "Do you have an existing Vault Elastic IP to enter manually? (y/N): " MANUAL_IP_CHOICE
    if [[ "$MANUAL_IP_CHOICE" =~ ^[Yy]$ ]]; then
        read -p "Enter your Vault Elastic IP: " MANUAL_IP
        if [ -n "$MANUAL_IP" ]; then
            mkdir -p "$CREDENTIALS_DIR"
            echo "$MANUAL_IP" > "$CREDENTIALS_DIR/server_ip"
            local tmp_json=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")
            echo "$tmp_json" | sed "s/}/, \"elastic_ip\": \"$MANUAL_IP\"}/" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
            success "Elastic IP recorded manually: $MANUAL_IP"
            return 0
        fi
    fi

    fatal_step_error "4" "Infrastructure Provisioning (OpenTofu)" "No AWS infrastructure was provisioned and no Elastic IP was provided. Cannot proceed to Step 5 (DNS Delegation)."
}

# ── IP Resolution Helper ──────────────────────────────────────────────────────

get_target_ip() {
    local ip=""
    if [ -f "$CREDENTIALS_DIR/server_ip" ]; then
        ip=$(cat "$CREDENTIALS_DIR/server_ip" 2>/dev/null | tr -d '\r\n ' || echo "")
    fi
    if [ -z "$ip" ] && [ -f "$STATE_FILE" ]; then
        ip=$(grep -o '"elastic_ip": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
    fi
    if [ -z "$ip" ] && [ -f "$REPO_ROOT/infra/terraform.tfstate" ]; then
        ip=$(grep -o '"value": "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*"' "$REPO_ROOT/infra/terraform.tfstate" 2>/dev/null | head -n1 | cut -d'"' -f4 || echo "")
    fi
    echo "$ip"
}

# ── Step 5: Live DNS Propagation Poller ───────────────────────────────────────

poll_dns() {
    banner
    print_step "5" "DNS Delegation & Live Propagation Poller"

    local domain=$(get_target_domain)
    domain="${domain:-yourdomain.com}"
    local target_ip=$(get_target_ip)

    if [ -z "$target_ip" ]; then
        fatal_step_error "5" "DNS Delegation & Live Propagation Poller" "No server Elastic IP found. Please run Step 4 (Infrastructure Provisioning) first."
    fi

    echo -e "${YELLOW}${BOLD}📖 GUIDANCE: DNS Delegation Instructions:${NC}"
    echo -e "  1. Log into your Domain Registrar (Cloudflare, Namecheap, Route 53, etc.)"
    echo -e "  2. Select domain '${BOLD}$domain${NC}' → Open DNS Management"
    echo -e "  3. Add or update the ${BOLD}A Record${NC}:"
    echo -e "     • Type:  ${BOLD}A${NC}"
    echo -e "     • Name:  ${BOLD}@${NC}"
    echo -e "     • Value: ${CYAN}${target_ip}${NC}"
    echo -e "     • TTL:   300 seconds"
    echo ""

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

    sleep 1
}

get_target_domain() {
    local dom=""
    if [ -f "$CREDENTIALS_DIR/domain.txt" ]; then
        dom=$(cat "$CREDENTIALS_DIR/domain.txt" 2>/dev/null | tr -d '\r\n ' || echo "")
    fi
    if [ -z "$dom" ] && [ -f "$STATE_FILE" ]; then
        dom=$(grep -o '"domain": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
    fi
    echo "$dom"
}

get_webhook_url() {
    local url=""
    if [ -f "$CREDENTIALS_DIR/webhook_url.txt" ]; then
        url=$(cat "$CREDENTIALS_DIR/webhook_url.txt" 2>/dev/null | tr -d '\r\n' || echo "")
        if [ -n "$url" ] && [[ "$url" != */submit ]] && [[ "$url" != */submit/ ]]; then
            url="${url%/}/submit"
        fi
    fi
    echo "$url"
}

get_api_key() {
    local key=""
    if [ -f "$CREDENTIALS_DIR/api_key.txt" ]; then
        key=$(cat "$CREDENTIALS_DIR/api_key.txt" 2>/dev/null | tr -d '\r\n' || echo "")
    fi
    echo "$key"
}

# ── Step 6: Deployment & Handover Launch ──────────────────────────────────────

deploy_direct_ssh() {
    local target_ip="$1"
    local target_domain=$(get_target_domain)
    local webhook_url=$(get_webhook_url)
    local api_key=$(get_api_key)
    local key_file="$CREDENTIALS_DIR/moi01-vault-key.pem"

    if [ ! -f "$key_file" ] && [ -f "$HOME/.ssh/moi01-vault-key.pem" ]; then
        key_file="$HOME/.ssh/moi01-vault-key.pem"
    fi

    if [ ! -f "$key_file" ]; then
        error "SSH Private Key file not found at $key_file or $CREDENTIALS_DIR/moi01-vault-key.pem."
        return 1
    fi

    info "Deploying zero-knowledge vault directly to EC2 ($target_ip) via SSH..."
    echo -e "${CYAN}▸ Connecting to ubuntu@$target_ip...${NC}"

    local ssh_ready=false
    local attempts=0
    while [ $attempts -lt 12 ]; do
        attempts=$((attempts + 1))
        if ssh -i "$key_file" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$target_ip" "echo 'SSH_READY'" 2>/dev/null | grep -q "SSH_READY"; then
            ssh_ready=true
            break
        fi
        echo -ne "  Waiting for EC2 SSH daemon to be ready (attempt $attempts/12)...\r"
        sleep 5
    done
    echo ""

    if [ "$ssh_ready" = false ]; then
        error "Could not connect to EC2 server ($target_ip) via SSH."
        echo ""
        echo -e "${YELLOW}${BOLD}💡 DIAGNOSIS & RESOLUTION:${NC}"
        echo -e "  The EC2 server at ${BOLD}$target_ip${NC} is offline or was terminated (e.g. via destroy.sh)."
        echo -e "  To provision a fresh server on AWS and deploy automatically:"
        echo -e "    1. Run: ${CYAN}${BOLD}./tools/configure.sh${NC}"
        echo -e "    2. Select option ${BOLD}[3] (Start fresh from Step 1)${NC} or jump to ${BOLD}Step 4 (Provisioning)${NC}"
        echo ""
        return 1
    fi

    success "SSH connection established with EC2 instance!"

    info "Preparing application directory on EC2 server..."
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$target_ip" "sudo mkdir -p /var/www/moi01.vip/app /var/www/moi01.vip/tools && sudo chown -R ubuntu:ubuntu /var/www/moi01.vip"

    info "Syncing ONLY app application & server-init.sh script (Ultra-Fast & Secure)..."
    if command -v rsync &>/dev/null; then
        rsync -avz -e "ssh -i $key_file -o StrictHostKeyChecking=no" --exclude="node_modules" "$REPO_ROOT/app/" ubuntu@"$target_ip":/var/www/moi01.vip/app/ 2>/dev/null || true
        rsync -avz -e "ssh -i $key_file -o StrictHostKeyChecking=no" "$REPO_ROOT/tools/server-init.sh" ubuntu@"$target_ip":/var/www/moi01.vip/tools/server-init.sh 2>/dev/null || true
    else
        scp -i "$key_file" -o StrictHostKeyChecking=no -r "$REPO_ROOT/app"/* ubuntu@"$target_ip":/var/www/moi01.vip/app/ 2>/dev/null || true
        scp -i "$key_file" -o StrictHostKeyChecking=no "$REPO_ROOT/tools/server-init.sh" ubuntu@"$target_ip":/var/www/moi01.vip/tools/server-init.sh 2>/dev/null || true
    fi

    info "Running OS hardening, domain setup ($target_domain) & server initialization on EC2..."
    ssh -i "$key_file" -o StrictHostKeyChecking=no ubuntu@"$target_ip" "cd /var/www/moi01.vip && chmod +x tools/server-init.sh && sudo DOMAIN='$target_domain' WEBHOOK_URL='$webhook_url' API_KEY='$api_key' ./tools/server-init.sh"

    echo ""
    echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  🎉 DIRECT DEPLOYMENT COMPLETE!${NC}"
    echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
    echo -e "Your Zero-Knowledge Vault is now live and running on EC2!"
    echo -e "  • Web App Direct URL: ${CYAN}${BOLD}http://$target_ip${NC}"
    echo -e "  • Target Domain:      ${CYAN}${BOLD}https://$target_domain${NC}"
    echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

github_secrets_summary() {
    banner
    print_step "6" "Automated Server Deployment & Handover Launch"

    local target_ip=$(get_target_ip)

    if [ -z "$target_ip" ]; then
        fatal_step_error "6" "Automated Server Deployment & Handover Launch" "No server Elastic IP found in credentials/server_ip or state. Please run Step 4 (Infrastructure Provisioning) first."
    fi

    info "Target EC2 Server Elastic IP: ${CYAN}${BOLD}$target_ip${NC}"
    echo ""

    # Automatically execute Direct SSH Deployment without complex prompts
    deploy_direct_ssh "$target_ip"

    echo -e "${YELLOW}${BOLD}📌 DOMAIN DNS DELEGATION CHECKLIST:${NC}"
    echo -e "If your domain does not resolve to your server ($target_ip) yet:"
    echo -e "  1. Log into your Domain Registrar DNS Control Panel (Cloudflare, Namecheap, Route 53, etc.)."
    echo -e "  2. Ensure the ${BOLD}A Record${NC} for '${BOLD}@${NC}' points to your Elastic IP: ${GREEN}${BOLD}$target_ip${NC}"
    echo -e "  3. ${RED}${BOLD}CRITICAL:${NC} Ensure there is ${BOLD}ONLY ONE${NC} A-record for '${BOLD}@${NC}'. Delete or edit any old duplicate A-records pointing to previous IP addresses."
    echo -e "  4. Allow 2-5 minutes for DNS propagation."
    echo ""
}

# ── State Management & Resumption Engine ─────────────────────────────────────

update_state_file() {
    local step_num="$1"
    local os="${DETECTED_OS:-unknown}"
    local domain="${DOMAIN:-moi01.vip}"
    local aws_region="${AWS_REGION:-us-east-1}"
    local max_mb="${MAX_MB:-1}"
    local elastic_ip=""

    if [ -f "$STATE_FILE" ]; then
        domain=$(grep -o '"domain": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "$domain")
        aws_region=$(grep -o '"aws_region": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "$aws_region")
        max_mb=$(grep -o '"max_mb": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "$max_mb")
        elastic_ip=$(grep -o '"elastic_ip": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
    fi

    cat > "$STATE_FILE" <<EOF
{
  "last_completed_step": $step_num,
  "os": "$os",
  "domain": "$domain",
  "aws_region": "$aws_region",
  "max_mb": "$max_mb",
  "elastic_ip": "$elastic_ip",
  "updated_at": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
}
EOF
}

check_resumable_state() {
    # Check if OpenTofu tfstate exists on disk and extract live elastic_ip
    if [ -f "$REPO_ROOT/infra/terraform.tfstate" ]; then
        local live_ip=$(grep -o '"value": "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*"' "$REPO_ROOT/infra/terraform.tfstate" 2>/dev/null | head -n1 | cut -d'"' -f4 || echo "")
        if [ -n "$live_ip" ]; then
            local current_step=$(grep -o '"last_completed_step": [0-9]*' "$STATE_FILE" 2>/dev/null | cut -d':' -f2 | xargs 2>/dev/null || echo "0")
            if [ "$current_step" -lt 4 ]; then
                update_state_file 4
                local tmp_json=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")
                echo "$tmp_json" | sed "s/}/, \"elastic_ip\": \"$live_ip\"}/" > "$STATE_FILE.tmp" 2>/dev/null && mv "$STATE_FILE.tmp" "$STATE_FILE"
            fi
        fi
    fi

    if [ -f "$STATE_FILE" ]; then
        local last_step=$(grep -o '"last_completed_step": [0-9]*' "$STATE_FILE" 2>/dev/null | cut -d':' -f2 | xargs 2>/dev/null || echo "0")
        local domain=$(grep -o '"domain": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
        local ip=$(grep -o '"elastic_ip": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")
        local region=$(grep -o '"aws_region": "[^"]*"' "$STATE_FILE" 2>/dev/null | cut -d'"' -f4 || echo "")

        if [ "$last_step" -gt 0 ]; then
            banner
            echo -e "${CYAN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${CYAN}${BOLD}  🔄 RESUMABLE WIZARD STATE DETECTED${NC}"
            echo -e "${CYAN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
            echo -e "Previous Execution Progress:"
            echo -e "  • Last Completed Step:  ${GREEN}${BOLD}Step $last_step of 6${NC}"
            [ -n "$domain" ] && echo -e "  • Target Domain:        ${YELLOW}$domain${NC}"
            [ -n "$region" ] && echo -e "  • AWS Region:           ${CYAN}$region${NC}"
            [ -n "$ip" ] && echo -e "  • Provisioned IP:       ${GREEN}${BOLD}$ip${NC}"
            echo -e "${CYAN}${BOLD}─────────────────────────────────────────────────────────────────────${NC}"
            echo "Options:"
            local resume_next=$((last_step >= 6 ? 6 : last_step + 1))
            echo -e "  ${BOLD}[1] Resume from Step $resume_next${NC} (Continue wizard execution)"
            echo -e "  ${BOLD}[2] Select specific Step [1-6]${NC} to run"
            echo -e "  ${BOLD}[3] Start fresh from Step 1${NC} (Reset previous state)"
            echo ""
            read -r -p "Choose option [1-3, default: 1]: " RESUME_CHOICE
            RESUME_CHOICE="${RESUME_CHOICE:-1}"

            case "$RESUME_CHOICE" in
                1)
                    START_FROM_STEP=$resume_next
                    info "Resuming wizard from Step $START_FROM_STEP..."
                    sleep 1
                    ;;
                2)
                    read -r -p "Enter Step number [1-6]: " JUMP_STEP
                    START_FROM_STEP="${JUMP_STEP:-1}"
                    info "Jumping directly to Step $START_FROM_STEP..."
                    sleep 1
                    ;;
                3)
                    warn "Resetting wizard state and starting fresh from Step 1..."
                    rm -f "$STATE_FILE"
                    START_FROM_STEP=1
                    sleep 1
                    ;;
                *)
                    START_FROM_STEP=$resume_next
                    ;;
            esac
        fi
    fi
}

# ── Main Wizard Entry Point ───────────────────────────────────────────────────

main() {
    local target_step=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--step)
                target_step="$2"
                shift 2
                ;;
            --step=*)
                target_step="${1#*=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -n "$target_step" ]; then
        START_FROM_STEP="$target_step"
        info "CLI flag detected: Jumping directly to Step $START_FROM_STEP..."
        sleep 1
    else
        START_FROM_STEP=1
        check_resumable_state
    fi

    if [ "$START_FROM_STEP" -le 1 ]; then
        audit_tools
        update_state_file 1
    fi

    if [ "$START_FROM_STEP" -le 2 ]; then
        audit_aws_credentials
        update_state_file 2
    fi

    if [ "$START_FROM_STEP" -le 3 ]; then
        configure_settings
        update_state_file 3
    fi

    if [ "$START_FROM_STEP" -le 4 ]; then
        provision_infrastructure
        update_state_file 4
    fi

    if [ "$START_FROM_STEP" -le 5 ]; then
        poll_dns
        update_state_file 5
    fi

    if [ "$START_FROM_STEP" -le 6 ]; then
        github_secrets_summary
        update_state_file 6
    fi
}

main "$@"
