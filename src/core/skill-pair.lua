-- A pair is one key: side A (priority) and side B (fallback). Each side is a
-- spell or one of the player's own macros.
--
-- Data: a pair p keeps the field names of version 1 so saved data still
-- works: p.ranged / p.rangedMacro = side A (priority),
--        p.melee  / p.meleeMacro  = side B (fallback).

local _, ns = ...

local A, B = ns.A, ns.B
local Short, MacroIndex, SpellName = ns.Short, ns.MacroIndex, ns.SpellName
local SpellTexture, SpellKnown, CanCast = ns.SpellTexture, ns.SpellKnown, ns.CanCast

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
	for i, p in ipairs(ns.db.pairs) do
		if p.melee == d.melee and p.ranged == d.ranged
			and p.meleeMacro == d.meleeMacro and p.rangedMacro == d.rangedMacro then
			return i
		end
	end
end

local function IsOwnMacro(name)
	for _, p in ipairs(ns.db.pairs) do
		if MacroName(p) == name then return true end
	end
	return false
end

-- The side that will cast now: "Always use" conditions first, then A when
-- A can be cast (with the checks the pair has turned on), else B.
local function NowSide(p)
	if CondTrue(p.forceA) then return A end
	if CondTrue(p.forceB) then return B end
	if not ns.db.swap or p.off then return A end
	return CanCast(SideSpell(p, A), p) and A or B
end

ns.Side = Side
ns.MacroLines = MacroLines
ns.SideLabel = SideLabel
ns.SideShort = SideShort
ns.SideSpell = SideSpell
ns.SideIcon = SideIcon
ns.SideKnown = SideKnown
ns.MacroName = MacroName
ns.OldMacroName = OldMacroName
ns.Body = Body
ns.NormalizeCond = NormalizeCond
ns.FindPair = FindPair
ns.IsOwnMacro = IsOwnMacro
ns.NowSide = NowSide
