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

if util.exec("unar -version >/dev/null 2>&1") then
	local f = function(archive, target)
		assert(util.exec("unar -quiet -force-overwrite -no-directory %s -output-directory %s", archive, target))
	end

	if not base.archivemap["7z"] then
		util.log("Extracting .7z archives using unar")
		base.archivemap["7z"] = f
	end

	if not base.archivemap["rar"] and util.exec("7z i | grep -Fq Rar.so") then
		util.log("Extracting .rar archives using unar")
		base.archivemap["rar"] = f
	end

	if not base.archivemap["zip"] then
		util.log("Extracting .zip archives using unar")
		base.archivemap["zip"] = f
	end
end

if util.exec("7z i >/dev/null 2>&1") then
	local f = function(archive, target)
		assert(util.exec("7z x -y -o%s %s >/dev/null", target, archive))
	end

	if not base.archivemap["7z"] then
		util.log("Extracting .7z archives using p7zip")
		base.archivemap["7z"] = f
	end

	if not base.archivemap["rar"] and util.exec("7z i | grep -Fq Rar.so") then
		util.log("Extracting .rar archives using p7zip")
		base.archivemap["rar"] = f
	end

	if not base.archivemap["zip"] then
		util.log("Extracting .zip archives using p7zip")
		base.archivemap["zip"] = f
	end
end

if not base.archivemap["rar"] and util.exec("unrar >/dev/null 2>&1") then
	util.log("Extracting .rar archives using unrar")
	base.archivemap["rar"] = function(archive, target)
		assert(util.exec("unrar x -y %s %s >/dev/null", archive, target))
	end
end

if not base.archivemap["zip"] and util.exec("unzip -v >/dev/null 2>&1") then
	util.log("Extracting .zip archives using unzip")
	base.archivemap["zip"] = function(archive, target)
		assert(util.exec("unzip %s -d %s", archive, target))
	end
end

if not base.archivemap["7z" ] then util.warn "found no program to unpack .7z archives, supported are: 7z (from p7zip)" end
if not base.archivemap["rar"] then util.warn "found no program to unpack .rar archives, supported are: 7z (from p7zip), unrar" end
if not base.archivemap["zip"] then util.warn "found no program to unpack .zip archives, supported are: 7z (from p7zip), unzip" end

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
		download = true,
		unpack = true,
		install = true,
	}
end

-- Get dependencies as mod objects.
function base.modmt.__index:getdeps()
	return {}
end

function base.modmt.__index.download(url, path)
	assert(util.exec("wget --quiet --output-document=%s %s", path, url))
end

function base.modmt.__index.unpack(src, dst)
	base.unpack(src, dst)
end

function base.modmt.__index.install(src, dst)
	assert(util.exec("rsync --quiet --archive %s/ %s", src, dst))
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

function base.modmt.__index:installname()
	local ret = "with"
	for _, f in ipairs(self:getfiles()) do ret = ret .. "-" .. f.id end
	return ret
end

function base.modmt.__index:installpath()
	return self.path .. "/install/" .. self:installname()
end

function base.modmt.__index:cached(prev, marker, override, fn)
	local run = override

	if not run and not util.exec('test -n "$(find %s/completed/%s -type f 2>/dev/null)"', self.path, marker) then
		run = true
	end

	for _, v in ipairs(prev) do
		if not run and not util.exec("test %s/completed/%s -ot %s/completed/%s >/dev/null 2>&1", self.path, v, self.path, marker) then
			run = true
			break
		end
	end

	if run then
		fn()
		util.exec("mkdir -p %s/completed", self.path)
		util.exec("touch %s/completed/%s", self.path, marker)
	end
end

function base.modmt.__index:do_download()
	assert(util.exec('mkdir -p %s', self:downloadpath()))
	for _, f in ipairs(self:getfiles()) do
		self:cached({}, f.id .. ".downloaded", self.redownload, function()
			util.action("Download", f.filename)
			self.download(type(f.url) == "function" and f.url() or f.url, self:downloadpath(f.filename))
		end)
	end
end

function base.modmt.__index:do_unpack()
	for _, f in ipairs(self:getfiles()) do
		self:cached({f.id .. ".downloaded"}, f.id .. ".unpacked", self.reunpack, function()
			local src = self:downloadpath(f.filename)
			local dst = self:unpackpath(f.filename)
			util.exec('rm -r %s 2>/dev/null', dst)
			assert(util.exec('mkdir -p %s', dst))
			util.action("Unpack", f.filename)
			self.unpack(src, dst)
		end)
	end
end

function base.modmt.__index:do_install()
	local triggers = {}
	for _, f in ipairs(self:getfiles()) do
		table.insert(triggers, f.id .. ".unpacked")
	end

	self:cached(triggers, self:installname() .. ".installed", self.reinstall, function()
		local dst = self:installpath()
		util.exec("rm -r %s 2>/dev/null", dst)
		assert(util.exec("mkdir -p %s", dst))
		for _, f in ipairs(self:getfiles()) do
			util.action("Install", f.filename)
			self.install(self:unpackpath(f.filename), dst)
		end
	end)
end

--  Utility Functions    -----------------------------------------------------------------------------------------------

function base.modmt.__index:error(...)
	util.error("\nWhile processing %q (%s)\nAn error occured: %s", self.name, self.url, fmt:format(...))
end

return base
