# Nexusmods module

The following settings are required:

- `nexus.apikey = "<key>"`: API key to use.
  Navigate to [your API settings](https://www.nexusmods.com/users/myaccount?tab=api), and use your personal key (at the bottom) until we get our own.

- `nexus.game "<name>"`:
  Game name, as seen in the game's URL on nexusmods, e.g. `cyberpunk2077`.
  Note that this is a call, not an assignment, do not use `=`.

## Installing mods

Mods are pulled in by declaring them in the following form:

```lua
nexus.mod "<url>"

nexus.mod "<url>" {
    -- mod properties go here
}
```

The URL should be the one to the mod's main page, i.e. have the form `https://www.nexusmods.com/<game>/mods/<id>`.

### Basic properties

- `collisions`: TODO

- `files`: List of file IDs to install.
  Automatically filled in for single-file mods.
  Hover over the file download link and look for the `?id=<x>` part near the end.

### Dependencies

Dependencies of a mod are mods that are required by that mod to work.
`hmm` makes sure dependencies are always loaded before any mod that needs them.

Dependency information is currently scraped from the mod page.
This is cumbersome, prone to breakage on minor changes, and inaccurate, but we currently don't have a better way.
Vortex uses a special modmeta-db server for this kind of information, but alas, we don't currently have access to that.

All mods listed in the "Nexus requirements" section are considered as dependencies, as we cannot get much useful information from the "Notes" field.
This is *good enough* for most mods, but some mods pull in *absolutely everything*, while others have some dependencies that are mentioned in the description, but not declared in the metadata.
The inferred dependencies can be used in the following ways:

- Take the list of dependencies as-is (default).
- Take the list of dependencies, but add (`deps`) and/or remove (`ignoredeps`) some.
- Ignore the list of dependencies (`ignoredeps = true`), and optionally add some back (`deps`).

This can be achieved using the following properties:

- `deps`: List of additional mod URLs to consider as dependencies.

- `ignoredeps`: Either `true` to ignore all dependencies of this mod (except those explicitly specified via `deps`), or a list of mod URLs to ignore.

### Phase management

- `redownload`: Set this to `true` to re-download the mod, even if it is already downloaded.

- `reunpack`: Set this to `true` to re-unpack the mod, even if it is already unpacked.

- `reinstall`: Set this to `true` to re-install the mod, even if it is already installed.
  Note that *install* does not mean "put the mod's files into the game directory", but rather "put the relevant files from the mod into a directory".

- `download`: Overwrite the download function for this mod with your own implementation.
  Receives the download URL and the target file name.

- `unpack`: Overwrite the unpack function for this mod with your own implementation.
  Receives the source file name and the target directory.

- `install`: Overwrite the install function for this mod with your own implementation.
  Receives the unpacked directory and the target directory.

## Blocking mods from being installed

Mods can be blocked from being installed on your system, either explicitly, or implicitly via dependencies:

```lua
nexus.block "<url>"
```

This statement must be placed above all `nexus.mod` declarations to have any effect.
If something tries to install the blocked mod, an error message is printed instead, and the installation is aborted.

## Free / Premium account features and `nxm:` link integration

Only premium account users can download files automatically, free users have to go through the website for each file.
`hmm` aims to make this process as seamless as possible, but some friction still remains.

When `hmm` needs to download a file with a free account, it aborts with an error and opens the download website for you.
You need to click on the big yellow "Download" button, and `hmm` will use the information provided by the link to download that file.
On the next run, `hmm` will pick up the downloaded file and continue.
This process needs to be repeated once for each file to download.

The premium status of a user is automatically determined via the API, but can be overridden by setting `nexus.premium = true/false`.
Note that the restrictions on free users are enforced by the Nexusmods API, not `hmm`, so setting `nexus.premium = true` on a free account does not lead to happiness.

## Example file

```lua
gamedir = "/home/boonami/.local/share/Steam/steamapps/common/Cyberpunk 2077"

nexus.apikey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

nexus.game "cyberpunk2077"

-- We do not want cybercmd installed because cmd is smelly windows software.
nexus.block "https://www.nexusmods.com/cyberpunk2077/mods/5176"

-- Metro System is simple enough to install.
nexus.mod "https://www.nexusmods.com/cyberpunk2077/mods/3560"

-- Cyberarms come in two variants, we need to select one of them.
nexus.mod "https://www.nexusmods.com/cyberpunk2077/mods/5295" {
	files = {32354},
}

-- All Vanilla Clothes Atelier Store, because we want to be fashionable as soon as possible ...
nexus.mod "https://www.nexusmods.com/cyberpunk2077/mods/5544" {

	-- ... but we do not want big booba, which is listed as an optional dependency.
	ignoredeps = {
		"https://www.nexusmods.com/cyberpunk2077/mods/5408",
	},

}

-- Hyst's Store has a nice dress, but also pulls in a lot of rather skimpy mods ...
nexus.mod "https://www.nexusmods.com/cyberpunk2077/mods/6015" {

	-- ... which we do not want ...
	ignoredeps = true,

	-- ... but we need to add back redscript and Virtual Atelier, or otherwise it won't work ...
	deps = {
		"https://www.nexusmods.com/cyberpunk2077/mods/1511",
		"https://www.nexusmods.com/cyberpunk2077/mods/2987",
	},

}

-- ... aand here is the dress we wanted.
nexus.mod "https://www.nexusmods.com/cyberpunk2077/mods/6238"

-- This early mod was not packaged with mod installers in mind, and has one
-- archive with many variants. We select the ones we like most using a custom
-- install function, and set `reinstall = true` so that changes in that function
-- are picked up immediately.
nexus.mod "https://www.nexusmods.com/cyberpunk2077/mods/2792" {
	files = {24273},
	reinstall = true,
	install = function(src, dst)
		local dst_ = dst .. "/archive/pc/mod"
		assert(util.exec("mkdir -p %s", dst_))
		local files = {
			"Chrome Heels/Jinguji_FleetsToChromeHeels.archive",
			"Corset Top/Jinguji_BikerJacketToCorsetBlackGold.archive",
		}
		for _, f in ipairs(files) do
			assert(util.exec("cp %s %s", src .. "/JingujiAllInOne/" .. f, dst_))
		end
	end,
}

```
