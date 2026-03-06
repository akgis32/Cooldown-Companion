--[[
    CooldownCompanion - Config/TalentPicker.lua: Visual talent tree picker
    rendered inside the existing config panel columns (col1 = class, col3 = spec).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

local ipairs = ipairs
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

local NORMAL_BORDER_SIZE = 2
local CHOICE_BORDER_SIZE = 3

local EDGE_THICKNESS_ACTIVE = 1.8
local EDGE_THICKNESS_INACTIVE = 1.2

local BTN_ROW_HEIGHT = 30

-- Colors
local COLOR_BORDER_TAKEN    = { 0.3, 0.85, 0.3, 1 }
local COLOR_BORDER_NOTTAKEN = { 0.4, 0.4, 0.4, 0.7 }
local COLOR_BORDER_SELECTED = { 1.0, 0.82, 0.0, 1 }
local COLOR_BORDER_CHOICE   = { 0.6, 0.5, 0.85, 1 }
local COLOR_EDGE_ACTIVE     = { 0.85, 0.75, 0.2, 0.9 }
local COLOR_EDGE_INACTIVE   = { 0.35, 0.35, 0.35, 0.5 }

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local classTreeFrame = nil
local specTreeFrame = nil
local specEmptyText = nil
local backBtn = nil
local clearBtn = nil
local nodeButtons = {}
local choiceButtons = {}
local classEdgeLines = {}
local specEdgeLines = {}
local onSelectCallback = nil
local savedCol1Title = nil
local savedCol3Title = nil
local savedPanelTitle = nil
local isRestoring = false

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

local function CreateNodeButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(NODE_SIZE, NODE_SIZE)

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
        if self._talentName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._talentName, 1, 1, 1)
            if self._rankText then
                GameTooltip:AddLine(self._rankText, 0.7, 0.7, 0.7)
            end
            if self._isChoiceNode then
                GameTooltip:AddLine("Click to see choices", 0.5, 0.8, 1)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local function CreateChoiceButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CHOICE_ICON_SIZE, CHOICE_ICON_SIZE)

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
        if self._spellID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self._spellID)
            GameTooltip:Show()
        elseif self._talentName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._talentName, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local function SetNodeBorderColor(btn, color)
    for _, border in ipairs(btn.borders) do
        SetBorderColor(border, color)
    end
end

------------------------------------------------------------------------
-- CHOICE SUBMENU (floating frame, parented to configFrame.frame)
------------------------------------------------------------------------
local choiceFrame = nil

local function HideChoiceFrame()
    if choiceFrame then
        choiceFrame:Hide()
    end
end

-- Forward declarations
local HideTalentPicker
local PopulateTree

local function ShowChoiceFrame(parentBtn, entries, nodeID, currentEntryID)
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
    end

    choiceFrame:SetParent(configFrame.frame)
    choiceFrame:SetFrameStrata("FULLSCREEN_DIALOG")

    -- Hide previous choice buttons
    for _, cb in ipairs(choiceButtons) do
        cb:Hide()
    end

    local count = #entries
    local totalWidth = count * CHOICE_ICON_SIZE + (count - 1) * CHOICE_ICON_GAP + 12
    choiceFrame:SetSize(totalWidth, CHOICE_ICON_SIZE + 10)
    choiceFrame:ClearAllPoints()
    choiceFrame:SetPoint("TOP", parentBtn, "BOTTOM", 0, -4)
    choiceFrame:Show()

    for i, entry in ipairs(entries) do
        local cb = choiceButtons[i]
        if not cb then
            cb = CreateChoiceButton(choiceFrame)
            choiceButtons[i] = cb
        end

        cb:SetParent(choiceFrame)
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", choiceFrame, "LEFT", 6 + (i - 1) * (CHOICE_ICON_SIZE + CHOICE_ICON_GAP), 0)
        cb:Show()

        cb.icon:SetTexture(entry.icon)
        cb.icon:SetDesaturated(not entry.isTaken)
        if not entry.isTaken then
            cb.icon:SetVertexColor(0.6, 0.6, 0.6)
        else
            cb.icon:SetVertexColor(1, 1, 1)
        end

        local borderColor = COLOR_BORDER_NOTTAKEN
        if entry.entryID == currentEntryID then
            borderColor = COLOR_BORDER_SELECTED
        elseif entry.isTaken then
            borderColor = COLOR_BORDER_TAKEN
        end
        SetNodeBorderColor(cb, borderColor)

        cb._talentName = entry.name
        cb._spellID = entry.spellID

        cb:SetScript("OnClick", function()
            HideChoiceFrame()
            local selectCb = onSelectCallback
            local result = {
                nodeID = nodeID,
                entryID = entry.entryID,
                spellID = entry.spellID,
                talentName = entry.name,
            }
            HideTalentPicker()
            if selectCb then
                selectCb(result)
            end
        end)
    end
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
    if not specTreeFrame then
        specTreeFrame = CreateFrame("Frame", nil, configFrame.col3.content)
    end
end

------------------------------------------------------------------------
-- BACK + CLEAR BUTTONS (lazy, created once)
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
            local cb = onSelectCallback
            HideTalentPicker()
            if cb then
                cb(nil)
            end
        end)
    end
end

------------------------------------------------------------------------
-- SHOW / HIDE TALENT PICKER
------------------------------------------------------------------------
local function ShowTalentPicker(configFrame, currentNodeID, currentEntryID)
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
    configFrame:SetTitle("Pick a Talent")

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

    -- Create/show tree frames + buttons
    EnsureTreeFrames()
    EnsureButtons()

    -- Parent tree frames to correct content areas
    classTreeFrame:SetParent(col1.content)
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

    -- Position spec tree (full content area)
    specTreeFrame:ClearAllPoints()
    specTreeFrame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    specTreeFrame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    specTreeFrame:Show()

    -- Populate talent trees
    PopulateTree(currentNodeID, currentEntryID)
end

HideTalentPicker = function()
    if isRestoring then return end
    isRestoring = true

    local configFrame = CS.configFrame
    CS.talentPickerMode = false

    -- Hide talent content
    if classTreeFrame then classTreeFrame:Hide() end
    if specTreeFrame then specTreeFrame:Hide() end
    if specEmptyText then specEmptyText:Hide() end
    if backBtn then backBtn.frame:Hide() end
    if clearBtn then clearBtn.frame:Hide() end
    HideChoiceFrame()

    -- Hide all node buttons and edges
    for _, btn in ipairs(nodeButtons) do btn:Hide() end
    for _, cb in ipairs(choiceButtons) do cb:Hide() end
    for _, line in ipairs(classEdgeLines) do line:Hide() end
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
    onSelectCallback = nil
    isRestoring = false

    -- RefreshConfigPanel restores col3 state correctly
    if configFrame then
        CooldownCompanion:RefreshConfigPanel()
    end
end

------------------------------------------------------------------------
-- POPULATE TREE
------------------------------------------------------------------------
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
                                  currentNodeID, currentEntryID,
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

        btn._talentName = primaryEntry.name
        btn._isChoiceNode = node.isChoice
        btn._rankText = (node.activeRank .. "/" .. node.maxRanks)

        -- Border color: selected > taken > choice-untaken > not taken
        local borderColor
        if node.nodeID == currentNodeID then
            borderColor = COLOR_BORDER_SELECTED
        elseif isTaken then
            borderColor = COLOR_BORDER_TAKEN
        elseif node.isChoice then
            borderColor = COLOR_BORDER_CHOICE
        else
            borderColor = COLOR_BORDER_NOTTAKEN
        end
        SetNodeBorderColor(btn, borderColor)

        -- Click handler
        local nodeRef = node
        btn:SetScript("OnClick", function(self)
            if nodeRef.isChoice and #nodeRef.entries > 1 then
                ShowChoiceFrame(self, nodeRef.entries, nodeRef.nodeID, currentEntryID)
            else
                HideChoiceFrame()
                local cb = onSelectCallback
                local result = {
                    nodeID = nodeRef.nodeID,
                    entryID = nil,
                    spellID = primaryEntry.spellID,
                    talentName = primaryEntry.name,
                }
                HideTalentPicker()
                if cb then
                    cb(result)
                end
            end
        end)

        nodeIDToBtn[node.nodeID] = btn
    end

    return btnIndex
end

local function DrawEdgesInPanel(scrollChild, panelNodes, nodeIDToBtn, edgePool)
    local lineIndex = 0

    for _, node in ipairs(panelNodes) do
        if node.visibleEdges then
            local srcBtn = nodeIDToBtn[node.nodeID]
            if srcBtn then
                for _, edge in ipairs(node.visibleEdges) do
                    local dstBtn = nodeIDToBtn[edge.targetNode]
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

PopulateTree = function(currentNodeID, currentEntryID)
    -- Hide all existing buttons and edges
    for _, btn in ipairs(nodeButtons) do btn:Hide() end
    for _, cb in ipairs(choiceButtons) do cb:Hide() end
    for _, line in ipairs(classEdgeLines) do line:Hide() end
    for _, line in ipairs(specEdgeLines) do line:Hide() end
    HideChoiceFrame()

    -- Hide empty-state text if it exists
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

    -- Get tree currencies for class/spec split
    local treeCurrencyInfo = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    local classCurrencyID, specCurrencyID
    if treeCurrencyInfo and #treeCurrencyInfo >= 2 then
        classCurrencyID = treeCurrencyInfo[1].traitCurrencyID
        specCurrencyID = treeCurrencyInfo[2].traitCurrencyID
    end

    -- Gather visible class/spec nodes (exclude hero talent subtrees)
    local classNodes = {}
    local specNodes = {}
    local allNodes = {}

    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        if nodeInfo and nodeInfo.isVisible and not nodeInfo.subTreeID
           and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection then
            local px = nodeInfo.posX / 10
            local py = nodeInfo.posY / 10

            -- Build entry display info
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

            if #entries > 0 then
                local isChoice = (nodeInfo.type == Enum.TraitNodeType.Selection)
                local record = {
                    nodeID = nodeID,
                    px = px,
                    py = py,
                    activeRank = nodeInfo.activeRank or 0,
                    maxRanks = nodeInfo.maxRanks or 1,
                    activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or nil,
                    entries = entries,
                    isChoice = isChoice,
                    nodeType = nodeInfo.type,
                    visibleEdges = nodeInfo.visibleEdges,
                }

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
        end
    end

    if #allNodes == 0 then return end

    local dualPanel = (#classNodes > 0 and #specNodes > 0)
    local nodeIDToBtn = {}
    local btnIndex = 0

    if dualPanel then
        -- Class panel
        local cFrameW = classTreeFrame:GetWidth()
        local cFrameH = classTreeFrame:GetHeight()
        local cMinX, cMaxX, cMinY, cMaxY = ComputeBounds(classNodes)
        local cTreeW = cMaxX - cMinX + NODE_SIZE
        local cTreeH = cMaxY - cMinY + NODE_SIZE
        local cScaleX = cTreeW > 0 and (cFrameW - NODE_PADDING * 2) / cTreeW or 1
        local cScaleY = cTreeH > 0 and (cFrameH - NODE_PADDING * 2) / cTreeH or 1
        local cScale = math_min(cScaleX, cScaleY, 1.0)

        local cContentW = cTreeW * cScale + NODE_PADDING * 2
        local cOffsetX = math_max(0, (cFrameW - cContentW) * 0.5)

        btnIndex = PlaceNodesInPanel(classTreeFrame, classNodes, cOffsetX, 0,
            cMinX, cMinY, cScale, currentNodeID, currentEntryID, btnIndex, nodeIDToBtn)

        DrawEdgesInPanel(classTreeFrame, classNodes, nodeIDToBtn, classEdgeLines)

        -- Spec panel
        local sFrameW = specTreeFrame:GetWidth()
        local sFrameH = specTreeFrame:GetHeight()
        local sMinX, sMaxX, sMinY, sMaxY = ComputeBounds(specNodes)
        local sTreeW = sMaxX - sMinX + NODE_SIZE
        local sTreeH = sMaxY - sMinY + NODE_SIZE
        local sScaleX = sTreeW > 0 and (sFrameW - NODE_PADDING * 2) / sTreeW or 1
        local sScaleY = sTreeH > 0 and (sFrameH - NODE_PADDING * 2) / sTreeH or 1
        local sScale = math_min(sScaleX, sScaleY, 1.0)

        local sContentW = sTreeW * sScale + NODE_PADDING * 2
        local sOffsetX = math_max(0, (sFrameW - sContentW) * 0.5)

        btnIndex = PlaceNodesInPanel(specTreeFrame, specNodes, sOffsetX, 0,
            sMinX, sMinY, sScale, currentNodeID, currentEntryID, btnIndex, nodeIDToBtn)

        DrawEdgesInPanel(specTreeFrame, specNodes, nodeIDToBtn, specEdgeLines)
    else
        -- Single-panel fallback: all nodes in left container
        local cFrameW = classTreeFrame:GetWidth()
        local cFrameH = classTreeFrame:GetHeight()
        local minX, maxX, minY, maxY = ComputeBounds(allNodes)
        local treeW = maxX - minX + NODE_SIZE
        local treeH = maxY - minY + NODE_SIZE
        local scaleX = treeW > 0 and (cFrameW - NODE_PADDING * 2) / treeW or 1
        local scaleY = treeH > 0 and (cFrameH - NODE_PADDING * 2) / treeH or 1
        local scale = math_min(scaleX, scaleY, 1.0)

        local contentW = treeW * scale + NODE_PADDING * 2
        local offsetX = math_max(0, (cFrameW - contentW) * 0.5)

        btnIndex = PlaceNodesInPanel(classTreeFrame, allNodes, offsetX, 0,
            minX, minY, scale, currentNodeID, currentEntryID, btnIndex, nodeIDToBtn)

        DrawEdgesInPanel(classTreeFrame, allNodes, nodeIDToBtn, classEdgeLines)

        -- Right container: empty message
        if not specEmptyText then
            specEmptyText = specTreeFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            specEmptyText:SetPoint("CENTER", specTreeFrame, "CENTER", 0, 0)
            specEmptyText:SetText("No spec talents found")
        end
        specEmptyText:Show()
    end
end

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------

-- Open the talent picker inside the config panel columns.
-- callback(result): called with { nodeID, entryID, spellID, talentName } or nil (clear).
-- currentNodeID/currentEntryID: highlight current selection.
function CooldownCompanion:OpenTalentPicker(callback, currentNodeID, currentEntryID)
    local configFrame = CS.configFrame
    if not configFrame then return end
    onSelectCallback = callback
    ShowTalentPicker(configFrame, currentNodeID, currentEntryID)
end

function CooldownCompanion:CloseTalentPicker()
    HideTalentPicker()
end

function CooldownCompanion:IsTalentPickerOpen()
    return CS.talentPickerMode
end
