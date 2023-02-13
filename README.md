# hmm

Scripting based game mod manager for Linux.
Currently supports [nexusmods.com](https://www.nexusmods.com).
Tested with Cyberpunk 2077, but shoud work with any other game that does not require post-processing steps after extracting the mods.

WARNING: This is experimental software.
Use with caution, back up your files.
You have been warned!

## Installation

### tl;dr

1. Install requirements.
2. Put this repository into your `LUA_PATH`.
3. Symlink `hmm.lua` and `hmm-nxm.lua` into your `PATH`, but without the `.lua` suffix.
4. Copy `hmm-nxm.desktop` into `~/.local/share/applications` and bully `xdg-utils` into using it for `nxm:` links.

### 1. Install requirements

- Lua 5.4 (executable `lua5.4`)
- curl (executable `curl`)
- libxml2 (executable `xmllint`)
- p7zip (executable `7z`)
- rsync (executable `rsync`)
- unrar (executable `unrar`)
- wget (executable `wget`)
- xdg-utils (executable `xdg-open`)
- zenity (executable `zenity`)

### 2. Library placement

1. Create `~/.local/share/lua`.
2. Put the repository into that directory.
3. Append this to your `.profile` or `.bashrc`:

```bash
export LUA_PATH="$HOME/.local/share/lua/?.lua;$HOME/.local/share/lua/?/init.lua;;"
```

Alternatively, for a system-wide installation:

1. Put this repository somewhere into your `LUA_PATH`, `lua5.4 -e 'print(package.path)'` shows you the defaults.

Alternatively:

### 3. Executables

From within the repository directory:

```bash
mkdir -p "$HOME/.local/bin"
ln -s "$PWD/hmm.lua" "$HOME/.local/bin/"
ln -s "$PWD/hmm-nxm.lua" "$HOME/.local/bin/"
```

### 4. Link handlers

From within the repository directory:

```bash
mkdir -p "$HOME/.local/share/applications"
cp "hmm-nxm.desktop" "$HOME/.local/share/applications/"
xdg-settings set default-url-scheme-handler nxm hmm-nxm.desktop
xdg-mime default hmm-nxm.desktop x-scheme-handler/nxm
```

## Usage

```bash
hmm "<script file>"
```

This downloads, unpacks, installs and deploys all the mods declared in the file.
Previous deployments are automatically cleaned up beforehand.

## Script file

Script files are regular Lua files that are executed by `hmm` in a special environment.
They should have

```lua
gamedir = "<path>"
```

as their first statement, the rest is mod source specific:

- [nexusmods.com](doc/nexusmods.md)

## Removal

To remove all mods from a game, create a script file with just a `gamedir` setting, and run `hmm` on it.
To uninstall `hmm` itself, remove all the files mentioned in the installation process, and the directory `~/.local/share/hmm`.
