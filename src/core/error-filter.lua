-- Hides the red error text of the side that did not cast.

local _, ns = ...

local IsSecret = ns.IsSecret

-- Error filter: every press has one side that fails ("Out of range",
-- "Ability is not ready yet"...). With hideErrors on, UIErrorsFrame stops
-- listening and we pass on every error except these expected ones right
-- after one of our keys. "Not enough mana/rage" and the like still show.
local EXPECTED_ERRORS = {}
for _, name in ipairs({
	"SPELL_FAILED_OUT_OF_RANGE", "ERR_OUT_OF_RANGE", "SPELL_FAILED_TOO_CLOSE",
	"SPELL_FAILED_NOT_READY", "ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN",
	"ERR_GENERIC_NO_TARGET", "SPELL_FAILED_SPELL_IN_PROGRESS",
	"SPELL_FAILED_TARGET_AURASTATE", "SPELL_FAILED_CASTER_AURASTATE",
	"SPELL_FAILED_UNIT_NOT_INFRONT", "ERR_BADATTACKFACING", "ERR_BADATTACKPOS",
	"SPELL_FAILED_NOT_BEHIND",
}) do
	local text = _G[name]
	if type(text) == "string" then EXPECTED_ERRORS[text] = true end
end

local function IsExpectedError(message)
	if IsSecret(message) then return true end -- can't read it: treat as ours
	return type(message) == "string" and EXPECTED_ERRORS[message] or false
end

local function ApplyErrorFilter()
	if not UIErrorsFrame then return end
	if ns.db.hideErrors then
		UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
	else
		UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
	end
end

-- UI_ERROR_MESSAGE, only when hideErrors took the event away from
-- UIErrorsFrame: drop the expected range/cooldown errors right after one of
-- our keys, pass on everything else (e.g. "Not enough mana").
local function OnErrorMessage(event, ...)
	if not ns.db.hideErrors or not UIErrorsFrame then return end
	local ours = GetTime() - ns.LastKeyPressTime() <= 0.5 and IsExpectedError(select(2, ...))
	if not ours then
		local handler = UIErrorsFrame:GetScript("OnEvent")
		if handler then handler(UIErrorsFrame, event, ...) end
	end
end

ns.ApplyErrorFilter = ApplyErrorFilter
ns.OnErrorMessage = OnErrorMessage
