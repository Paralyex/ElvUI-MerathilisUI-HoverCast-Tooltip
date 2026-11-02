local addonName = ...
local E = unpack(ElvUI)
local MER = unpack(ElvUI_MerathilisUI)
local HC = MER:GetModule("MER_HoverCast")

local _G = _G
local ipairs, type, tostring, format = ipairs, type, tostring, string.format
local tsort = table.sort

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local DEFAULTS = {
	enabled = true,
	groupOnly = false,
	position = "AUTO", -- AUTO, TOP, BOTTOM, LEFT, RIGHT
	anchorTo = "FRAME", -- FRAME (hovered unit frame) or GROUP (whole party/raid frame)
	offset = 4,
}

MER_HoverTooltipDB = MER_HoverTooltipDB or {}
local db = MER_HoverTooltipDB
for k, v in pairs(DEFAULTS) do
	if db[k] == nil then
		db[k] = v
	end
end

-------------------------------------------------------------------------------
--  Frame detection
-------------------------------------------------------------------------------
local GROUP_PATTERNS = { "^ElvUF_Party", "^ElvUF_Raid", "^CompactParty", "^CompactRaid" }

local function IsGroupName(name)
	if not name then
		return false
	end
	for _, pattern in ipairs(GROUP_PATTERNS) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

-- The unit button under the mouse that HoverCast has registered
local function GetHoveredUnitFrame()
	local foci = _G.GetMouseFoci and _G.GetMouseFoci()
	local frame = foci and foci[1]
	local ccf = _G.ClickCastFrames
	if not (frame and ccf) then
		return nil
	end
	for _ = 1, 4 do
		if not frame or frame == UIParent then
			return nil
		end
		if ccf[frame] then
			return frame
		end
		frame = frame.GetParent and frame:GetParent()
	end
	return nil
end

local function IsGroupFrame(frame)
	local f = frame
	while f and f ~= UIParent do
		if IsGroupName(f.GetName and f:GetName()) then
			return true
		end
		f = f.GetParent and f:GetParent()
	end
	return false
end

-- Highest named party/raid ancestor larger than the unit button; the button itself otherwise
local function GetGroupContainer(frame)
	local best
	local f = frame:GetParent()
	while f and f ~= UIParent and IsGroupName(f.GetName and f:GetName()) do
		if f:GetWidth() > frame:GetWidth() or f:GetHeight() > frame:GetHeight() then
			best = f
		end
		f = f:GetParent()
	end
	return best or frame
end

local function GetUnitReaction(frame)
	local unit = frame.unit or (frame.GetAttribute and frame:GetAttribute("unit"))
	if type(unit) ~= "string" or not UnitExists(unit) then
		return nil, nil
	end
	return UnitCanAttack("player", unit) and "harmful" or "friendly", unit
end

-------------------------------------------------------------------------------
--  Binding resolution
-------------------------------------------------------------------------------
local function CurrentCtx()
	local _, instType = IsInInstance()
	if instType == "pvp" or instType == "arena" then
		return "pvp"
	end
	if IsInRaid() then
		return "raid"
	end
	if IsInGroup() then
		return "party"
	end
	return "solo"
end

local function CurrentMods()
	return (IsAltKeyDown() and "ALT-" or "")
		.. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "")
		.. (IsMetaKeyDown and IsMetaKeyDown() and "META-" or "")
end

-- Splits "ALT-SHIFT-BUTTON1" into a canonical modifier prefix and the base key
local function SplitKey(key)
	local alt, ctrl, shift, meta = false, false, false, false
	local rest = key
	while true do
		local pre = rest:sub(1, 4) == "ALT-" and 4
			or rest:sub(1, 5) == "CTRL-" and 5
			or rest:sub(1, 6) == "SHIFT-" and 6
			or rest:sub(1, 5) == "META-" and 5
		if not pre or #rest <= pre then
			break
		end
		local name = rest:sub(1, pre - 1)
		alt, ctrl, shift, meta = alt or name == "ALT", ctrl or name == "CTRL", shift or name == "SHIFT",
			meta or name == "META"
		rest = rest:sub(pre + 1)
	end
	return (alt and "ALT-" or "") .. (ctrl and "CTRL-" or "") .. (shift and "SHIFT-" or "") .. (meta and "META-" or ""),
		rest
end

local function IsSpellKnown(id)
	if type(id) ~= "number" or id <= 0 then
		return true
	end
	local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
	if not (C_SpellBook.IsSpellInSpellBook and bank) then
		return true
	end
	if C_SpellBook.IsSpellInSpellBook(id, bank, true) then
		return true
	end
	local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(id)
	return type(base) == "number" and base > 0 and base ~= id and C_SpellBook.IsSpellInSpellBook(base, bank, true)
		or false
end

-- Preset actions that only make sense on friendly units
local FRIENDLY_ONLY = { dispel = true, external = true, dynamicrez = true }

-- Returns name, icon for the binding as seen on a unit of this reaction, or nil
local function ResolveEntry(b, reaction)
	if HC:IsReactionBinding(b) then
		local unitType = HC:GetBindingUnitType(b)
		if unitType ~= "both" and unitType ~= reaction then
			return nil
		end
	elseif FRIENDLY_ONLY[b.type] and reaction ~= "friendly" then
		return nil
	end
	return HC:GetBindingName(b), HC:GetBindingIcon(b)
end

local function Collect(list, reaction, mods, inCombat, ctx, blocked, out)
	for _, b in ipairs(list) do
		if
			b.key
			and HC:IsBindingActive(b)
			and HC:CtxEnabled(b, ctx)
			and (not inCombat or not b.oocOnly)
			and (b.type ~= "spell" or IsSpellKnown(b.spellID))
		then
			local bindMods, base = SplitKey(b.key)
			if bindMods == mods and not (blocked and blocked[base]) then
				local name, icon = ResolveEntry(b, reaction)
				if name then
					out[#out + 1] = { key = base, name = name, icon = icon }
				end
			end
		end
	end
end

local function SortValue(key)
	local n = key:match("^BUTTON(%d+)$")
	return n and format("%03d", tonumber(n)) or ("999" .. key)
end

local function GetEntries(reaction)
	local cc = HC:GetDB()
	if not (cc and cc.enabled) or HC:IsCliqueLoaded() then
		return {}
	end
	local mods, inCombat, ctx = CurrentMods(), InCombatLockdown(), CurrentCtx()

	local spec, global = {}, {}
	Collect(HC:GetSpecBindings(), reaction, mods, inCombat, ctx, nil, spec)
	-- A spec binding on a key replaces the global one
	local specKeys = {}
	for _, e in ipairs(spec) do
		specKeys[e.key] = true
	end
	Collect(HC:GetGlobalBindings(), reaction, mods, inCombat, ctx, specKeys, global)

	local entries, seen = {}, {}
	for _, list in ipairs({ spec, global }) do
		for _, e in ipairs(list) do
			local id = e.key .. e.name
			if not seen[id] then
				seen[id] = true
				e.sort = SortValue(e.key)
				entries[#entries + 1] = e
			end
		end
	end
	tsort(entries, function(a, b)
		return a.sort < b.sort
	end)
	return entries
end

-------------------------------------------------------------------------------
--  Tooltip
-------------------------------------------------------------------------------
local tip

local function GetTooltip()
	if not tip then
		tip = CreateFrame("GameTooltip", "MER_HoverTooltip", UIParent, "GameTooltipTemplate")
		tip:SetFrameStrata("TOOLTIP")
		tip:SetClampedToScreen(true)
		local TT = E:GetModule("Tooltip")
		if TT and TT.SetStyle then
			pcall(TT.SetStyle, TT, tip)
		end
	end
	return tip
end

local SIDE_ORDER_FRAME = { "TOP", "BOTTOM", "RIGHT", "LEFT" }
local SIDE_ORDER_GROUP = { "RIGHT", "LEFT", "BOTTOM", "TOP" }

-- The first side with room for the tooltip; the roomiest one when none fits
local function ChooseSide(target, width, height, isGroup)
	local left, bottom, w, h = target:GetScaledRect()
	if not left then
		return "TOP"
	end
	local scale = UIParent:GetEffectiveScale()
	local sw, sh = UIParent:GetWidth() * scale, UIParent:GetHeight() * scale
	local tScale = tip:GetEffectiveScale()
	local gap = db.offset * tScale
	local slack = {
		LEFT = left - (width * tScale + gap),
		RIGHT = sw - (left + w) - (width * tScale + gap),
		BOTTOM = bottom - (height * tScale + gap),
		TOP = sh - (bottom + h) - (height * tScale + gap),
	}
	local best, bestSlack
	for _, side in ipairs(isGroup and SIDE_ORDER_GROUP or SIDE_ORDER_FRAME) do
		if slack[side] >= 0 then
			return side
		end
		if not bestSlack or slack[side] > bestSlack then
			best, bestSlack = side, slack[side]
		end
	end
	return best
end

local ANCHORS = {
	TOP = { "BOTTOM", "TOP", 0, 1 },
	BOTTOM = { "TOP", "BOTTOM", 0, -1 },
	LEFT = { "RIGHT", "LEFT", -1, 0 },
	RIGHT = { "LEFT", "RIGHT", 1, 0 },
}

local MOD_NAMES = { ALT = "Alt", CTRL = "Ctrl", SHIFT = "Shift", META = "Meta" }

local function ModsText(mods)
	if mods == "" then
		return "No modifier"
	end
	local parts = {}
	for m in mods:gmatch("([^-]+)") do
		parts[#parts + 1] = MOD_NAMES[m] or m
	end
	return table.concat(parts, " + ")
end

local function HideTooltip()
	if tip then
		tip:Hide()
	end
end

local function ShowTooltip(frame, reaction)
	local entries = GetEntries(reaction)
	if #entries == 0 then
		return HideTooltip()
	end

	local t = GetTooltip()
	t:SetOwner(UIParent, "ANCHOR_NONE")
	t:AddDoubleLine("HoverCast", ModsText(CurrentMods()), 1, 1, 1, 0.6, 0.8, 1)
	for _, e in ipairs(entries) do
		local text = e.icon and format("|T%s:14:14:0:0:64:64:5:59:5:59|t %s", tostring(e.icon), e.name) or e.name
		t:AddDoubleLine(HC:FormatKey(e.key), text, 0.9, 0.8, 0.5, 1, 1, 1)
	end
	t:Show() -- sizes the tooltip, which the auto direction needs

	local isGroup = db.anchorTo == "GROUP"
	local target = isGroup and GetGroupContainer(frame) or frame
	local side = db.position
	if side == "AUTO" then
		side = ChooseSide(target, t:GetWidth(), t:GetHeight(), isGroup and target ~= frame)
	end
	local a = ANCHORS[side]
	t:ClearAllPoints()
	t:SetPoint(a[1], target, a[2], a[3] * db.offset, a[4] * db.offset)
end

-------------------------------------------------------------------------------
--  Hover tracking
-------------------------------------------------------------------------------
local lastSignature
local elapsed = 0

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.05 then
		return
	end
	elapsed = 0

	local frame = db.enabled and GetHoveredUnitFrame()
	if frame and db.groupOnly and not IsGroupFrame(frame) then
		frame = nil
	end
	local reaction, unit
	if frame then
		reaction, unit = GetUnitReaction(frame)
	end
	if not reaction then
		if lastSignature then
			lastSignature = nil
			HideTooltip()
		end
		return
	end

	local signature = format(
		"%s|%s|%s|%s|%s|%s|%s|%s",
		tostring(frame),
		unit,
		reaction,
		CurrentMods(),
		tostring(InCombatLockdown()),
		db.position,
		db.anchorTo,
		db.offset
	)
	if signature ~= lastSignature then
		lastSignature = signature
		ShowTooltip(frame, reaction)
	end
end)

-- Bindings and gating change with these; force a redraw on the next tick
for _, event in ipairs({ "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
	driver:RegisterEvent(event)
end
driver:SetScript("OnEvent", function()
	lastSignature = nil
end)

-------------------------------------------------------------------------------
--  Options (ElvUI config)
-------------------------------------------------------------------------------
local function InsertOptions()
	local function toggle(order, name, key, desc)
		return {
			order = order,
			type = "toggle",
			name = name,
			desc = desc,
			get = function()
				return db[key]
			end,
			set = function(_, value)
				db[key] = value
				lastSignature = nil
			end,
		}
	end
	local function select(order, name, key, values, desc)
		return {
			order = order,
			type = "select",
			name = name,
			desc = desc,
			values = values,
			get = function()
				return db[key]
			end,
			set = function(_, value)
				db[key] = value
				lastSignature = nil
			end,
		}
	end

	E.Options.args.merHoverTooltip = {
		order = 99,
		type = "group",
		name = "MerathilisUI HoverCast Tooltip",
		args = {
			enabled = toggle(1, "Enable", "enabled"),
			groupOnly = toggle(2, "Party / Raid Frames Only", "groupOnly",
				"Only show the tooltip on party and raid frames."),
			anchorTo = select(3, "Anchor To", "anchorTo", {
				FRAME = "Hovered Frame",
				GROUP = "Whole Party / Raid Frame",
			}, "The whole group frame keeps the tooltip from covering the other unit frames."),
			position = select(4, "Position", "position", {
				AUTO = "Auto",
				TOP = "Above",
				BOTTOM = "Below",
				LEFT = "Left",
				RIGHT = "Right",
			}, "Auto picks the first side with room on screen."),
			offset = {
				order = 5,
				type = "range",
				name = "Offset",
				min = 0,
				max = 50,
				step = 1,
				get = function()
					return db.offset
				end,
				set = function(_, value)
					db.offset = value
				end,
			},
		},
	}
end

E.Libs.EP:RegisterPlugin(addonName, InsertOptions)

SLASH_MERHOVERTOOLTIP1 = "/hctip"
SlashCmdList.MERHOVERTOOLTIP = function()
	E:ToggleOptions("merHoverTooltip")
end
