--[[
    CooldownCompanion - Config/TalentPicker.lua: Visual talent tree picker
    rendered inside the existing config panel columns (col1 = class, col3 = spec).
    Supports multi-condition 3-way toggle (taken / not taken / clear) with Accept to commit.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local wipe = wipe
local math_min = math.min
local math_max = math.max
local math_floor = math.floor

------------------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------------------
local NODE_SIZE = 32
local NODE_PADDING = 16
local CHOICE_ICON_SIZE = 22
local CHOICE_ICON_GAP = 2
local HERO_GUTTER_WIDTH = 120
local HERO_HEADER_HEIGHT = 20

local NORMAL_BORDER_SIZE = 2
local CHOICE_BORDER_SIZE = 3

local EDGE_THICKNESS_ACTIVE = 1.8
local EDGE_THICKNESS_INACTIVE = 1.2

local BTN_ROW_HEIGHT = 30

-- Colors
local COLOR_BORDER_TAKEN           = { 0.3, 0.85, 0.3, 1 }
local COLOR_BORDER_NOTTAKEN        = { 0.4, 0.4, 0.4, 0.7 }
local COLOR_BORDER_CHOICE          = { 0.6, 0.5, 0.85, 1 }
local COLOR_BORDER_PENDING_TAKEN   = { 0.3, 0.7, 1.0, 1 }
local COLOR_BORDER_PENDING_NOTTAKEN = { 1.0, 0.3, 0.3, 1 }
local COLOR_EDGE_ACTIVE            = { 0.85, 0.75, 0.2, 0.9 }
local COLOR_EDGE_INACTIVE          = { 0.35, 0.35, 0.35, 0.5 }

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local classTreeFrame = nil
local heroTreeFrame = nil
local heroTreeTitle = nil
local specTreeFrame = nil
local specEmptyText = nil
local backBtn = nil
local clearBtn = nil
local acceptBtn = nil
local nodeButtons = {}
local choiceButtons = {}
local classEdgeLines = {}
local heroEdgeLines = {}
local specEdgeLines = {}
local onAcceptCallback = nil
local savedCol1Title = nil
local savedCol3Title = nil
local savedPanelTitle = nil
local isRestoring = false

-- Pending conditions: key = "nodeID" or "nodeID:entryID" → condition table
local pendingConditions = {}

------------------------------------------------------------------------
-- PENDING STATE HELPERS
------------------------------------------------------------------------
local function PendingKey(nodeID, entryID)
    if entryID then
        return tostring(nodeID) .. ":" .. tostring(entryID)
    end
    return tostring(nodeID)
end

local function GetPendingState(nodeID, entryID)
    return pendingConditions[PendingKey(nodeID, entryID)]
end

local function ClearPendingStateForNode(nodeID)
    local directKey = tostring(nodeID)
    pendingConditions[directKey] = nil

    local prefix = directKey .. ":"
    for key in pairs(pendingConditions) do
        if key:sub(1, #prefix) == prefix then
            pendingConditions[key] = nil
        end
    end
end

local function SetPendingState(nodeID, entryID, spellID, name, show)
    local key = PendingKey(nodeID, entryID)
    if show then
        pendingConditions[key] = {
            nodeID  = nodeID,
            entryID = entryID,
            spellID = spellID,
            name    = name,
            show    = show,
        }
    else
        pendingConditions[key] = nil
    end
end

local function CyclePendingState(nodeID, entryID, spellID, name)
    local existing = GetPendingState(nodeID, entryID)
    if not existing then
        SetPendingState(nodeID, entryID, spellID, name, "taken")
    elseif existing.show == "taken" then
        SetPendingState(nodeID, entryID, spellID, name, "not_taken")
    else
        -- not_taken → clear
        SetPendingState(nodeID, entryID, nil, nil, nil)
    end
end

local function CycleChoicePendingState(nodeID, entryID, spellID, name)
    local existing = GetPendingState(nodeID, entryID)
    local nextShow
    if not existing then
        nextShow = "taken"
    elseif existing.show == "taken" then
        nextShow = "not_taken"
    end

    ClearPendingStateForNode(nodeID)
    if nextShow then
        SetPendingState(nodeID, entryID, spellID, name, nextShow)
    end
end

-- Check if any entry of a given nodeID has a pending condition (for choice node parents)
local function GetPendingStateForNode(nodeID)
    -- Check direct node key first (non-choice nodes)
    local direct = pendingConditions[tostring(nodeID)]
    if direct then return direct end

    -- Check all entry keys for this node
    local prefix = tostring(nodeID) .. ":"
    for key, cond in pairs(pendingConditions) do
        if key:sub(1, #prefix) == prefix then
            return cond
        end
    end
    return nil
end

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function SetBorderColor(tex, color)
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function SetNodeBorderThickness(btn, thickness)
    btn.borders[1]:SetHeight(thickness)
    btn.borders[2]:SetHeight(thickness)
    btn.borders[3]:SetWidth(thickness)
    btn.borders[4]:SetWidth(thickness)
    btn.icon:ClearAllPoints()
    btn.icon:SetPoint("TOPLEFT", thickness, -thickness)
    btn.icon:SetPoint("BOTTOMRIGHT", -thickness, thickness)
end

local function SetNodeBorderColor(btn, color)
    for _, border in ipairs(btn.borders) do
        SetBorderColor(border, color)
    end
end

local function AddPendingTooltipLine(pending, isChoiceNode)
    if not pending then return end

    local r, g, b = 0.3, 0.7, 1.0
    if pending.show == "not_taken" then
        r, g, b = 1.0, 0.3, 0.3
    end

    local line
    if isChoiceNode and pending.name then
        if pending.show == "not_taken" then
            line = "Condition: Show when " .. pending.name .. " is NOT taken"
        else
            line = "Condition: Show when " .. pending.name .. " is taken"
        end
    elseif pending.show == "not_taken" then
        line = "Condition: Show when NOT taken"
    else
        line = "Condition: Show when taken"
    end

    GameTooltip:AddLine(line, r, g, b, true)
end

-- Determine border color for a node button based on pending state and talent state
local function GetNodeBorderColor(nodeID, entryID, isTaken, isChoice)
    -- Check pending state: for choice nodes check the specific entry, for regular check the node
    local pending
    if entryID then
        pending = GetPendingState(nodeID, entryID)
    else
        pending = GetPendingStateForNode(nodeID)
    end

    if pending then
        if pending.show == "taken" then
            return COLOR_BORDER_PENDING_TAKEN
        else
            return COLOR_BORDER_PENDING_NOTTAKEN
        end
    end

    -- No pending state — use talent state colors
    if isTaken then
        return COLOR_BORDER_TAKEN
    elseif isChoice then
        return COLOR_BORDER_CHOICE
    end
    return COLOR_BORDER_NOTTAKEN
end

------------------------------------------------------------------------
-- REFRESH PICKER BORDERS
------------------------------------------------------------------------
local RefreshPickerBorders

local function CreateNodeButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(NODE_SIZE, NODE_SIZE)
    btn:RegisterForClicks("AnyUp")

    -- Icon
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", NORMAL_BORDER_SIZE, -NORMAL_BORDER_SIZE)
    btn.icon:SetPoint("BOTTOMRIGHT", -NORMAL_BORDER_SIZE, NORMAL_BORDER_SIZE)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border (4 edge textures)
    btn.borders = {}
    local bSize = NORMAL_BORDER_SIZE
    local b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("TOPRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[1] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[2] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetWidth(bSize)
    btn.borders[3] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPRIGHT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetWidth(bSize)
    btn.borders[4] = b

    -- Highlight
    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.15)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._spellID then
            GameTooltip:SetSpellByID(self._spellID)
            if self._rankText then
                GameTooltip:AddLine(self._rankText, 0.7, 0.7, 0.7)
            end
        elseif self._talentName then
            GameTooltip:AddLine(self._talentName, 1, 1, 1)
            if self._rankText then
                GameTooltip:AddLine(self._rankText, 0.7, 0.7, 0.7)
            end
        end
        -- Pending state info
        local pending = self._entryID
            and GetPendingState(self._nodeID, self._entryID)
            or  GetPendingStateForNode(self._nodeID)
        AddPendingTooltipLine(pending, self._isChoiceNode)
        if self._isChoiceNode then
            GameTooltip:AddLine("Left-click to show or hide choices", 0.5, 0.8, 1)
        else
            GameTooltip:AddLine("Click to cycle condition", 0.5, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local function CreateChoiceButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CHOICE_ICON_SIZE, CHOICE_ICON_SIZE)
    btn:RegisterForClicks("AnyUp")

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.borders = {}
    local bSize = 2
    local b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("TOPRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[1] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[2] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetWidth(bSize)
    btn.borders[3] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPRIGHT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetWidth(bSize)
    btn.borders[4] = b

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.15)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self._spellID then
            GameTooltip:SetSpellByID(self._spellID)
        elseif self._talentName then
            GameTooltip:AddLine(self._talentName, 1, 1, 1)
        end
        -- Pending state info
        if self._nodeID then
            local pending = GetPendingState(self._nodeID, self._entryID)
            AddPendingTooltipLine(pending, true)
        end
        GameTooltip:AddLine("Click to cycle a specific choice", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

------------------------------------------------------------------------
-- CHOICE SUBMENU (floating frame, parented to configFrame.frame)
------------------------------------------------------------------------
local choiceFrame = nil

local function HideChoiceFrame()
    if choiceFrame then
        choiceFrame._nodeID = nil
        choiceFrame:Hide()
    end
end

-- Forward declarations
local HideTalentPicker
local PopulateTree

local function GetChoiceFrameLevel(parentBtn)
    local level = 0
    local configFrame = CS.configFrame

    if configFrame and configFrame.frame then
        level = math_max(level, configFrame.frame:GetFrameLevel() or 0)
        if configFrame.col1 and configFrame.col1.frame then
            level = math_max(level, configFrame.col1.frame:GetFrameLevel() or 0)
        end
        if configFrame.col3 and configFrame.col3.frame then
            level = math_max(level, configFrame.col3.frame:GetFrameLevel() or 0)
        end
    end

    if classTreeFrame then
        level = math_max(level, classTreeFrame:GetFrameLevel() or 0)
    end
    if heroTreeFrame then
        level = math_max(level, heroTreeFrame:GetFrameLevel() or 0)
    end
    if specTreeFrame then
        level = math_max(level, specTreeFrame:GetFrameLevel() or 0)
    end
    if parentBtn then
        level = math_max(level, parentBtn:GetFrameLevel() or 0)
    end

    return level + 20
end

local function ShowChoiceFrame(parentBtn, entries, nodeID)
    local configFrame = CS.configFrame
    if not configFrame then return end

    if not choiceFrame then
        choiceFrame = CreateFrame("Frame", nil, configFrame.frame, "BackdropTemplate")
        choiceFrame:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        choiceFrame:SetBackdropColor(0.12, 0.12, 0.18, 0.98)
        choiceFrame:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
        choiceFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        choiceFrame:SetToplevel(true)
    end

    choiceFrame:SetParent(configFrame.frame)
    choiceFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    choiceFrame:SetFrameLevel(GetChoiceFrameLevel(parentBtn))

    -- Hide previous choice buttons
    for _, cb in ipairs(choiceButtons) do
        cb:Hide()
    end

    local count = #entries
    local totalWidth = count * CHOICE_ICON_SIZE + (count - 1) * CHOICE_ICON_GAP + 12
    choiceFrame:SetSize(totalWidth, CHOICE_ICON_SIZE + 10)
    choiceFrame:ClearAllPoints()
    choiceFrame:SetPoint("TOP", parentBtn, "BOTTOM", 0, -4)
    choiceFrame._nodeID = nodeID
    choiceFrame:Show()
    choiceFrame:Raise()

    for i, entry in ipairs(entries) do
        local cb = choiceButtons[i]
        if not cb then
            cb = CreateChoiceButton(choiceFrame)
            choiceButtons[i] = cb
        end

        cb:SetParent(choiceFrame)
        cb:SetFrameStrata(choiceFrame:GetFrameStrata())
        cb:SetFrameLevel(choiceFrame:GetFrameLevel() + 1)
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", choiceFrame, "LEFT", 6 + (i - 1) * (CHOICE_ICON_SIZE + CHOICE_ICON_GAP), 0)
        cb:Show()
        cb:Raise()

        cb.icon:SetTexture(entry.icon)
        cb.icon:SetDesaturated(not entry.isTaken)
        if not entry.isTaken then
            cb.icon:SetVertexColor(0.6, 0.6, 0.6)
        else
            cb.icon:SetVertexColor(1, 1, 1)
        end

        -- Store identity for pending state lookups
        cb._nodeID = nodeID
        cb._entryID = entry.entryID
        cb._isTaken = entry.isTaken
        cb._talentName = entry.name
        cb._spellID = entry.spellID

        -- Border color: pending state > taken > not taken
        local borderColor = GetNodeBorderColor(nodeID, entry.entryID, entry.isTaken, false)
        SetNodeBorderColor(cb, borderColor)

        cb:SetScript("OnClick", function(_, mouseButton)
            if mouseButton and mouseButton ~= "LeftButton" then return end
            CycleChoicePendingState(nodeID, entry.entryID, entry.spellID, entry.name)
            RefreshPickerBorders()
        end)
    end
end

local function ToggleChoiceFrame(parentBtn, entries, nodeID)
    if choiceFrame and choiceFrame:IsShown() and choiceFrame._nodeID == nodeID then
        HideChoiceFrame()
        return
    end
    ShowChoiceFrame(parentBtn, entries, nodeID)
end

------------------------------------------------------------------------
-- TREE FRAME CREATION (lazy, created once, reused)
------------------------------------------------------------------------
local function EnsureTreeFrames()
    local configFrame = CS.configFrame
    if not configFrame then return end
    if not classTreeFrame then
        classTreeFrame = CreateFrame("Frame", nil, configFrame.col1.content)
    end
    if not heroTreeFrame then
        heroTreeFrame = CreateFrame("Frame", nil, configFrame.col3.content)
        heroTreeTitle = heroTreeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        heroTreeTitle:SetPoint("TOPLEFT", heroTreeFrame, "TOPLEFT", 4, -2)
        heroTreeTitle:SetPoint("TOPRIGHT", heroTreeFrame, "TOPRIGHT", -4, -2)
        heroTreeTitle:SetJustifyH("LEFT")
        heroTreeTitle:SetJustifyV("TOP")
    end
    if not specTreeFrame then
        specTreeFrame = CreateFrame("Frame", nil, configFrame.col3.content)
    end
end

local function LayoutSpecFrames(col3Content, hasHeroChoices)
    if hasHeroChoices and heroTreeFrame then
        heroTreeFrame:SetParent(col3Content)
        heroTreeFrame:ClearAllPoints()
        heroTreeFrame:SetPoint("TOPLEFT", col3Content, "TOPLEFT", 0, 0)
        heroTreeFrame:SetPoint("BOTTOMLEFT", col3Content, "BOTTOMLEFT", 0, 0)
        heroTreeFrame:SetWidth(HERO_GUTTER_WIDTH)
        heroTreeFrame:SetFrameStrata(specTreeFrame:GetFrameStrata())
        heroTreeFrame:SetFrameLevel((specTreeFrame:GetFrameLevel() or 0) + 10)
        heroTreeFrame:Show()
    else
        if heroTreeFrame then
            heroTreeFrame:Hide()
        end
        if heroTreeTitle then
            heroTreeTitle:Hide()
        end

    end

    specTreeFrame:ClearAllPoints()
    specTreeFrame:SetPoint("TOPLEFT", col3Content, "TOPLEFT", 0, 0)
    specTreeFrame:SetPoint("BOTTOMRIGHT", col3Content, "BOTTOMRIGHT", 0, 0)
end

------------------------------------------------------------------------
-- BACK + CLEAR + ACCEPT BUTTONS (lazy, created once)
------------------------------------------------------------------------
local function EnsureButtons()
    if not backBtn then
        backBtn = AceGUI:Create("Button")
        backBtn:SetText("Back")
        backBtn:SetWidth(80)
        backBtn:SetCallback("OnClick", function()
            HideTalentPicker()
        end)
    end

    if not clearBtn then
        clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear")
        clearBtn:SetWidth(80)
        clearBtn:SetCallback("OnClick", function()
            wipe(pendingConditions)
            RefreshPickerBorders()
        end)
    end

    if not acceptBtn then
        acceptBtn = AceGUI:Create("Button")
        acceptBtn:SetText("Accept")
        acceptBtn:SetWidth(160)
        acceptBtn:SetCallback("OnClick", function()
            local results = nil
            local count = 0
            for _ in pairs(pendingConditions) do count = count + 1 end
            if count > 0 then
                results = {}
                for _, cond in pairs(pendingConditions) do
                    results[#results + 1] = {
                        nodeID  = cond.nodeID,
                        entryID = cond.entryID,
                        spellID = cond.spellID,
                        name    = cond.name,
                        show    = cond.show,
                    }
                end
                local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                if changed then
                    results = normalized
                end
            end
            local cb = onAcceptCallback
            HideTalentPicker()
            if cb then
                cb(results)
            end
        end)
    end
end

------------------------------------------------------------------------
-- SHOW / HIDE TALENT PICKER
------------------------------------------------------------------------
local function ShowTalentPicker(configFrame, initialConditions)
    CS.talentPickerMode = true

    local col1 = configFrame.col1
    local col2 = configFrame.col2
    local col3 = configFrame.col3
    local col4 = configFrame.col4

    -- Save titles
    savedCol1Title = col1.titletext:GetText()
    savedCol3Title = col3.titletext:GetText()
    savedPanelTitle = configFrame.titletext:GetText()

    -- Change titles
    col1:SetTitle("Class")
    col3:SetTitle("Spec")
    configFrame:SetTitle("Pick Talent Conditions")

    -- Hide col2 + col4
    col2.frame:Hide()
    col4.frame:Hide()

    -- Hide col1 normal content
    CS.col1Scroll.frame:Hide()
    CS.col1ButtonBar:Hide()

    -- Hide col3 normal content (all possible states)
    if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
    if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
    if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
    if col3._autoAddScroll then col3._autoAddScroll.frame:Hide() end
    if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end

    -- Recompute column layout (2-column mode)
    configFrame.LayoutColumns()

    -- Hide panel elements
    configFrame.modeStatusRow:Hide()
    if configFrame.profileBar:IsShown() then
        configFrame.profileBar:Hide()
    end

    -- Hide column info buttons during talent picker
    if CS.columnInfoButtons[1] then CS.columnInfoButtons[1]:Hide() end
    if CS.columnInfoButtons[3] then CS.columnInfoButtons[3]:Hide() end

    -- Initialize pending conditions from initial conditions
    wipe(pendingConditions)
    if initialConditions then
        local source = initialConditions
        local normalized, changed = CooldownCompanion:NormalizeTalentConditions(initialConditions)
        if changed then
            source = normalized
        end
        for _, cond in ipairs(source or {}) do
            local key = PendingKey(cond.nodeID, cond.entryID)
            pendingConditions[key] = {
                nodeID  = cond.nodeID,
                entryID = cond.entryID,
                spellID = cond.spellID,
                name    = cond.name,
                show    = cond.show,
            }
        end
    end

    -- Create/show tree frames + buttons
    EnsureTreeFrames()
    EnsureButtons()

    -- Parent tree frames to correct content areas
    classTreeFrame:SetParent(col1.content)
    if heroTreeFrame then
        heroTreeFrame:SetParent(col3.content)
    end
    specTreeFrame:SetParent(col3.content)

    -- Position AceGUI buttons in col1.content
    backBtn.frame:SetParent(col1.content)
    backBtn.frame:ClearAllPoints()
    backBtn.frame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, 0)
    backBtn.frame:Show()

    clearBtn.frame:SetParent(col1.content)
    clearBtn.frame:ClearAllPoints()
    clearBtn.frame:SetPoint("LEFT", backBtn.frame, "RIGHT", 4, 0)
    clearBtn.frame:Show()

    -- Position class tree below buttons
    classTreeFrame:ClearAllPoints()
    classTreeFrame:SetPoint("TOPLEFT", col1.content, "TOPLEFT", 0, -BTN_ROW_HEIGHT)
    classTreeFrame:SetPoint("BOTTOMRIGHT", col1.content, "BOTTOMRIGHT", 0, 0)
    classTreeFrame:Show()

    -- Position spec content; hero gutter is enabled during PopulateTree when needed
    LayoutSpecFrames(col3.content, false)
    specTreeFrame:Show()

    -- Position accept button at bottom center of main panel (where modeStatusRow normally sits)
    acceptBtn.frame:SetParent(configFrame.frame)
    acceptBtn.frame:ClearAllPoints()
    acceptBtn.frame:SetPoint("BOTTOM", configFrame.frame, "BOTTOM", 0, 21)
    acceptBtn.frame:Show()

    -- Populate talent trees
    PopulateTree()
end

HideTalentPicker = function()
    if isRestoring then return end
    isRestoring = true

    local configFrame = CS.configFrame
    CS.talentPickerMode = false

    -- Hide talent content
    if classTreeFrame then classTreeFrame:Hide() end
    if heroTreeFrame then heroTreeFrame:Hide() end
    if heroTreeTitle then heroTreeTitle:Hide() end
    if specTreeFrame then specTreeFrame:Hide() end
    if specEmptyText then specEmptyText:Hide() end
    if backBtn then backBtn.frame:Hide() end
    if clearBtn then clearBtn.frame:Hide() end
    if acceptBtn then acceptBtn.frame:Hide() end
    HideChoiceFrame()

    -- Hide all node buttons and edges
    for _, btn in ipairs(nodeButtons) do btn:Hide() end
    for _, cb in ipairs(choiceButtons) do cb:Hide() end
    for _, line in ipairs(classEdgeLines) do line:Hide() end
    for _, line in ipairs(heroEdgeLines) do line:Hide() end
    for _, line in ipairs(specEdgeLines) do line:Hide() end

    if configFrame then
        -- Restore titles
        if savedCol1Title then configFrame.col1:SetTitle(savedCol1Title) end
        if savedCol3Title then configFrame.col3:SetTitle(savedCol3Title) end
        if savedPanelTitle then configFrame:SetTitle(savedPanelTitle) end

        -- Show col2 + col4
        configFrame.col2.frame:Show()
        configFrame.col4.frame:Show()

        -- Restore column info buttons
        if not CooldownCompanion.db.profile.hideInfoButtons then
            if CS.columnInfoButtons[1] then CS.columnInfoButtons[1]:Show() end
            if CS.columnInfoButtons[3] then CS.columnInfoButtons[3]:Show() end
        end

        -- Show col1 normal content
        CS.col1Scroll.frame:Show()
        CS.col1ButtonBar:Show()

        -- Restore modeStatusRow visibility (SyncModeToggleWithProfileBar is a closure,
        -- so replicate its visibility logic: row shows when profileBar is hidden)
        if configFrame.modeStatusRow and configFrame.profileBar then
            configFrame.modeStatusRow:SetShown(not configFrame.profileBar:IsShown())
        end

        -- Recompute layout (4-column mode) then refresh
        configFrame.LayoutColumns()
        if configFrame.UpdateModeNavigationUI then
            configFrame.UpdateModeNavigationUI()
        end
    end

    savedCol1Title = nil
    savedCol3Title = nil
    savedPanelTitle = nil
    onAcceptCallback = nil
    wipe(pendingConditions)
    isRestoring = false

    -- RefreshConfigPanel restores col3 state correctly
    if configFrame then
        CooldownCompanion:RefreshConfigPanel()
    end
end

------------------------------------------------------------------------
-- POPULATE TREE
------------------------------------------------------------------------
local function ShouldIncludeBaseTreeNode(nodeInfo)
    return nodeInfo
        and nodeInfo.isVisible
        and not nodeInfo.subTreeID
        and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection
end

local function ShouldIncludeHeroChoiceNode(nodeInfo, activeHeroSubTreeID)
    return nodeInfo
        and activeHeroSubTreeID
        and nodeInfo.isVisible
        and nodeInfo.subTreeID == activeHeroSubTreeID
        and nodeInfo.type == Enum.TraitNodeType.Selection
end

local function GetEntryDisplayInfo(configID, entryID)
    local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
    if not entryInfo or not entryInfo.definitionID then return nil end

    local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
    if not defInfo then return nil end

    local spellID = defInfo.spellID
    local name = defInfo.overrideName
    local icon = defInfo.overrideIcon

    if spellID then
        if not name then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            name = spellInfo and spellInfo.name
        end
        if not icon then
            icon = C_Spell.GetSpellTexture(spellID)
        end
    end

    return {
        entryID = entryID,
        definitionID = entryInfo.definitionID,
        spellID = spellID,
        name = name or ("Entry " .. entryID),
        icon = icon or 134400,
    }
end

local function BuildNodeRecord(configID, nodeID, nodeInfo)
    local entries = {}
    if nodeInfo.entryIDs then
        for _, eid in ipairs(nodeInfo.entryIDs) do
            local displayInfo = GetEntryDisplayInfo(configID, eid)
            if displayInfo then
                displayInfo.isTaken = (nodeInfo.activeEntry
                    and nodeInfo.activeEntry.entryID == eid
                    and nodeInfo.activeRank > 0)
                entries[#entries + 1] = displayInfo
            end
        end
    end

    if #entries == 0 then
        return nil
    end

    return {
        nodeID = nodeID,
        px = nodeInfo.posX / 10,
        py = nodeInfo.posY / 10,
        activeRank = nodeInfo.activeRank or 0,
        maxRanks = nodeInfo.maxRanks or 1,
        activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or nil,
        entries = entries,
        isChoice = (nodeInfo.type == Enum.TraitNodeType.Selection),
        nodeType = nodeInfo.type,
        visibleEdges = nodeInfo.visibleEdges,
        subTreeID = nodeInfo.subTreeID,
    }
end

local function ComputeBounds(nodeSet)
    local mnX, mxX, mnY, mxY = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(nodeSet) do
        if n.px < mnX then mnX = n.px end
        if n.px > mxX then mxX = n.px end
        if n.py < mnY then mnY = n.py end
        if n.py > mxY then mxY = n.py end
    end
    return mnX, mxX, mnY, mxY
end

local function PlaceNodesInPanel(scrollChild, nodeSet, panelOffsetX, yOffset,
                                  panelMinX, panelMinY, panelScale,
                                  btnIndex, nodeIDToBtn)
    for _, node in ipairs(nodeSet) do
        btnIndex = btnIndex + 1
        local btn = nodeButtons[btnIndex]
        if not btn then
            btn = CreateNodeButton(scrollChild, btnIndex)
            nodeButtons[btnIndex] = btn
        end

        local x = panelOffsetX + (node.px - panelMinX) * panelScale + NODE_PADDING
        local y = yOffset + (node.py - panelMinY) * panelScale + NODE_PADDING

        btn:SetParent(scrollChild)
        btn:SetFrameStrata(scrollChild:GetFrameStrata())
        btn:SetFrameLevel((scrollChild:GetFrameLevel() or 0) + 5)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, -y)
        btn:Show()

        -- Border thickness: choice nodes get thicker borders
        if node.isChoice then
            SetNodeBorderThickness(btn, CHOICE_BORDER_SIZE)
        else
            SetNodeBorderThickness(btn, NORMAL_BORDER_SIZE)
        end

        -- Display: use active entry's icon for choice nodes, else first entry
        local primaryEntry = node.entries[1]
        if node.isChoice and node.activeEntryID then
            for _, entry in ipairs(node.entries) do
                if entry.entryID == node.activeEntryID then
                    primaryEntry = entry
                    break
                end
            end
        end

        btn.icon:SetTexture(primaryEntry.icon)
        local isTaken = node.activeRank > 0
        btn.icon:SetDesaturated(not isTaken)
        if not isTaken then
            btn.icon:SetVertexColor(0.6, 0.6, 0.6)
        else
            btn.icon:SetVertexColor(1, 1, 1)
        end

        -- Store identity for pending state and border refresh
        btn._nodeID = node.nodeID
        btn._entryID = nil  -- regular nodes use nil; choice entries set per-entry
        btn._isTaken = isTaken
        btn._isChoiceNode = node.isChoice
        btn._talentName = primaryEntry.name
        btn._spellID = primaryEntry.spellID
        btn._rankText = (node.activeRank .. "/" .. node.maxRanks)

        -- Border color: pending > taken > choice > not taken
        local borderColor = GetNodeBorderColor(node.nodeID, nil, isTaken, node.isChoice)
        SetNodeBorderColor(btn, borderColor)

        -- Click handler
        local nodeRef = node
        btn:SetScript("OnClick", function(self, mouseButton)
            if nodeRef.isChoice and #nodeRef.entries > 1 then
                if mouseButton == "LeftButton" or mouseButton == nil then
                    ToggleChoiceFrame(self, nodeRef.entries, nodeRef.nodeID)
                end
            else
                HideChoiceFrame()
                CyclePendingState(nodeRef.nodeID, nil, primaryEntry.spellID, primaryEntry.name)
                RefreshPickerBorders()
            end
        end)

        nodeIDToBtn[node.nodeID] = btn
    end

    return btnIndex
end

local function DrawEdgesInPanel(scrollChild, panelNodes, nodeIDToBtn, edgePool)
    local lineIndex = 0
    local panelNodeIDs = {}

    for _, node in ipairs(panelNodes) do
        panelNodeIDs[node.nodeID] = true
    end

    for _, node in ipairs(panelNodes) do
        if node.visibleEdges then
            local srcBtn = nodeIDToBtn[node.nodeID]
            if srcBtn then
                for _, edge in ipairs(node.visibleEdges) do
                    local dstBtn = panelNodeIDs[edge.targetNode] and nodeIDToBtn[edge.targetNode] or nil
                    if dstBtn then
                        lineIndex = lineIndex + 1
                        local line = edgePool[lineIndex]
                        if not line then
                            line = scrollChild:CreateLine(nil, "BACKGROUND")
                            edgePool[lineIndex] = line
                        end

                        line:ClearAllPoints()
                        line:SetStartPoint("CENTER", srcBtn)
                        line:SetEndPoint("CENTER", dstBtn)

                        if edge.isActive then
                            line:SetThickness(EDGE_THICKNESS_ACTIVE)
                            line:SetColorTexture(COLOR_EDGE_ACTIVE[1], COLOR_EDGE_ACTIVE[2],
                                                 COLOR_EDGE_ACTIVE[3], COLOR_EDGE_ACTIVE[4])
                        else
                            line:SetThickness(EDGE_THICKNESS_INACTIVE)
                            line:SetColorTexture(COLOR_EDGE_INACTIVE[1], COLOR_EDGE_INACTIVE[2],
                                                 COLOR_EDGE_INACTIVE[3], COLOR_EDGE_INACTIVE[4])
                        end

                        line:Show()
                    end
                end
            end
        end
    end
end

local function RenderNodePanel(panelFrame, nodeSet, nodeIDToBtn, edgePool, btnIndex, topPadding)
    if not panelFrame or #nodeSet == 0 then
        for _, line in ipairs(edgePool) do
            line:Hide()
        end
        return btnIndex
    end

    local frameW = panelFrame:GetWidth()
    local frameH = panelFrame:GetHeight()
    local panelTopPadding = topPadding or 0
    local usableW = math_max(frameW - NODE_PADDING * 2, NODE_SIZE)
    local usableH = math_max(frameH - panelTopPadding - NODE_PADDING * 2, NODE_SIZE)
    local minX, maxX, minY, maxY = ComputeBounds(nodeSet)
    local treeW = maxX - minX + NODE_SIZE
    local treeH = maxY - minY + NODE_SIZE
    local scaleX = treeW > 0 and usableW / treeW or 1
    local scaleY = treeH > 0 and usableH / treeH or 1
    local scale = math_min(scaleX, scaleY, 1.0)
    local contentW = treeW * scale + NODE_PADDING * 2
    local offsetX = math_max(0, (frameW - contentW) * 0.5)

    btnIndex = PlaceNodesInPanel(panelFrame, nodeSet, offsetX, panelTopPadding,
        minX, minY, scale, btnIndex, nodeIDToBtn)
    DrawEdgesInPanel(panelFrame, nodeSet, nodeIDToBtn, edgePool)

    return btnIndex
end

local function RenderHeroChoiceList(panelFrame, nodeSet, nodeIDToBtn, btnIndex)
    for _, line in ipairs(heroEdgeLines) do
        line:Hide()
    end

    if not panelFrame or #nodeSet == 0 then
        return btnIndex
    end

    local orderedNodes = {}
    for i, node in ipairs(nodeSet) do
        orderedNodes[i] = node
    end

    table.sort(orderedNodes, function(a, b)
        if a.py == b.py then
            return a.px < b.px
        end
        return a.py < b.py
    end)

    local centeredX = math_max(NODE_PADDING, math_floor((panelFrame:GetWidth() - NODE_SIZE) * 0.5))
    local nextY = HERO_HEADER_HEIGHT + 8

    for _, node in ipairs(orderedNodes) do
        btnIndex = PlaceNodesInPanel(panelFrame, { node }, centeredX - NODE_PADDING, nextY - NODE_PADDING,
            node.px, node.py, 0, btnIndex, nodeIDToBtn)
        nextY = nextY + NODE_SIZE + 10
    end

    return btnIndex
end

-- Re-apply border colors to all visible node + choice buttons based on pending state
RefreshPickerBorders = function()
    for _, btn in ipairs(nodeButtons) do
        if btn:IsShown() and btn._nodeID then
            local borderColor = GetNodeBorderColor(btn._nodeID, btn._entryID, btn._isTaken, btn._isChoiceNode)
            SetNodeBorderColor(btn, borderColor)
        end
    end
    for _, cb in ipairs(choiceButtons) do
        if cb:IsShown() and cb._nodeID then
            local pending = GetPendingState(cb._nodeID, cb._entryID)
            local borderColor
            if pending then
                borderColor = pending.show == "taken" and COLOR_BORDER_PENDING_TAKEN or COLOR_BORDER_PENDING_NOTTAKEN
            elseif cb._isTaken then
                borderColor = COLOR_BORDER_TAKEN
            else
                borderColor = COLOR_BORDER_NOTTAKEN
            end
            SetNodeBorderColor(cb, borderColor)
        end
    end
end

PopulateTree = function()
    -- Hide all existing buttons and edges
    for _, btn in ipairs(nodeButtons) do btn:Hide() end
    for _, cb in ipairs(choiceButtons) do cb:Hide() end
    for _, line in ipairs(classEdgeLines) do line:Hide() end
    for _, line in ipairs(heroEdgeLines) do line:Hide() end
    for _, line in ipairs(specEdgeLines) do line:Hide() end
    HideChoiceFrame()

    -- Hide empty-state text if it exists
    if heroTreeFrame then
        heroTreeFrame:Hide()
    end
    if heroTreeTitle then
        heroTreeTitle:Hide()
    end
    if specEmptyText then
        specEmptyText:Hide()
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local specID = CooldownCompanion._currentSpecId
    if not specID then return end

    local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not treeID then return end

    local nodeIDs = C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then return end
    local activeHeroSubTreeID = C_ClassTalents.GetActiveHeroTalentSpec()
    local activeHeroSubTreeInfo = activeHeroSubTreeID and C_Traits.GetSubTreeInfo(configID, activeHeroSubTreeID) or nil

    -- Get tree currencies for class/spec split
    local treeCurrencyInfo = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    local classCurrencyID, specCurrencyID
    if treeCurrencyInfo and #treeCurrencyInfo >= 2 then
        classCurrencyID = treeCurrencyInfo[1].traitCurrencyID
        specCurrencyID = treeCurrencyInfo[2].traitCurrencyID
    end

    -- Gather visible class/spec nodes plus active hero choice nodes.
    local classNodes = {}
    local heroNodes = {}
    local specNodes = {}
    local allNodes = {}

    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        if ShouldIncludeBaseTreeNode(nodeInfo) then
            local record = BuildNodeRecord(configID, nodeID, nodeInfo)
            if record then
                allNodes[#allNodes + 1] = record

                -- Classify by currency
                if classCurrencyID and specCurrencyID then
                    local costs = C_Traits.GetNodeCost(configID, nodeID)
                    local isSpec = false
                    if costs and #costs > 0 then
                        for _, cost in ipairs(costs) do
                            if cost.ID == specCurrencyID then
                                isSpec = true
                                break
                            end
                        end
                        if isSpec then
                            specNodes[#specNodes + 1] = record
                        else
                            classNodes[#classNodes + 1] = record
                        end
                    else
                        -- No cost (granted starting talents) -> default to class
                        classNodes[#classNodes + 1] = record
                    end
                end
            end
        elseif ShouldIncludeHeroChoiceNode(nodeInfo, activeHeroSubTreeID) then
            local record = BuildNodeRecord(configID, nodeID, nodeInfo)
            if record then
                heroNodes[#heroNodes + 1] = record
            end
        end
    end

    if #allNodes == 0 and #heroNodes == 0 then return end

    local hasHeroChoices = #heroNodes > 0
    LayoutSpecFrames(CS.configFrame.col3.content, hasHeroChoices)
    if hasHeroChoices and heroTreeTitle then
        heroTreeTitle:SetText((activeHeroSubTreeInfo and activeHeroSubTreeInfo.name) or "Hero Choices")
        heroTreeTitle:Show()
    end

    local dualPanel = (#classNodes > 0 and #specNodes > 0)
    local nodeIDToBtn = {}
    local btnIndex = 0

    if dualPanel then
        btnIndex = RenderNodePanel(classTreeFrame, classNodes, nodeIDToBtn, classEdgeLines, btnIndex, 0)
        btnIndex = RenderNodePanel(specTreeFrame, specNodes, nodeIDToBtn, specEdgeLines, btnIndex, 0)
    else
        -- Single-panel fallback: all nodes in left container
        btnIndex = RenderNodePanel(classTreeFrame, allNodes, nodeIDToBtn, classEdgeLines, btnIndex, 0)

        -- Right container: empty message
        if not specEmptyText then
            specEmptyText = specTreeFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            specEmptyText:SetPoint("CENTER", specTreeFrame, "CENTER", 0, 0)
            specEmptyText:SetText("No spec talents found")
        end
        specEmptyText:Show()
    end

    if hasHeroChoices then
        btnIndex = RenderHeroChoiceList(heroTreeFrame, heroNodes, nodeIDToBtn, btnIndex)
    end
end

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------

-- Open the talent picker inside the config panel columns.
-- callback(results): called with array of conditions or nil (clear all).
-- initialConditions: array of existing conditions to pre-load as pending.
function CooldownCompanion:OpenTalentPicker(callback, initialConditions)
    local configFrame = CS.configFrame
    if not configFrame then return end
    onAcceptCallback = callback
    ShowTalentPicker(configFrame, initialConditions)
end

function CooldownCompanion:CloseTalentPicker()
    HideTalentPicker()
end

function CooldownCompanion:IsTalentPickerOpen()
    return CS.talentPickerMode
end
