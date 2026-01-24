#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# MULTICLAUDE REMOTE INSTALLER
# One-liner installation script - downloads and installs multiclaude
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/pankajgarkoti/multiclaude/main/remote-install.sh | bash
#
#   Or with a custom install directory:
#   curl -fsSL ... | INSTALL_PATH=~/tools/multiclaude bash
#═══════════════════════════════════════════════════════════════════════════════

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
REPO_URL="${MULTICLAUDE_REPO:-https://github.com/pankajgarkoti/multiclaude.git}"
INSTALL_PATH="${INSTALL_PATH:-$HOME/.multiclaude}"
BRANCH="${MULTICLAUDE_BRANCH:-main}"

echo ""
printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}  MULTICLAUDE REMOTE INSTALLER${NC}\n"
printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
echo ""

#───────────────────────────────────────────────────────────────────────────────
# Pre-flight checks
#───────────────────────────────────────────────────────────────────────────────

# Check for git (required to clone)
if ! command -v git &>/dev/null; then
    printf "${RED}✗${NC} git is required but not installed.\n"
    echo ""
    case "$(uname -s)" in
        Darwin*)
            printf "  Install with: ${CYAN}xcode-select --install${NC}\n"
            printf "  Or:           ${CYAN}brew install git${NC}\n"
            ;;
        Linux*)
            printf "  Install with: ${CYAN}sudo apt install git${NC} (Debian/Ubuntu)\n"
            printf "                ${CYAN}sudo dnf install git${NC} (Fedora/RHEL)\n"
            printf "                ${CYAN}sudo pacman -S git${NC} (Arch)\n"
            ;;
    esac
    echo ""
    exit 1
fi

printf "${BOLD}Install location:${NC} $INSTALL_PATH\n"
echo ""

#───────────────────────────────────────────────────────────────────────────────
# Clone or update repository
#───────────────────────────────────────────────────────────────────────────────

if [[ -d "$INSTALL_PATH/.git" ]]; then
    printf "${GREEN}✓${NC} multiclaude already cloned, updating...\n"
    cd "$INSTALL_PATH"
    git fetch origin "$BRANCH" --quiet
    git reset --hard "origin/$BRANCH" --quiet
    printf "${GREEN}✓${NC} Updated to latest version\n"
else
    if [[ -d "$INSTALL_PATH" ]]; then
        printf "${YELLOW}!${NC} Directory exists but is not a git repo: $INSTALL_PATH\n"
        read -p "  Remove and re-clone? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy] ]]; then
            rm -rf "$INSTALL_PATH"
        else
            printf "${RED}✗${NC} Aborted.\n"
            exit 1
        fi
    fi

    printf "Cloning multiclaude...\n"
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_PATH" --quiet
    printf "${GREEN}✓${NC} Cloned successfully\n"
fi

echo ""

#───────────────────────────────────────────────────────────────────────────────
# Run the full installer
#───────────────────────────────────────────────────────────────────────────────

printf "Running installer...\n"
echo ""

cd "$INSTALL_PATH"
exec ./install.sh
