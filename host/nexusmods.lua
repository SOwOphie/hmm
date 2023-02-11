local nexus = {}

local json = require "hmm.json"
local util = require "hmm.util"

local domain = "nexusmods.com"
local apidomain = "api." .. domain
local webdomain = "www." .. domain



nexus.apikey = false

local game = false

local function apicmd(flags, fmt, ...)
	if not nexus.apikey then util.error("nexus.apikey required") end
	local url = ("https://%s/" .. fmt):format(apidomain, ...)
	return ("curl --silent --request GET --header 'accept: application/json' --header 'apikey: %s' %s '%s'"):format(nexus.apikey, flags, url)
end

local function api_tofile(fname, fmt, ...)
	local cmd = apicmd("--output " .. util.shellesc(fname) .. " --create-dirs", fmt, ...)
	assert(os.execute(cmd))
end

local function api(fmt, ...)
	local cmd = apicmd("", fmt, ...)
	local h = io.popen(cmd, "r")
	local r = h:read("a")
	h:close()
	return json.decode(r)
end

local function cached_api(path, validity, fmt, ...)
	if not util.exec("find %s -type f -mmin -%s >/dev/null 2>&1", path, validity) then
		api_tofile(path, fmt, ...)
	end
	return json.decode(assert(io.open(path, "r")):read("a"))
end



local modcache = {}

local mt = {__index = {}}

function mt.__index:error(fmt, ...)
	util.error("\nWhile processing %q (%s)\nAn error occured: %s", self.name, self.url, fmt:format(...))
end

local propmap = {
	collisions = true,
	deps = true,
	files = true,
	ignoredeps = true,
	redownload = true,
	reunpack = true,
}

function mt:__call(info)
	for k, v in pairs(info) do
		if not propmap[k] then self:error("unknown property: %s = %s", tostring(k), tostring(v)) end
		self[k] = v
	end
	return self
end

function mt.__index:getfiles()
	if not self.files then
		local primary = false
		for _, v in ipairs(self._files.files) do
			if v.category_id == 1 then
				if primary then
					util.errmsg("%q (%s):\nmod consists of multiple files, please specify their IDs manually", self.name, self.url)
					util.log("\nfound files:")
					for _, f in ipairs(self._files.files) do
						if f.category_id ~= 4 and f.category_id ~= 7 then
							util.log("%s %d: %s", f.category_name, f.file_id, f.name)
						end
					end
					util.log("\nMore info on %s?tab=files\n", self.url)
					os.exit(1)
				end
				primary = v.file_id
			end
		end
		if not primary then self:error("no primary file found, please specify file IDs manually") end

		self.files = {primary}
	end

	return self.files
end

function mt.__index:downloads()
	local ret = {}
	for _, fileid in ipairs(self:getfiles()) do
		local ext = false
		for _, v in ipairs(self._files.files) do
			if v.file_id == fileid then
				ext = v.file_name:match("%.(%w+)$")
				break
			end
		end
		if not ext then self:error("could not find file %s", fileid) end

		assert(util.exec("mkdir -p %s/download", self.cachepath))

		local path = ("%s/download/%d.%s"):format(self.cachepath, fileid, ext)

		if self.redownload or not util.exec("find %s -type f >/dev/null 2>&1", path) then
			util.log("Download %s/%d/%d.%s", self.game, self.id, fileid, ext)
			local url = api("v1/games/%s/mods/%d/files/%d/download_link.json", self.game, self.id, fileid)[1].URI
			assert(util.exec("wget --quiet --output-document=%s %s", path, url))
		end

		table.insert(ret, path)
	end
	return ret
end

function mt.__index:datadir()
	local path = ("%s/data"):format(self.cachepath)
	for _, v in ipairs(self:getfiles()) do path = ("%s-%d"):format(path, v) end

	if self.reunpack or not util.exec("find %s -type f >/dev/null 2>&1", path) then
		util.exec("rm -r %s 2>/dev/null", path)
		assert(util.exec("mkdir -p %s", path))

		for _, v in ipairs(self:downloads()) do
			util.log("Extract %s/%d/%s", self.game, self.id, (v:match("%d+%.%w+$")))
			assert(util.exec("7z x -y -o%s %s >/dev/null", path, v))
		end
	end

	return path
end

local function nexusmod(url)
	if not modcache[url] then
		local self = {}
		self.game, self.id = url:match("^https://www.nexusmods.com/([^/]*)/mods/([0-9]*)")
		if not self.game then util.error("could not parse URL: %s", url) end
		if not game then util.error("no game specified before defining mods") end

		self.cachepath = ("%s/api/nexus/%s/%d"):format(cachedir, self.game, self.id)
		assert(util.exec("mkdir -p %s", self.cachepath))

		setmetatable(self, mt)
		if self.game ~= game.name then self:error("game set to %s, but this mod is for %s", game.name, self.game) end

		self._info  = cached_api(self.cachepath .. "/info.json" , 23 * 60, "v1/games/%s/mods/%d.json", self.game, self.id)
		self._files = cached_api(self.cachepath .. "/files.json", 23 * 60, "v1/games/%s/mods/%d/files.json", self.game, self.id)

		self.name = self._info.name
		self.url  = ("https://%s/%s/mods/%d"):format(webdomain, self.game, self.id)

		assert(util.exec("mkdir -p %s/_name", self.cachepath))
		assert(util.exec("touch %s/_name/%s", self.cachepath, self.name))

		modcache[url] = self
	end

	return modcache[url]
end

function nexus.mod(url)
	local self = nexusmod(url)
	table.insert(nexus._mods, self)
	return self
end

function mt.__index:getdeps()
	local path = self.cachepath .. "/scraped.html"
	local url = ("https://%s/Core/Libs/Common/Widgets/ModDescriptionTab?id=%d&game_id=%d"):format(webdomain, self.id, game.id)

	if not util.exec("find %s -type f -mmin -%s >/dev/null 2>&1", path, 23 * 60) then
		assert(util.exec("wget --quiet --output-document=%s %s", path, url))
	end

	local path_ = self.cachepath .. "/deps"
	if not util.exec("test %s -ot %s 2>/dev/null", path, path_) then
		local xpath = '//div[@class="tabbed-block" and h3="Nexus requirements"]//td[@class="table-require-name"]/a/@href'
		local sedexpr = [[s:^ *href="\(.*\)"$:\1:g]]
		assert(util.exec("xmllint --html --xpath %s %s 2>/dev/null | sed %s > %s", xpath, path, sedexpr, path_))
	end

	local ret = {}
	if self.deps then
		for _, v in ipairs(self.deps) do
			table.insert(ret, nexusmod(v))
		end
	end
	for l in io.lines(path_) do
		local skip = false
		for _, v in ipairs(self.ignoredeps or {}) do
			if v == l then
				skip = true
				break
			end
		end
		if skip then
			util.log("Skipping %s ==> %s", self.url, l)
		else
			for _, v in ipairs(ret) do
				if v.url == l then
					util.warn("Duplicate dependency: %s ==> %s", self.url, l)
				end
			end
			table.insert(ret, nexusmod(l))
		end
	end
	return ret
end

function nexus.game(name)
	local self = {}

	self.name = name
	self._info = cached_api(("%s/api/nexus/%s/info.json"):format(cachedir, name), 30 * 24 * 60, "v1/games/%s.json", name)

	self.id = self._info.id
	self.displayname = self._info.name

	game = self
end

return nexus
