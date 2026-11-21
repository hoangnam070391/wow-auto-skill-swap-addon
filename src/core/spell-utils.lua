-- Spell and macro helpers: names, icons, range, cooldown and "can cast now".

local _, ns = ...

local CLASS, MELEE_TEST = ns.CLASS, ns.MELEE_TEST

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

ns.IsSecret = IsSecret
ns.Short = Short
ns.MacroIndex = MacroIndex
ns.SpellName = SpellName
ns.SpellTexture = SpellTexture
ns.SpellInfo = SpellInfo
ns.SpellID = SpellID
ns.SpellKnown = SpellKnown
ns.InRange = InRange
ns.TargetInMelee = TargetInMelee
ns.CanCast = CanCast
