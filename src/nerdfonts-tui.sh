#!/usr/bin/env bash
#
# NerdFonts TUI Installer
# A terminal-based font installer for NerdFonts
# Run with: curl -s https://raw.githubusercontent.com/OWNER/REPO/BRANCH/nerdfonts-tui.sh | bash
# Or save and run: ./nerdfonts-tui.sh
#

set -o pipefail
shopt -s globstar

NERDFONTS_TUI_VERSION="1.0.0"
NERDFONTS_REPO="${NERDFONTS_REPO:-ryanoasis/nerd-fonts}"
NERDFONTS_API_URL="https://api.github.com/repos/${NERDFONTS_REPO}/releases"
NERDFONTS_BASE_URL="https://github.com/${NERDFONTS_REPO}/releases/download"

declare -A FONT_STATUS
declare -A FONT_URLS

array_contains_key() {
    local key="$1"
    shift
    for item in "$@"; do
        [[ "$item" == "$key" ]] && return 0
    done
    return 1
}
SELECTED_FONTS=()
INSTALLED_FONTS=()
SEARCH_QUERY=""
CURRENT_PAGE=0
ITEMS_PER_PAGE=20
TOTAL_FONTS=0

if [[ -z "${BASH_VERSION}" ]]; then
    echo "Error: Bash is required"
    exit 1
fi

if [[ "${BASH_VERSION%%.*}" -lt 5 ]]; then
    echo "Error: Bash 5.0+ is required (current: ${BASH_VERSION})"
    exit 1
fi

draw_hline() {
    local char="${1:-─}"
    local width="${2:-$TPUT_COLS}"
    printf "%b" "${BOLD}${FG_BLUE}"
    printf -- "$char" $(seq 1 $width)
    printf "%b" "${NORMAL}\n"
}

# Repeat a character n times (works with UTF-8 multi-byte chars)
repeat_char() {
    local char="$1"
    local count="$2"
    local i
    for ((i = 0; i < count; i++)); do
        printf '%s' "$char"
    done
}

draw_box_line() {
    local content="$1"
    local w=$TPUT_COLS
    local content_len=$(echo -n "$content" | wc -c)
    local padding=$((w - content_len - 2))
    [[ $padding -lt 0 ]] && padding=0
    printf "%b" "${BOLD}${FG_BLUE}${BOX_VERT}${NORMAL}${content}"
    printf "%${padding}s" ""
    printf "%b" "${FG_BLUE}${BOX_VERT}${NORMAL}\n"
}

setup_locale() {
    if locale -a 2>/dev/null | grep -qi utf; then
        export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 2>/dev/null || true
    else
        export LANG=C LC_ALL=C 2>/dev/null || true
    fi
}

setup_terminal() {
    if [[ -t 0 ]]; then
        stty -echo -icanon 2>/dev/null || true
    fi
    
    refresh_dimensions
    
    ESC=$'\033'
    CLR_SCREEN="${ESC}[H${ESC}[J"
    CLR_LINE="${ESC}[2K"
    BOLD="${ESC}[1m"
    DIM="${ESC}[2m"
    NORMAL="${ESC}[0m"
    UNDERLINE="${ESC}[4m"
    HIGHLIGHT="${ESC}[7m"
    INVERT="${ESC}[7m"
    
    CURSOR_HIDE="${ESC}[?25l"
    CURSOR_SHOW="${ESC}[?25h"
    CURSOR_POS="${ESC}[%d;%dH"
    SAVE_POS="${ESC}7"
    RESTORE_POS="${ESC}8"
    
    # Alternate screen buffer (like vim uses)
    ALT_SCREEN_ON="${ESC}[?1049h"
    ALT_SCREEN_OFF="${ESC}[?1049l"
    
    FG_BLACK="${ESC}[30m"
    FG_RED="${ESC}[31m"
    FG_GREEN="${ESC}[32m"
    FG_YELLOW="${ESC}[33m"
    FG_BLUE="${ESC}[34m"
    FG_MAGENTA="${ESC}[35m"
    FG_CYAN="${ESC}[36m"
    FG_WHITE="${ESC}[37m"
    
    BG_BLACK="${ESC}[40m"
    BG_WHITE="${ESC}[47m"
    BG_BLUE="${ESC}[44m"
    
    if [[ "$(locale charmap 2>/dev/null)" == "UTF-8" ]]; then
        BOX_HORIZ="─"
        BOX_VERT="│"
        BOX_TOP_LEFT="┌"
        BOX_TOP_RIGHT="┐"
        BOX_BOTTOM_LEFT="└"
        BOX_BOTTOM_RIGHT="┘"
        BOX_CROSS_H="├"
        BOX_CROSS_V="┼"
        BOX_CROSS_T="┬"
        BOX_CROSS_B="┴"
    else
        BOX_HORIZ="-"
        BOX_VERT="|"
        BOX_TOP_LEFT="+"
        BOX_TOP_RIGHT="+"
        BOX_BOTTOM_LEFT="+"
        BOX_BOTTOM_RIGHT="+"
        BOX_CROSS_H="+"
        BOX_CROSS_V="+"
        BOX_CROSS_T="+"
        BOX_CROSS_B="+"
    fi
    
    INITIALIZED=1
}

refresh_dimensions() {
    if command -v tput &>/dev/null && [[ -t 0 ]]; then
        TPUT_LINES=$(tput lines 2>/dev/null || echo 24)
        TPUT_COLS=$(tput cols 2>/dev/null || echo 80)
    else
        TPUT_LINES=${TPUT_LINES:-24}
        TPUT_COLS=${TPUT_COLS:-80}
    fi
    
    # Header: 8 rows, Footer: 4 rows = 12 total chrome rows
    ITEMS_PER_PAGE=$((TPUT_LINES - 12))
    [[ $ITEMS_PER_PAGE -lt 5 ]] && ITEMS_PER_PAGE=5
}

cleanup() {
    stty echo 2>/dev/null || true
    printf "%s" "${CURSOR_SHOW}"
    printf "%s" "${ALT_SCREEN_OFF}"
}

trap cleanup EXIT

read_key() {
    local key
    local c
    
    IFS= read -r -n1 -t 0.1 c 2>/dev/null || return 1
    
    if [[ "$c" == "$ESC" ]]; then
        IFS= read -r -n1 -t 0.1 c 2>/dev/null || return 1
        if [[ "$c" == "[" ]]; then
            IFS= read -r -n1 -t 0.1 c 2>/dev/null || return 1
            case "$c" in
                A) echo "UP" ;;
                B) echo "DOWN" ;;
                C) echo "RIGHT" ;;
                D) echo "LEFT" ;;
                F) echo "END" ;;
                H) echo "HOME" ;;
                *) echo "UNKNOWN" ;;
            esac
            return 0
        fi
        echo "ESC"
        return 0
    fi
    
    case "$c" in
        $'\n'|"" ) echo "ENTER" ;;
        $'\t')     echo "TAB" ;;
        $'\x7f')   echo "BACKSPACE" ;;
        "a")       echo "A" ;;
        "A")       echo "A" ;;
        "i")       echo "I" ;;
        "I")       echo "I" ;;
        "q")       echo "Q" ;;
        "Q")       echo "Q" ;;
        "r")       echo "R" ;;
        "R")       echo "R" ;;
        "u")       echo "U" ;;
        "U")       echo "U" ;;
        "s")       echo "S" ;;
        "S")       echo "S" ;;
        " ")       echo "SPACE" ;;
        *)         echo "KEY_$c" ;;
    esac
}

get_release_info() {
    local release_data
    release_data=$(curl -s --max-time 30 "${NERDFONTS_API_URL}/latest" 2>/dev/null) || return 1
    
    local version
    version=$(echo "$release_data" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [[ -z "$version" ]]; then
        version=$(echo "$release_data" | grep -o '"name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    echo "$version"
}

fetch_font_list() {
    echo -e "${FG_CYAN}Fetching NerdFonts release information...${NORMAL}"
    
    local release_data
    release_data=$(curl -s --max-time 60 "${NERDFONTS_API_URL}/latest" 2>/dev/null) || {
        echo -e "${FG_RED}Failed to fetch release information${NORMAL}"
        return 1
    }
    
    local version
    version=$(echo "$release_data" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [[ -z "$version" ]]; then
        echo -e "${FG_RED}Could not determine latest release version${NORMAL}"
        return 1
    fi
    
    echo -e "${FG_GREEN}Found version: ${version}${NORMAL}"
    
    FONT_URLS=()
    
    local assets
    assets=$(echo "$release_data" | grep -o '"browser_download_url": *"[^"]*\.zip"[^}]*' | grep -v "Windows\|Powerline\|旧字体" | head -100)
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        local url
        url=$(echo "$line" | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4)
        
        [[ -z "$url" ]] && continue
        [[ "$url" != *".zip" ]] && continue
        
        local filename
        filename=$(basename "$url" .zip)
        
        FONT_URLS["$filename"]="${NERDFONTS_BASE_URL}/${version}/${filename}.zip"
    done <<< "$assets"
    
    TOTAL_FONTS=${#FONT_URLS[@]}
    
    if [[ $TOTAL_FONTS -eq 0 ]]; then
        echo -e "${FG_RED}No fonts found in release${NORMAL}"
        return 1
    fi
    
    echo -e "${FG_GREEN}Found ${TOTAL_FONTS} fonts${NORMAL}"
    
    detect_installed_fonts
}

detect_installed_fonts() {
    INSTALLED_FONTS=()
    
    local font_dirs=()
    
    if [[ -d "$HOME/.local/share/fonts" ]]; then
        font_dirs+=("$HOME/.local/share/fonts")
    fi
    
    if [[ -d "$HOME/.fonts" ]]; then
        font_dirs+=("$HOME/.fonts")
    fi
    
    if [[ -d "/usr/local/share/fonts" ]]; then
        font_dirs+=("/usr/local/share/fonts")
    fi
    
    if [[ -d "/usr/share/fonts" ]]; then
        font_dirs+=("/usr/share/fonts")
    fi
    
    for font_dir in "${font_dirs[@]}"; do
        if [[ -d "$font_dir" ]]; then
            for font_file in "$font_dir"/**/*.ttf "$font_dir"/**/*.otf "$font_dir"/*.ttf "$font_dir"/*.otf; do
                [[ -f "$font_file" ]] || continue
                
                local font_basename
                font_basename=$(basename "$font_file")
                
                for font_name in "${!FONT_URLS[@]}"; do
                    if [[ "$font_basename" == *"${font_name}"* ]]; then
                        INSTALLED_FONTS["$font_name"]=1
                    fi
                done
            done
        fi
    done
    
    local font_names=()
    for font_name in "${!FONT_URLS[@]}"; do
        font_names+=("$font_name")
    done
    
    for font_name in "${font_names[@]}"; do
        local is_installed=0
        for installed_key in "${!INSTALLED_FONTS[@]}"; do
            if [[ "$installed_key" == "$font_name" ]]; then
                is_installed=1
                break
            fi
        done
        if [[ $is_installed -eq 1 ]]; then
            FONT_STATUS["$font_name"]="installed"
        else
            FONT_STATUS["$font_name"]="none"
        fi
    done
}

get_filtered_fonts() {
    local filtered=()
    
    for font_name in "${!FONT_URLS[@]}"; do
        if [[ -z "$SEARCH_QUERY" ]] || [[ "${font_name,,}" == *"${SEARCH_QUERY,,}"* ]]; then
            filtered+=("$font_name")
        fi
    done
    
    printf '%s\n' "${filtered[@]}" | sort
}

draw_header() {
    refresh_dimensions
    local w=$TPUT_COLS
    
    printf "%s" "${ESC}[H"
    printf "%b" "${BOLD}${FG_BLUE}${BOX_TOP_LEFT}"
    repeat_char "$BOX_HORIZ" "$w"
    printf "%b" "${BOX_TOP_RIGHT}${NORMAL}\n"
    
    draw_box_line "     ${FG_WHITE}NerdFonts TUI Installer v${NERDFONTS_TUI_VERSION}${NORMAL}"
    draw_box_line "     ${DIM}Select fonts to install/uninstall${NORMAL}"
    
    printf "%b" "${BOLD}${FG_BLUE}${BOX_CROSS_T}"
    repeat_char "$BOX_HORIZ" "$w"
    printf "%b" "${BOX_CROSS_B}${NORMAL}\n"
    
    draw_box_line " ${FG_CYAN}[I]${NORMAL}=Install  ${FG_YELLOW}[U]${NORMAL}=Uninstall  ${FG_GREEN}[S]${NORMAL}=Select All  ${FG_RED}[R]${NORMAL}=Deselect All"
    
    printf "%b" "${BOLD}${FG_BLUE}${BOX_CROSS_T}"
    repeat_char "$BOX_HORIZ" "$w"
    printf "%b" "${BOX_CROSS_B}${NORMAL}\n"
    
    local search_line=" Search: [${FG_YELLOW}${SEARCH_QUERY}${NORMAL}]"
    draw_box_line "$search_line"
    
    printf "%b" "${BOLD}${FG_BLUE}${BOX_CROSS_T}"
    repeat_char "$BOX_HORIZ" "$w"
    printf "%b" "${BOX_CROSS_B}${NORMAL}\n"
}

draw_footer() {
    local selected_count=0
    local installed_count=0
    
    for font_name in "${!FONT_STATUS[@]}"; do
        if [[ "${FONT_STATUS[$font_name]}" == "selected" ]]; then
            ((selected_count++))
        fi
        if [[ "${FONT_STATUS[$font_name]}" == "installed" ]]; then
            ((installed_count++))
        fi
    done
    
    local total_pages=$(((TOTAL_FONTS + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE))
    [[ $total_pages -lt 1 ]] && total_pages=1
    
    local w=$TPUT_COLS
    
    printf "%b" "${BOLD}${FG_BLUE}${BOX_CROSS_H}"
    repeat_char "$BOX_HORIZ" "$w"
    printf "%b" "${BOX_CROSS_H}${NORMAL}\n"
    
    local status_text=" Selected: ${FG_GREEN}${selected_count}${NORMAL} | Installed: ${FG_YELLOW}${installed_count}${NORMAL} | Total: ${TOTAL_FONTS} | Page: $((CURRENT_PAGE + 1))/${total_pages}"
    draw_box_line "$status_text"
    
    local help_text=" [↑/↓] Navigate  [Space] Toggle  [Enter] Install/Uninstall  [Q] Quit"
    draw_box_line "$help_text"
    
    printf "%b" "${BOLD}${FG_BLUE}${BOX_BOTTOM_LEFT}"
    repeat_char "$BOX_HORIZ" "$w"
    printf "%b" "${BOX_BOTTOM_RIGHT}${NORMAL}\n"
}

draw_font_list() {
    local selected_idx="${1:-0}"
    local fonts_array=()
    while IFS= read -r font; do
        [[ -n "$font" ]] && fonts_array+=("$font")
    done < <(get_filtered_fonts)
    
    local total_filtered=${#fonts_array[@]}
    local total_pages=$(((total_filtered + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE))
    [[ $total_pages -lt 1 ]] && total_pages=1
    
    [[ $CURRENT_PAGE -ge $total_pages ]] && CURRENT_PAGE=0
    [[ $CURRENT_PAGE -lt 0 ]] && CURRENT_PAGE=$((total_pages - 1))
    [[ $CURRENT_PAGE -lt 0 ]] && CURRENT_PAGE=0
    
    local start_idx=$((CURRENT_PAGE * ITEMS_PER_PAGE))
    local end_idx=$((start_idx + ITEMS_PER_PAGE))
    [[ $end_idx -gt $total_filtered ]] && end_idx=$total_filtered
    [[ $start_idx -ge $total_filtered ]] && start_idx=0
    
    local w=$TPUT_COLS
    local content_w=$((w - 4))
    local line_num=0
    
    for ((i = start_idx; i < end_idx && i < total_filtered; i++)); do
        local font_name="${fonts_array[$i]}"
        local status="${FONT_STATUS[$font_name]:-none}"
        
        local checkbox="[ ]"
        local color="$FG_WHITE"
        
        if [[ $i -eq $selected_idx ]]; then
            if [[ "$status" == "selected" || "$status" == "both" ]]; then
                checkbox="[✓]"
                color="$FG_GREEN"
            elif [[ "$status" == "installed" ]]; then
                checkbox="[I]"
                color="$FG_YELLOW"
            fi
            # Selected row: │ + space + > + space + checkbox + space + fontname + pad + │
            # Content width: 1 + 1 + 1 + 3 + 1 + fontname = 7 + fontname
            # pad = w - 2 (borders) - 7 - fontname = w - 9 - fontname
            printf "%b" "${BOLD}${FG_BLUE}${BOX_VERT}${NORMAL}"
            printf "%b" " ${BOLD}${FG_CYAN}>${NORMAL} ${color}${checkbox} ${font_name:0:$content_w}${NORMAL}"
            local pad=$((w - 2 - 7 - ${#font_name}))
            [[ $pad -gt 0 ]] && printf "%${pad}s" ""
            printf "%b" "${FG_BLUE}${BOX_VERT}${NORMAL}\n"
        else
            case "$status" in
                selected|both)
                    checkbox="[✓]"
                    color="$FG_GREEN"
                    ;;
                installed)
                    checkbox="[I]"
                    color="$FG_YELLOW"
                    ;;
            esac
            # Non-selected row: │ + space + space + checkbox + space + fontname + pad + │
            # Content width: 1 + 1 + 3 + 1 + fontname = 6 + fontname  
            # pad = w - 2 (borders) - 6 - fontname = w - 8 - fontname
            printf "%b" "${BOLD}${FG_BLUE}${BOX_VERT}${NORMAL}  ${color}${checkbox} ${font_name:0:$content_w}${NORMAL}"
            local pad=$((w - 2 - 6 - ${#font_name}))
            [[ $pad -gt 0 ]] && printf "%${pad}s" ""
            printf "%b" "${FG_BLUE}${BOX_VERT}${NORMAL}\n"
        fi
        
        ((line_num++))
    done
    
    while [[ $line_num -lt $ITEMS_PER_PAGE ]]; do
        # Empty row: │ + (w-2 spaces) + │
        printf "%b" "${BOLD}${FG_BLUE}${BOX_VERT}${NORMAL}"
        printf "%$((w - 2))s" ""
        printf "%b" "${FG_BLUE}${BOX_VERT}${NORMAL}\n"
        ((line_num++))
    done
}

toggle_font_selection() {
    local font_name="$1"
    local current_status="${FONT_STATUS[$font_name]:-none}"
    
    case "$current_status" in
        selected|both)
            if array_contains_key "$font_name" "${!INSTALLED_FONTS[@]}"; then
                FONT_STATUS["$font_name"]="installed"
            else
                FONT_STATUS["$font_name"]="none"
            fi
            ;;
        installed)
            FONT_STATUS["$font_name"]="both"
            ;;
        *)
            FONT_STATUS["$font_name"]="selected"
            ;;
    esac
}

select_all_filtered() {
    local fonts_array=()
    while IFS= read -r font; do
        [[ -n "$font" ]] && fonts_array+=("$font")
    done < <(get_filtered_fonts)
    
    for font_name in "${fonts_array[@]}"; do
        local current="${FONT_STATUS[$font_name]:-none}"
        if [[ "$current" != "selected" && "$current" != "both" ]]; then
            if array_contains_key "$font_name" "${!INSTALLED_FONTS[@]}"; then
                FONT_STATUS["$font_name"]="both"
            else
                FONT_STATUS["$font_name"]="selected"
            fi
        fi
    done
}

deselect_all_filtered() {
    local fonts_array=()
    while IFS= read -r font; do
        [[ -n "$font" ]] && fonts_array+=("$font")
    done < <(get_filtered_fonts)
    
    for font_name in "${fonts_array[@]}"; do
        local current="${FONT_STATUS[$font_name]:-none}"
        if [[ "$current" == "selected" || "$current" == "both" ]]; then
            if array_contains_key "$font_name" "${!INSTALLED_FONTS[@]}"; then
                FONT_STATUS["$font_name"]="installed"
            else
                FONT_STATUS["$font_name"]="none"
            fi
        fi
    done
}

get_fonts_to_install() {
    local to_install=()
    for font_name in "${!FONT_STATUS[@]}"; do
        local status="${FONT_STATUS[$font_name]}"
        if [[ "$status" == "selected" || "$status" == "both" ]]; then
            if ! array_contains_key "$font_name" "${!INSTALLED_FONTS[@]}" || [[ "$status" == "both" ]]; then
                to_install+=("$font_name")
            fi
        fi
    done
    printf '%s\n' "${to_install[@]}"
}

get_fonts_to_uninstall() {
    local to_uninstall=()
    for font_name in "${!FONT_STATUS[@]}"; do
        local status="${FONT_STATUS[$font_name]}"
        if [[ "$status" == "none" || "$status" == "installed" ]]; then
            local is_installed=0
            array_contains_key "$font_name" "${!INSTALLED_FONTS[@]}" && is_installed=1
            if [[ "$status" == "none" && $is_installed -eq 1 ]]; then
                to_uninstall+=("$font_name")
            fi
        fi
    done
    printf '%s\n' "${to_uninstall[@]}"
}

get_font_dir() {
    local use_system=false
    
    if [[ -w "/usr/local/share/fonts" ]]; then
        echo "/usr/local/share/fonts"
        return
    fi
    
    if [[ -w "/usr/share/fonts" ]]; then
        echo "/usr/share/fonts"
        return
    fi
    
    mkdir -p "$HOME/.local/share/fonts"
    echo "$HOME/.local/share/fonts"
}

download_and_install_fonts() {
    local fonts_to_install=()
    while IFS= read -r font; do
        [[ -n "$font" ]] && fonts_to_install+=("$font")
    done < <(get_fonts_to_install)
    
    local fonts_to_uninstall=()
    while IFS= read -r font; do
        [[ -n "$font" ]] && fonts_to_uninstall+=("$font")
    done < <(get_fonts_to_uninstall)
    
    if [[ ${#fonts_to_install[@]} -eq 0 && ${#fonts_to_uninstall[@]} -eq 0 ]]; then
        echo -e "${FG_YELLOW}No changes to make${NORMAL}"
        return 0
    fi
    
    echo -e "${CLR_SCREEN}"
    echo -e "${BOLD}${FG_BLUE}═══════════════════════════════════════════════════════════════════${NORMAL}"
    echo -e "${BOLD}                     NerdFonts Installation${NORMAL}"
    echo -e "${BOLD}${FG_BLUE}═══════════════════════════════════════════════════════════════════${NORMAL}"
    echo ""
    
    local font_dir
    font_dir=$(get_font_dir)
    echo -e "Installing to: ${FG_CYAN}${font_dir}${NORMAL}"
    echo ""
    
    local success_count=0
    local fail_count=0
    
    for font_name in "${fonts_to_install[@]}"; do
        local url="${FONT_URLS[$font_name]}"
        
        echo -ne "${FG_WHITE}Installing ${FG_GREEN}${font_name}${FG_WHITE}... "
        
        local temp_zip
        temp_zip=$(mktemp /tmp/nerdfonts-XXXXXX.zip)
        
        if curl -sL --max-time 120 -o "$temp_zip" "$url" 2>/dev/null; then
            mkdir -p "$font_dir"
            
            if unzip -q -o "$temp_zip" -d "$font_dir" 2>/dev/null; then
                rm -f "$temp_zip"
                INSTALLED_FONTS["$font_name"]=1
                FONT_STATUS["$font_name"]="installed"
                echo -e "${FG_GREEN}✓${NORMAL}"
                ((success_count++))
            else
                rm -f "$temp_zip"
                echo -e "${FG_RED}✗ (unzip failed)${NORMAL}"
                ((fail_count++))
            fi
        else
            rm -f "$temp_zip"
            echo -e "${FG_RED}✗ (download failed)${NORMAL}"
            ((fail_count++))
        fi
    done
    
    if [[ ${#fonts_to_uninstall[@]} -gt 0 ]]; then
        echo ""
        echo -e "${FG_YELLOW}Uninstalling fonts...${NORMAL}"
        
        for font_name in "${fonts_to_uninstall[@]}"; do
            echo -ne "${FG_WHITE}Uninstalling ${FG_YELLOW}${font_name}${FG_WHITE}... "
            
            local found=false
            for ext in ttf otf; do
                local font_pattern="${font_dir}/${font_name}-${ext}"
                if ls "$font_pattern"* &>/dev/null; then
                    rm -f "$font_pattern"*
                    found=true
                fi
            done
            
            if [[ -d "$HOME/.fonts" ]]; then
                for ext in ttf otf; do
                    local font_pattern="$HOME/.fonts/${font_name}-${ext}"
                    if ls "$font_pattern"* &>/dev/null; then
                        rm -f "$font_pattern"*
                        found=true
                    fi
                done
            fi
            
            if [[ "$found" == "true" ]]; then
                unset INSTALLED_FONTS["$font_name"]
                FONT_STATUS["$font_name"]="none"
                echo -e "${FG_GREEN}✓${NORMAL}"
                ((success_count++))
            else
                echo -e "${FG_YELLOW}not found${NORMAL}"
            fi
        done
    fi
    
    echo ""
    echo -e "${BOLD}${FG_BLUE}═══════════════════════════════════════════════════════════════════${NORMAL}"
    echo -e "Summary: ${FG_GREEN}${success_count} success${NORMAL}, ${FG_RED}${fail_count} failed${NORMAL}"
    echo ""
    
    if [[ $success_count -gt 0 ]]; then
        echo -e "${FG_CYAN}Refreshing font cache...${NORMAL}"
        
        if command -v fc-cache &>/dev/null; then
            fc-cache -f -v &>/dev/null || true
        fi
        
        if command -v mkfontscale &>/dev/null; then
            mkfontscale "$font_dir" &>/dev/null || true
        fi
        
        if command -v mkfontdir &>/dev/null; then
            mkfontdir "$font_dir" &>/dev/null || true
        fi
        
        echo -e "${FG_GREEN}Font cache refreshed${NORMAL}"
    fi
    
    echo ""
    echo -e "Press ${FG_YELLOW}Enter${NORMAL} to return to menu..."
    read -r
}

show_about() {
    echo -e "${CLR_SCREEN}"
    echo -e "${BOLD}${FG_BLUE}═══════════════════════════════════════════════════════════════════${NORMAL}"
    echo -e "${BOLD}                          About NerdFonts TUI${NORMAL}"
    echo -e "${BOLD}${FG_BLUE}═══════════════════════════════════════════════════════════════════${NORMAL}"
    echo ""
    echo -e "Version: ${FG_CYAN}${NERDFONTS_TUI_VERSION}${NORMAL}"
    echo -e "Font Repository: ${FG_CYAN}${NERDFONTS_REPO}${NORMAL}"
    echo ""
    echo -e "${FG_YELLOW}Usage:${NORMAL}"
    echo "  curl -s https://raw.githubusercontent.com/ryanoasis/nerdfonts/master/nerdfonts-tui.sh | bash"
    echo ""
    echo -e "${FG_YELLOW}Keyboard Shortcuts:${NORMAL}"
    echo "  ↑/↓     - Navigate font list"
    echo "  Space   - Toggle font selection"
    echo "  Enter   - Proceed to install/uninstall"
    echo "  I       - Mark selected fonts for installation"
    echo "  U       - Mark selected fonts for uninstallation"
    echo "  S       - Select all visible fonts"
    echo "  R       - Deselect all visible fonts"
    echo "  /       - Focus search field"
    echo "  Q       - Quit"
    echo ""
    echo -e "Press ${FG_YELLOW}Enter${NORMAL} to return..."
    read -r
}

main_loop() {
    local selected_idx=0
    local needs_redraw=1
    
    # Switch to alternate screen buffer to reduce flicker
    printf "%s" "${ALT_SCREEN_ON}"
    printf "%s" "${CURSOR_HIDE}"
    
    while true; do
        if [[ $needs_redraw -eq 1 ]]; then
            draw_header
            draw_font_list "$selected_idx"
            draw_footer
            needs_redraw=0
        fi
        
        local key
        key=$(read_key)
        [[ -z "$key" ]] && continue
        
        local fonts_array=()
        while IFS= read -r font; do
            [[ -n "$font" ]] && fonts_array+=("$font")
        done < <(get_filtered_fonts)
        
        local total_filtered=${#fonts_array[@]}
        [[ $total_filtered -eq 0 ]] && total_filtered=0
        local total_pages=$(((total_filtered + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE))
        [[ $total_pages -lt 1 ]] && total_pages=1
        
        local prev_idx=$selected_idx
        local prev_page=$CURRENT_PAGE
        
        case "$key" in
            UP)
                ((selected_idx--))
                [[ $selected_idx -lt 0 ]] && selected_idx=0
                [[ $selected_idx -lt $((CURRENT_PAGE * ITEMS_PER_PAGE)) ]] && CURRENT_PAGE=$((selected_idx / ITEMS_PER_PAGE))
                [[ $CURRENT_PAGE -lt 0 ]] && CURRENT_PAGE=0
                ;;
            DOWN)
                ((selected_idx++))
                [[ $selected_idx -ge $total_filtered ]] && selected_idx=$((total_filtered - 1))
                [[ $selected_idx -lt 0 ]] && selected_idx=0
                [[ $selected_idx -ge $(((CURRENT_PAGE + 1) * ITEMS_PER_PAGE)) ]] && CURRENT_PAGE=$((selected_idx / ITEMS_PER_PAGE))
                ;;
            PAGE_UP)
                CURRENT_PAGE=$((CURRENT_PAGE - 1))
                [[ $CURRENT_PAGE -lt 0 ]] && CURRENT_PAGE=0
                selected_idx=$((CURRENT_PAGE * ITEMS_PER_PAGE))
                ;;
            PAGE_DOWN)
                CURRENT_PAGE=$((CURRENT_PAGE + 1))
                [[ $CURRENT_PAGE -ge $total_pages ]] && CURRENT_PAGE=$((total_pages - 1))
                [[ $CURRENT_PAGE -lt 0 ]] && CURRENT_PAGE=0
                selected_idx=$((CURRENT_PAGE * ITEMS_PER_PAGE))
                ;;
            HOME)
                selected_idx=0
                CURRENT_PAGE=0
                ;;
            END)
                selected_idx=$((total_filtered - 1))
                [[ $selected_idx -lt 0 ]] && selected_idx=0
                CURRENT_PAGE=$((total_pages - 1))
                [[ $CURRENT_PAGE -lt 0 ]] && CURRENT_PAGE=0
                ;;
            SPACE)
                if [[ $total_filtered -gt 0 && $selected_idx -lt $total_filtered ]]; then
                    local font_name="${fonts_array[$selected_idx]}"
                    toggle_font_selection "$font_name"
                    needs_redraw=1
                fi
                ;;
            ENTER)
                download_and_install_fonts
                fetch_font_list
                selected_idx=0
                CURRENT_PAGE=0
                needs_redraw=1
                continue
                ;;
            I)
                if [[ $total_filtered -gt 0 && $selected_idx -lt $total_filtered ]]; then
                    local font_name="${fonts_array[$selected_idx]}"
                    if ! array_contains_key "$font_name" "${!INSTALLED_FONTS[@]}"; then
                        FONT_STATUS["$font_name"]="selected"
                        needs_redraw=1
                    fi
                fi
                ;;
            U)
                if [[ $total_filtered -gt 0 && $selected_idx -lt $total_filtered ]]; then
                    local font_name="${fonts_array[$selected_idx]}"
                    if array_contains_key "$font_name" "${!INSTALLED_FONTS[@]}"; then
                        FONT_STATUS["$font_name"]="none"
                        needs_redraw=1
                    fi
                fi
                ;;
            S)
                select_all_filtered
                needs_redraw=1
                ;;
            R)
                deselect_all_filtered
                needs_redraw=1
                ;;
            Q|q)
                echo -e "${FG_CYAN}Goodbye!${NORMAL}"
                break
                ;;
            "/")
                printf "%s" "${ESC}[5;1H${ESC}[K"
                printf "%b" "${FG_CYAN}Enter search query:${NORMAL} "
                read -r SEARCH_QUERY
                selected_idx=0
                CURRENT_PAGE=0
                needs_redraw=1
                continue
                ;;
            A)
                show_about
                needs_redraw=1
                continue
                ;;
            ESC)
                ;;
            *)
                continue
                ;;
        esac
        
        if [[ $prev_idx -ne $selected_idx || $prev_page -ne $CURRENT_PAGE ]]; then
            needs_redraw=1
        fi
    done
}

print_banner() {
    echo -e "${FG_MAGENTA}"
    echo "   _   _                       _____ _                      "
    echo "  | | | | ___  ___  _ __  ___  |_   _| |__   ___  ___  ___  "
    echo "  | |_| |/ _ \\/ _ \\| '_ \\/ __|   | | | '_ \\ / _ \\/ _ \\/ __| "
    echo "  |  _  |  __/ (_) | | | \\__ \\   | | | | | |  __/  __/\\__ \\ "
    echo "  |_| |_|\\___|\\___/|_| |_|___/   |_| |_| |_|\\___|\\___||___/ "
    echo -e "${NORMAL}"
    echo -e "                 ${BOLD}TUI Installer v${NERDFONTS_TUI_VERSION}${NORMAL}"
    echo ""
}

check_dependencies() {
    local missing=()
    
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi
    
    if ! command -v unzip &>/dev/null; then
        missing+=("unzip")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${FG_RED}Missing required dependencies: ${missing[*]}${NORMAL}"
        echo "Please install them and try again."
        exit 1
    fi
}

main() {
    setup_locale
    check_dependencies
    setup_terminal
    
    print_banner
    
    if ! fetch_font_list; then
        echo -e "${FG_RED}Failed to fetch font list. Please check your internet connection.${NORMAL}"
        exit 1
    fi
    
    main_loop
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
