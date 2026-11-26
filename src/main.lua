-- Auto Skill Swap
--
-- One key, two skills:
--   * key press   -> tries the PRIORITY skill (A)
--   * key release -> tries the FALLBACK skill (B)
-- The game blocks A when it can't be used right now (wrong range, on
-- cooldown, not enough mana/rage, target health too high, no dodge/parry
-- yet...), and then B casts. Each side is a spell or one of the player's own
-- macros. The macro icon and the name on the action button show the skill
-- that will cast now.
--
-- Why press/release: on Forever one input event tries only ONE skill that
-- uses the global cooldown, so a plain "/cast A /cast B" macro never falls
-- through from a failed A to B. Press and release are two input events.
--
-- Data: a pair p keeps the field names of version 1 so saved data still
-- works: p.ranged / p.rangedMacro = side A (priority),
--        p.melee  / p.meleeMacro  = side B (fallback).
--
-- This file: saved variables, events and slash commands. Load order and the
-- other files: see AutoSkillSwap.toc.

local ADDON, ns = ...

local INTERVAL, P, A, CLASS = ns.INTERVAL, ns.PREFIX, ns.A, ns.CLASS
local MacroIndex, CanCast, TargetInMelee = ns.MacroIndex, ns.CanCast, ns.TargetInMelee
local MacroName, SideSpell = ns.MacroName, ns.SideSpell
local shown, failed, CollectButtons, Update = ns.shown, ns.failed, ns.CollectButtons, ns.Update
local boundKeys, Rebind, QueueRebind = ns.boundKeys, ns.Rebind, ns.QueueRebind
local ApplyErrorFilter, Migrate, FixBodies = ns.ApplyErrorFilter, ns.Migrate, ns.FixBodies
local Refresh, RefreshNow, OpenSettings = ns.Refresh, ns.RefreshNow, ns.OpenSettings

-- AutoSkillSwapDB: { swap, names, smart, hideErrors, hideMinimap, minimap,
--   minimapAngle, winPos, pairs = { pair }, migrated, nameV2 }

local frame = CreateFrame("Frame")
local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < INTERVAL then return end
	elapsed = 0
	Update(false)
	RefreshNow()
end)

-- UPDATE_MACROS never calls Update(true): SetMacroSpell may fire it (loop).
for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
	"UPDATE_MACROS", "UI_ERROR_MESSAGE", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR" }) do
	pcall(frame.RegisterEvent, frame, ev)
end
frame:SetScript("OnEvent", function(_, event, ...)
	local arg1 = ...
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		AutoSkillSwapDB = AutoSkillSwapDB or {}
		local db = AutoSkillSwapDB
		if db.swap == nil then db.swap = true end
		if db.names == nil then db.names = true end
		if db.smart == nil then db.smart = true end
		if db.hideErrors == nil then db.hideErrors = true end
		db.pairs = db.pairs or {}
		ns.db = db
		ns.BuildPanel()
		ns.BuildEditor(ns.BuildWindow())
		ns.BuildMinimapButton()
		ApplyErrorFilter()
	elseif not ns.db then
		return
	elseif event == "UI_ERROR_MESSAGE" then
		ns.OnErrorMessage(event, ...)
	elseif event == "PLAYER_ENTERING_WORLD" then
		Migrate()
		FixBodies()
		CollectButtons()
		Update(true)
		Rebind()
	elseif event == "PLAYER_TARGET_CHANGED" then
		Update(false)
	elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED"
		or event == "UPDATE_BONUS_ACTIONBAR" then
		QueueRebind()
	elseif event == "UPDATE_MACROS" then
		-- a player's macro may have changed: refresh copies and key texts
		FixBodies()
		QueueRebind()
	elseif event == "UPDATE_BINDINGS" then
		-- our own override bindings fire this too; only react to the user's changes
		if GetTime() - ns.LastBindTime() > 1 then QueueRebind() end
	else -- combat start/end
		if event == "PLAYER_REGEN_ENABLED" then
			Migrate()
			FixBodies()
			ns.RebindIfPending()
		end
		Refresh()
	end
end)

-- /skillswap or /sswap : open settings.  /skillswap debug : print what the addon sees.
SLASH_AUTOSKILLSWAP1 = "/skillswap"
SLASH_AUTOSKILLSWAP2 = "/sswap"
-- tostring that does not touch secret values (combat)
local function Text(v)
	if ns.IsSecret(v) then return "secret" end
	return tostring(v)
end

SlashCmdList.AUTOSKILLSWAP = function(msg)
	if (msg or ""):lower():match("debug") then
		print(P .. "class " .. tostring(CLASS) .. ", target in melee: " .. tostring(TargetInMelee())
			.. ", in combat: " .. tostring(InCombatLockdown()))
		for _, id in ipairs(ns.MELEE_TEST) do
			local spell = ns.SpellName(id)
			print(P .. "  melee test " .. tostring(spell) .. " in range: " .. Text(spell and ns.InRange(spell, "target")))
		end
		for i, p in ipairs(ns.db.pairs) do
			print(P .. MacroName(p) .. ": macro " .. tostring(MacroIndex(MacroName(p)))
				.. ", key " .. tostring(boundKeys[i]) .. ", now " .. tostring(shown[MacroName(p)]))
			for _, side in ipairs({ A, ns.B }) do
				local spell = SideSpell(p, side)
				local info = spell and ns.SpellInfo(spell)
				local usable = spell and C_Spell and C_Spell.IsSpellUsable and C_Spell.IsSpellUsable(spell)
				local cd = spell and C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spell)
				print(P .. "  " .. (side == A and "A " or "B ") .. tostring(spell)
					.. ": can cast " .. tostring(CanCast(spell, p))
					.. ", usable " .. Text(usable)
					.. ", cd " .. Text(cd and cd.duration)
					.. ", in range " .. Text(spell and ns.InRange(spell, "target"))
					.. ", min range " .. Text(info and info.minRange))
			end
		end
		wipe(failed)
		Update(true)
		return
	end
	OpenSettings()
end
