#!/usr/bin/env lua5.4

if #arg ~= 1 then
	print("Usage: " .. arg[0] .. " <script file>")
	os.exit(1)
end

local util = require "hmm.util"

local mods = {}



util.log "\nResolving mods ..."

cachedir = os.getenv("HOME") .. "/.local/share/hmm"
gamedir  = false

nexus = require "hmm.host.nexusmods"
nexus._mods = mods

dofile(arg[1])

if not gamedir then util.err("gamedir not provided") end

local loadorder = {}
local function addmod(m)
	for _, v in ipairs(loadorder) do
		if v.id == m.id then return end
	end

	util.log("%s ==> %s", m.url, m.name)
	for _, dep in ipairs(m:getdeps()) do addmod(dep) end
	table.insert(loadorder, m)
end
for _, m in ipairs(mods) do addmod(m) end

util.log "Done."



util.log "\nDependencies:"
for _, m in ipairs(loadorder) do
	util.log("%s", m.name)
	local deps = m:getdeps()
	for _, d in ipairs(deps) do util.log("    ==> %s", d.name) end
end

util.log "\nLoad order:"
for _, m in ipairs(loadorder) do util.log("%s", m.name) end



util.log("\nPreparing files ...")
for _, m in ipairs(loadorder) do m:datadir() end
util.log("Done.")



if util.exec("find %s/hmm -type f >/dev/null 2>&1", gamedir) then
	util.log("\nCleaning up previous deployment ...")
	for l in io.lines(gamedir .. "/hmm") do
		util.exec("cd %s && rm %s", gamedir, l)
	end
	util.exec("rm %s/hmm", gamedir)
	util.log("Done.")
end


util.log "\nInstalling files ..."
local ho = io.open(gamedir .. "/hmm", "a")
for _, m in ipairs(loadorder) do
	util.log(m.name)
	local d = m:datadir()


	local hi = io.popen(("find %s -type f -printf '%%P\\n' >> %s/hmm"):format(util.shellesc(d), util.shellesc(gamedir)))
	local files = {}
	for l in hi:lines() do
		if util.exec("find %s/%s -type f >/dev/null 2>&1", gamedir, l) then
			local ok = false
			for _, v in ipairs(m.collisions or {}) do
				if v == l then
					ok = true
					break
				end
			end
			if not ok then error("file %s from mod %q collides, please allow explicitly to continue") end
		end
		ho:write(l, "\n")
	end
	hi:close()

	assert(util.exec("rsync --quiet --archive %s/ %s", d, gamedir))
end
ho:close()
util.log "Done."


--[[
local dirstack = false
for i, m in ipairs(loadorder) do
	dirstack = (dirstack and (dirstack .. ":") or "") .. m:datadir()
end

util.log "Done."

util.log "\nMounting overlay ..."
assert(util.exec("mkdir -p %s %s", workdir, upperdir))
assert(util.exec("rsync -a --delete %s/ %s", srcdir, upperdir))
assert(util.exec("fuse-overlayfs -o lowerdir=%s,upperdir=%s,workdir=%s %s", dirstack, upperdir, workdir, srcdir))
util.log "Done."

local cmd = util.shellesc(arg[2])

for i = 3, #arg do
	cmd = cmd .. " " .. util.shellesc(arg[i])
end
util.log("%s", cmd)
os.execute(cmd)

util.log "\nUnmounting overlay ..."
assert(util.exec("fusermount -u %s", srcdir))
assert(util.exec("rsync -a --delete %s/ %s", upperdir, srcdir))
util.log "Done."
]]
