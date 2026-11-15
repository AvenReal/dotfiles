#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
MAP_FILE="$DOTFILES_DIR/.dotfiles_map"

get_dotfile_property() {
    local dotfile="$1"
    local prop_name="$2"
    if [ ! -f "$dotfile" ]; then
        return 0
    fi
    awk -F ':' -v prop="$prop_name" '
        BEGIN { IGNORECASE=1 }
        $1 ~ "^[[:space:]]*" prop "[[:space:]]*$" {
            sub(/^[^:]*:[[:space:]]*/, "");
            sub(/[[:space:]]+$/, "");
            print;
            exit;
        }
    ' "$dotfile"
}

strip_surrounding_quotes() {
    local val="$1"
    if [[ "$val" == \"*\" ]] && [ ${#val} -ge 2 ]; then
        val="${val:1:${#val}-2}"
    elif [[ "$val" == \'*\' ]] && [ ${#val} -ge 2 ]; then
        val="${val:1:${#val}-2}"
    fi
    echo "$val"
}

get_restore_destination() {
    local folder_name="$1"
    local raw_path="$2"

    raw_path="$(echo "$raw_path" | xargs)"
    raw_path="$(strip_surrounding_quotes "$raw_path")"

    if [ -z "$raw_path" ]; then
        raw_path="~/.config/"
    fi

    local expanded_path
    if [[ "$raw_path" == "~"* ]]; then
        expanded_path="${HOME}${raw_path:1}"
    else
        expanded_path="$raw_path"
    fi

    if [ "$expanded_path" = "$HOME" ]; then
        echo "$HOME/$folder_name"
        return
    fi

    if [[ "$expanded_path" == */ ]]; then
        expanded_path="${expanded_path%/}"
        echo "$expanded_path/$folder_name"
    elif [ -d "$expanded_path" ] && [ "$(basename "$expanded_path")" != "$folder_name" ]; then
        echo "$expanded_path/$folder_name"
    elif [ "$(basename "$expanded_path")" = "$folder_name" ]; then
        echo "$expanded_path"
    else
        echo "$expanded_path/$folder_name"
    fi
}

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
            echo "it back to its target location (specified by .dotfile or ~/.config/), removing any existing symlink."
            echo ""
            echo "Options:"
            echo "  -y, --yes    Overwrite existing target file/folder without confirmation prompt."
            echo "  -h, --help   Show this help message."
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") kitty                   # Moves kitty back to ~/.config/kitty"
            echo "  $(basename "$0") .bashrc                 # Moves .bashrc back to ~/"
            echo "  $(basename "$0") -y starship.toml        # Overwrites without prompt if target exists"
            exit 0
            ;;
        -y|--yes)
            ASSUME_YES=true
            ;;
        -*)
            echo "Error: Unknown option '$arg'." >&2
            echo "Run '$(basename "$0") --help' for details and examples." >&2
            exit 1
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

# 1. Check if INPUT is directly a folder/file in dotfiles repo
if [ -e "$DOTFILES_DIR/$INPUT" ] || [ -L "$DOTFILES_DIR/$INPUT" ]; then
    KEY="$INPUT"
# 2. Check if INPUT is an absolute or relative path pointing inside dotfiles repo
elif [[ "$INPUT" == "$DOTFILES_DIR/"* ]]; then
    KEY="${INPUT#$DOTFILES_DIR/}"
# 3. Check if INPUT is a symlink pointing into dotfiles repo
elif [ -L "$INPUT" ]; then
    RESOLVED_LINK="$(readlink -f "$INPUT" || true)"
    if [[ "$RESOLVED_LINK" == "$DOTFILES_DIR/"* ]]; then
        KEY="${RESOLVED_LINK#$DOTFILES_DIR/}"
        RESTORE_TARGET="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
    fi
fi

# 4. If not found yet, check all config folders in dotfiles repo with a .dotfile
if [ -z "$KEY" ]; then
    for candidate_dir in "$DOTFILES_DIR"/*/; do
        [ -d "$candidate_dir" ] || continue
        candidate_name="$(basename "$candidate_dir")"
        case "$candidate_name" in
            .git|__packages__|tests|test_*) continue ;;
        esac
        candidate_dotfile=""
        [ -f "$candidate_dir/.dotfile" ] && candidate_dotfile="$candidate_dir/.dotfile"
        [ -z "$candidate_dotfile" ] && [ -f "$candidate_dir/.dotfiles" ] && candidate_dotfile="$candidate_dir/.dotfiles"
        if [ -n "$candidate_dotfile" ]; then
            candidate_path="$(get_dotfile_property "$candidate_dotfile" "path")"
            candidate_dest="$(get_restore_destination "$candidate_name" "$candidate_path")"
            if [ "$candidate_dest" = "$INPUT" ] || [ "$candidate_dest" = "${INPUT/#\~/$HOME}" ]; then
                KEY="$candidate_name"
                RESTORE_TARGET="$candidate_dest"
                break
            fi
        fi
    done
fi

# 5. Fallback to .dotfiles_map if KEY still not resolved
if [ -z "$KEY" ]; then
    MAP_VAL="$(lookup_map_by_key "$INPUT")"
    if [ -n "$MAP_VAL" ]; then
        KEY="$INPUT"
        RESTORE_TARGET="${MAP_VAL/#\~/$HOME}"
    fi
fi

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
    dotfile=""
    [ -f "$REPO_ITEM/.dotfile" ] && dotfile="$REPO_ITEM/.dotfile"
    [ -z "$dotfile" ] && [ -f "$REPO_ITEM/.dotfiles" ] && dotfile="$REPO_ITEM/.dotfiles"
    if [ -n "$dotfile" ]; then
        raw_path="$(get_dotfile_property "$dotfile" "path")"
        RESTORE_TARGET="$(get_restore_destination "$KEY" "$raw_path")"
    fi
fi

# Fallback resolution for RESTORE_TARGET if still empty:
if [ -z "$RESTORE_TARGET" ]; then
    MAP_VAL="$(lookup_map_by_key "$KEY")"
    if [ -n "$MAP_VAL" ]; then
        RESTORE_TARGET="${MAP_VAL/#\~/$HOME}"
    elif [ -L "$CONFIG_DIR/$KEY" ] && [ "$(readlink -f "$CONFIG_DIR/$KEY" || true)" = "$REPO_ITEM" ]; then
        RESTORE_TARGET="$CONFIG_DIR/$KEY"
    elif [ -L "$HOME/$KEY" ] && [ "$(readlink -f "$HOME/$KEY" || true)" = "$REPO_ITEM" ]; then
        RESTORE_TARGET="$HOME/$KEY"
    elif [[ "$KEY" == .* ]]; then
        RESTORE_TARGET="$HOME/$KEY"
    else
        RESTORE_TARGET="$CONFIG_DIR/$KEY"
    fi
fi

# Guard: check if source and destination are identical
if [ "$REPO_ITEM" = "$RESTORE_TARGET" ] || { [ -e "$REPO_ITEM" ] && [ -e "$RESTORE_TARGET" ] && [ "$(readlink -f "$REPO_ITEM" 2>/dev/null)" = "$(readlink -f "$RESTORE_TARGET" 2>/dev/null)" ] && [ ! -L "$RESTORE_TARGET" ]; }; then
    echo "Item '$KEY' is already at restore destination '$RESTORE_TARGET'."
    exit 0
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

# Step 4: Clean up .dotfiles_map if present
remove_from_map "$KEY"

# Clean up empty parent directories in dotfiles repo if nested
if [[ "$KEY" == *"/"* ]]; then
    rmdir -p "$(dirname "$REPO_ITEM")" 2>/dev/null || true
fi

echo "Done! Successfully restored $(basename "$RESTORE_TARGET") to $RESTORE_TARGET."
