local base = {}

local util = require "hmm.util"

--  Extracting Archives  ===============================================================================================

function base.unpack(archive, target)
	local _, ext = util.extsplit(archive)
	local f = base.archivemap[ext]
	if not f then util.error("cannot open arcive of type %s", ext) end
	f(archive, target)
end

base.archivemap = {}

base.archivemap["7z"] = function(archive, target) assert(util.exec("7z x -y -o%s %s >/dev/null", target, archive)) end
base.archivemap.rar   = function(archive, target) assert(util.exec("unrar x -y %s %s >/dev/null", archive, target)) end
base.archivemap.zip   = base.archivemap["7z"]

--  Mod Base Implementation  ===========================================================================================

base.modmt = {__index = {}}

--  Must Be Implemented  -----------------------------------------------------------------------------------------------

-- Resolve internal information after object has been created, runs before all
-- other functions.
--
-- Required fields to be filled in by this function:
--
--  - path (string): base path below `cachedir .. "/mods"` for all files
--  - id (string): unique identifier for the mod within this deployment
--  - name (string): human-readable name for the mod
--  - url (string): mod page url
function base.modmt.__index:resolve()
end

-- Get files. The result is a list of objects with the following fields:
--
--  - filename (string): sensible file name without any path components
--  - url (string | function): download url, possibly wrapped in a function,
--      which is only to be called if the download is actually carried out
--  - id (string): identifier of some kind, unique within this mod
function base.modmt.__index:getfiles()
	return {}
end

--  May Be Implemented  ------------------------------------------------------------------------------------------------

-- Returns a map of keys that are okay for the user to set. The values in this
-- table can either be `true` or a function, through which the user-supplied
-- value is passed before setting.
function base.modmt.__index:userkeys()
	return {
		redownload = true,
		reunpack = true,
		reinstall = true,
		collisions = util.toset,
	}
end

-- Get dependencies as mod objects.
function base.modmt.__index:getdeps()
	return {}
end

-- Default implementation for the download phase. Only redownloads if prompted.
function base.modmt.__index:download()
	assert(util.exec('mkdir -p %s', self:downloadpath()))
	for _, f in ipairs(self:getfiles()) do
		local path = self:downloadpath(f.filename)
		if self.redownload or not util.exec("find %s -type f >/dev/null 2>&1", path) then
			util.log("Download %s", f.filename)
			assert(util.exec("wget --quiet --output-document=%s %s", path, type(f.url) == "function" and f.url() or f.url))
		end
	end
end

-- Default implementation for the unpack phase. Only reunpacks if prompted.
function base.modmt.__index:unpack()
	for _, f in ipairs(self:getfiles()) do
		local src = self:downloadpath(f.filename)
		local dst = self:unpackpath(f.filename)
		if self.reunpack or not util.exec("find %s -type d >/dev/null 2>&1", dst) then
			util.exec('rm -r %s 2>/dev/null', dst)
			assert(util.exec('mkdir -p %s', dst))
			util.log("Unpack %s", f.filename)
			base.unpack(src, dst)
		end
	end
end

-- Default implementation for the prepare phase, does nothing.
function base.modmt.__index:prepare()
end

-- Default implementation for the install phase, copies files from all the
-- unpacked directories into the root of the install directory.
function base.modmt.__index:install()
	local dst = self:installpath()
	if self.reinstall or not util.exec("find %s -type d >/dev/null 2>&1", dst) then
		util.exec("rm -r %s 2>/dev/null", dst)
		assert(util.exec("mkdir -p %s", dst))
		for _, f in ipairs(self:getfiles()) do
			util.log("Install %s", f.filename)
			assert(util.exec("rsync --quiet --archive %s/ %s", self:unpackpath(f.filename), dst))
		end
	end
end

--  Interface Functions  -----------------------------------------------------------------------------------------------

function base.modmt:__call(data)
	local map = self:userkeys()
	for k, v in pairs(data) do
		    if type(map[k]) == "function" then self[k] = map[k](v)
		elseif      map[k]                then self[k] =        v
		else self:error("unknown property: %s = %s", tostring(k), tostring(v))
		end
	end
end

function base.modmt.__index:downloadpath(filename)
	return self.path .. "/download" .. (filename and ("/" .. filename) or "")
end

function base.modmt.__index:unpackpath(filename)
	if filename then
		return self.path .. "/unpack/" .. (util.extsplit(filename))
	else
		return self.path .. "/unpack"
	end
end

function base.modmt.__index:installpath()
	local base = "with"
	for _, f in ipairs(self:getfiles()) do base = base .. "-" .. f.id end
	return self.path .. "/install/" .. base
end

--  Utility Functions    -----------------------------------------------------------------------------------------------

function base.modmt.__index:error(...)
	util.error("\nWhile processing %q (%s)\nAn error occured: %s", self.name, self.url, fmt:format(...))
end

return base
