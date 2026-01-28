#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# MULTICLAUDE INSTALLER / UPDATER
# Installs or updates multiclaude CLI to /usr/local/bin
#═══════════════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
VERSION="0.1.10"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

#───────────────────────────────────────────────────────────────────────────────
# OS Detection
#───────────────────────────────────────────────────────────────────────────────

detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            ;;
        Linux*)
            OS="linux"
            # Detect Linux distribution
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                DISTRO="$ID"
            elif [[ -f /etc/debian_version ]]; then
                DISTRO="debian"
            elif [[ -f /etc/redhat-release ]]; then
                DISTRO="rhel"
            else
                DISTRO="unknown"
            fi
            ;;
        *)
            OS="unknown"
            ;;
    esac
}

#───────────────────────────────────────────────────────────────────────────────
# Package Manager Detection
#───────────────────────────────────────────────────────────────────────────────

detect_package_manager() {
    if [[ "$OS" == "macos" ]]; then
        if command -v brew &>/dev/null; then
            PKG_MANAGER="brew"
            PKG_INSTALL="brew install"
        else
            PKG_MANAGER="none"
        fi
    elif [[ "$OS" == "linux" ]]; then
        if command -v apt-get &>/dev/null; then
            PKG_MANAGER="apt"
            PKG_INSTALL="sudo apt-get install -y"
        elif command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
            PKG_INSTALL="sudo dnf install -y"
        elif command -v yum &>/dev/null; then
            PKG_MANAGER="yum"
            PKG_INSTALL="sudo yum install -y"
        elif command -v pacman &>/dev/null; then
            PKG_MANAGER="pacman"
            PKG_INSTALL="sudo pacman -S --noconfirm"
        elif command -v apk &>/dev/null; then
            PKG_MANAGER="apk"
            PKG_INSTALL="sudo apk add"
        else
            PKG_MANAGER="none"
        fi
    else
        PKG_MANAGER="none"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Tool Installation Functions
#───────────────────────────────────────────────────────────────────────────────

install_homebrew() {
    printf "${YELLOW}!${NC} Homebrew not found. Installing Homebrew...\n"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add to PATH for this session
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if command -v brew &>/dev/null; then
        PKG_MANAGER="brew"
        PKG_INSTALL="brew install"
        printf "${GREEN}✓${NC} Homebrew installed successfully\n"
        return 0
    else
        printf "${RED}✗${NC} Failed to install Homebrew\n"
        return 1
    fi
}

install_tool() {
    local tool="$1"
    local package="$2"

    printf "  Installing ${BOLD}$tool${NC}..."

    if [[ "$PKG_MANAGER" == "none" ]]; then
        printf " ${RED}FAILED${NC} (no package manager)\n"
        return 1
    fi

    # Handle package name differences across package managers
    local pkg_name="$package"
    case "$PKG_MANAGER" in
        pacman)
            # Arch uses different package names sometimes
            case "$package" in
                jq) pkg_name="jq" ;;
            esac
            ;;
    esac

    if $PKG_INSTALL "$pkg_name" &>/dev/null; then
        printf " ${GREEN}OK${NC}\n"
        return 0
    else
        printf " ${RED}FAILED${NC}\n"
        return 1
    fi
}

install_claude_cli() {
    printf "  Installing ${BOLD}Claude Code CLI${NC}...\n"

    # Claude CLI is installed via npm
    if ! command -v npm &>/dev/null; then
        printf "    ${YELLOW}!${NC} npm not found, installing Node.js first...\n"

        if [[ "$OS" == "macos" ]]; then
            if ! $PKG_INSTALL node &>/dev/null; then
                printf "    ${RED}✗${NC} Failed to install Node.js\n"
                return 1
            fi
        elif [[ "$OS" == "linux" ]]; then
            case "$PKG_MANAGER" in
                apt)
                    # Use NodeSource for more recent Node.js
                    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - &>/dev/null
                    sudo apt-get install -y nodejs &>/dev/null
                    ;;
                dnf|yum)
                    curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - &>/dev/null
                    $PKG_INSTALL nodejs &>/dev/null
                    ;;
                pacman)
                    $PKG_INSTALL nodejs npm &>/dev/null
                    ;;
                apk)
                    $PKG_INSTALL nodejs npm &>/dev/null
                    ;;
                *)
                    printf "    ${RED}✗${NC} Cannot install Node.js automatically\n"
                    return 1
                    ;;
            esac
        fi
    fi

    if ! command -v npm &>/dev/null; then
        printf "    ${RED}✗${NC} npm still not available\n"
        return 1
    fi

    # Install Claude CLI globally
    printf "    Installing @anthropic-ai/claude-code via npm...\n"
    if npm install -g @anthropic-ai/claude-code &>/dev/null; then
        printf "    ${GREEN}✓${NC} Claude Code CLI installed\n"
        return 0
    else
        printf "    ${RED}✗${NC} Failed to install Claude Code CLI\n"
        printf "    Try manually: ${CYAN}npm install -g @anthropic-ai/claude-code${NC}\n"
        return 1
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Dependency Check and Installation
#───────────────────────────────────────────────────────────────────────────────

check_and_install_dependencies() {
    printf "${BOLD}Checking dependencies...${NC}\n"
    echo ""

    local failed=""

    # Required tools: git, tmux, claude
    # Check and install each one

    # --- git ---
    if command -v git &>/dev/null; then
        printf "  ${GREEN}✓${NC} git\n"
    else
        printf "  ${YELLOW}!${NC} git not found\n"
        if install_tool "git" "git"; then
            if command -v git &>/dev/null; then
                printf "  ${GREEN}✓${NC} git installed successfully\n"
            else
                failed="$failed git"
            fi
        else
            failed="$failed git"
        fi
    fi

    # --- tmux ---
    if command -v tmux &>/dev/null; then
        printf "  ${GREEN}✓${NC} tmux\n"
    else
        printf "  ${YELLOW}!${NC} tmux not found\n"
        if install_tool "tmux" "tmux"; then
            if command -v tmux &>/dev/null; then
                printf "  ${GREEN}✓${NC} tmux installed successfully\n"
            else
                failed="$failed tmux"
            fi
        else
            failed="$failed tmux"
        fi
    fi

    # --- claude ---
    if command -v claude &>/dev/null; then
        printf "  ${GREEN}✓${NC} claude\n"
    else
        printf "  ${YELLOW}!${NC} claude not found\n"
        if install_claude_cli; then
            if command -v claude &>/dev/null; then
                printf "  ${GREEN}✓${NC} claude installed successfully\n"
            else
                failed="$failed claude"
            fi
        else
            failed="$failed claude"
        fi
    fi

    echo ""

    # Check and install optional tools
    printf "${BOLD}Checking optional dependencies...${NC}\n"

    # --- jq ---
    if command -v jq &>/dev/null; then
        printf "  ${GREEN}✓${NC} jq\n"
    else
        printf "  ${YELLOW}!${NC} jq not found (optional)\n"
        if install_tool "jq" "jq"; then
            printf "  ${GREEN}✓${NC} jq installed\n"
        else
            printf "  ${YELLOW}!${NC} jq installation failed (continuing anyway)\n"
        fi
    fi

    echo ""

    # Check if any required tools failed
    if [[ -n "$failed" ]]; then
        printf "${RED}═══════════════════════════════════════════════════════════════${NC}\n"
        printf "${RED}  INSTALLATION FAILED${NC}\n"
        printf "${RED}═══════════════════════════════════════════════════════════════${NC}\n"
        echo ""
        printf "  Could not install required tools:${RED}$failed${NC}\n"
        echo ""
        printf "  Please install manually:\n"
        if [[ "$failed" == *"git"* ]]; then
            printf "    git:   ${CYAN}brew install git${NC} (macOS)\n"
            printf "           ${CYAN}sudo apt install git${NC} (Debian/Ubuntu)\n"
            printf "           ${CYAN}sudo dnf install git${NC} (Fedora/RHEL)\n"
        fi
        if [[ "$failed" == *"tmux"* ]]; then
            printf "    tmux:  ${CYAN}brew install tmux${NC} (macOS)\n"
            printf "           ${CYAN}sudo apt install tmux${NC} (Debian/Ubuntu)\n"
            printf "           ${CYAN}sudo dnf install tmux${NC} (Fedora/RHEL)\n"
        fi
        if [[ "$failed" == *"claude"* ]]; then
            printf "    claude: ${CYAN}npm install -g @anthropic-ai/claude-code${NC}\n"
            printf "            Or visit: https://claude.ai/code\n"
        fi
        echo ""
        exit 1
    fi

    printf "${GREEN}✓${NC} All required dependencies satisfied\n"
    echo ""
}

#───────────────────────────────────────────────────────────────────────────────
# Main Installation
#───────────────────────────────────────────────────────────────────────────────

echo ""
printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
printf "${BOLD}  MULTICLAUDE INSTALLER v${VERSION}${NC}\n"
printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
echo ""

# Detect OS and package manager
detect_os
detect_package_manager

printf "${BOLD}System detected:${NC} $OS"
if [[ "$OS" == "linux" ]]; then
    printf " ($DISTRO)"
fi
echo ""
printf "${BOLD}Package manager:${NC} "
if [[ "$PKG_MANAGER" == "none" ]]; then
    printf "${YELLOW}none found${NC}\n"
else
    printf "${GREEN}$PKG_MANAGER${NC}\n"
fi
echo ""

# On macOS without Homebrew, offer to install it
if [[ "$OS" == "macos" && "$PKG_MANAGER" == "none" ]]; then
    printf "${YELLOW}!${NC} Homebrew is required to install dependencies on macOS.\n"
    read -p "  Install Homebrew now? (Y/n): " confirm
    if [[ ! "$confirm" =~ ^[Nn] ]]; then
        if ! install_homebrew; then
            printf "${RED}✗${NC} Cannot proceed without a package manager.\n"
            exit 1
        fi
    else
        printf "${RED}✗${NC} Cannot proceed without Homebrew on macOS.\n"
        printf "  Install manually: ${CYAN}https://brew.sh${NC}\n"
        exit 1
    fi
    echo ""
fi

# On Linux without package manager, halt
if [[ "$OS" == "linux" && "$PKG_MANAGER" == "none" ]]; then
    printf "${RED}✗${NC} No supported package manager found.\n"
    printf "  Supported: apt, dnf, yum, pacman, apk\n"
    printf "  Please install dependencies manually.\n"
    exit 1
fi

# Unsupported OS
if [[ "$OS" == "unknown" ]]; then
    printf "${RED}✗${NC} Unsupported operating system.\n"
    printf "  multiclaude supports macOS and Linux.\n"
    exit 1
fi

# Check and install dependencies
check_and_install_dependencies

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
chmod +x "$SCRIPT_DIR/monitor.sh"
chmod +x "$SCRIPT_DIR/feature.sh"
chmod +x "$SCRIPT_DIR/install.sh"
chmod +x "$SCRIPT_DIR/remote-install.sh" 2>/dev/null || true
printf "${GREEN}✓${NC} All scripts are executable\n"
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
