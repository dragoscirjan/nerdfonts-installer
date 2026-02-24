#!/usr/bin/env bash
#
# NerdFonts TUI Installer
# Run directly from GitHub:
#   curl -sL https://raw.githubusercontent.com/OWNER/REPO/BRANCH/nerdfonts-tui.sh | bash
#
# Or use these environment variables:
#   NERDFONTS_SCRIPT_URL - Full URL to the TUI script
#   NERDFONTS_REPO       - GitHub repo (owner/repo)
#   NERDFONTS_BRANCH     - Branch name (default: master)
#

set -o pipefail

NERDFONTS_TUI_VERSION="1.0.0"
NERDFONTS_SCRIPT_URL="${NERDFONTS_SCRIPT_URL:-}"

detect_git_repo() {
    local repo=""
    local branch=""
    
    if [[ -d ".git" ]]; then
        repo=$(git remote get-url origin 2>/dev/null | sed 's|git@github.com:||' | sed 's|.*github.com/||' | sed 's|\.git$||')
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    fi
    
    if [[ -n "$repo" ]]; then
        echo "$repo|$branch"
    fi
}

if [[ -z "$NERDFONTS_SCRIPT_URL" ]]; then
    if [[ -z "$NERDFONTS_REPO" ]]; then
        git_info=$(detect_git_repo)
        if [[ -n "$git_info" ]]; then
            NERDFONTS_REPO="${git_info%%|*}"
            detected_branch="${git_info##*|}"
            NERDFONTS_BRANCH="${NERDFONTS_BRANCH:-$detected_branch}"
        fi
    fi
    NERDFONTS_BRANCH="${NERDFONTS_BRANCH:-master}"
fi

if [[ -z "${BASH_VERSION}" ]]; then
    echo "Error: Bash is required"
    exit 1
fi

if [[ "${BASH_VERSION%%.*}" -lt 5 ]]; then
    echo "Error: Bash 5.0+ is required (current: ${BASH_VERSION})"
    exit 1
fi

check_dependencies() {
    local missing=()
    
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v unzip &>/dev/null; then
        missing+=("unzip")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing[*]}"
        echo "Please install them and try again."
        exit 1
    fi
}

download_and_run() {
    local temp_dir
    temp_dir=$(mktemp -d)
    
    local script_path="${temp_dir}/nerdfonts-tui.sh"
    
    if [[ -n "$NERDFONTS_SCRIPT_URL" ]]; then
        echo "Downloading NerdFonts TUI from custom URL..."
        if ! curl -sL --max-time 60 -o "$script_path" "$NERDFONTS_SCRIPT_URL"; then
            echo "Error: Failed to download from $NERDFONTS_SCRIPT_URL"
            rm -rf "$temp_dir"
            exit 1
        fi
    elif [[ -n "$NERDFONTS_REPO" ]]; then
        echo "Downloading NerdFonts TUI from ${NERDFONTS_REPO}..."
        local script_url="https://raw.githubusercontent.com/${NERDFONTS_REPO}/${NERDFONTS_BRANCH}/src/nerdfonts-tui.sh"
        if ! curl -sL --max-time 60 -o "$script_path" "$script_url"; then
            echo "Error: Failed to download from $script_url"
            rm -rf "$temp_dir"
            exit 1
        fi
    else
        echo "Error: Please set NERDFONTS_SCRIPT_URL or NERDFONTS_REPO environment variable"
        echo ""
        echo "Usage:"
        echo "  # From a GitHub repo:"
        echo "  NERDFONTS_REPO=your-username/nerd-fonts bash nerdfonts-tui.sh"
        echo "  NERDFONTS_REPO=your-username/nerd-fonts NERDFONTS_BRANCH=main bash nerdfonts-tui.sh"
        echo ""
        echo "  # From a direct URL:"
        echo "  NERDFONTS_SCRIPT_URL=https://example.com/nerdfonts-tui.sh bash nerdfonts-tui.sh"
        echo ""
        echo "  # Or run the TUI directly:"
        echo "  bash src/nerdfonts-tui.sh"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    chmod +x "$script_path"
    
    unset NERDFONTS_REPO NERDFONTS_BRANCH
    exec bash "$script_path"
}

check_dependencies
download_and_run
