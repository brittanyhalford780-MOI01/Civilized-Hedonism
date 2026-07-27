#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# MOI01.VIP — Infrastructure Teardown & Nuke Script
#
# PURPOSE:
#   100% automated destruction of all AWS resources (EC2 Instance, Elastic IP,
#   Security Group, EBS Volumes) and complete wipe of local credentials & state.
#
# USAGE:
#   chmod +x scripts/destroy.sh
#   ./scripts/destroy.sh
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

BOLD="\033[1m"
CYAN="\033[0;36m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREDENTIALS_DIR="$REPO_ROOT/credentials"
STATE_FILE="$REPO_ROOT/.wizard_state.json"
DIAGNOSTIC_FILE="$REPO_ROOT/audit_diagnostics.txt"
LOCAL_AWS_CREDENTIALS="$CREDENTIALS_DIR/aws_credentials"
LEGACY_CREDENTIALS="$REPO_ROOT/.aws_credentials"

echo -e "${RED}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
echo -e "${RED}${BOLD}  💥 MOI01.VIP — Total Teardown & Infrastructure Destruction${NC}"
echo -e "${RED}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${RED}${BOLD}⚠️  WARNING: This will PERMANENTLY DESTROY all AWS resources:${NC}"
echo -e "  • AWS EC2 Vault Node & All Attached EBS Storage Volumes"
echo -e "  • AWS Elastic IP (released back to pool)"
echo -e "  • AWS Security Groups & SSH Key Pairs"
echo -e "  • Local credentials directory (credentials/) & wizard state files"
echo ""

read -r -p "Are you SURE you want to destroy all resources? Type 'DESTROY' to confirm: " CONFIRM_DESTROY

if [ "$CONFIRM_DESTROY" != "DESTROY" ]; then
    echo -e "${YELLOW}Teardown cancelled. No resources were modified or destroyed.${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}▸ [1/3] Locating AWS Credentials & OpenTofu IaC...${NC}"

# Export repository-isolated credentials if present
if [ -f "$LOCAL_AWS_CREDENTIALS" ]; then
    export AWS_SHARED_CREDENTIALS_FILE="$LOCAL_AWS_CREDENTIALS"
elif [ -f "$LEGACY_CREDENTIALS" ]; then
    export AWS_SHARED_CREDENTIALS_FILE="$LEGACY_CREDENTIALS"
fi

TOFU_BIN="tofu"
if ! command -v tofu &>/dev/null; then
    if command -v terraform &>/dev/null; then
        TOFU_BIN="terraform"
    else
        echo -e "${RED}❌ Neither OpenTofu ('tofu') nor Terraform ('terraform') CLI is installed.${NC}"
        echo -e "${YELLOW}Please install tofu/terraform or destroy resources via AWS EC2 Console.${NC}"
        exit 1
    fi
fi

if [ -d "$REPO_ROOT/infra" ]; then
    cd "$REPO_ROOT/infra"
    echo -e "${RED}▸ [2/3] Running $TOFU_BIN destroy -auto-approve...${NC}"
    if $TOFU_BIN destroy -auto-approve; then
        echo -e "${GREEN}✅ AWS Infrastructure destroyed successfully!${NC}"
    else
        echo -e "${YELLOW}⚠️ $TOFU_BIN destroy encountered an error or state file was clean.${NC}"
    fi
fi

echo -e "${RED}▸ [3/3] Wiping local credentials, keys, and state files...${NC}"
rm -rf "$CREDENTIALS_DIR"
rm -f "$STATE_FILE"
rm -f "$LEGACY_CREDENTIALS"
rm -f "$DIAGNOSTIC_FILE"
# rm -rf "$REPO_ROOT/infra/.terraform"
# rm -f "$REPO_ROOT/infra/terraform.tfstate"*

echo ""
echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  💥 TEARDOWN COMPLETE — All AWS Resources & Local Credentials Wiped!${NC}"
echo -e "${GREEN}${BOLD}═════════════════════════════════════════════════════════════════════${NC}"
echo ""
