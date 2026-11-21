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

local ADDON = ...

local TITLE = "Auto Skill Swap"
local P = "|cff66ccffAuto Skill Swap|r: "
local INTERVAL = 0.2
local MAX_PAIRS = 18 -- WoW allows 18 character-specific macros
local A, B = "ranged", "melee" -- side keys (see Data above)

local CLASS = select(2, UnitClass("player"))

-- Ready-made pairs per class: { A = priority, B = fallback, why = condition }.
-- Spell IDs (rank 1), so the names come out in the client's language.
local PRESETS = {
	HUNTER = {
		{ A = 3044,  B = 2973, why = "range" },         -- Arcane Shot > Raptor Strike
		{ A = 1978,  B = 2973, why = "range" },         -- Serpent Sting > Raptor Strike
		{ A = 5116,  B = 2974, why = "range" },         -- Concussive Shot > Wing Clip
		{ A = 2643,  B = 2973, why = "range" },         -- Multi-Shot > Raptor Strike
		{ A = 19434, B = 2973, why = "range" },         -- Aimed Shot > Raptor Strike
		{ A = 3044,  B = 781,  why = "range" },         -- Arcane Shot > Disengage
		{ A = 1495,  B = 2973, why = "after a dodge" }, -- Mongoose Bite > Raptor Strike
	},
	WARRIOR = {
		{ A = 5308, B = 78,   why = "target below 20% health" },   -- Execute > Heroic Strike
		{ A = 7384, B = 78,   why = "after a dodge" },             -- Overpower > Heroic Strike
		{ A = 6572, B = 7386, why = "after a block/dodge/parry" }, -- Revenge > Sunder Armor
		{ A = 7384, B = 772,  why = "after a dodge" },             -- Overpower > Rend
	},
	ROGUE = {
		{ A = 14251, B = 1752, why = "after a parry" }, -- Riposte > Sinister Strike
		{ A = 14278, B = 1752, why = "cooldown" },      -- Ghostly Strike > Sinister Strike
	},
	MAGE = {
		{ A = 2136, B = 116, why = "cooldown" }, -- Fire Blast > Frostbolt
		{ A = 2136, B = 133, why = "cooldown" }, -- Fire Blast > Fireball
		{ A = 122,  B = 116, why = "cooldown" }, -- Frost Nova > Frostbolt
	},
	WARLOCK = {
		{ A = 17877, B = 686, why = "cooldown" }, -- Shadowburn > Shadow Bolt
		{ A = 6789,  B = 686, why = "cooldown" }, -- Death Coil > Shadow Bolt
	},
	SHAMAN = {
		{ A = 8042, B = 403, why = "cooldown" }, -- Earth Shock > Lightning Bolt
		{ A = 8050, B = 403, why = "cooldown" }, -- Flame Shock > Lightning Bolt
	},
	PRIEST = {
		{ A = 8092, B = 585,   why = "cooldown" }, -- Mind Blast > Smite
		{ A = 8092, B = 15407, why = "cooldown" }, -- Mind Blast > Mind Flay
	},
	PALADIN = {
		{ A = 24275, B = 20271, why = "target below 20% health" },       -- Hammer of Wrath > Judgement
		{ A = 879,   B = 20271, why = "undead/demon target, cooldown" }, -- Exorcism > Judgement
	},
	DRUID = {
		{ A = 5221, B = 1082, why = "behind the target" }, -- Shred > Claw
		{ A = 2912, B = 5176, why = "mana" },              -- Starfire > Wrath
	},
}

-- Version 1 macro names and their pairs; renamed once to the new names.
local OLD_PRESETS = {
	{ melee = "Raptor Strike", ranged = "Arcane Shot" },
	{ melee = "Mongoose Bite", ranged = "Serpent Sting" },
	{ melee = "Wing Clip",     ranged = "Concussive Shot" },
	{ melee = "Raptor Strike", ranged = "Multi-Shot" },
	{ melee = "Raptor Strike", ranged = "Aimed Shot" },
	{ melee = "Mongoose Bite", ranged = "Viper Sting" },
	{ melee = "Wing Clip",     ranged = "Scatter Shot" },
}
local OLD_NAMES = {
	["RS-Arcane"] = 1, ["MB-Serpent"] = 2, ["WC-Concuss"] = 3, ["RS-Multi"] = 4,
	["RS-Aimed"] = 5, ["MB-Viper"] = 6, ["WC-Scatter"] = 7,
}

-- Conditions for "Always use A / B when". They are macro conditions, so the
-- secure key button can test them in combat (SecureCmdOptionParse).
local CONDITIONS = {
	{ label = "Never" },
	{ label = "Shift held",         cond = "[mod:shift]" },
	{ label = "Ctrl held",          cond = "[mod:ctrl]" },
	{ label = "Alt held",           cond = "[mod:alt]" },
	{ label = "Out of combat",      cond = "[nocombat]" },
	{ label = "In combat",          cond = "[combat]" },
	{ label = "Target is friendly", cond = "[@target,help]" },
	{ label = "No enemy target",    cond = "[@target,noharm][@target,dead]" },
	{ label = "Stealthed",          cond = "[stealth]" },
	{ label = "Mounted",            cond = "[mounted]" },
	{ label = "In a group",         cond = "[group]" },
	{ label = "No pet / pet dead",  cond = "[nopet][@pet,dead]" },
	{ label = "Custom...",          custom = true },
}

-- Hunter melee range test. Raptor Strike is left out: on Forever it reports
-- "in range" at any distance (same finding as the HunterRange addon).
local MELEE_TEST = { 2974, 1495 } -- Wing Clip, Mongoose Bite (spell IDs)

-- AutoSkillSwapDB: { swap, names, smart, hideErrors, hideMinimap,
--   minimapAngle, winPos, pairs = { pair }, migrated, nameV2 }
local db

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function IsSecret(v)
	return type(issecretvalue) == "function" and issecretvalue(v) or false
end

-- "Raptor Strike" -> "Raptor", "Multi-Shot" -> "Multi"
local function Short(spell)
	return spell:match("^[^%s%-]+") or spell
end

local function MacroIndex(name)
	local i = GetMacroIndexByName(name)
	return (i and i > 0) and i or nil
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end

local function SpellTexture(spell)
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) end
	return GetSpellTexture and GetSpellTexture(spell) or nil
end

local function SpellInfo(name)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, name)
		return ok and info or nil
	end
	if GetSpellInfo then
		local n, _, icon, _, minRange, maxRange, id = GetSpellInfo(name)
		return n and { name = n, iconID = icon, minRange = minRange, maxRange = maxRange, spellID = id } or nil
	end
end

local function SpellID(name)
	local info = SpellInfo(name)
	return info and info.spellID or nil
end

local function SpellKnown(name)
	return SpellInfo(name) ~= nil
end

local function SpellCooldown(spell)
	if C_Spell and C_Spell.GetSpellCooldown then
		local cd = C_Spell.GetSpellCooldown(spell)
		if cd then return cd.startTime, cd.duration end
		return 0, 0
	end
	return GetSpellCooldown(spell)
end

-- true = in range, false = out of range, nil = can't tell
local function InRange(spell, unit)
	local ok, r
	if C_Spell and C_Spell.IsSpellInRange then
		ok, r = pcall(C_Spell.IsSpellInRange, spell, unit)
	else
		ok, r = pcall(IsSpellInRange, spell, unit)
	end
	if not ok or r == nil or IsSecret(r) then return nil end
	return r == true or r == 1
end

local function TargetInMelee()
	if CLASS ~= "HUNTER" then return false end
	if not UnitExists("target") or UnitIsDead("target") then return false end
	for _, id in ipairs(MELEE_TEST) do
		local spell = SpellName(id)
		if spell and InRange(spell, "target") == true then return true end
	end
	return false
end

-- Can this spell be cast right now? true / false. Unknown answers (secret
-- values in combat) count as true, so the icon keeps showing the priority.
-- p (optional) turns checks off: p.noUsable, p.noCooldown, p.noRange.
local function CanCast(spell, p)
	if not spell then return true end
	p = p or {}
	-- usable: mana/rage/energy, procs (Overpower...), target health (Execute...)
	local usable
	if p.noUsable then
		usable = nil
	elseif C_Spell and C_Spell.IsSpellUsable then
		local ok, u = pcall(C_Spell.IsSpellUsable, spell)
		if ok and not IsSecret(u) then usable = u end
	elseif IsUsableSpell then
		local ok, u = pcall(IsUsableSpell, spell)
		if ok then usable = u end
	end
	if usable == false then return false end
	-- cooldown, ignoring the global cooldown
	local ok, start, duration = pcall(SpellCooldown, spell)
	if not p.noCooldown and ok and not IsSecret(start) and not IsSecret(duration)
		and start and duration and start > 0 and duration > 1.6 then
		return false
	end
	-- range to a hostile target (including the minimum range of shots)
	if not p.noRange and UnitExists("target") and UnitCanAttack("player", "target") then
		if InRange(spell, "target") == false then return false end
		local info = SpellInfo(spell)
		if info and (info.minRange or 0) > 0 and TargetInMelee() then return false end
	end
	return true
end

---------------------------------------------------------------------------
-- Pair sides: each side is a spell or one of the player's macros
---------------------------------------------------------------------------

local function Side(p, side)
	local m = p[side .. "Macro"]
	if m then return "macro", m end
	return "spell", p[side]
end

-- Macro text of a player's macro without its #showtooltip/#show lines.
local function MacroLines(name)
	local index = MacroIndex(name)
	if not index then return nil end
	local _, _, body = GetMacroInfo(index)
	if not body then return nil end
	local out = {}
	for line in body:gmatch("[^\r\n]+") do
		if not line:match("^%s*#show") then out[#out + 1] = line end
	end
	return table.concat(out, "\n")
end

local function SideLabel(p, side)
	local _, v = Side(p, side)
	return v
end

-- Short text for the action button: "Raptor", or the macro name.
local function SideShort(p, side)
	local kind, v = Side(p, side)
	return kind == "macro" and v or Short(v)
end

local function SideCast(p, side)
	local kind, v = Side(p, side)
	if kind == "macro" then return MacroLines(v) or "" end
	return "/cast " .. v
end

-- Spell behind a side (a macro side: the spell its macro shows).
local function SideSpell(p, side)
	local kind, v = Side(p, side)
	if kind == "spell" then return v end
	local index = MacroIndex(v)
	local id = index and GetMacroSpell and GetMacroSpell(index)
	return id and SpellName(id) or nil
end

local function SideIcon(p, side)
	local kind, v = Side(p, side)
	if kind == "spell" then return SpellTexture(v) end
	local index = MacroIndex(v)
	if not index then return nil end
	local _, icon = GetMacroInfo(index)
	return icon
end

local function SideKnown(p, side)
	local kind, v = Side(p, side)
	if kind == "macro" then return MacroIndex(v) ~= nil end
	return SpellKnown(v)
end

-- "Arcane>Raptor": priority > fallback
local function MacroName(p)
	return (SideShort(p, A) .. ">" .. SideShort(p, B)):sub(1, 16)
end

-- Version 1.x name: "Raptor/Arcane" (melee/ranged)
local function OldMacroName(p)
	return (SideShort(p, B) .. "/" .. SideShort(p, A)):sub(1, 16)
end

-- Used for mouse clicks; keys use Smart keys. With two spell sides, the
-- "Always use A / B when" conditions go into the first /cast line.
local function Body(p)
	local show = SideSpell(p, A)
	local first = SideCast(p, A)
	local ka, va = Side(p, A)
	local kb, vb = Side(p, B)
	if ka == "spell" and kb == "spell" and (p.forceA or p.forceB) then
		first = "/cast " .. (p.forceA and (p.forceA .. " " .. va .. "; ") or "")
			.. (p.forceB and (p.forceB .. " " .. vb .. "; ") or "") .. va
	end
	local body = "#showtooltip" .. (show and (" " .. show) or "") .. "\n"
		.. first .. "\n" .. SideCast(p, B)
	return body:sub(1, 255)
end

-- true when a macro condition like "[mod:shift]" is true right now
local function CondTrue(cond)
	if not cond then return false end
	local ok, r = pcall(SecureCmdOptionParse, cond .. " x")
	return ok and r == "x"
end

-- "mod:shift" -> "[mod:shift]"; nil for empty or invalid text
local function NormalizeCond(text)
	text = (text or ""):match("^%s*(.-)%s*$")
	if text == "" then return nil end
	if text:sub(1, 1) ~= "[" then text = "[" .. text .. "]" end
	if not pcall(SecureCmdOptionParse, text .. " x") then return nil end
	return text
end

-- d: { ranged, rangedMacro, melee, meleeMacro }
local function FindPair(d)
	for i, p in ipairs(db.pairs) do
		if p.melee == d.melee and p.ranged == d.ranged
			and p.meleeMacro == d.meleeMacro and p.rangedMacro == d.rangedMacro then
			return i
		end
	end
end

local function IsOwnMacro(name)
	for _, p in ipairs(db.pairs) do
		if MacroName(p) == name then return true end
	end
	return false
end

-- The side that will cast now: "Always use" conditions first, then A when
-- A can be cast (with the checks the pair has turned on), else B.
local function NowSide(p)
	if CondTrue(p.forceA) then return A end
	if CondTrue(p.forceB) then return B end
	if not db.swap or p.off then return A end
	return CanCast(SideSpell(p, A), p) and A or B
end

---------------------------------------------------------------------------
-- Icon + button name
---------------------------------------------------------------------------

local shown = {}  -- macro name -> side shown now
local failed = {} -- macro name -> error already printed

local buttons
local function CollectButtons()
	buttons = {}
	-- button prefix -> key binding command prefix
	local bars = {
		{ "ActionButton", "ACTIONBUTTON" },
		{ "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
		{ "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
		{ "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
		{ "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" },
		{ "MultiBar5Button", "MULTIACTIONBAR5BUTTON" },
		{ "MultiBar6Button", "MULTIACTIONBAR6BUTTON" },
		{ "MultiBar7Button", "MULTIACTIONBAR7BUTTON" },
	}
	for _, bar in ipairs(bars) do
		for i = 1, 12 do
			local b = _G[bar[1] .. i]
			if b and b.Name then
				b.mriCommand = bar[2] .. i
				b.mriMain = bar[1] == "ActionButton" -- main bar: pages and stance bars
				b.mriIndex = i
				buttons[#buttons + 1] = b
			end
		end
	end
end

-- Write the skill name on buttons that hold one of our macros.
-- Runs every tick: Blizzard rewrites the name when the bar updates.
local function ApplyNames()
	if not buttons then CollectButtons() end
	local text = {}
	for _, p in ipairs(db.pairs) do
		local name = MacroName(p)
		text[name] = SideShort(p, shown[name] or A)
	end
	for _, b in ipairs(buttons) do
		local slot = b.action
		if type(slot) == "number" then
			local macro = GetActionText(slot)
			local want = macro and text[macro]
			if want then
				if not db.names then want = macro end
				if b.Name:GetText() ~= want then b.Name:SetText(want) end
			end
		end
	end
end

local function Update(force)
	if not db then return end
	for _, p in ipairs(db.pairs) do
		local name = MacroName(p)
		local side = NowSide(p)
		if force or shown[name] ~= side then
			shown[name] = side
			local index = MacroIndex(name)
			local spell = SideSpell(p, side)
			if index and spell then
				local ok, err = pcall(SetMacroSpell, index, spell)
				if not ok and not failed[name] then
					failed[name] = true
					print(P .. "cannot change icon of " .. name .. ": " .. tostring(err))
				end
			end
		end
	end
	ApplyNames()
end

---------------------------------------------------------------------------
-- Smart keys: the key of an action button that holds one of our macros is
-- bound (override binding, out of combat) to a hidden secure button.
-- Key down tries side A, key up tries side B.
---------------------------------------------------------------------------

local Refresh -- settings page refresh, defined below
local editor, editPair -- per-key settings panel and the pair it shows

local KEY_BUTTONS = 36 -- one hidden button per action button holding a key

local keyOwner = CreateFrame("Frame")
local keyHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
local keyButtons = {}
local boundKeys = {}   -- pair index -> "3, SHIFT-3"
local pendingBind = false
local lastBind = 0
local lastPress = 0    -- time of the last smart key event (error filter)

-- Main bar button i shows a different action slot per page and stance /
-- form / stealth bar. This macro condition gives the slot shown now.
local function MainBarSlotCond(i)
	local parts = { "[bonusbar:5] " .. (120 + i) } -- possess (mind control)
	for k = 1, 4 do
		parts[#parts + 1] = "[actionbar:1,bonusbar:" .. k .. "] " .. (72 + (k - 1) * 12 + i)
	end
	for page = 2, 6 do
		parts[#parts + 1] = "[actionbar:" .. page .. "] " .. ((page - 1) * 12 + i)
	end
	parts[#parts + 1] = tostring(i)
	return table.concat(parts, "; ")
end

for i = 1, KEY_BUTTONS do
	local b = CreateFrame("Button", "AutoSkillSwapKey" .. i, UIParent, "SecureActionButtonTemplate")
	b:Hide()
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetAttribute("type", "spell")
	-- 1. Main bar: if the bar now shows another slot (other page or stance),
	--    act as that slot instead (key down only).
	-- 2. "Always use A/B when" (macro conditions): that side on key down,
	--    nothing on key up.
	-- 3. Else key down -> side A ("ranged"), key up -> side B ("melee").
	-- A side is a spell (type "spell") or macro text (type "macro").
	keyHeader:WrapScript(b, "OnClick", [[
		local slotCond = self:GetAttribute("mri-slotcond")
		if slotCond then
			local now = tonumber(SecureCmdOptionParse(slotCond))
			if now and now ~= self:GetAttribute("mri-slot") then
				self:SetAttribute("useOnKeyDown", down and true or false)
				if down then
					self:SetAttribute("type", "action")
					self:SetAttribute("action", now)
				else
					self:SetAttribute("type", nil)
				end
				return
			end
		end
		local forced
		local fa = self:GetAttribute("mri-forceA")
		local fb = self:GetAttribute("mri-forceB")
		if fa and SecureCmdOptionParse(fa .. " x") == "x" then
			forced = "ranged"
		elseif fb and SecureCmdOptionParse(fb .. " x") == "x" then
			forced = "melee"
		end
		local side
		if forced then
			if down then side = forced end
		else
			side = down and "ranged" or "melee"
		end
		self:SetAttribute("useOnKeyDown", down and true or false)
		if side then
			self:SetAttribute("type", self:GetAttribute("mri-" .. side .. "-type") or "spell")
			self:SetAttribute("spell", self:GetAttribute("mri-" .. side))
			self:SetAttribute("macrotext", self:GetAttribute("mri-" .. side .. "-text"))
		else
			self:SetAttribute("type", nil)
		end
	]])
	b:HookScript("PreClick", function() lastPress = GetTime() end)
	keyButtons[i] = b
end

local function Rebind()
	if InCombatLockdown() then pendingBind = true return end
	pendingBind = false
	lastBind = GetTime()
	ClearOverrideBindings(keyOwner)
	wipe(boundKeys)
	if not db.smart then return end
	if not buttons then CollectButtons() end
	local byName = {}
	for i, p in ipairs(db.pairs) do byName[MacroName(p)] = i end
	local used = 0
	for _, b in ipairs(buttons) do
		local slot = b.action
		local i = type(slot) == "number" and byName[GetActionText(slot) or ""]
		local keys = b.mriCommand and { GetBindingKey(b.mriCommand) } or {}
		if i and #keys > 0 and used < KEY_BUTTONS then
			used = used + 1
			local kb, p = keyButtons[used], db.pairs[i]
			for _, side in ipairs({ A, B }) do
				local kind, v = Side(p, side)
				kb:SetAttribute("mri-" .. side .. "-type", kind == "macro" and "macro" or "spell")
				kb:SetAttribute("mri-" .. side, kind == "spell" and v or nil)
				kb:SetAttribute("mri-" .. side .. "-text", kind == "macro" and MacroLines(v) or nil)
			end
			kb:SetAttribute("mri-forceA", p.forceA)
			kb:SetAttribute("mri-forceB", p.forceB)
			kb:SetAttribute("mri-slot", slot)
			kb:SetAttribute("mri-slotcond", b.mriMain and MainBarSlotCond(b.mriIndex) or nil)
			for _, key in ipairs(keys) do
				SetOverrideBindingClick(keyOwner, true, key, kb:GetName(), "LeftButton")
				boundKeys[i] = boundKeys[i] and (boundKeys[i] .. ", " .. key) or key
			end
		end
	end
end

local rebindQueued = false
local function QueueRebind()
	if rebindQueued then return end
	rebindQueued = true
	C_Timer.After(0.3, function()
		rebindQueued = false
		Rebind()
		if Refresh then Refresh() end
	end)
end

-- Error filter: every press has one side that fails ("Out of range",
-- "Ability is not ready yet"...). With hideErrors on, UIErrorsFrame stops
-- listening and we pass on only the errors that are not from our keys.
local function ApplyErrorFilter()
	if not UIErrorsFrame then return end
	if db.hideErrors then
		UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	else
		UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
	end
end

---------------------------------------------------------------------------
-- Macro create / remove / migrate
---------------------------------------------------------------------------

local function AfterListChange()
	wipe(shown)
	Update(true)
	Rebind()
	Refresh()
end

-- d: { ranged or rangedMacro = A, melee or meleeMacro = B }
local function AddPair(d)
	if InCombatLockdown() then print(P .. "not in combat.") return end
	if not (d.ranged or d.rangedMacro) or not (d.melee or d.meleeMacro) then
		print(P .. "put a skill or macro in both boxes first.")
		return
	end
	if FindPair(d) then print(P .. "this key is already in your list.") return end
	if #db.pairs >= MAX_PAIRS then print(P .. "list is full (" .. MAX_PAIRS .. ").") return end
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
	db.pairs[#db.pairs + 1] = p
	print(P .. "created " .. name .. ". Click Pick up and drop it on your action bar.")
	AfterListChange()
end

local function RemovePair(i)
	if InCombatLockdown() then print(P .. "not in combat.") return end
	local p = db.pairs[i]
	if not p then return end
	local index = MacroIndex(MacroName(p))
	if index then DeleteMacro(index) end
	table.remove(db.pairs, i)
	if editor and editPair == p then editor:Hide() end
	print(P .. "deleted " .. MacroName(p) .. ".")
	AfterListChange()
end

-- Rewrite macro text that differs from Body(); also copies changes from the
-- player's own macros used as a side. Out of combat only.
local triedBody = {} -- macro name -> body already written (no edit loops)
local function FixBodies()
	if InCombatLockdown() then return end
	for _, p in ipairs(db.pairs) do
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
	if not db.migrated then
		for old, n in pairs(OLD_NAMES) do
			local index = MacroIndex(old)
			local p = OLD_PRESETS[n]
			if index then
				if not MacroIndex(MacroName(p)) then pcall(EditMacro, index, MacroName(p), nil, nil) end
				if not FindPair(p) then
					db.pairs[#db.pairs + 1] = { melee = p.melee, ranged = p.ranged, off = db.off and db.off[old] or nil }
				end
			end
		end
		db.off = nil
		db.migrated = true
	end
	if not db.nameV2 then
		for _, p in ipairs(db.pairs) do
			local index = MacroIndex(OldMacroName(p))
			if index and not MacroIndex(MacroName(p)) then
				pcall(EditMacro, index, MacroName(p), nil, nil)
			end
		end
		db.nameV2 = true
	end
end

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------

local panel = CreateFrame("Frame")
local category
local draft = {}   -- the two boxes: { ranged/rangedMacro = A, melee/meleeMacro = B }
local slots = {}   -- the two drop boxes
local rows = {}    -- "My keys" rows

local W = 660
local ROW_H = 26
local MIN_WIN_H = 300
local VISIBLE = 8 -- rows shown at once; more rows scroll
local LIST_W = W - 26 -- room for the scroll bar on the right
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local MACRO_TAG = " |cff888888(macro)|r"

local function Label(parent, template, text)
	local fs = parent:CreateFontString(nil, "ARTWORK", template)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	if text then fs:SetText(text) end
	return fs
end

local function Place(region, x, y)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
end

local function Tooltip(frame, title, text)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Section title with a thin line to the right edge. Returns the new y.
local function Section(text, y)
	local t = Label(panel, "GameFontNormal", text)
	Place(t, 0, y)
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.25)
	line:SetHeight(1)
	line:SetPoint("LEFT", t, "RIGHT", 8, 0)
	line:SetWidth(W - t:GetStringWidth() - 8)
	return y + 20
end

local function CheckBox(text, tip, x, y, onClick)
	local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	c:SetSize(26, 26)
	Place(c, x - 3, y)
	local t = Label(c, "GameFontHighlight", text)
	t:SetPoint("LEFT", c, "RIGHT", 2, 1)
	c:SetScript("OnClick", onClick)
	Tooltip(c, text, tip)
	return c
end

local function Button(parent, text, w, h, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, h)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- Spell tooltip, or the macro's text for a macro side.
local function SideTooltip(owner, p, side)
	local kind, v = Side(p, side)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if kind == "spell" then
		local id = SpellID(v)
		if not id then
			GameTooltip:AddLine(v)
			GameTooltip:AddLine("not learned", 1, 0.4, 0.4)
		else
			GameTooltip:SetSpellByID(id)
		end
	else
		GameTooltip:AddLine(v .. " (macro)")
		GameTooltip:AddLine(MacroLines(v) or "|cffff6060macro not found|r", 1, 1, 1, true)
	end
	GameTooltip:Show()
end

local function UpdateSlot(s)
	if draft[s.key] or draft[s.key .. "Macro"] then
		s.icon:SetTexture(SideIcon(draft, s.key) or QUESTION)
		s.icon:SetAlpha(1)
		s.text:SetText(SideLabel(draft, s.key))
		s.hint:SetText(draft[s.key .. "Macro"] and "macro" or "")
	else
		s.icon:SetTexture(EMPTY_SLOT)
		s.icon:SetAlpha(0.6)
		s.text:SetText("|cffaaaaaa" .. s.label .. "|r")
		s.hint:SetText("drag a skill or macro here")
	end
end

-- Opens the spellbook if it is not open yet (old and new spellbook UIs).
local function OpenSpellBook()
	if (SpellBookFrame and SpellBookFrame:IsShown())
		or (PlayerSpellsFrame and PlayerSpellsFrame:IsShown()) then return end
	if PlayerSpellsUtil and PlayerSpellsUtil.OpenToSpellBookTab then
		pcall(PlayerSpellsUtil.OpenToSpellBookTab)
	elseif ToggleSpellBook then
		pcall(ToggleSpellBook, BOOKTYPE_SPELL or "spell")
	end
end

-- A box that takes a skill (spellbook, action bar) or a macro (/macro).
local function DropSlot(key, label, x, y)
	local s = CreateFrame("Button", nil, panel)
	s:SetSize(40, 40)
	Place(s, x, y)
	s.key, s.label = key, label

	local edge = s:CreateTexture(nil, "BACKGROUND")
	edge:SetPoint("TOPLEFT", -1, 1)
	edge:SetPoint("BOTTOMRIGHT", 1, -1)
	edge:SetColorTexture(0.5, 0.5, 0.5, 0.8)
	local bg = s:CreateTexture(nil, "BORDER")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.8)
	s.icon = s:CreateTexture(nil, "ARTWORK")
	s.icon:SetAllPoints()
	s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	s.text = Label(s, "GameFontHighlight")
	s.text:SetPoint("TOPLEFT", s, "TOPRIGHT", 8, -6)
	s.text:SetWidth(150)
	s.hint = Label(s, "GameFontDisableSmall")
	s.hint:SetPoint("TOPLEFT", s.text, "BOTTOMLEFT", 0, -3)

	-- false = the cursor held no spell or macro
	local function accept()
		local kind, slot, book, id = GetCursorInfo()
		if kind == "spell" then
			local name = id and SpellName(id)
			if not name and slot and GetSpellBookItemName then name = GetSpellBookItemName(slot, book) end
			ClearCursor()
			if name then
				draft[key], draft[key .. "Macro"] = name, nil
				UpdateSlot(s)
			end
			return true
		elseif kind == "macro" then
			local name = GetMacroInfo(slot)
			ClearCursor()
			if name and IsOwnMacro(name) then
				print(P .. "that macro was made by this addon; use one of your own macros.")
			elseif name then
				draft[key], draft[key .. "Macro"] = nil, name
				UpdateSlot(s)
			end
			return true
		end
		return false
	end
	s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	s:SetScript("OnReceiveDrag", accept)
	s:SetScript("OnClick", function(_, button)
		if accept() then return end
		if button == "RightButton" then
			draft[key], draft[key .. "Macro"] = nil, nil
			UpdateSlot(s)
		else
			OpenSpellBook()
		end
	end)
	s:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(label)
		GameTooltip:AddLine("Drag a skill here from your spellbook or action bar, "
			.. "or one of your macros from the macro window (/macro).", 1, 1, 1, true)
		GameTooltip:AddLine("Left-click: open spellbook", 0.6, 0.8, 1)
		GameTooltip:AddLine("Right-click: clear", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	s:SetScript("OnLeave", function() GameTooltip:Hide() end)
	slots[#slots + 1] = s
	return s
end

local win -- the settings window

function Refresh()
	if not db or not panel:IsVisible() then return end
	panel.swap:SetChecked(db.swap)
	panel.names:SetChecked(db.names)
	panel.mm:SetChecked(not db.hideMinimap)
	panel.smart:SetChecked(db.smart)
	panel.errors:SetChecked(db.hideErrors)
	local combat = InCombatLockdown()
	panel.create:SetEnabled(not combat)
	for _, s in ipairs(slots) do UpdateSlot(s) end
	panel.empty:SetShown(#db.pairs == 0)

	local offset = 0
	if panel.scroll then
		FauxScrollFrame_Update(panel.scroll, #db.pairs, VISIBLE, ROW_H)
		offset = FauxScrollFrame_GetOffset(panel.scroll)
	else
		panel.offset = math.max(0, math.min(panel.offset or 0, #db.pairs - VISIBLE))
		offset = panel.offset
	end
	for n, r in ipairs(rows) do
		local i = offset + n
		local p = db.pairs[i]
		r.index = i
		r:SetShown(p ~= nil)
		if p then
			local exists = MacroIndex(MacroName(p)) ~= nil
			local known = SideKnown(p, A) and SideKnown(p, B)
			r.check:SetChecked(not p.off)
			r.check:SetEnabled(db.swap)
			r.name:SetText(MacroName(p))
			r.iconA.pair, r.iconB.pair = p, p
			r.iconA.tex:SetTexture(SideIcon(p, A) or QUESTION)
			r.iconB.tex:SetTexture(SideIcon(p, B) or QUESTION)
			r.textA:SetText(SideLabel(p, A) .. (p.rangedMacro and MACRO_TAG or ""))
			r.textB:SetText(SideLabel(p, B) .. (p.meleeMacro and MACRO_TAG or ""))
			if not exists then
				r.status:SetText("|cffff6060missing|r")
			elseif not known then
				r.status:SetText("|cffffcc00not learned|r")
			elseif db.smart and boundKeys[i] then
				r.status:SetText("|cff40ff40" .. boundKeys[i] .. "|r")
			elseif db.smart then
				r.status:SetText("|cffaaaaaanot on bar|r")
			else
				r.status:SetText("|cffff9900A only|r")
			end
			r.pickup:SetText(exists and "Pick up" or "Create")
			r.pickup:SetEnabled(not combat)
			r.remove:SetEnabled(not combat)
		end
	end
	if win then
		local listH = math.max(1, math.min(#db.pairs, VISIBLE)) * ROW_H
		win:SetHeight(math.max(MIN_WIN_H, panel.listTop + listH + 46))
	end
end

-- The "Now" icons change all the time; refreshed by the update ticker.
local function RefreshNow()
	if not win or not win:IsShown() then return end
	for _, r in ipairs(rows) do
		local p = r:IsShown() and db.pairs[r.index]
		if p then
			local side = shown[MacroName(p)] or A
			r.now.pair, r.now.side = p, side
			r.now.tex:SetTexture(SideIcon(p, side) or QUESTION)
		end
	end
end

local function BuildPanel()
	local y = 0

	local desc = Label(panel, "GameFontHighlightSmall",
		"Put two skills on one key. When you press it, skill |cffffd100A|r casts if it can be used; "
		.. "if not (out of range, on cooldown, no mana or rage...), skill |cffffd100B|r casts instead. "
		.. "The button icon always shows the skill that will cast.")
	desc:SetWordWrap(true)
	desc:SetWidth(W)
	Place(desc, 0, y)
	y = y + math.max(34, desc:GetStringHeight() + 10)

	-- Options: 2 columns
	y = Section("Options", y)
	local col2 = W / 2
	panel.swap = CheckBox("Show next skill on icon",
		"The macro icon shows the skill that will cast now: A when A can be used, else B.",
		0, y, function(self)
			db.swap = self:GetChecked() and true or false
			Update(true)
			Refresh()
		end)
	panel.names = CheckBox("Show skill name on buttons", "Write the next skill's name on the action button.",
		col2, y, function(self)
			db.names = self:GetChecked() and true or false
			Update(true)
		end)
	y = y + ROW_H
	panel.smart = CheckBox("Smart keys", "Key press tries A, key release tries B. Without it, a key "
		.. "only casts A (B only when B is off the global cooldown, like Raptor Strike).",
		0, y, function(self)
			if InCombatLockdown() then
				self:SetChecked(db.smart)
				print(P .. "not in combat.")
				return
			end
			db.smart = self:GetChecked() and true or false
			Rebind()
			Refresh()
		end)
	panel.mm = CheckBox("Minimap button", "Show the button on the minimap.",
		col2, y, function(self)
			db.hideMinimap = not self:GetChecked() or nil
			if panel.UpdateMinimap then panel.UpdateMinimap() end
		end)
	y = y + ROW_H
	panel.errors = CheckBox("Hide error text from these keys",
		"Each press has one skill that fails (\"Out of range\", \"Ability is not ready yet\"...). "
		.. "Hide those red messages. Other errors still show.",
		0, y, function(self)
			db.hideErrors = self:GetChecked() and true or false
			ApplyErrorFilter()
		end)
	y = y + ROW_H + 12

	-- New key: A box + B box + Create
	y = Section("New key", y)
	DropSlot(A, "Priority skill (A)", 0, y)
	local arrow = Label(panel, "GameFontNormal", "else  >")
	Place(arrow, 200, y + 13)
	DropSlot(B, "Fallback skill (B)", 250, y)
	panel.create = Button(panel, "Create", 100, 26, function() AddPair(draft) end)
	Place(panel.create, W - 100, y + 7)
	y = y + 48

	-- Presets for the player's class, 4 per row. Spell IDs -> names in the
	-- client's language; presets whose spells this client doesn't have are left out.
	local list = {}
	for _, pr in ipairs(PRESETS[CLASS] or {}) do
		local a, b = SpellName(pr.A), SpellName(pr.B)
		if a and b then list[#list + 1] = { A = a, B = b, why = pr.why } end
	end
	local className = (UnitClass("player")) or CLASS
	local presetLabel = Label(panel, "GameFontDisableSmall",
		#list > 0 and ("Presets for " .. className .. " (click to fill the boxes):") or "No presets for your class.")
	Place(presetLabel, 0, y)
	y = y + 16
	local gap, perRow = 6, 4
	local bw = (W - gap * (perRow - 1)) / perRow
	for i, pr in ipairs(list) do
		local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
		local b = Button(panel, Short(pr.A) .. " > " .. Short(pr.B), bw, 22, function()
			draft.ranged, draft.melee = pr.A, pr.B
			draft.rangedMacro, draft.meleeMacro = nil, nil
			Refresh()
		end)
		Tooltip(b, pr.A .. "  >  " .. pr.B, "A: " .. pr.A .. "\nB: " .. pr.B .. "\nB casts when: " .. pr.why)
		Place(b, col * (bw + gap), y + row * 26)
	end
	y = y + math.max(1, math.ceil(#list / perRow)) * 26 + 12

	-- My keys: column headers + rows
	y = Section("My keys", y)
	local X = { check = 0, name = 32, a = 146, b = 280, now = 414, key = 444, edit = 504, pickup = 550, remove = 612 }
	local heads = { { "On", X.check + 2 }, { "Macro", X.name }, { "Priority (A)", X.a },
		{ "Fallback (B)", X.b }, { "Now", X.now - 2 }, { "Key", X.key } }
	for _, h in ipairs(heads) do
		local t = Label(panel, "GameFontDisableSmall", h[1])
		Place(t, h[2], y)
	end
	y = y + 16
	panel.listTop = y

	panel.empty = Label(panel, "GameFontDisableSmall", "No keys yet. Fill both boxes above (or click a preset), then Create.")
	Place(panel.empty, X.name, y + 6)

	-- Scroll: VISIBLE rows are reused for the part of the list in view.
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", "AutoSkillSwapScroll", panel, "FauxScrollFrameTemplate")
	if ok and scroll then
		scroll:SetSize(LIST_W, VISIBLE * ROW_H)
		Place(scroll, 0, y)
		scroll:SetScript("OnVerticalScroll", function(self, value)
			FauxScrollFrame_OnVerticalScroll(self, value, ROW_H, Refresh)
		end)
		panel.scroll = scroll
	else -- no template: mouse wheel only
		local area = CreateFrame("Frame", nil, panel)
		area:SetSize(LIST_W, VISIBLE * ROW_H)
		Place(area, 0, y)
		area:EnableMouseWheel(true)
		area:SetScript("OnMouseWheel", function(_, delta)
			panel.offset = (panel.offset or 0) - delta
			Refresh()
		end)
	end

	local function IconCell(r, x)
		local icon = CreateFrame("Frame", nil, r)
		icon:SetSize(20, 20)
		icon:EnableMouse(true)
		icon:SetPoint("LEFT", x, 0)
		icon.tex = icon:CreateTexture(nil, "ARTWORK")
		icon.tex:SetAllPoints()
		icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return icon
	end

	for i = 1, VISIBLE do
		local r = CreateFrame("Frame", nil, panel)
		r:SetSize(LIST_W, ROW_H)
		Place(r, 0, y + (i - 1) * ROW_H)
		r:SetFrameLevel(panel:GetFrameLevel() + 5)

		if i % 2 == 0 then -- stripe every second row
			local stripe = r:CreateTexture(nil, "BACKGROUND")
			stripe:SetAllPoints()
			stripe:SetColorTexture(1, 1, 1, 0.04)
		end

		r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
		r.check:SetSize(24, 24)
		r.check:SetPoint("LEFT", X.check, 0)
		r.check:SetScript("OnClick", function(self)
			local p = db.pairs[r.index]
			if p then p.off = (not self:GetChecked()) or nil end
			Update(true)
		end)
		Tooltip(r.check, "Show next skill", "Off: the icon always shows A.")

		r.name = Label(r, "GameFontHighlightSmall")
		r.name:SetPoint("LEFT", X.name, 0)
		r.name:SetWidth(X.a - X.name - 6)

		r.iconA = IconCell(r, X.a)
		r.iconA:SetScript("OnEnter", function(self) if self.pair then SideTooltip(self, self.pair, A) end end)
		r.textA = Label(r, "GameFontHighlightSmall")
		r.textA:SetPoint("LEFT", r.iconA, "RIGHT", 5, 0)
		r.textA:SetWidth(X.b - X.a - 31)

		r.iconB = IconCell(r, X.b)
		r.iconB:SetScript("OnEnter", function(self) if self.pair then SideTooltip(self, self.pair, B) end end)
		r.textB = Label(r, "GameFontHighlightSmall")
		r.textB:SetPoint("LEFT", r.iconB, "RIGHT", 5, 0)
		r.textB:SetWidth(X.now - X.b - 31)

		r.now = IconCell(r, X.now)
		r.now:SetScript("OnEnter", function(self)
			if self.pair then SideTooltip(self, self.pair, self.side or A) end
		end)

		r.status = Label(r, "GameFontHighlightSmall")
		r.status:SetPoint("LEFT", X.key, 0)
		r.status:SetWidth(X.edit - X.key - 4)

		r.edit = Button(r, "Edit", X.pickup - X.edit - 4, 20, function()
			local p = db.pairs[r.index]
			if p and panel.OpenEditor then panel.OpenEditor(p) end
		end)
		r.edit:SetPoint("LEFT", X.edit, 0)
		r.edit:SetNormalFontObject("GameFontNormalSmall")
		r.edit:SetHighlightFontObject("GameFontHighlightSmall")
		Tooltip(r.edit, "Conditions", "When the icon shows B, and when to always use A or B.")

		r.pickup = Button(r, "Pick up", X.remove - X.pickup - 4, 20, function()
			local p = db.pairs[r.index]
			if not p or InCombatLockdown() then return end
			local index = MacroIndex(MacroName(p))
			if index then
				PickupMacro(index)
			else
				pcall(CreateMacro, MacroName(p), "INV_MISC_QUESTIONMARK", Body(p), true)
				AfterListChange()
			end
		end)
		r.pickup:SetPoint("LEFT", X.pickup, 0)
		r.pickup:SetNormalFontObject("GameFontNormalSmall")
		r.pickup:SetHighlightFontObject("GameFontHighlightSmall")
		Tooltip(r.pickup, "Pick up", "Put the macro on your cursor, then drop it on an action bar.")

		r.remove = Button(r, "X", LIST_W - X.remove, 20, function() RemovePair(r.index) end)
		r.remove:SetPoint("LEFT", X.remove, 0)
		Tooltip(r.remove, "Delete this key and its macro")

		rows[i] = r
	end

	panel:SetScript("OnShow", Refresh)
end

-- Own movable window (not the Options screen), so it stays open next to
-- the spellbook while you drag skills into it.
local function BuildWindow()
	local name = "AutoSkillSwapWindow"
	local ok, w = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplateWithInset")
	if not ok then
		w = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
		w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 } })
		local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
	end
	w:SetSize(W + 28, 500) -- height is set by Refresh()
	w:SetFrameStrata("HIGH")
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.winPos = { point, relPoint, x, y }
	end)
	if db.winPos then
		w:SetPoint(db.winPos[1], UIParent, db.winPos[2], db.winPos[3], db.winPos[4])
	else
		w:SetPoint("CENTER", 250, 0) -- right of center: the spellbook opens on the left
	end
	w:Hide()
	tinsert(UISpecialFrames, name) -- Esc closes it

	local title = Label(w, "GameFontHighlight", TITLE)
	title:SetPoint("TOP", 0, -5)

	panel:SetParent(w)
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", 14, -32)
	panel:SetPoint("BOTTOMRIGHT", -14, 12)
	panel:Show()
	w:SetScript("OnShow", function() Refresh() RefreshNow() end)
	win = w

	-- Options > AddOns entry: one button that opens the window.
	local stub = CreateFrame("Frame")
	local t = Label(stub, "GameFontNormalLarge", TITLE)
	t:SetPoint("TOPLEFT", 16, -16)
	local open = CreateFrame("Button", nil, stub, "UIPanelButtonTemplate")
	open:SetSize(200, 26)
	open:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
	open:SetText("Open settings window")
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		win:Show()
	end)
	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(stub, TITLE)
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		stub.name = TITLE
		InterfaceOptions_AddCategory(stub)
	end
end

-- Per-key settings, opened with a row's Edit button. Sits to the right of
-- the main window.
local function BuildEditor()
	local name = "AutoSkillSwapEditor"
	local ok, e = pcall(CreateFrame, "Frame", name, win, "BasicFrameTemplateWithInset")
	if not ok then
		e = CreateFrame("Frame", name, win, "BackdropTemplate")
		e:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 } })
		local close = CreateFrame("Button", nil, e, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", -2, -2)
	end
	e:SetSize(300, 330)
	e:SetPoint("TOPLEFT", win, "TOPRIGHT", 2, 0)
	e:EnableMouse(true)
	e:Hide()
	editor = e

	e.title = Label(e, "GameFontHighlight", "")
	e.title:SetPoint("TOP", 0, -5)

	local function changed()
		FixBodies()
		Rebind()
		wipe(shown)
		Update(true)
		Refresh()
	end

	-- 1. which checks switch the icon to B
	local h1 = Label(e, "GameFontNormal", "Icon shows B when A is:")
	h1:SetPoint("TOPLEFT", 16, -34)
	local checks = {
		{ key = "noRange",    text = "out of range" },
		{ key = "noCooldown", text = "on cooldown" },
		{ key = "noUsable",   text = "not usable (mana, proc, target health)" },
	}
	e.checks = {}
	for i, c in ipairs(checks) do
		local cb = CreateFrame("CheckButton", nil, e, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", -4, -2 - (i - 1) * 22)
		local t = Label(cb, "GameFontHighlightSmall", c.text)
		t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
		cb:SetScript("OnClick", function(self)
			if editPair then editPair[c.key] = (not self:GetChecked()) or nil end
			changed()
		end)
		cb.key = c.key
		e.checks[i] = cb
	end
	local note1 = Label(e, "GameFontDisableSmall", "Only the icon. The game still decides if A casts.")
	note1:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -72)

	-- 2. "Always use A / B when": a button that cycles the conditions,
	--    plus a text box for a custom macro condition
	local function CondIndex(cond)
		if not cond then return 1 end
		for i, c in ipairs(CONDITIONS) do
			if c.cond == cond then return i end
		end
		return #CONDITIONS -- custom
	end
	local function CondControl(text, field, y)
		local t = Label(e, "GameFontNormal", text)
		t:SetPoint("TOPLEFT", 16, -y)
		local b = Button(e, "", 200, 22)
		b:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local box = CreateFrame("EditBox", nil, e, "InputBoxTemplate")
		box:SetSize(190, 20)
		box:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 6, -4)
		box:SetAutoFocus(false)
		box:Hide()
		local ctl = { mode = 1 }
		local function show(mode)
			ctl.mode = mode
			local c = CONDITIONS[mode]
			b:SetText(c.label)
			box:SetShown(c.custom or false)
		end
		function ctl.Load(p)
			show(CondIndex(p[field]))
			box:SetText(CONDITIONS[ctl.mode].custom and (p[field] or "") or "")
		end
		b:SetScript("OnClick", function(_, button)
			if not editPair then return end
			local n = #CONDITIONS
			show((ctl.mode + (button == "RightButton" and -2 or 0)) % n + 1)
			local c = CONDITIONS[ctl.mode]
			if c.custom then
				box:SetText("")
				box:SetFocus()
				editPair[field] = nil
			else
				editPair[field] = c.cond
			end
			changed()
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(text)
			GameTooltip:AddLine("Left-click: next, right-click: previous.", 1, 1, 1)
			GameTooltip:AddLine("Shift/Ctrl/Alt only work when that key combination "
				.. "is not bound to something else.", 0.6, 0.8, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		box:SetScript("OnEnterPressed", function(self)
			local cond = NormalizeCond(self:GetText())
			if self:GetText() ~= "" and not cond then
				print(P .. "that is not a valid macro condition, e.g. [mod:shift] or [@focus,exists].")
			end
			if editPair then editPair[field] = cond end
			self:SetText(cond or "")
			self:ClearFocus()
			changed()
		end)
		box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		return ctl
	end
	e.condA = CondControl("Always use A when:", "forceA", 150)
	e.condB = CondControl("Always use B when:", "forceB", 220)
	local note2 = Label(e, "GameFontDisableSmall", "Works in combat. Custom: a macro condition, e.g. [@focus,exists]")
	note2:SetPoint("BOTTOMLEFT", 16, 14)
	note2:SetWidth(270)
	note2:SetWordWrap(true)
end

function panel.OpenEditor(p)
	if not editor then return end
	if editor:IsShown() and editPair == p then editor:Hide() return end
	editPair = p
	editor.title:SetText(MacroName(p))
	for _, cb in ipairs(editor.checks) do cb:SetChecked(not p[cb.key]) end
	editor.condA.Load(p)
	editor.condB.Load(p)
	editor:Show()
end

local function OpenSettings()
	if not win then return end
	win:SetShown(not win:IsShown())
end

---------------------------------------------------------------------------
-- Minimap button: left-click = settings, right-click = "show next skill"
-- on/off, drag = move around the minimap (round or square minimap).
---------------------------------------------------------------------------

local mmButton

local function PlaceMinimapButton()
	local a = math.rad(db.minimapAngle or 225)
	local x, y = math.cos(a), math.sin(a)
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		x = math.max(-1, math.min(1, x * 1.42))
		y = math.max(-1, math.min(1, y * 1.42))
	end
	local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
	mmButton:ClearAllPoints()
	mmButton:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function UpdateMinimap()
	if not mmButton then return end
	mmButton:SetShown(not db.hideMinimap)
	PlaceMinimapButton()
end
panel.UpdateMinimap = UpdateMinimap

local function MinimapClick(button)
	if button == "RightButton" then
		db.swap = not db.swap
		print(P .. "show next skill on icon: " .. (db.swap and "ON" or "OFF"))
		Update(true)
		Refresh()
	else
		OpenSettings()
	end
end

local function MinimapTooltip(tt)
	tt:AddLine(TITLE)
	tt:AddLine("Show next skill: " .. (db.swap and "|cff40ff40ON|r" or "|cffff6060OFF|r"), 1, 1, 1)
	tt:AddLine("Left-click: settings", 0.6, 0.8, 1)
	tt:AddLine("Right-click: show next skill on/off", 0.6, 0.8, 1)
end

-- Own button, only used when LibDBIcon is missing.
local function BuildCustomMinimapButton()
	local b = CreateFrame("Button", "AutoSkillSwapMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -5)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Key_03")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			db.swap = not db.swap
			print(P .. "show next skill on icon: " .. (db.swap and "ON" or "OFF"))
			Update(true)
			Refresh()
		else
			OpenSettings()
		end
	end)

	local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			db.minimapAngle = math.deg(atan2(py / s - my, px / s - mx))
			PlaceMinimapButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(TITLE)
		GameTooltip:AddLine("Show next skill: " .. (db.swap and "|cff40ff40ON|r" or "|cffff6060OFF|r"), 1, 1, 1)
		GameTooltip:AddLine("Left-click: settings", 0.6, 0.8, 1)
		GameTooltip:AddLine("Right-click: show next skill on/off", 0.6, 0.8, 1)
		GameTooltip:AddLine("Drag: move", 0.6, 0.8, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	mmButton = b
	UpdateMinimap()
end

-- LibDBIcon button: the standard minimap button, so minimap button
-- collectors (Leatrix Plus addon button menu, Bazooka...) pick it up.
local function BuildMinimapButton()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (LDB and DBI) then
		BuildCustomMinimapButton()
		return
	end
	-- the old own button's angle becomes the LibDBIcon position
	db.minimap = db.minimap or { minimapPos = db.minimapAngle or 225 }
	db.minimap.hide = db.hideMinimap or nil
	local obj = LDB:NewDataObject("AutoSkillSwap", {
		type = "launcher",
		text = TITLE,
		icon = "Interface\\Icons\\INV_Misc_Key_03",
		OnClick = function(_, button) MinimapClick(button) end,
		OnTooltipShow = function(tt) MinimapTooltip(tt) end,
	})
	DBI:Register("AutoSkillSwap", obj, db.minimap)
	panel.UpdateMinimap = function()
		db.minimap.hide = db.hideMinimap or nil
		if db.hideMinimap then DBI:Hide("AutoSkillSwap") else DBI:Show("AutoSkillSwap") end
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

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
		db = AutoSkillSwapDB
		if db.swap == nil then db.swap = true end
		if db.names == nil then db.names = true end
		if db.smart == nil then db.smart = true end
		if db.hideErrors == nil then db.hideErrors = true end
		db.pairs = db.pairs or {}
		BuildPanel()
		BuildWindow()
		BuildEditor()
		BuildMinimapButton()
		ApplyErrorFilter()
	elseif not db then
		return
	elseif event == "UI_ERROR_MESSAGE" then
		-- only when hideErrors took the event away from UIErrorsFrame:
		-- pass on every error that is not right after one of our keys
		if db.hideErrors and GetTime() - lastPress > 0.5 and UIErrorsFrame then
			local handler = UIErrorsFrame:GetScript("OnEvent")
			if handler then handler(UIErrorsFrame, event, ...) end
		end
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
		if GetTime() - lastBind > 1 then QueueRebind() end
	else -- combat start/end
		if event == "PLAYER_REGEN_ENABLED" then
			Migrate()
			FixBodies()
			if pendingBind then Rebind() end
		end
		Refresh()
	end
end)

-- /skillswap or /sswap : open settings.  /skillswap debug : print what the addon sees.
SLASH_AUTOSKILLSWAP1 = "/skillswap"
SLASH_AUTOSKILLSWAP2 = "/sswap"
SlashCmdList.AUTOSKILLSWAP = function(msg)
	if (msg or ""):lower():match("debug") then
		print(P .. "class " .. tostring(CLASS) .. ", target in melee: " .. tostring(TargetInMelee()))
		for i, p in ipairs(db.pairs) do
			local a = SideSpell(p, A)
			print(P .. MacroName(p) .. ": macro " .. tostring(MacroIndex(MacroName(p)))
				.. ", key " .. tostring(boundKeys[i]) .. ", A can cast " .. tostring(CanCast(a))
				.. ", now " .. tostring(shown[MacroName(p)]))
		end
		wipe(failed)
		Update(true)
		return
	end
	OpenSettings()
end
