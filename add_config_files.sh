#!/usr/bin/env bash

set -euo pipefail

# Display help/usage information
if [ $# -ge 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; }; then
    echo "Usage: $(basename "$0") <file-or-folder>"
    echo ""
    echo "Moves a configuration folder or file into the dotfiles repository and replaces"
    echo "it with a symbolic link. It tracks the original location (~/ or ~/.config/)"
    echo "in .dotfiles_map so that remove_config_files.sh can restore it accurately."
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") nvim                    # Moves ~/.config/nvim and symlinks it"
    echo "  $(basename "$0") starship.toml           # Moves ~/.config/starship.toml and symlinks it"
    echo "  $(basename "$0") ~/.config/kitty         # Works with full paths"
    echo "  $(basename "$0") ~/.bashrc               # Works with files in ~/"
    echo "  $(basename "$0") .bashrc                 # Automatically checks ~/.config then ~/"
    exit 0
fi

if [ $# -lt 1 ] || [ -z "$1" ]; then
    echo "Usage: $(basename "$0") <file-or-folder>" >&2
    echo "Run '$(basename "$0") --help' for details and examples." >&2
    exit 1
fi

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
MAP_FILE="$DOTFILES_DIR/.dotfiles_map"

update_map() {
    local key="$1"
    local value="$2"
    local tmp_file
    tmp_file="$(mktemp)"
    if [ -f "$MAP_FILE" ]; then
        awk -v k="${key}: " 'index($0, k) != 1' "$MAP_FILE" > "$tmp_file"
    fi
    echo "${key}: ${value}" >> "$tmp_file"
    sort -u "$tmp_file" > "$MAP_FILE"
    rm -f "$tmp_file"
}

# Normalize input (strip trailing slashes)
INPUT="$1"
while [ "${INPUT: -1}" = "/" ] && [ ${#INPUT} -gt 1 ]; do
    INPUT="${INPUT%/}"
done

# Expand leading tilde '~' if passed in quotes
if [[ "$INPUT" == "~"* ]]; then
    INPUT="${HOME}${INPUT:1}"
fi

# Locate the source file or folder:
# 1. If explicit path starting with '/', './', or '../', inspect it directly
# 2. Otherwise check if it exists in ~/.config/
# 3. Otherwise check if it exists in ~/ (e.g. .bashrc, .zshrc)
# 4. Otherwise check current directory
SOURCE=""
if [[ "$INPUT" == /* ]] || [[ "$INPUT" == ./* ]] || [[ "$INPUT" == ../* ]]; then
    if [ -e "$INPUT" ] || [ -L "$INPUT" ]; then
        SOURCE="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
    fi
else
    if [ -e "$CONFIG_DIR/$INPUT" ] || [ -L "$CONFIG_DIR/$INPUT" ]; then
        SOURCE="$(cd "$(dirname "$CONFIG_DIR/$INPUT")" && pwd)/$(basename "$CONFIG_DIR/$INPUT")"
    elif [ -e "$HOME/$INPUT" ] || [ -L "$HOME/$INPUT" ]; then
        SOURCE="$(cd "$(dirname "$HOME/$INPUT")" && pwd)/$(basename "$HOME/$INPUT")"
    elif [ -e "$INPUT" ] || [ -L "$INPUT" ]; then
        SOURCE="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
    fi
fi

if [ -z "$SOURCE" ]; then
    echo "Error: Target '$1' not found." >&2
    echo "Checked '$INPUT', '$CONFIG_DIR/$INPUT', and '$HOME/$INPUT'." >&2
    exit 1
fi

# Guard: Do not allow adding a path that is already inside the dotfiles repo
if [[ "$SOURCE" == "$DOTFILES_DIR" || "$SOURCE" == "$DOTFILES_DIR/"* ]]; then
    echo "Error: Target '$SOURCE' is already inside the dotfiles repository." >&2
    exit 1
fi

# Determine the destination path inside dotfiles repo:
# - If the source is under ~/.config, preserve its relative path structure
# - Otherwise, place it in dotfiles under its basename
if [[ "$SOURCE" == "$CONFIG_DIR/"* ]]; then
    REL_PATH="${SOURCE#$CONFIG_DIR/}"
    DEST="$DOTFILES_DIR/$REL_PATH"
else
    REL_PATH="$(basename "$SOURCE")"
    DEST="$DOTFILES_DIR/$REL_PATH"
fi

# Determine portable representation of source (using ~ for paths under $HOME)
if [[ "$SOURCE" == "$HOME/"* ]]; then
    PORTABLE_SOURCE="~/${SOURCE#$HOME/}"
else
    PORTABLE_SOURCE="$SOURCE"
fi

# Guard: If source is already a symlink, check where it points
if [ -L "$SOURCE" ]; then
    CURRENT_TARGET="$(readlink "$SOURCE" || true)"
    RESOLVED_TARGET="$(readlink -f "$SOURCE" || true)"
    if [ "$CURRENT_TARGET" = "$DEST" ] || [ "$RESOLVED_TARGET" = "$DEST" ]; then
        update_map "$REL_PATH" "$PORTABLE_SOURCE"
        echo "'$SOURCE' is already symlinked to '$DEST' (mapping saved in .dotfiles_map)."
        exit 0
    else
        echo "Error: '$SOURCE' is already a symlink pointing to '$CURRENT_TARGET'." >&2
        echo "Please remove or update the existing symlink manually." >&2
        exit 1
    fi
fi

# Guard: Avoid overwriting an existing file/folder in dotfiles repo
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
    echo "Error: Destination '$DEST' already exists in the dotfiles repository." >&2
    exit 1
fi

# Create parent directory in dotfiles if needed
mkdir -p "$(dirname "$DEST")"

TYPE="file"
if [ -d "$SOURCE" ]; then
    TYPE="folder"
fi

echo "Moving $TYPE: $SOURCE -> $DEST"
mv "$SOURCE" "$DEST"

echo "Creating symlink: $SOURCE -> $DEST"
if ! ln -s "$DEST" "$SOURCE"; then
    echo "Error: Failed to create symlink. Rolling back move..." >&2
    mv "$DEST" "$SOURCE"
    exit 1
fi

# Remember origin location in .dotfiles_map
update_map "$REL_PATH" "$PORTABLE_SOURCE"

echo "Successfully added and symlinked $(basename "$DEST") (origin: $PORTABLE_SOURCE)."
