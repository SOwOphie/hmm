#!/usr/bin/env lua5.4

if #arg ~= 1 then
	print("Usage: " .. arg[0] .. " <script file>")
	os.exit(1)
end

util = require "hmm.util"

local base = require "hmm.base"

local mods = {}
cleanup = {}



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



copyfrom = base.modmt.__index.install



util.begin "Resolving mods"

dofile(arg[1])

if not gamedir then util.err("gamedir not provided") end

assert(util.exec("realpath %s > /tmp/hmm.lastrun", arg[1]))

local loadorder = {}
local function addmod(m)
	for _, v in ipairs(loadorder) do
		if v.id == m.id then return end
	end

	m:resolve()
	util.trace_push(m)
	for _, dep in ipairs(m:getdeps()) do addmod(dep) end
	util.trace_pop()
	table.insert(loadorder, m)
end
for _, m in ipairs(mods) do addmod(m) end

util.done()


util.note "\nDependencies:"
for _, m in ipairs(loadorder) do
	local deps = m:getdeps()
	util.note(" - %q (%s)", m.name, m.url)
	for _, d in ipairs(deps) do util.note("     ==> %q (%s)", d.name, d.url) end
end

util.note "\nLoad order:"
for i, m in ipairs(loadorder) do util.note(" %4d  %q (%s)", i, m.name, m.url) end



util.begin "Processing mods"
for _, m in ipairs(loadorder) do
	util.step(m.name, m.url)
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
	util.exec("find %s -type d -empty -delete", gamedir)
	util.done()
end



util.begin "Deploying mods"
util.log("Target directory: %s", gamedir)
local ho <close> = io.open(gamedir .. "/hmm", "a")
for _, m in ipairs(loadorder) do
	util.step(m.name, m.url)
	local d = m:installpath()

	local hi <close> = io.popen(("find %s -type f -printf '%%P\\n'"):format(util.shellesc(d)))
	local files = {}
	for l in hi:lines() do
		if util.exec('test -e %s/%s', gamedir, l) then
			if not (m.collisions or {})[l] then
				m:error("file %q collides, please allow explicitly to continue (add the file path to the `collisions` list of this mod)", l)
			end
		else
			ho:write(l, "\n")
		end
	end

	assert(util.exec("rsync --quiet --archive %s/ %s", d, gamedir))
end
util.done()

for _, v in ipairs(cleanup) do v() end
