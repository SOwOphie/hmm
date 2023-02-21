#!/usr/bin/env lua5.4

if #arg ~= 1 then
	print("Usage: " .. arg[0] .. " <script file>")
	os.exit(1)
end

util = require "hmm.util"

local mods = {}



cachedir = os.getenv("HOME") .. "/.local/share/hmm"
gamedir  = false

local function monkeypatch(module)
	local ret = {}
	ret.mod = function(...)
		local ret = module.mod(...)
		table.insert(mods, ret)
		return ret
	end
	setmetatable(ret, {__index = module, __newindex = module})
	return ret
end

nexus = monkeypatch(require "hmm.modules.nexusmods")



util.begin "Resolving mods"

dofile(arg[1])

if not gamedir then util.err("gamedir not provided") end

assert(util.exec("realpath %s > /tmp/hmm.lastrun", arg[1]))

local indent = 0
local loadorder = {}
local function addmod(m)
	util.log("%s%s", ("  "):rep(indent), m.url)

	for _, v in ipairs(loadorder) do
		if v.id == m.id then return end
	end

	m:resolve()
	indent = indent + 1
	for _, dep in ipairs(m:getdeps()) do
		-- util.log("%s%s ==> %s", dep.url)
		addmod(dep)
	end
	indent = indent - 1
	table.insert(loadorder, m)
end
for _, m in ipairs(mods) do addmod(m) end

util.done()


util.log "\nDependencies:"
for _, m in ipairs(loadorder) do
	local deps = m:getdeps()
	if deps[1] then
		util.log(" - %q (%s)", m.name, m.url)
		for _, d in ipairs(deps) do util.log("     ==> %q (%s)", d.name, d.url) end
	end
end

util.log "\nLoad order:"
for i, m in ipairs(loadorder) do util.log(" %4d  %q (%s)", i, m.name, m.url) end



util.begin "Processing mods"
for _, m in ipairs(loadorder) do
	util.step(m.name)
	m:do_download()
	m:do_unpack()
	m:do_install()
end
util.done()



if util.exec('test -n "$(find %s/hmm -type f 2>/dev/null)"', gamedir) then
	util.begin "Cleaning up previous deployment"
	for l in io.lines(gamedir .. "/hmm") do
		util.exec("cd %s && rm %s", gamedir, l)
	end
	util.exec("rm %s/hmm", gamedir)
	util.done()
end



util.begin "Deploying mods"
util.log("Target directory: %s", gamedir)
local ho <close> = io.open(gamedir .. "/hmm", "a")
for _, m in ipairs(loadorder) do
	util.step(m.name)
	local d = m:installpath()

	local hi <close> = io.popen(("find %s -type f -printf '%%P\\n' >> %s/hmm"):format(util.shellesc(d), util.shellesc(gamedir)))
	local files = {}
	for l in hi:lines() do
		if util.exec('test -n "$(find %s/%s -type f 2>/dev/null)"', gamedir, l) and not (m.collisions or {})[l] then
			m:error("file %q collides, please allow explicitly to continue")
		end
		ho:write(l, "\n")
	end

	assert(util.exec("rsync --quiet --archive %s/ %s", d, gamedir))
end
util.done()
