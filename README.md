# Dotfiles

A modular dotfiles management repository with automated package installation, symlink management, and per-configuration deployment metadata.

---

## Table of Contents

- [Overview](#overview)
- [Configuration Metadata (`.dotfile`)](#configuration-metadata-dotfile)
- [Scripts Reference](#scripts-reference)
  - [`install.sh`](#installsh)
  - [`add_config_files.sh`](#add_config_filessh)
  - [`remove_config_files.sh`](#remove_config_filessh)
- [Workflow Examples](#workflow-examples)

---

## Overview

Each configuration directory in this repository (e.g., `fish/`, `kitty/`, `zed/`) contains its config files along with a `.dotfile` metadata file that controls how the configuration is installed and deployed.

---

## Configuration Metadata (`.dotfile`)

Inside each configuration folder, a `.dotfile` file defines deployment behavior:

```yaml
path:
install:
desktop-environment:
```

| Field                   | Description                                                                                                               | Default (when empty)                                         |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `path: `                | Destination directory where the config folder should be placed during export/restoration. Supports `~` expansion.         | `~/.config/`                                                 |
| `install: `             | Custom package installation command override. Can be set to `skip` or `none` to bypass package installation.              | Uses the OS package manager specified during `./install.sh`. |
| `desktop-environment: ` | Specific desktop environment(s) for this configuration (e.g. `gnome`, `kde`, `hyprland`). Supports comma-separated lists. | Installs for all desktop environments.                       |

---

## Scripts Reference

### `install.sh`

Automates the installation of packages and moves/deploys the corresponding configuration folders to their target destinations using `remove_config_files.sh`.

#### Usage

```bash
./install.sh --desktop-environment <de> --package-manager <pm> [options]
```

#### Options

| Option                         | Shorthand | Type          | Description                                                                                                     |
| ------------------------------ | --------- | ------------- | --------------------------------------------------------------------------------------------------------------- |
| `--desktop-environment <name>` | `-d`      | **Mandatory** | Target desktop environment (e.g. `gnome`, `kde`, `hyprland`). Filters configurations based on their `.dotfile`. |
| `--package-manager <name>`     | `-p`      | **Mandatory** | Package manager to use (`nix`, `dnf`, `pacman`, `apt`, `brew`, `zypper`).                                       |
| `--yes`                        | `-y`      | Optional      | Overwrite existing files/folders at target destinations without prompting for confirmation.                     |
| `--dry-run`                    | `-n`      | Optional      | Preview the package installation and file movements without making any changes.                                 |
| `--help`                       | `-h`      | Optional      | Display usage information and examples.                                                                         |

#### Supported Package Managers & Generated Commands

- **`nix`**: `nix profile install nixpkgs#[folder]`
- **`dnf`**: `dnf install -y [folder]`
- **`pacman`**: `pacman -Sy [folder]`
- **`apt`** / **`apt-get`**: `apt-get install -y [folder]`
- **`brew`**: `brew install [folder]`
- **`zypper`**: `zypper install -y [folder]`

_(If `install: ` is defined in `.dotfile`, that custom command is run instead.)_

#### Examples

```bash
# Preview what would be installed and moved (no changes made)
./install.sh -d gnome -p nix --dry-run

# Install packages with DNF on KDE, auto-overwriting existing configs
./install.sh -d kde -p dnf -y

# Install on Hyprland using Pacman
./install.sh --desktop-environment hyprland --package-manager pacman
```

---

### `add_config_files.sh`

Imports a configuration folder or file into the dotfiles repository and replaces the original path with a symbolic link.

- If given a bare name (e.g., `kitty`), it automatically checks `~/.config/`, then `~/`.
- Accepts full paths (e.g., `~/.config/nvim`, `~/.bashrc`).
- Automatically creates or updates the `.dotfile` metadata file inside imported folders.
- Preserves directory structures and handles trailing slashes from tab-completion safely.

#### Usage

```bash
./add_config_files.sh <file-or-folder>
```

#### Examples

```bash
# Add a folder from ~/.config/
./add_config_files.sh nvim

# Add a single file from ~/.config/
./add_config_files.sh starship.toml

# Add using a full path
./add_config_files.sh ~/.config/kitty

# Add a dotfile from the home directory
./add_config_files.sh ~/.bashrc
```

---

### `remove_config_files.sh`

Performs the opposite of `add_config_files.sh`: removes the symbolic link from the target destination (if it exists) and moves the folder or file back to its correct system location.

- Destination path is determined from the folder's `.dotfile` (`path: `), defaulting to `~/.config/` (or `~/` for home dotfiles).
- If a real file or folder already exists at the destination, asks for confirmation before overwriting unless `-y` is provided.

#### Usage

```bash
./remove_config_files.sh [-y] <file-or-folder>
```

#### Options

| Option   | Shorthand | Description                                                           |
| -------- | --------- | --------------------------------------------------------------------- |
| `--yes`  | `-y`      | Overwrite existing files or folders at destination without prompting. |
| `--help` | `-h`      | Display usage information and examples.                               |

#### Examples

```bash
# Restore kitty back to ~/.config/kitty and remove its symlink
./remove_config_files.sh kitty

# Restore a home dotfile back to ~/.bashrc
./remove_config_files.sh .bashrc

# Overwrite destination directly without asking for confirmation
./remove_config_files.sh -y starship.toml
```

---

## Workflow Examples

### 1. Adding a new tool to dotfiles

```bash
# 1. Move ~/.config/helix into repo and create symlink ~/.config/helix -> ./helix
./add_config_files.sh helix

# 2. (Optional) Customize helix/.dotfile if needed
# e.g., set desktop-environment: or custom install command
```

### 2. Exporting/Removing a tool from dotfiles

```bash
# Move ./helix back to ~/.config/helix and remove symlink
./remove_config_files.sh helix
```

### 3. Deploying on a new machine

```bash
# Clone the repository
git clone <repo-url> ~/dotfiles
cd ~/dotfiles

# Deploy all configs matching your DE and install packages
./install.sh --desktop-environment gnome --package-manager dnf -y
```
