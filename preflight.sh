#!/bin/bash
# Pre-flight checks for Talos Homelab deployment
# Run this script to verify all prerequisites are installed

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Talos Homelab Pre-flight Checks ===${NC}"
echo ""

ERRORS=0
WARNINGS=0

# Function to check if command exists
check_command() {
    local cmd=$1
    local name=$2
    local install_hint=$3
    local required=${4:-true}
    
    if command -v "$cmd" &> /dev/null; then
        # Special case for commands that don't have version flags
        case "$cmd" in
            envsubst)
                version="installed ($(which $cmd))"
                ;;
            *)
                # Try version commands with a subshell and timeout via read
                version=$( (echo "" | $cmd --version 2>/dev/null || $cmd version 2>/dev/null || echo "installed") | head -1 )
                ;;
        esac
        echo -e "${GREEN}✓${NC} $name: $version"
        return 0
    else
        if [ "$required" = true ]; then
            echo -e "${RED}✗${NC} $name: NOT FOUND"
            echo -e "  ${YELLOW}Install: $install_hint${NC}"
            ((ERRORS++))
        else
            echo -e "${YELLOW}○${NC} $name: not found (optional)"
            echo -e "  ${YELLOW}Install: $install_hint${NC}"
            ((WARNINGS++))
        fi
        return 1
    fi
}

# Function to check minimum version
check_version() {
    local cmd=$1
    local name=$2
    local min_version=$3
    local current_version=$4
    
    if [ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)" = "$min_version" ]; then
        return 0
    else
        echo -e "  ${YELLOW}Warning: $name version $current_version may be older than recommended ($min_version)${NC}"
        ((WARNINGS++))
        return 1
    fi
}

echo -e "${BLUE}Checking required tools...${NC}"
echo ""

# Required tools
check_command "talosctl" "talosctl" "https://www.talos.dev/latest/introduction/getting-started/#talosctl"

check_command "kubectl" "kubectl" "https://kubernetes.io/docs/tasks/tools/"

check_command "helm" "helm" "https://helm.sh/docs/intro/install/"

check_command "envsubst" "envsubst (gettext)" "brew install gettext (macOS) or apt install gettext-base (Linux)"

echo ""
echo -e "${BLUE}Checking optional tools...${NC}"
echo ""

# Optional tools
check_command "curl" "curl" "Should be pre-installed on most systems" false

check_command "jq" "jq" "brew install jq (macOS) or apt install jq (Linux)" false

check_command "openssl" "openssl" "brew install openssl (macOS) or apt install openssl (Linux)" false

echo ""
echo -e "${BLUE}Checking configuration...${NC}"
echo ""

# Check if config.env exists
if [ -f "config.env" ]; then
    echo -e "${GREEN}✓${NC} config.env: found"
    
    # Source it to check for required variables
    source config.env
    
    # Check required variables
    required_vars=(
        "CLUSTER_NAME"
        "CP_IP"
        "WORKER1_IP"
        "WORKER2_IP"
        "GATEWAY"
        "CLOUDFLARE_DOMAIN"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -n "${!var}" ] && [ "${!var}" != "your-"* ] && [ "${!var}" != "yourdomain"* ]; then
            echo -e "${GREEN}✓${NC} $var: configured"
        else
            echo -e "${YELLOW}○${NC} $var: not configured or using placeholder"
            ((WARNINGS++))
        fi
    done
else
    echo -e "${YELLOW}○${NC} config.env: not found"
    echo -e "  ${YELLOW}Run: cp config.example.env config.env${NC}"
    ((WARNINGS++))
fi

echo ""
echo -e "${BLUE}Checking network connectivity...${NC}"
echo ""

# Check if we can reach common endpoints
if command -v curl &> /dev/null; then
    # Check Talos Image Factory
    if curl -s --connect-timeout 3 https://factory.talos.dev > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Talos Image Factory: reachable"
    else
        echo -e "${YELLOW}○${NC} Talos Image Factory: unreachable (may affect image downloads)"
        ((WARNINGS++))
    fi
    
    # Check GitHub (for cloudflare-operator)
    if curl -s --connect-timeout 3 https://github.com > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} GitHub: reachable"
    else
        echo -e "${YELLOW}○${NC} GitHub: unreachable (may affect deployments)"
        ((WARNINGS++))
    fi
    
    # Check Helm charts
    if curl -s --connect-timeout 3 https://charts.longhorn.io > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Helm chart repositories: reachable"
    else
        echo -e "${YELLOW}○${NC} Helm chart repositories: some may be unreachable"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}○${NC} Skipping network checks (curl not available)"
fi

echo ""
echo -e "${BLUE}Checking OS compatibility...${NC}"
echo ""

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macOS"
    echo -e "${GREEN}✓${NC} Operating System: $OS"
    
    # Check for GNU sed vs BSD sed
    if sed --version 2>/dev/null | grep -q "GNU"; then
        echo -e "${GREEN}✓${NC} sed: GNU sed (compatible)"
    else
        echo -e "${YELLOW}○${NC} sed: BSD sed (scripts use macOS-compatible syntax)"
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="Linux"
    echo -e "${GREEN}✓${NC} Operating System: $OS"
    echo -e "${YELLOW}○${NC} Note: Scripts use 'sed -i \"\"' (macOS syntax). You may need to modify to 'sed -i' for Linux."
    ((WARNINGS++))
else
    echo -e "${YELLOW}○${NC} Operating System: $OSTYPE (untested)"
    ((WARNINGS++))
fi

echo ""
echo "────────────────────────────────────────────"
echo ""

# Summary
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ All pre-flight checks passed!${NC}"
    echo ""
    echo "You're ready to deploy. Run:"
    echo "  1. ./talos/scripts/generate-configs.sh"
    echo "  2. ./talos/scripts/apply-configs.sh"
    echo "  3. ./talos/scripts/bootstrap.sh"
    echo "  4. ./deploy.sh"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Pre-flight checks passed with $WARNINGS warning(s)${NC}"
    echo ""
    echo "You can proceed, but review the warnings above."
    exit 0
else
    echo -e "${RED}❌ Pre-flight checks failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Please install missing required tools before proceeding."
    exit 1
fi
