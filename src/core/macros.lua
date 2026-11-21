-- Macro create / remove / migrate.

local _, ns = ...

local P, MAX_PAIRS = ns.PREFIX, ns.MAX_PAIRS
local OLD_PRESETS, OLD_NAMES = ns.OLD_PRESETS, ns.OLD_NAMES
local MacroIndex, MacroName, OldMacroName = ns.MacroIndex, ns.MacroName, ns.OldMacroName
local Body, FindPair, IsOwnMacro = ns.Body, ns.FindPair, ns.IsOwnMacro
local shown, Update, Rebind = ns.shown, ns.Update, ns.Rebind

local function AfterListChange()
	wipe(shown)
	Update(true)
	Rebind()
	ns.Refresh()
end

-- d: { ranged or rangedMacro = A, melee or meleeMacro = B }
local function AddPair(d)
	if InCombatLockdown() then print(P .. "not in combat.") return end
	if not (d.ranged or d.rangedMacro) or not (d.melee or d.meleeMacro) then
		print(P .. "put a skill or macro in both boxes first.")
		return
	end
	if FindPair(d) then print(P .. "this key is already in your list.") return end
	if #ns.db.pairs >= MAX_PAIRS then print(P .. "list is full (" .. MAX_PAIRS .. ").") return end
	local p = { ranged = d.ranged, rangedMacro = d.rangedMacro, melee = d.melee, meleeMacro = d.meleeMacro }
	local name = MacroName(p)
	if IsOwnMacro(name) then
		print(P .. "another key already uses the name " .. name .. ". Pick a different pair.")
		return
	end
	if not MacroIndex(name) then
		local ok, res = pcall(CreateMacro, name, "INV_MISC_QUESTIONMARK", Body(p), true)
		if not ok or not res then
			print(P .. "could not create " .. name .. " (macro slots full?)")
			return
		end
	end
	ns.db.pairs[#ns.db.pairs + 1] = p
	print(P .. "created " .. name .. ". Click Pick up and drop it on your action bar.")
	AfterListChange()
end

local function RemovePair(i)
	if InCombatLockdown() then print(P .. "not in combat.") return end
	local p = ns.db.pairs[i]
	if not p then return end
	local index = MacroIndex(MacroName(p))
	if index then DeleteMacro(index) end
	table.remove(ns.db.pairs, i)
	ns.CloseEditorFor(p)
	print(P .. "deleted " .. MacroName(p) .. ".")
	AfterListChange()
end

-- Rewrite macro text that differs from Body(); also copies changes from the
-- player's own macros used as a side. Out of combat only.
local triedBody = {} -- macro name -> body already written (no edit loops)
local function FixBodies()
	if InCombatLockdown() then return end
	for _, p in ipairs(ns.db.pairs) do
		local name = MacroName(p)
		local index = MacroIndex(name)
		local body = Body(p)
		if index and GetMacroBody(index) ~= body and triedBody[name] ~= body then
			triedBody[name] = body
			pcall(EditMacro, index, nil, nil, body)
		end
	end
end

-- Version 1.0/1.1 names (RS-Arcane...) and 1.2+ names (Raptor/Arcane) ->
-- the new names (Arcane>Raptor). The macro stays on the action bar.
local function Migrate()
	if InCombatLockdown() then return end
	if (GetNumMacros() or 0) == 0 then return end -- macros not loaded yet
	if not ns.db.migrated then
		for old, n in pairs(OLD_NAMES) do
			local index = MacroIndex(old)
			local p = OLD_PRESETS[n]
			if index then
				if not MacroIndex(MacroName(p)) then pcall(EditMacro, index, MacroName(p), nil, nil) end
				if not FindPair(p) then
					ns.db.pairs[#ns.db.pairs + 1] = { melee = p.melee, ranged = p.ranged, off = ns.db.off and ns.db.off[old] or nil }
				end
			end
		end
		ns.db.off = nil
		ns.db.migrated = true
	end
	if not ns.db.nameV2 then
		for _, p in ipairs(ns.db.pairs) do
			local index = MacroIndex(OldMacroName(p))
			if index and not MacroIndex(MacroName(p)) then
				pcall(EditMacro, index, MacroName(p), nil, nil)
			end
		end
		ns.db.nameV2 = true
	end
end

ns.AfterListChange = AfterListChange
ns.AddPair = AddPair
ns.RemovePair = RemovePair
ns.FixBodies = FixBodies
ns.Migrate = Migrate
