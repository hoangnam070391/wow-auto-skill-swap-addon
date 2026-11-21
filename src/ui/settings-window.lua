-- Settings window: options, the A/B drop boxes, class presets and the
-- "My keys" list. Own movable window (not the Options screen), so it stays
-- open next to the spellbook while you drag skills into it.

local _, ns = ...

local TITLE, P, A, B = ns.TITLE, ns.PREFIX, ns.A, ns.B
local CLASS, PRESETS = ns.CLASS, ns.PRESETS
local Short, SpellName, SpellID, MacroIndex = ns.Short, ns.SpellName, ns.SpellID, ns.MacroIndex
local Side, MacroLines, SideIcon, SideLabel = ns.Side, ns.MacroLines, ns.SideIcon, ns.SideLabel
local SideKnown, MacroName, Body, IsOwnMacro = ns.SideKnown, ns.MacroName, ns.Body, ns.IsOwnMacro
local shown, Update, Rebind, boundKeys = ns.shown, ns.Update, ns.Rebind, ns.boundKeys
local ApplyErrorFilter = ns.ApplyErrorFilter
local AddPair, RemovePair, AfterListChange = ns.AddPair, ns.RemovePair, ns.AfterListChange

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

local function Refresh()
	if not ns.db or not panel:IsVisible() then return end
	panel.swap:SetChecked(ns.db.swap)
	panel.names:SetChecked(ns.db.names)
	panel.mm:SetChecked(not ns.db.hideMinimap)
	panel.smart:SetChecked(ns.db.smart)
	panel.errors:SetChecked(ns.db.hideErrors)
	local combat = InCombatLockdown()
	panel.create:SetEnabled(not combat)
	for _, s in ipairs(slots) do UpdateSlot(s) end
	panel.empty:SetShown(#ns.db.pairs == 0)

	local offset = 0
	if panel.scroll then
		FauxScrollFrame_Update(panel.scroll, #ns.db.pairs, VISIBLE, ROW_H)
		offset = FauxScrollFrame_GetOffset(panel.scroll)
	else
		panel.offset = math.max(0, math.min(panel.offset or 0, #ns.db.pairs - VISIBLE))
		offset = panel.offset
	end
	for n, r in ipairs(rows) do
		local i = offset + n
		local p = ns.db.pairs[i]
		r.index = i
		r:SetShown(p ~= nil)
		if p then
			local exists = MacroIndex(MacroName(p)) ~= nil
			local known = SideKnown(p, A) and SideKnown(p, B)
			r.check:SetChecked(not p.off)
			r.check:SetEnabled(ns.db.swap)
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
			elseif ns.db.smart and boundKeys[i] then
				r.status:SetText("|cff40ff40" .. boundKeys[i] .. "|r")
			elseif ns.db.smart then
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
		local listH = math.max(1, math.min(#ns.db.pairs, VISIBLE)) * ROW_H
		win:SetHeight(math.max(MIN_WIN_H, panel.listTop + listH + 46))
	end
end

-- The "Now" icons change all the time; refreshed by the update ticker.
local function RefreshNow()
	if not win or not win:IsShown() then return end
	for _, r in ipairs(rows) do
		local p = r:IsShown() and ns.db.pairs[r.index]
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
			ns.db.swap = self:GetChecked() and true or false
			Update(true)
			Refresh()
		end)
	panel.names = CheckBox("Show skill name on buttons", "Write the next skill's name on the action button.",
		col2, y, function(self)
			ns.db.names = self:GetChecked() and true or false
			Update(true)
		end)
	y = y + ROW_H
	panel.smart = CheckBox("Smart keys", "Key press tries A, key release tries B. Without it, a key "
		.. "only casts A (B only when B is off the global cooldown, like Raptor Strike).",
		0, y, function(self)
			if InCombatLockdown() then
				self:SetChecked(ns.db.smart)
				print(P .. "not in combat.")
				return
			end
			ns.db.smart = self:GetChecked() and true or false
			Rebind()
			Refresh()
		end)
	panel.mm = CheckBox("Minimap button", "Show the button on the minimap.",
		col2, y, function(self)
			ns.db.hideMinimap = not self:GetChecked() or nil
			if ns.UpdateMinimap then ns.UpdateMinimap() end
		end)
	y = y + ROW_H
	panel.errors = CheckBox("Hide error text from these keys",
		"Each press has one skill that fails (\"Out of range\", \"Ability is not ready yet\"...). "
		.. "Hide those red messages. Other errors, like \"Not enough mana\", still show.",
		0, y, function(self)
			ns.db.hideErrors = self:GetChecked() and true or false
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
			local p = ns.db.pairs[r.index]
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
			local p = ns.db.pairs[r.index]
			if p then ns.OpenEditor(p) end
		end)
		r.edit:SetPoint("LEFT", X.edit, 0)
		r.edit:SetNormalFontObject("GameFontNormalSmall")
		r.edit:SetHighlightFontObject("GameFontHighlightSmall")
		Tooltip(r.edit, "Conditions", "When the icon shows B, and when to always use A or B.")

		r.pickup = Button(r, "Pick up", X.remove - X.pickup - 4, 20, function()
			local p = ns.db.pairs[r.index]
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
		ns.db.winPos = { point, relPoint, x, y }
	end)
	if ns.db.winPos then
		w:SetPoint(ns.db.winPos[1], UIParent, ns.db.winPos[2], ns.db.winPos[3], ns.db.winPos[4])
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
	return w
end

local function OpenSettings()
	if not win then return end
	win:SetShown(not win:IsShown())
end

ns.Label = Label
ns.Button = Button
ns.Refresh = Refresh
ns.RefreshNow = RefreshNow
ns.BuildPanel = BuildPanel
ns.BuildWindow = BuildWindow
ns.OpenSettings = OpenSettings
