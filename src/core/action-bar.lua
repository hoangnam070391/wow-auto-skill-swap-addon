-- Icon + button name: the macro icon and the action button name show the
-- skill that will cast now.

local _, ns = ...

local A, P = ns.A, ns.PREFIX
local MacroIndex, MacroName, SideShort = ns.MacroIndex, ns.MacroName, ns.SideShort
local SideSpell, NowSide = ns.SideSpell, ns.NowSide

local shown = {}  -- macro name -> side shown now
local failed = {} -- macro name -> error already printed

local buttons = {}
local collected = false
local function CollectButtons()
	wipe(buttons)
	collected = true
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
	if not collected then CollectButtons() end
	local text = {}
	for _, p in ipairs(ns.db.pairs) do
		local name = MacroName(p)
		text[name] = SideShort(p, shown[name] or A)
	end
	for _, b in ipairs(buttons) do
		local slot = b.action
		if type(slot) == "number" then
			local macro = GetActionText(slot)
			local want = macro and text[macro]
			if want then
				if not ns.db.names then want = macro end
				if b.Name:GetText() ~= want then b.Name:SetText(want) end
			end
		end
	end
end

local function Update(force)
	if not ns.db then return end
	for _, p in ipairs(ns.db.pairs) do
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

-- All action buttons with a key binding command, collected once.
local function GetActionButtons()
	if not collected then CollectButtons() end
	return buttons
end

ns.shown = shown
ns.failed = failed
ns.CollectButtons = CollectButtons
ns.GetActionButtons = GetActionButtons
ns.Update = Update
