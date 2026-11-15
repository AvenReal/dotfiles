#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

show_help() {
    echo "Usage: $(basename "$0") --desktop-environment <de> --package-manager <pm> [options]"
    echo ""
    echo "Installs required packages and deploys/moves configuration folders to their"
    echo "target locations using remove_config_files.sh based on per-folder .dotfile specifications."
    echo ""
    echo "Mandatory options:"
    echo "  -d, --desktop-environment <name>   Desktop environment (e.g. gnome, kde, hyprland, etc.)"
    echo "  -p, --package-manager <name>       Package manager (nix, dnf, pacman, apt, brew, zypper)"
    echo ""
    echo "Other options:"
    echo "  -y, --yes                          Automatically overwrite existing files/folders without prompting."
    echo "  -n, --dry-run                      Preview actions without installing packages or moving files."
    echo "  -h, --help                         Show this help message."
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") --desktop-environment gnome --package-manager dnf"
    echo "  $(basename "$0") -d kde -p nix -y"
    echo "  $(basename "$0") --desktop-environment hyprland --package-manager pacman --dry-run"
}

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

matches_de() {
    local target_de="$1"
    local dotfile_de="$2"

    # Default (empty) matches all desktop environments
    if [ -z "$dotfile_de" ]; then
        return 0
    fi

    local lower_target
    lower_target="$(echo "$target_de" | tr '[:upper:]' '[:lower:]' | xargs)"
    local lower_dotfile
    lower_dotfile="$(echo "$dotfile_de" | tr '[:upper:]' '[:lower:]')"

    for item in ${lower_dotfile//,/ }; do
        item="$(echo "$item" | xargs)"
        if [ "$item" = "$lower_target" ] || [ "$item" = "all" ]; then
            return 0
        fi
    done
    return 1
}

DESKTOP_ENVIRONMENT=""
PACKAGE_MANAGER=""
ASSUME_YES=false
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --desktop-environment)
            if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: --desktop-environment requires a non-empty argument." >&2
                exit 1
            fi
            DESKTOP_ENVIRONMENT="$2"
            shift 2
            ;;
        --desktop-environment=*)
            DESKTOP_ENVIRONMENT="${1#*=}"
            shift
            ;;
        -d)
            if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: -d requires a non-empty argument." >&2
                exit 1
            fi
            DESKTOP_ENVIRONMENT="$2"
            shift 2
            ;;
        --package-manager)
            if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: --package-manager requires a non-empty argument." >&2
                exit 1
            fi
            PACKAGE_MANAGER="$2"
            shift 2
            ;;
        --package-manager=*)
            PACKAGE_MANAGER="${1#*=}"
            shift
            ;;
        -p)
            if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
                echo "Error: -p requires a non-empty argument." >&2
                exit 1
            fi
            PACKAGE_MANAGER="$2"
            shift 2
            ;;
        -y|--yes)
            ASSUME_YES=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Error: Unknown option '$1'." >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
done

DESKTOP_ENVIRONMENT="$(echo "$DESKTOP_ENVIRONMENT" | xargs)"
PACKAGE_MANAGER="$(echo "$PACKAGE_MANAGER" | xargs)"

if [ -z "$DESKTOP_ENVIRONMENT" ]; then
    echo "Error: --desktop-environment is mandatory." >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
fi

if [ -z "$PACKAGE_MANAGER" ]; then
    echo "Error: --package-manager is mandatory." >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
fi

PACKAGE_MANAGER="$(echo "$PACKAGE_MANAGER" | tr '[:upper:]' '[:lower:]')"

case "$PACKAGE_MANAGER" in
    nix|dnf|pacman|apt|apt-get|brew|zypper)
        ;;
    *)
        echo "Error: Unsupported package manager '$PACKAGE_MANAGER'." >&2
        echo "Supported package managers: nix, dnf, pacman, apt, brew, zypper." >&2
        exit 1
        ;;
esac

# Find all configuration folders containing a .dotfile or .dotfiles
config_folders=()
shopt -s dotglob nullglob
for item in "$DOTFILES_DIR"/*; do
    [ -d "$item" ] || continue
    folder_name="$(basename "$item")"
    case "$folder_name" in
        .|..|.git|__packages__|tests|test_*)
            continue
            ;;
    esac
    if [ -f "$item/.dotfile" ] || [ -f "$item/.dotfiles" ]; then
        config_folders+=("$folder_name")
    fi
done
shopt -u dotglob nullglob

if [ ${#config_folders[@]} -eq 0 ]; then
    echo "No configuration folders with a .dotfile found in $DOTFILES_DIR."
    exit 0
fi

echo "Starting dotfiles installation..."
echo "Desktop Environment: $DESKTOP_ENVIRONMENT"
echo "Package Manager:     $PACKAGE_MANAGER"
echo "Discovered configs:  ${config_folders[*]}"
echo "--------------------------------------------------"

for folder in "${config_folders[@]}"; do
    folder_dir="$DOTFILES_DIR/$folder"
    dotfile="$folder_dir/.dotfile"
    [ ! -f "$dotfile" ] && dotfile="$folder_dir/.dotfiles"

    dotfile_de="$(get_dotfile_property "$dotfile" "desktop-environment")"
    dotfile_de="$(strip_surrounding_quotes "$dotfile_de")"

    dotfile_install="$(get_dotfile_property "$dotfile" "install")"
    dotfile_install="$(strip_surrounding_quotes "$dotfile_install")"

    # Filter by Desktop Environment
    if ! matches_de "$DESKTOP_ENVIRONMENT" "$dotfile_de"; then
        echo "==> Skipping '$folder': Configured for DE '$dotfile_de', not '$DESKTOP_ENVIRONMENT'."
        continue
    fi

    echo "==> Processing configuration folder '$folder'..."

    # Determine installation command
    install_cmd="$dotfile_install"
    if [ -z "$install_cmd" ]; then
        case "$PACKAGE_MANAGER" in
            nix)
                install_cmd="nix profile install nixpkgs#$folder"
                ;;
            dnf)
                install_cmd="dnf install -y $folder"
                ;;
            pacman)
                install_cmd="pacman -Sy $folder"
                ;;
            apt|apt-get)
                install_cmd="apt-get install -y $folder"
                ;;
            brew)
                install_cmd="brew install $folder"
                ;;
            zypper)
                install_cmd="zypper install -y $folder"
                ;;
        esac
    fi

    if [ "$install_cmd" = "none" ] || [ "$install_cmd" = "skip" ]; then
        echo "Skipping package installation for '$folder' (configured as '$install_cmd')."
    else
        echo "Installing package for '$folder': $install_cmd"
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] Command: $install_cmd"
        else
            eval "$install_cmd"
        fi
    fi

    # Move config folder using remove_config_files.sh
    echo "Moving config folder '$folder' via remove_config_files.sh..."
    remove_args=()
    if [ "$ASSUME_YES" = true ]; then
        remove_args+=("-y")
    fi
    remove_args+=("$folder")

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Executing: $DOTFILES_DIR/remove_config_files.sh ${remove_args[*]}"
    else
        bash "$DOTFILES_DIR/remove_config_files.sh" "${remove_args[@]}"
    fi

    echo "Completed processing '$folder'."
    echo ""
done

echo "All eligible configurations installed and deployed successfully."
