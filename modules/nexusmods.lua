local nexus = {}

local util = require "hmm.util"
local json = require "hmm.json"
local base = require "hmm.base"

--  API  ===============================================================================================================

local domain = "nexusmods.com"
local apidomain = "api." .. domain
local webdomain = "www." .. domain

nexus.apikey = false

function nexus.api(path, validity, fmt, ...)
	if not validity or not util.exec('test -n "$(find %s -type f -mmin -%s 2>/dev/null)"', path, validity) then
		if not nexus.apikey then util.error("nexus.apikey required") end
		local url = ("https://%s/" .. fmt):format(apidomain, ...)
		util.action("Query", url)
		local cmd = table.concat({"curl",
			"--silent",
			"--request", "GET",
			"--header", "'accept: application/json'",
			"--header", ("'apikey: %s'"):format(nexus.apikey),
			"--output", util.shellesc(path),
			"--create-dirs",
			util.shellesc(url)
		}, " ")
		assert(os.execute(cmd))
		assert(os.execute("sleep 1"))
	end
	local h <close> = assert(io.open(path, "r"))
	return json.decode(h:read("a"))
end

function nexus.ispremium()
	if nexus.premium == nil then
		local resp = nexus.api(("%s/api/nexus/%s.json"):format(cachedir, nexus.apikey), 23 * 60, "v1/users/validate.json")
		nexus.premium = resp.is_premium
	end
	return not not nexus.premium
end

--  Games  =============================================================================================================

local game = false

function nexus.game(name)
	local self = {}

	self.name = name
	self._info = nexus.api(("%s/api/nexus/%s/info.json"):format(cachedir, name), 30 * 24 * 60, "v1/games/%s.json", name)

	self.id = self._info.id
	self.displayname = self._info.name

	game = self
end

--  Mod Class  =========================================================================================================

nexus.modmt = {__index = {}}
setmetatable(nexus.modmt.__index, base.modmt)
nexus.modmt.__call = base.modmt.__call

local cache = {}

local blocked = {}

function nexus.block(url)
	blocked[url] = true
end

function nexus.mod(url)
	if blocked[url] then
		util.error("mod %s is blocked", url)
	end

	if not cache[url] then
		local self = {}
		self.game, self.id = url:match("^https://www.nexusmods.com/([^/]*)/mods/([0-9]*)$")
		if not self.game then util.error("could not parse URL: %s", url) end
		if not game then util.error("no game specified before defining mods") end

		self.url  = url
		self.name = "?"

		self.path = cachedir .. "/mods/nexus/" .. self.id
		self.apipath = self.path .. "/api"
		setmetatable(self, nexus.modmt)

		if self.game ~= game.name then self:error("game set to %s, but this mod is for %s", game.name, self.game) end

		cache[url] = self
	end

	return cache[url]
end

function nexus.modmt.__index:userkeys()
	local ret = base.modmt.__index.userkeys(self)
	ret.deps = true
	ret.files = true
	ret.ignoredeps = function(x) return type(x) == "table" and util.toset(x) or x end
	return ret
end

function nexus.modmt.__index:resolve()
	if not self._resolved then
		self._info  = nexus.api(self.apipath .. "/info.json" , 23 * 60, "v1/games/%s/mods/%s.json"      , self.game, self.id)
		self._files = nexus.api(self.apipath .. "/files.json", 23 * 60, "v1/games/%s/mods/%s/files.json", self.game, self.id)

		self.name = self._info.name

		if not self.files then
			local primary = false
			for _, v in ipairs(self._files.files) do
				if v.category_id == 1 then
					if primary then
						util.errmsg("%q (%s):\nmod consists of multiple files, please specify their IDs manually", self.name, self.url)
						util.note("\nfound files:")
						for _, f in ipairs(self._files.files) do
							if f.category_id ~= 4 and f.category_id ~= 6 then
								util.note("%s %d: %s", f.category_name, f.file_id, f.name)
							end
						end
						util.note("\nMore info on %s?tab=files\n", self.url)
						os.exit(1)
					end
					primary = v.file_id
				end
			end
			if not primary then self:error("no primary file found, please specify file IDs manually") end

			self.files = {primary}
		else
			local function newest(self, id)
				for _, v in ipairs(self._files.file_updates) do
					if v.old_file_id == id then
						return newest(self, v.new_file_id) or v.new_file_id
					end
				end
			end

			for _, f in ipairs(self.files) do
				for _, v in ipairs(self._files.files) do
					if f == v.file_id then
						if v.category_id == 4 then
							local new = newest(self, f)
							util.warn("%s: file %d is outdated%s", self.url, f, new and (", try " .. new) or "")
						end

						if v.category_id == 6 then
							local new = newest(self, f)
							util.warn("%s: file %d is deleted" , self.url, f, new and (", try " .. new) or "")
						end
					end
				end
			end
		end

		self._resolved = true
	end
end

function nexus.modmt.__index:getfiles()
	local ret = {}
	for _, fileid in ipairs(self.files) do
		local f = false
		for _, v in ipairs(self._files.files) do
			if v.file_id == fileid then
				local _, ext = util.extsplit(v.file_name)
				f = {}
				f.id       = ("%d"):format(fileid)
				f.filename = f.id .. "." .. ext
				f.url      = function()
					if nexus.ispremium() then
						return nexus.api(self.apipath .. "/download/" .. f.id .. ".json", 1,
							"v1/games/%s/mods/%s/files/%s/download_link.json",
							self.game,
							self.id,
							f.id
						)[1].URI
					else
						local url = ("https://%s/Core/Libs/Common/Widgets/DownloadPopUp?id=%s&nmm=1&game_id=%s"):format(
							webdomain,
							f.id,
							game.id
						)
						util.exec("xdg-open %s", url)
						util.note("\nDownload link: %s", url)
						util.error "Non-premium users cannot download mods without the website. Please click the download button in the new browser window."
					end
				end
				break
			end
		end
		if not f then self:error("could not find file %s", fileid) end
		table.insert(ret, f)
	end
	return ret
end

function nexus.modmt.__index:getdeps()
	assert(util.exec("mkdir -p %s/deps", self.path))

	local path = self.path .. "/deps/scraped.html"
	local url = ("https://%s/Core/Libs/Common/Widgets/ModDescriptionTab?id=%d&game_id=%d"):format(webdomain, self.id, game.id)

	if not util.exec('test -n "$(find %s -type f -mmin -%s 2>/dev/null)"', path, 23 * 60) then
		assert(util.exec("wget --quiet --output-document=%s %s", path, url))
		assert(os.execute("sleep 1"))
	end

	local path_ = self.path .. "/deps/list"
	if not util.exec("test %s -ot %s 2>/dev/null", path, path_) then
		local xpath = '//div[@class="tabbed-block" and h3="Nexus requirements"]//td[@class="table-require-name"]/a/@href'
		local sedexpr = [[s:^ *href="\(.*\)"$:\1:g]]
		assert(util.exec("xmllint --html --xpath %s %s 2>/dev/null | sed %s > %s", xpath, path, sedexpr, path_))
	end

	local ret = {}
	if self.deps then
		for _, v in ipairs(self.deps) do
			table.insert(ret, nexus.mod(v))
		end
	end
	for l in io.lines(path_) do
		local skip = (self.ignoredeps == true) or (type(self.ignoredeps) == "table" and self.ignoredeps[l])
		if not skip then
			for _, v in ipairs(ret) do
				if v.url == l then util.warn("Duplicate dependency: %s ==> %s", self.url, l) end
			end
			table.insert(ret, nexus.mod(l))
		end
	end
	return ret
end

return nexus
