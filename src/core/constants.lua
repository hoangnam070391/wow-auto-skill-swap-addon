-- Constants and static data: class presets, version 1 macro names and the
-- "Always use A / B when" conditions.

local _, ns = ...

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

-- Hunter melee skills (spell IDs): Raptor Strike, Mongoose Bite, Wing Clip,
-- Counterattack.
local HUNTER_MELEE = { 2973, 1495, 2974, 19306 }

ns.TITLE = TITLE
ns.PREFIX = P
ns.INTERVAL = INTERVAL
ns.MAX_PAIRS = MAX_PAIRS
ns.A, ns.B = A, B
ns.CLASS = CLASS
ns.PRESETS = PRESETS
ns.OLD_PRESETS = OLD_PRESETS
ns.OLD_NAMES = OLD_NAMES
ns.CONDITIONS = CONDITIONS
ns.MELEE_TEST = MELEE_TEST
ns.HUNTER_MELEE = HUNTER_MELEE
