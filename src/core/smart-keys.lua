-- Smart keys: the key of an action button that holds one of our macros is
-- bound (override binding, out of combat) to a hidden secure button.
-- Key down tries side A, key up tries side B.

local _, ns = ...

local A, B = ns.A, ns.B
local Side, MacroLines, MacroName = ns.Side, ns.MacroLines, ns.MacroName
local GetActionButtons = ns.GetActionButtons

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

-- Every slot main bar button i can show: pages 1-6, stance bars 1-4, possess.
local function MainBarSlots(i)
	local list = { i }
	for page = 2, 6 do list[#list + 1] = (page - 1) * 12 + i end
	for k = 1, 5 do list[#list + 1] = 72 + (k - 1) * 12 + i end
	return list
end

-- A key button serves one action button. For each slot that holds one of
-- our macros it keeps "mri-s<slot>-..." attributes, so in combat the key
-- follows page and stance changes on its own:
-- 1. Find the slot the bar shows now. Not one of ours: act as that action
--    slot (key down only).
-- 2. "Always use A/B when" (macro conditions): that side on key down,
--    nothing on key up.
-- 3. Else key down -> side A ("ranged"), key up -> side B ("melee").
-- A side is a spell (type "spell") or macro text (type "macro").
for i = 1, KEY_BUTTONS do
	local b = CreateFrame("Button", "AutoSkillSwapKey" .. i, UIParent, "SecureActionButtonTemplate")
	b:Hide()
	b:RegisterForClicks("AnyDown", "AnyUp")
	b:SetAttribute("type", "spell")
	keyHeader:WrapScript(b, "OnClick", [[
		local slot = self:GetAttribute("mri-slot")
		local slotCond = self:GetAttribute("mri-slotcond")
		if slotCond then
			slot = tonumber(SecureCmdOptionParse(slotCond)) or slot
		end
		self:SetAttribute("useOnKeyDown", down and true or false)
		local key = "mri-s" .. tostring(slot) .. "-"
		if not self:GetAttribute(key .. "on") then
			if down then
				self:SetAttribute("type", "action")
				self:SetAttribute("action", slot)
			else
				self:SetAttribute("type", nil)
			end
			return
		end
		local forced
		local fa = self:GetAttribute(key .. "forceA")
		local fb = self:GetAttribute(key .. "forceB")
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
		if side then
			self:SetAttribute("type", self:GetAttribute(key .. side .. "-type") or "spell")
			self:SetAttribute("spell", self:GetAttribute(key .. side))
			self:SetAttribute("macrotext", self:GetAttribute(key .. side .. "-text"))
		else
			self:SetAttribute("type", nil)
		end
	]])
	b:HookScript("PreClick", function() lastPress = GetTime() end)
	b.mriSlots = {} -- slots whose attributes are set on this button
	keyButtons[i] = b
end

-- Write (or clear, p = nil) the attributes of one slot on a key button.
local function SetSlotAttributes(kb, slot, p)
	local key = "mri-s" .. slot .. "-"
	kb:SetAttribute(key .. "on", p and true or nil)
	for _, side in ipairs({ A, B }) do
		local kind, v
		if p then kind, v = Side(p, side) end
		kb:SetAttribute(key .. side .. "-type", kind == "macro" and "macro" or (p and "spell" or nil))
		kb:SetAttribute(key .. side, kind == "spell" and v or nil)
		kb:SetAttribute(key .. side .. "-text", kind == "macro" and MacroLines(v) or nil)
	end
	kb:SetAttribute(key .. "forceA", p and p.forceA or nil)
	kb:SetAttribute(key .. "forceB", p and p.forceB or nil)
end

local function Rebind()
	if InCombatLockdown() then pendingBind = true return end
	pendingBind = false
	lastBind = GetTime()
	ClearOverrideBindings(keyOwner)
	wipe(boundKeys)
	for _, kb in ipairs(keyButtons) do
		for slot in pairs(kb.mriSlots) do SetSlotAttributes(kb, slot, nil) end
		wipe(kb.mriSlots)
	end
	if not ns.db.smart then return end
	local byName = {}
	for i, p in ipairs(ns.db.pairs) do byName[MacroName(p)] = i end
	local used = 0
	for _, b in ipairs(GetActionButtons()) do
		local keys = b.mriCommand and { GetBindingKey(b.mriCommand) } or {}
		local slots = b.mriMain and MainBarSlots(b.mriIndex) or { b.action }
		-- slots of this button that hold one of our macros
		local hits = {}
		for _, slot in ipairs(slots) do
			local i = type(slot) == "number" and byName[GetActionText(slot) or ""]
			if i then hits[slot] = i end
		end
		if next(hits) and #keys > 0 and used < KEY_BUTTONS then
			used = used + 1
			local kb = keyButtons[used]
			for slot, i in pairs(hits) do
				SetSlotAttributes(kb, slot, ns.db.pairs[i])
				kb.mriSlots[slot] = true
			end
			kb:SetAttribute("mri-slot", b.action)
			kb:SetAttribute("mri-slotcond", b.mriMain and MainBarSlotCond(b.mriIndex) or nil)
			for _, key in ipairs(keys) do
				SetOverrideBindingClick(keyOwner, true, key, kb:GetName(), "LeftButton")
			end
			local keyText = table.concat(keys, ", ")
			for _, i in pairs(hits) do
				if not (boundKeys[i] or ""):find(keyText, 1, true) then
					boundKeys[i] = boundKeys[i] and (boundKeys[i] .. ", " .. keyText) or keyText
				end
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
		if ns.Refresh then ns.Refresh() end
	end)
end

local function RebindIfPending()
	if pendingBind then Rebind() end
end

ns.boundKeys = boundKeys
ns.Rebind = Rebind
ns.QueueRebind = QueueRebind
ns.RebindIfPending = RebindIfPending
ns.LastBindTime = function() return lastBind end
ns.LastKeyPressTime = function() return lastPress end
