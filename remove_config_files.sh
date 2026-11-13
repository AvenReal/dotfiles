#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
MAP_FILE="$DOTFILES_DIR/.dotfiles_map"

lookup_map_by_key() {
    local key="$1"
    if [ -f "$MAP_FILE" ]; then
        awk -v k="${key}: " 'index($0, k) == 1 { print substr($0, length(k) + 1) }' "$MAP_FILE"
    fi
}

lookup_map_by_value() {
    local val="$1"
    if [ -f "$MAP_FILE" ]; then
        awk -v v=": ${val}" '$0 ~ (v "$") { print substr($0, 1, length($0) - length(v)) }' "$MAP_FILE"
    fi
}

remove_from_map() {
    local key="$1"
    if [ -f "$MAP_FILE" ]; then
        local tmp_file
        tmp_file="$(mktemp)"
        awk -v k="${key}: " 'index($0, k) != 1' "$MAP_FILE" > "$tmp_file"
        if [ -s "$tmp_file" ]; then
            mv "$tmp_file" "$MAP_FILE"
        else
            rm -f "$tmp_file" "$MAP_FILE"
        fi
    fi
}

# Parse options and arguments
ASSUME_YES=false
TARGET_ARG=""

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "Usage: $(basename "$0") [-y] <file-or-folder>"
            echo ""
            echo "Removes a configuration file or folder from the dotfiles repository and moves"
            echo "it back to its original location (~/ or ~/.config/), removing any existing symlink."
            echo ""
            echo "Options:"
            echo "  -y, --yes    Overwrite existing target file/folder without confirmation prompt."
            echo "  -h, --help   Show this help message."
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") kitty                   # Moves kitty back to ~/.config/kitty"
            echo "  $(basename "$0") .bashrc                 # Moves .bashrc back to ~/.bashrc"
            echo "  $(basename "$0") -y starship.toml        # Overwrites without prompt if target exists"
            exit 0
            ;;
        -y|--yes)
            ASSUME_YES=true
            ;;
        *)
            if [ -z "$TARGET_ARG" ]; then
                TARGET_ARG="$arg"
            else
                echo "Error: Unexpected multiple targets provided ('$TARGET_ARG' and '$arg')." >&2
                exit 1
            fi
            ;;
    esac
done

if [ -z "$TARGET_ARG" ]; then
    echo "Usage: $(basename "$0") [-y] <file-or-folder>" >&2
    echo "Run '$(basename "$0") --help' for details and examples." >&2
    exit 1
fi

# Normalize input (strip trailing slashes)
INPUT="$TARGET_ARG"
while [ "${INPUT: -1}" = "/" ] && [ ${#INPUT} -gt 1 ]; do
    INPUT="${INPUT%/}"
done

# Expand leading tilde '~' if passed in quotes
if [[ "$INPUT" == "~"* ]]; then
    INPUT="${HOME}${INPUT:1}"
fi

# Resolve KEY (repo-relative path) and RESTORE_TARGET
KEY=""
RESTORE_TARGET=""

# 1. Check if INPUT is directly a key in .dotfiles_map
MAP_VAL="$(lookup_map_by_key "$INPUT")"
if [ -n "$MAP_VAL" ]; then
    KEY="$INPUT"
    RESTORE_TARGET="${MAP_VAL/#\~/$HOME}"
fi

# 2. Check if INPUT matches a portable or absolute value in .dotfiles_map
if [ -z "$KEY" ]; then
    PORTABLE_INPUT="$INPUT"
    if [[ "$INPUT" == "$HOME/"* ]]; then
        PORTABLE_INPUT="~/${INPUT#$HOME/}"
    fi
    MAP_KEY="$(lookup_map_by_value "$PORTABLE_INPUT")"
    if [ -n "$MAP_KEY" ]; then
        KEY="$MAP_KEY"
        RESTORE_TARGET="${PORTABLE_INPUT/#\~/$HOME}"
    fi
fi

# 3. If not found in map, attempt smart discovery:
if [ -z "$KEY" ]; then
    # If path is given inside dotfiles repo
    if [[ "$INPUT" == "$DOTFILES_DIR/"* ]]; then
        KEY="${INPUT#$DOTFILES_DIR/}"
    # If path exists in dotfiles repo
    elif [ -e "$DOTFILES_DIR/$INPUT" ] || [ -L "$DOTFILES_DIR/$INPUT" ]; then
        KEY="$INPUT"
    # If path given is a symlink pointing into dotfiles repo
    elif [ -L "$INPUT" ]; then
        RESOLVED_LINK="$(readlink -f "$INPUT" || true)"
        if [[ "$RESOLVED_LINK" == "$DOTFILES_DIR/"* ]]; then
            KEY="${RESOLVED_LINK#$DOTFILES_DIR/}"
            RESTORE_TARGET="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
        fi
    fi
fi

if [ -z "$KEY" ]; then
    echo "Error: Target '$TARGET_ARG' not found in dotfiles repository or mapping." >&2
    exit 1
fi

REPO_ITEM="$DOTFILES_DIR/$KEY"

if [ ! -e "$REPO_ITEM" ] && [ ! -L "$REPO_ITEM" ]; then
    echo "Error: Item '$REPO_ITEM' does not exist in the dotfiles repository." >&2
    exit 1
fi

# If RESTORE_TARGET has not been determined yet:
if [ -z "$RESTORE_TARGET" ]; then
    # Check if a symlink exists at ~/.config/$KEY pointing to REPO_ITEM
    if [ -L "$CONFIG_DIR/$KEY" ] && [ "$(readlink -f "$CONFIG_DIR/$KEY" || true)" = "$REPO_ITEM" ]; then
        RESTORE_TARGET="$CONFIG_DIR/$KEY"
    # Check if a symlink exists at ~/$KEY pointing to REPO_ITEM
    elif [ -L "$HOME/$KEY" ] && [ "$(readlink -f "$HOME/$KEY" || true)" = "$REPO_ITEM" ]; then
        RESTORE_TARGET="$HOME/$KEY"
    # Fallback convention: if starts with a dot, usually home directory; else ~/.config/
    elif [[ "$KEY" == .* ]]; then
        RESTORE_TARGET="$HOME/$KEY"
    else
        RESTORE_TARGET="$CONFIG_DIR/$KEY"
    fi
fi

echo "Source (in dotfiles): $REPO_ITEM"
echo "Restore destination:   $RESTORE_TARGET"

# Step 1: Remove existing symlink if present at restore destination
if [ -L "$RESTORE_TARGET" ]; then
    echo "Removing symlink: $RESTORE_TARGET"
    rm "$RESTORE_TARGET"
fi

# Step 2: If a real folder or file already exists at restore destination, prompt or check -y
if [ -e "$RESTORE_TARGET" ]; then
    echo "Warning: Target '$RESTORE_TARGET' already exists."
    if [ "$ASSUME_YES" = true ]; then
        echo "Overwriting (-y specified)..."
        rm -rf "$RESTORE_TARGET"
    else
        read -r -p "Do you want to overwrite '$RESTORE_TARGET'? [y/N]: " confirm
        case "$confirm" in
            [yY][eE][sS]|[yY])
                echo "Overwriting '$RESTORE_TARGET'..."
                rm -rf "$RESTORE_TARGET"
                ;;
            *)
                echo "Aborted by user. No files were modified." >&2
                exit 1
                ;;
        esac
    fi
fi

# Step 3: Ensure parent directory exists and move item back
mkdir -p "$(dirname "$RESTORE_TARGET")"

TYPE="file"
if [ -d "$REPO_ITEM" ]; then
    TYPE="folder"
fi

echo "Moving $TYPE: $REPO_ITEM -> $RESTORE_TARGET"
mv "$REPO_ITEM" "$RESTORE_TARGET"

# Step 4: Clean up .dotfiles_map
remove_from_map "$KEY"

# Clean up empty parent directories in dotfiles repo if nested
if [[ "$KEY" == *"/"* ]]; then
    rmdir -p "$(dirname "$REPO_ITEM")" 2>/dev/null || true
fi

echo "Done! Successfully restored $(basename "$RESTORE_TARGET") to $RESTORE_TARGET."
