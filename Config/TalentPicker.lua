--[[
    CooldownCompanion - Config/TalentPicker.lua: Visual talent tree picker
    embedded in the config panel overlay.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local ipairs = ipairs
local pairs = pairs
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

local PANEL_GAP = 12
local PANEL_HEADER_HEIGHT = 20
local NORMAL_BORDER_SIZE = 2
local CHOICE_BORDER_SIZE = 3

local EDGE_THICKNESS_ACTIVE = 1.8
local EDGE_THICKNESS_INACTIVE = 1.2

local TOP_ROW_HEIGHT = 36

-- Colors
local COLOR_BORDER_TAKEN    = { 0.3, 0.85, 0.3, 1 }
local COLOR_BORDER_NOTTAKEN = { 0.4, 0.4, 0.4, 0.7 }
local COLOR_BORDER_SELECTED = { 1.0, 0.82, 0.0, 1 }
local COLOR_BORDER_CHOICE   = { 0.6, 0.5, 0.85, 1 }
local COLOR_BG              = { 0.08, 0.08, 0.12, 0.95 }
local COLOR_EDGE_ACTIVE     = { 0.85, 0.75, 0.2, 0.9 }
local COLOR_EDGE_INACTIVE   = { 0.35, 0.35, 0.35, 0.5 }

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local overlayFrame = nil       -- raw Frame, child of config panel contentFrame
local nodeButtons = {}
local choiceButtons = {}
local edgeLines = {}
local onSelectCallback = nil
local savedTitle = nil         -- original panel title to restore
local isRestoring = false      -- guard against double-fire in OnHide

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
-- CHOICE SUBMENU
------------------------------------------------------------------------
local choiceFrame = nil

local function HideChoiceFrame()
    if choiceFrame then
        choiceFrame:Hide()
    end
end

-- Forward declarations
local HideOverlay
local PopulateTree

local function ShowChoiceFrame(parentBtn, entries, nodeID, currentEntryID)
    if not choiceFrame then
        choiceFrame = CreateFrame("Frame", nil, overlayFrame, "BackdropTemplate")
        choiceFrame:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        choiceFrame:SetBackdropColor(0.12, 0.12, 0.18, 0.98)
        choiceFrame:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
        choiceFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    end

    -- Reparent in case overlay was recreated
    choiceFrame:SetParent(overlayFrame)

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
            HideOverlay(CS.configFrame)
            if selectCb then
                selectCb(result)
            end
        end)
    end
end

------------------------------------------------------------------------
-- OVERLAY MANAGEMENT
------------------------------------------------------------------------
local function EnsureOverlay(configFrame)
    if overlayFrame then return end

    local contentFrame = configFrame.content

    overlayFrame = CreateFrame("Frame", nil, contentFrame)
    overlayFrame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    overlayFrame:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    overlayFrame:SetFrameStrata("DIALOG")
    overlayFrame:Hide()

    -- Background
    local bg = overlayFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(COLOR_BG[1], COLOR_BG[2], COLOR_BG[3], COLOR_BG[4])

    -- Top row
    local topRow = CreateFrame("Frame", nil, overlayFrame)
    topRow:SetPoint("TOPLEFT", overlayFrame, "TOPLEFT", 8, -8)
    topRow:SetPoint("TOPRIGHT", overlayFrame, "TOPRIGHT", -8, -8)
    topRow:SetHeight(TOP_ROW_HEIGHT)

    local backBtn = CreateFrame("Button", nil, topRow, "UIPanelButtonTemplate")
    backBtn:SetSize(80, 24)
    backBtn:SetPoint("TOPLEFT", topRow, "TOPLEFT", 0, 0)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function()
        HideOverlay(configFrame)
    end)

    local clearBtn = CreateFrame("Button", nil, topRow, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 24)
    clearBtn:SetPoint("LEFT", backBtn, "RIGHT", 6, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        local cb = onSelectCallback
        HideOverlay(configFrame)
        if cb then
            cb(nil)
        end
    end)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, overlayFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", topRow, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", overlayFrame, "BOTTOMRIGHT", -28, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1) -- sized dynamically
    scrollFrame:SetScrollChild(scrollChild)
    overlayFrame.scrollFrame = scrollFrame
    overlayFrame.scrollChild = scrollChild

    -- Panel header labels (positioned in PopulateTree)
    local classLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classLabel:SetText("Class")
    classLabel:SetTextColor(0.8, 0.8, 0.6, 1)
    classLabel:Hide()
    overlayFrame.classLabel = classLabel

    local specLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specLabel:SetText("Spec")
    specLabel:SetTextColor(0.8, 0.8, 0.6, 1)
    specLabel:Hide()
    overlayFrame.specLabel = specLabel

    -- Vertical divider line between panels (positioned in PopulateTree)
    local divider = scrollChild:CreateLine(nil, "ARTWORK")
    divider:SetThickness(1)
    divider:SetColorTexture(0.3, 0.3, 0.4, 0.6)
    divider:Hide()
    overlayFrame.divider = divider

    -- Escape key to go back (not close the whole config panel)
    overlayFrame:EnableKeyboard(true)
    overlayFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            HideOverlay(configFrame)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- OnHide: restore panel state if overlay hidden by parent closing
    overlayFrame:SetScript("OnHide", function()
        if isRestoring then return end
        if savedTitle then
            HideOverlay(configFrame)
        end
    end)
end

local function ShowOverlay(configFrame, currentNodeID, currentEntryID)
    -- Save title
    savedTitle = configFrame.titletext:GetText()
    configFrame:SetTitle("Pick a Talent")

    -- Hide panel elements
    configFrame.colParent:Hide()
    configFrame.versionText:Hide()
    configFrame.profileGear:Hide()
    if configFrame.profileBar:IsShown() then
        configFrame.profileBar:Hide()
    end
    configFrame.modeStatusRow:Hide()

    -- Create overlay if needed
    EnsureOverlay(configFrame)
    overlayFrame:Show()

    PopulateTree(currentNodeID, currentEntryID)
end

HideOverlay = function(configFrame)
    if isRestoring then return end
    isRestoring = true

    if overlayFrame then
        overlayFrame:Hide()
    end
    HideChoiceFrame()

    -- Restore title
    if configFrame and savedTitle then
        configFrame:SetTitle(savedTitle)
    end
    savedTitle = nil

    -- Restore panel elements
    if configFrame then
        configFrame.colParent:Show()
        configFrame.versionText:Show()
        configFrame.profileGear:Show()
        -- profileBar stays hidden (its default state — profileGear toggle controls it)
        -- modeStatusRow visibility is managed by UpdateModeNavigationUI
        if configFrame.UpdateModeNavigationUI then
            configFrame.UpdateModeNavigationUI()
        end
    end

    onSelectCallback = nil
    isRestoring = false
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
                HideOverlay(CS.configFrame)
                if cb then
                    cb(result)
                end
            end
        end)

        nodeIDToBtn[node.nodeID] = btn
    end

    return btnIndex
end

local function DrawEdges(scrollChild, allNodes, nodeIDToBtn)
    local lineIndex = 0

    for _, node in ipairs(allNodes) do
        if node.visibleEdges then
            local srcBtn = nodeIDToBtn[node.nodeID]
            if srcBtn then
                for _, edge in ipairs(node.visibleEdges) do
                    local dstBtn = nodeIDToBtn[edge.targetNode]
                    if dstBtn then
                        lineIndex = lineIndex + 1
                        local line = edgeLines[lineIndex]
                        if not line then
                            line = scrollChild:CreateLine(nil, "BACKGROUND")
                            edgeLines[lineIndex] = line
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
    local scrollChild = overlayFrame.scrollChild

    -- Hide all existing buttons and edges
    for _, btn in ipairs(nodeButtons) do btn:Hide() end
    for _, cb in ipairs(choiceButtons) do cb:Hide() end
    for _, line in ipairs(edgeLines) do line:Hide() end
    HideChoiceFrame()

    -- Hide panel UI until we know if dual-panel mode applies
    overlayFrame.classLabel:Hide()
    overlayFrame.specLabel:Hide()
    overlayFrame.divider:Hide()

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
                        -- No cost (granted starting talents) → default to class
                        classNodes[#classNodes + 1] = record
                    end
                end
            end
        end
    end

    if #allNodes == 0 then return end

    -- Use live dimensions from overlay scroll frame
    local availW = overlayFrame.scrollFrame:GetWidth()
    local availH = overlayFrame.scrollFrame:GetHeight()

    local dualPanel = (#classNodes > 0 and #specNodes > 0)
    local nodeIDToBtn = {}
    local btnIndex = 0

    if dualPanel then
        local panelAvailWidth = (availW - PANEL_GAP) / 2
        local panelAvailHeight = availH - PANEL_HEADER_HEIGHT

        -- Class panel bounds & scale
        local cMinX, cMaxX, cMinY, cMaxY = ComputeBounds(classNodes)
        local cTreeW = cMaxX - cMinX + NODE_SIZE
        local cTreeH = cMaxY - cMinY + NODE_SIZE
        local cScaleX = cTreeW > 0 and (panelAvailWidth - NODE_PADDING * 2) / cTreeW or 1
        local cScaleY = cTreeH > 0 and (panelAvailHeight - NODE_PADDING * 2) / cTreeH or 1
        local cScale = math_min(cScaleX, cScaleY, 1.0)

        -- Spec panel bounds & scale
        local sMinX, sMaxX, sMinY, sMaxY = ComputeBounds(specNodes)
        local sTreeW = sMaxX - sMinX + NODE_SIZE
        local sTreeH = sMaxY - sMinY + NODE_SIZE
        local sScaleX = sTreeW > 0 and (panelAvailWidth - NODE_PADDING * 2) / sTreeW or 1
        local sScaleY = sTreeH > 0 and (panelAvailHeight - NODE_PADDING * 2) / sTreeH or 1
        local sScale = math_min(sScaleX, sScaleY, 1.0)

        local classContentH = cTreeH * cScale + NODE_PADDING * 2 + PANEL_HEADER_HEIGHT
        local specContentH = sTreeH * sScale + NODE_PADDING * 2 + PANEL_HEADER_HEIGHT
        local contentHeight = math_max(classContentH, specContentH)
        local contentWidth = panelAvailWidth * 2 + PANEL_GAP

        scrollChild:SetSize(math_max(contentWidth, availW),
                            math_max(contentHeight, panelAvailHeight))

        -- Place class nodes (left panel)
        btnIndex = PlaceNodesInPanel(scrollChild, classNodes, 0, PANEL_HEADER_HEIGHT,
            cMinX, cMinY, cScale, currentNodeID, currentEntryID, btnIndex, nodeIDToBtn)

        -- Place spec nodes (right panel)
        btnIndex = PlaceNodesInPanel(scrollChild, specNodes,
            panelAvailWidth + PANEL_GAP, PANEL_HEADER_HEIGHT,
            sMinX, sMinY, sScale, currentNodeID, currentEntryID, btnIndex, nodeIDToBtn)

        -- Panel header labels
        overlayFrame.classLabel:ClearAllPoints()
        overlayFrame.classLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", NODE_PADDING, 0)
        overlayFrame.classLabel:Show()

        overlayFrame.specLabel:ClearAllPoints()
        overlayFrame.specLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT",
            panelAvailWidth + PANEL_GAP + NODE_PADDING, 0)
        overlayFrame.specLabel:Show()

        -- Vertical divider between panels
        local dividerX = panelAvailWidth + PANEL_GAP / 2
        overlayFrame.divider:ClearAllPoints()
        overlayFrame.divider:SetStartPoint("TOPLEFT", scrollChild, dividerX, 0)
        overlayFrame.divider:SetEndPoint("BOTTOMLEFT", scrollChild, dividerX, 0)
        overlayFrame.divider:Show()
    else
        -- Single-panel fallback (currency detection failed or all nodes in one category)
        local minX, maxX, minY, maxY = ComputeBounds(allNodes)
        local treeWidth = maxX - minX + NODE_SIZE
        local treeHeight = maxY - minY + NODE_SIZE

        local scaleX = treeWidth > 0 and (availW - NODE_PADDING * 2) / treeWidth or 1
        local scaleY = treeHeight > 0 and (availH - NODE_PADDING * 2) / treeHeight or 1
        local scale = math_min(scaleX, scaleY, 1.0)

        local contentWidth = treeWidth * scale + NODE_PADDING * 2
        local contentHeight = treeHeight * scale + NODE_PADDING * 2
        scrollChild:SetSize(math_max(contentWidth, availW),
                            math_max(contentHeight, availH))

        btnIndex = PlaceNodesInPanel(scrollChild, allNodes, 0, 0,
            minX, minY, scale, currentNodeID, currentEntryID, btnIndex, nodeIDToBtn)
    end

    -- Draw edge connector lines
    DrawEdges(scrollChild, allNodes, nodeIDToBtn)
end

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------

-- Open the talent picker overlay inside the config panel.
-- callback(result): called with { nodeID, entryID, spellID, talentName } or nil (clear).
-- currentNodeID/currentEntryID: highlight current selection.
function CooldownCompanion:OpenTalentPicker(callback, currentNodeID, currentEntryID)
    local configFrame = CS.configFrame
    if not configFrame then return end
    onSelectCallback = callback
    ShowOverlay(configFrame, currentNodeID, currentEntryID)
end

function CooldownCompanion:IsTalentPickerOpen()
    return overlayFrame and overlayFrame:IsShown()
end
