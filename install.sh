#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# MULTICLAUDE INSTALLER / UPDATER
# Installs or updates multiclaude CLI to /usr/local/bin
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo ""
printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}  MULTICLAUDE INSTALLER v${VERSION}${NC}\n"
printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
echo ""

# Check if already installed
EXISTING=""
if [[ -L "$INSTALL_DIR/multiclaude" ]]; then
    EXISTING=$(readlink "$INSTALL_DIR/multiclaude" 2>/dev/null || true)
    if [[ "$EXISTING" == "$SCRIPT_DIR/multiclaude" ]]; then
        printf "${GREEN}✓${NC} multiclaude is already installed from this directory\n"
        echo "  Updating to ensure all scripts are executable..."
        echo ""
    else
        printf "${YELLOW}!${NC} multiclaude is installed from a different location:\n"
        echo "  Current: $EXISTING"
        echo "  New:     $SCRIPT_DIR/multiclaude"
        echo ""
        read -p "  Replace with this version? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo "  Aborted."
            exit 0
        fi
        echo ""
    fi
elif [[ -f "$INSTALL_DIR/multiclaude" ]]; then
    printf "${YELLOW}!${NC} A non-symlink multiclaude exists at $INSTALL_DIR/multiclaude\n"
    read -p "  Replace it? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        echo "  Aborted."
        exit 0
    fi
    echo ""
fi

# Make all scripts executable
printf "${BOLD}Making scripts executable...${NC}\n"
chmod +x "$SCRIPT_DIR/multiclaude"
chmod +x "$SCRIPT_DIR/bootstrap.sh"
chmod +x "$SCRIPT_DIR/loop.sh"
chmod +x "$SCRIPT_DIR/qa.sh"
chmod +x "$SCRIPT_DIR/feature.sh"
chmod +x "$SCRIPT_DIR/install.sh"
printf "${GREEN}✓${NC} All scripts are executable\n"
echo ""

# Check dependencies
printf "${BOLD}Checking dependencies...${NC}\n"
missing=()
optional_missing=()

# Required
command -v git &>/dev/null || missing+=("git")

# Required for full functionality
command -v claude &>/dev/null || missing+=("claude")
command -v tmux &>/dev/null || optional_missing+=("tmux")
command -v jq &>/dev/null || optional_missing+=("jq")

if [[ ${#missing[@]} -gt 0 ]]; then
    printf "${RED}✗${NC} Missing required: ${missing[*]}\n"
    echo ""
    echo "  Please install:"
    for dep in "${missing[@]}"; do
        case "$dep" in
            git) echo "    git:   brew install git (macOS) or apt install git (Linux)" ;;
            claude) echo "    claude: https://claude.ai/code" ;;
        esac
    done
    echo ""
    exit 1
fi

if [[ ${#optional_missing[@]} -gt 0 ]]; then
    printf "${YELLOW}!${NC} Missing optional: ${optional_missing[*]}\n"
    echo "  Some features may not work without these."
    for dep in "${optional_missing[@]}"; do
        case "$dep" in
            tmux) echo "    tmux: brew install tmux (macOS) or apt install tmux (Linux)" ;;
            jq) echo "    jq:   brew install jq (macOS) or apt install jq (Linux)" ;;
        esac
    done
else
    printf "${GREEN}✓${NC} All dependencies satisfied\n"
fi
echo ""

# Install symlink
printf "${BOLD}Installing to $INSTALL_DIR...${NC}\n"
if [[ -w "$INSTALL_DIR" ]]; then
    ln -sf "$SCRIPT_DIR/multiclaude" "$INSTALL_DIR/multiclaude"
else
    echo "  Requires sudo to write to $INSTALL_DIR"
    sudo ln -sf "$SCRIPT_DIR/multiclaude" "$INSTALL_DIR/multiclaude"
fi
printf "${GREEN}✓${NC} Installed multiclaude to $INSTALL_DIR/multiclaude\n"
echo ""

# Verify installation
if command -v multiclaude &>/dev/null; then
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${GREEN}  Installation successful!${NC}\n"
    printf "${GREEN}═══════════════════════════════════════════════════════════════${NC}\n"
else
    printf "${YELLOW}Warning: multiclaude not found in PATH${NC}\n"
    echo "  Make sure $INSTALL_DIR is in your PATH"
fi

echo ""
printf "${BOLD}Quick Start:${NC}\n"
echo ""
printf "  ${CYAN}multiclaude new my-project${NC}    Create a new project\n"
printf "  ${CYAN}multiclaude run ./my-project${NC}  Run the development loop\n"
printf "  ${CYAN}multiclaude status${NC}            Check worker status\n"
printf "  ${CYAN}multiclaude merge${NC}             Merge complete features\n"
printf "  ${CYAN}multiclaude qa${NC}                Run QA agent\n"
echo ""
printf "  ${CYAN}multiclaude --help${NC}            Show all commands\n"
echo ""
printf "${BOLD}To update later:${NC}\n"
echo "  cd $SCRIPT_DIR && git pull && ./install.sh"
echo ""
