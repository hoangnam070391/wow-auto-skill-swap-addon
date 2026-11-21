-- Per-key settings, opened with a row's Edit button. Sits to the right of
-- the main window.

local _, ns = ...

local P, CONDITIONS = ns.PREFIX, ns.CONDITIONS
local MacroName, NormalizeCond = ns.MacroName, ns.NormalizeCond
local FixBodies, Rebind, shown, Update = ns.FixBodies, ns.Rebind, ns.shown, ns.Update
local Refresh, Label, Button = ns.Refresh, ns.Label, ns.Button

local editor, editPair -- the panel and the pair it shows

local function BuildEditor(win)
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

local function OpenEditor(p)
	if not editor then return end
	if editor:IsShown() and editPair == p then editor:Hide() return end
	editPair = p
	editor.title:SetText(MacroName(p))
	for _, cb in ipairs(editor.checks) do cb:SetChecked(not p[cb.key]) end
	editor.condA.Load(p)
	editor.condB.Load(p)
	editor:Show()
end

-- Hide the editor when it shows pair p (p was deleted).
local function CloseEditorFor(p)
	if editor and editPair == p then editor:Hide() end
end

ns.BuildEditor = BuildEditor
ns.OpenEditor = OpenEditor
ns.CloseEditorFor = CloseEditorFor
