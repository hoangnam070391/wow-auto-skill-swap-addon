-- Minimap button: left-click = settings, right-click = "show next skill"
-- on/off, drag = move around the minimap (round or square minimap).

local _, ns = ...

local TITLE, P = ns.TITLE, ns.PREFIX
local Update, Refresh, OpenSettings = ns.Update, ns.Refresh, ns.OpenSettings

local mmButton

local function PlaceMinimapButton()
	local a = math.rad(ns.db.minimapAngle or 225)
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
	mmButton:SetShown(not ns.db.hideMinimap)
	PlaceMinimapButton()
end
ns.UpdateMinimap = UpdateMinimap

local function MinimapClick(button)
	if button == "RightButton" then
		ns.db.swap = not ns.db.swap
		print(P .. "show next skill on icon: " .. (ns.db.swap and "ON" or "OFF"))
		Update(true)
		Refresh()
	else
		OpenSettings()
	end
end

local function MinimapTooltip(tt)
	tt:AddLine(TITLE)
	tt:AddLine("Show next skill: " .. (ns.db.swap and "|cff40ff40ON|r" or "|cffff6060OFF|r"), 1, 1, 1)
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
			ns.db.swap = not ns.db.swap
			print(P .. "show next skill on icon: " .. (ns.db.swap and "ON" or "OFF"))
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
			ns.db.minimapAngle = math.deg(atan2(py / s - my, px / s - mx))
			PlaceMinimapButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(TITLE)
		GameTooltip:AddLine("Show next skill: " .. (ns.db.swap and "|cff40ff40ON|r" or "|cffff6060OFF|r"), 1, 1, 1)
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
	ns.db.minimap = ns.db.minimap or { minimapPos = ns.db.minimapAngle or 225 }
	ns.db.minimap.hide = ns.db.hideMinimap or nil
	local obj = LDB:NewDataObject("AutoSkillSwap", {
		type = "launcher",
		text = TITLE,
		icon = "Interface\\Icons\\INV_Misc_Key_03",
		OnClick = function(_, button) MinimapClick(button) end,
		OnTooltipShow = function(tt) MinimapTooltip(tt) end,
	})
	DBI:Register("AutoSkillSwap", obj, ns.db.minimap)
	ns.UpdateMinimap = function()
		ns.db.minimap.hide = ns.db.hideMinimap or nil
		if ns.db.hideMinimap then DBI:Hide("AutoSkillSwap") else DBI:Show("AutoSkillSwap") end
	end
end

ns.BuildMinimapButton = BuildMinimapButton
