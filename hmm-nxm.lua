#!/usr/bin/env lua5.4

if not arg[1] then os.exit(1) end

local util = require "hmm.util"

-- deal with url

util.log("URL: %s", arg[1])

local game, mod, file, key, exp, user = arg[1]:match("^nxm://([^/]+)/mods/(%d+)/files/(%d+)%?key=([^&]+)&expires=(%d+)&user_id=(%d+)$")
if not game then util.error("failed to parse url") end

util.log("Got info:")
util.log("  game: %s", game)
util.log("  mod:  %s", mod )
util.log("  file: %s", file)
util.log("  key:  %s", key )
util.log("  exp:  %s", exp )
util.log("  user: %s", user)

-- load hmm file from last run

local hmmfile = false
do
	local h <close> = io.open("/tmp/hmm.lastrun", "r")
	if not h then
		util.exec("zenity --error --text='Please run hmm once before clicking download links!'")
		os.exit(0)
	end
	hmmfile = h:read("l")
end

cachedir = os.getenv("HOME") .. "/.local/share/hmm"
gamedir  = false
cleanup  = {}
nexus    = require "hmm.modules.nexusmods"

dofile(hmmfile)

-- handle the mod object

local m = nexus.mod("https://www.nexusmods.com/" .. game .. "/mods/" .. mod)
m:resolve()

local ext = false
for _, v in ipairs(m._files.files) do
	if tostring(v.file_id) == tostring(file) then
		print(v.file_name)
		local _, ext_ = util.extsplit(v.file_name)
		ext = ext_
		break
	end
end
if not ext then util.error("file %s not present in mod ... ?", file) end

local resp = nexus.api(m.apipath .. "/download/" .. file .. ".json", false,
	"v1/games/%s/mods/%s/files/%s/download_link.json?key=%s&expires=%s",
	game,
	mod,
	file,
	key,
	exp
)
local downloadlink = resp[1].URI

-- downloadlink = downloadlink .. "&key=" .. key .. "&expires=" .. exp

util.log("Download link: %s", downloadlink)

-- download the file

local p = io.popen("zenity --progress --pulsate --auto-close --text=" .. util.shellesc(arg[1]:gsub("&", "&amp;")), "w")

assert(util.exec("mkdir -p %s", m:downloadpath()))
m:cached({}, file .. ".downloaded", true, function()
	local f = file .. "." .. ext
	util.action("Download", f)
	m.download(downloadlink, m:downloadpath(f))
end)
