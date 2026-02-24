--[[
    CooldownCompanion - Config/AutoImport
    Auto-add import flow for selected group (Action Bars 1-6 / Spellbook / CDM Auras).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local IsPassiveOrProc = ST._IsPassiveOrProc
local IsSpellInCDMBuffBar = ST._IsSpellInCDMBuffBar
local IsSpellInCDMCooldown = ST._IsSpellInCDMCooldown
local IsNeverTrackableSpell = ST._IsNeverTrackableSpell
local ShouldSuppressSpellbookEntry = ST._ShouldSuppressSpellbookEntry

local ICON_FALLBACK = 134400
local ACTION_BAR_COUNT = 6
local BUTTONS_PER_BAR = 12

local previewWindow
local RenderPreview

local function ReleaseWindowIfOpen(windowRef)
    if windowRef then
        windowRef:Hide()
    end
end

local function CreateDefaultBarSelection()
    local selectedBars = {}
    for i = 1, ACTION_BAR_COUNT do
        selectedBars[i] = true
    end
    return selectedBars
end

local function CreatePreviewResult()
    return {
        spells = {},
        auras = {},
        items = {},
        skipped = {},
    }
end

local function AddSkipped(result, sourceLabel, reason, name)
    result.skipped[#result.skipped + 1] = {
        source = sourceLabel,
        reason = reason,
        name = name or "Unknown",
    }
end

local function TryAddEntry(result, seen, bucketKey, entry, sourceLabel)
    local dedupeKey
    if bucketKey == "items" then
        dedupeKey = "item:" .. tostring(entry.id)
    elseif bucketKey == "auras" then
        dedupeKey = "spell:" .. tostring(entry.id) .. ":aura"
    else
        dedupeKey = "spell:" .. tostring(entry.id) .. ":spell"
    end

    if seen[dedupeKey] then
        AddSkipped(result, sourceLabel, "Duplicate entry in this import selection.", entry.name)
        return
    end

    seen[dedupeKey] = true
    entry.importKey = dedupeKey
    result[bucketKey][#result[bucketKey] + 1] = entry
end

local function BuildActionBarPreview(selectedBars)
    local result = CreatePreviewResult()
    local seen = {}
    local hasSelectedBar = false

    for barIndex = 1, ACTION_BAR_COUNT do
        if selectedBars[barIndex] then
            hasSelectedBar = true
            for buttonIndex = 1, BUTTONS_PER_BAR do
                local slot = ((barIndex - 1) * BUTTONS_PER_BAR) + buttonIndex
                local sourceLabel = "Bar " .. barIndex .. " Slot " .. buttonIndex

                if C_ActionBar.HasAction(slot) then
                    if C_ActionBar.IsItemAction(slot) then
                        -- C_ActionBar has no GetActionInfo API in 12.0.x; GetActionInfo
                        -- remains the supported way to read item action IDs from slots.
                        local actionType, id = GetActionInfo(slot)
                        local itemID = tonumber(id)
                        if actionType ~= "item" or not itemID then
                            local shownType = actionType or "unknown"
                            AddSkipped(result, sourceLabel, "Unsupported action type: " .. shownType .. ".", "Unknown")
                        else
                            local itemName = C_Item.GetItemNameByID(itemID) or ("Item " .. itemID)
                            if not C_Item.GetItemSpell(itemID) then
                                AddSkipped(result, sourceLabel, "Item has no usable effect.", itemName)
                            else
                                TryAddEntry(result, seen, "items", {
                                    type = "item",
                                    id = itemID,
                                    name = itemName,
                                    icon = C_Item.GetItemIconByID(itemID) or C_ActionBar.GetActionTexture(slot) or ICON_FALLBACK,
                                    source = sourceLabel,
                                }, sourceLabel)
                            end
                        end
                    else
                        local spellID = C_ActionBar.GetSpell(slot)
                        if spellID and spellID ~= 0 then
                            local spellInfo = C_Spell.GetSpellInfo(spellID)
                            local spellName = spellInfo and spellInfo.name
                            if not spellName then
                                AddSkipped(result, sourceLabel, "Spell data is unavailable.", "Spell " .. spellID)
                            elseif IsNeverTrackableSpell(spellID) then
                                -- Omit known non-trackable spells from preview.
                            else
                                local isAura = IsPassiveOrProc(spellID)
                                if isAura and not IsSpellInCDMBuffBar(spellID) then
                                    AddSkipped(result, sourceLabel, "Passive/proc spell is not tracked in CDM.", spellName)
                                else
                                    local bucketKey = isAura and "auras" or "spells"
                                    TryAddEntry(result, seen, bucketKey, {
                                        type = "spell",
                                        id = spellID,
                                        name = spellName,
                                        icon = spellInfo.iconID or C_ActionBar.GetActionTexture(slot) or ICON_FALLBACK,
                                        source = sourceLabel,
                                    }, sourceLabel)
                                end
                            end
                        else
                            local actionType = GetActionInfo(slot)
                            local shownType = actionType or "unknown"
                            AddSkipped(result, sourceLabel, "Unsupported action type: " .. shownType .. ".", "Unknown")
                        end
                    end
                end
            end
        end
    end

    if not hasSelectedBar then
        AddSkipped(result, "Action Bars", "No action bars selected.", "None")
    end

    return result
end

local function BuildSpellbookPreview()
    local result = CreatePreviewResult()
    local seen = {}

    local function AddSpellbookEntry(itemInfo, sourceLabel, skillLineIndex)
        if not itemInfo or not itemInfo.spellID then return end
        if itemInfo.isOffSpec then return end
        if itemInfo.itemType == Enum.SpellBookItemType.Flyout then return end
        if itemInfo.itemType == Enum.SpellBookItemType.FutureSpell then return end

        local spellID = itemInfo.spellID
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local spellName = (spellInfo and spellInfo.name) or itemInfo.name
        if not spellName then
            AddSkipped(result, sourceLabel, "Spell data is unavailable.", "Spell " .. spellID)
            return
        end

        local isAura = IsPassiveOrProc(spellID)
        if isAura then
            -- Spellbook Auto Add no longer imports aura entries.
            return
        end
        if ShouldSuppressSpellbookEntry(spellID, skillLineIndex, isAura) then
            -- Omit filtered spellbook entries silently to reduce preview noise.
            return
        end
        local bucketKey = isAura and "auras" or "spells"
        TryAddEntry(result, seen, bucketKey, {
            type = "spell",
            id = spellID,
            name = spellName,
            icon = itemInfo.iconID or (spellInfo and spellInfo.iconID) or ICON_FALLBACK,
            source = sourceLabel,
        }, sourceLabel)
    end

    local numLines = C_SpellBook.GetNumSpellBookSkillLines()
    for lineIdx = 1, numLines do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
        if lineInfo and not lineInfo.shouldHide then
            local sourceLabel = lineInfo.name or "Spellbook"
            for slotOffset = 1, lineInfo.numSpellBookItems do
                local slotIdx = lineInfo.itemIndexOffset + slotOffset
                local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, Enum.SpellBookSpellBank.Player)
                AddSpellbookEntry(itemInfo, sourceLabel, lineIdx)
            end
        end
    end

    local numPetSpells = C_SpellBook.HasPetSpells()
    if numPetSpells and numPetSpells > 0 then
        for slotIdx = 1, numPetSpells do
            local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, Enum.SpellBookSpellBank.Pet)
            AddSpellbookEntry(itemInfo, "Pet", itemInfo and itemInfo.skillLineIndex)
        end
    end

    return result
end

local CDM_AURA_CATEGORY_INFO = {
    { category = Enum.CooldownViewerCategory.TrackedBuff, label = "CDM Tracked Buff" },
    { category = Enum.CooldownViewerCategory.TrackedBar, label = "CDM Tracked Bar" },
}

local function BuildCDMAuraPreview()
    local result = CreatePreviewResult()
    local seen = {}

    for _, catInfo in ipairs(CDM_AURA_CATEGORY_INFO) do
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(catInfo.category, false)
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                local cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if not cooldownInfo then
                    AddSkipped(result, catInfo.label, "Missing cooldown info.", "Cooldown " .. cooldownID)
                elseif not cooldownInfo.spellID then
                    AddSkipped(result, catInfo.label, "Entry has no spell ID.", "Cooldown " .. cooldownID)
                elseif not cooldownInfo.isKnown then
                    -- Known/current-spec only; omit unknown entries silently.
                else
                    local spellInfo = C_Spell.GetSpellInfo(cooldownInfo.spellID)
                    if not spellInfo or not spellInfo.name then
                        AddSkipped(result, catInfo.label, "Spell data is unavailable.", "Spell " .. cooldownInfo.spellID)
                    else
                        TryAddEntry(result, seen, "auras", {
                            type = "spell",
                            id = cooldownInfo.spellID,
                            name = spellInfo.name,
                            icon = spellInfo.iconID or ICON_FALLBACK,
                            source = catInfo.label,
                        }, catInfo.label)
                    end
                end
            end
        end
    end

    return result
end

local function CountPreviewEntries(preview)
    local spellCount = #preview.spells
    local auraCount = #preview.auras
    local itemCount = #preview.items
    return spellCount, auraCount, itemCount, spellCount + auraCount + itemCount
end

local function IteratePreviewEntries(preview, callback)
    for _, entry in ipairs(preview.spells) do
        callback(entry, "spells")
    end
    for _, entry in ipairs(preview.auras) do
        callback(entry, "auras")
    end
    for _, entry in ipairs(preview.items) do
        callback(entry, "items")
    end
end

local function NormalizeSelectionState(preview, selectedEntries)
    local active = {}
    IteratePreviewEntries(preview, function(entry)
        if entry.importKey then
            active[entry.importKey] = true
            if selectedEntries[entry.importKey] == nil then
                selectedEntries[entry.importKey] = true
            end
        end
    end)
    for key in pairs(selectedEntries) do
        if not active[key] then
            selectedEntries[key] = nil
        end
    end
end

local function CountSelectedEntries(preview, selectedEntries)
    local spellCount, auraCount, itemCount = 0, 0, 0
    for _, entry in ipairs(preview.spells) do
        if selectedEntries[entry.importKey] then
            spellCount = spellCount + 1
        end
    end
    for _, entry in ipairs(preview.auras) do
        if selectedEntries[entry.importKey] then
            auraCount = auraCount + 1
        end
    end
    for _, entry in ipairs(preview.items) do
        if selectedEntries[entry.importKey] then
            itemCount = itemCount + 1
        end
    end
    return spellCount, auraCount, itemCount, spellCount + auraCount + itemCount
end

local function SetAllEntriesSelected(preview, selectedEntries, value)
    IteratePreviewEntries(preview, function(entry)
        if entry.importKey then
            selectedEntries[entry.importKey] = value and true or false
        end
    end)
end

local function AddSectionHeading(scroll, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)
end

local function AddSelectableEntryRow(state, scroll, entry)
    local row = AceGUI:Create("CheckBox")
    local icon = tonumber(entry.icon) or ICON_FALLBACK
    row:SetLabel("|T" .. icon .. ":15:15:0:0|t " .. (entry.name or "Unknown") .. "  |cff9d9d9d[" .. (entry.source or "Unknown Source") .. "]|r")
    row:SetValue(state.selectedEntries[entry.importKey] ~= false)
    row:SetFullWidth(true)
    row:SetCallback("OnValueChanged", function(_, _, value)
        state.selectedEntries[entry.importKey] = value and true or false
        RenderPreview(state)
    end)
    scroll:AddChild(row)
end

local function AddEmptyRow(scroll)
    local row = AceGUI:Create("Label")
    row:SetText("None")
    row:SetFullWidth(true)
    scroll:AddChild(row)
end

local function AddSkippedRow(scroll, skipped)
    local row = AceGUI:Create("Label")
    local line = "- " .. skipped.name .. " [" .. skipped.source .. "]: " .. skipped.reason
    row:SetText(line)
    row:SetFullWidth(true)
    scroll:AddChild(row)
end

local function ApplyPreviewToGroup(groupID, preview, selectedEntries)
    selectedEntries = selectedEntries or {}
    local group = CooldownCompanion.db.profile.groups[groupID]
    if not group then
        CooldownCompanion:Print("Selected group no longer exists.")
        return false
    end

    local addedSpells, addedAuras, addedItems = 0, 0, 0
    local applySkipped = 0

    for _, entry in ipairs(preview.spells) do
        if selectedEntries[entry.importKey] then
            local spellInfo = C_Spell.GetSpellInfo(entry.id)
            if spellInfo and spellInfo.name then
                local forceAura = nil
                if IsSpellInCDMCooldown(entry.id) and IsSpellInCDMBuffBar(entry.id) then
                    forceAura = false
                end
                CooldownCompanion:AddButtonToGroup(groupID, "spell", entry.id, spellInfo.name, nil, nil, forceAura)
                addedSpells = addedSpells + 1
            else
                applySkipped = applySkipped + 1
            end
        end
    end

    for _, entry in ipairs(preview.auras) do
        if selectedEntries[entry.importKey] then
            local spellInfo = C_Spell.GetSpellInfo(entry.id)
            if spellInfo and spellInfo.name then
                local isPassive = IsPassiveOrProc(entry.id) and true or nil
                CooldownCompanion:AddButtonToGroup(groupID, "spell", entry.id, spellInfo.name, nil, isPassive, true)
                addedAuras = addedAuras + 1
            else
                applySkipped = applySkipped + 1
            end
        end
    end

    for _, entry in ipairs(preview.items) do
        if selectedEntries[entry.importKey] then
            if C_Item.GetItemSpell(entry.id) then
                local itemName = C_Item.GetItemNameByID(entry.id) or entry.name or ("Item " .. entry.id)
                CooldownCompanion:AddButtonToGroup(groupID, "item", entry.id, itemName)
                addedItems = addedItems + 1
            else
                applySkipped = applySkipped + 1
            end
        end
    end

    CooldownCompanion:RefreshConfigPanel()
    local totalAdded = addedSpells + addedAuras + addedItems
    CooldownCompanion:Print(
        "Auto Add complete: "
        .. totalAdded .. " added ("
        .. addedSpells .. " spells, "
        .. addedAuras .. " auras, "
        .. addedItems .. " items). "
        .. applySkipped .. " skipped during apply."
    )
    return true
end

RenderPreview = function(state)
    if not state or not state.summaryLabel or not state.previewScroll then return end
    state.selectedEntries = state.selectedEntries or {}
    if state.source == "actionbars" and not state.selectedBars then
        state.selectedBars = CreateDefaultBarSelection()
    end

    local preview
    if state.source == "actionbars" then
        preview = BuildActionBarPreview(state.selectedBars)
    elseif state.source == "spellbook" then
        preview = BuildSpellbookPreview()
    else
        preview = BuildCDMAuraPreview()
    end
    state.preview = preview
    NormalizeSelectionState(preview, state.selectedEntries)

    local spellCount, auraCount, itemCount, totalCount = CountPreviewEntries(preview)
    local selectedSpellCount, selectedAuraCount, selectedItemCount, selectedTotalCount =
        CountSelectedEntries(preview, state.selectedEntries)
    state.summaryLabel:SetText(
        "Preview: " .. selectedTotalCount .. "/" .. totalCount .. " selected ("
        .. selectedSpellCount .. "/" .. spellCount .. " spells, "
        .. selectedAuraCount .. "/" .. auraCount .. " auras, "
        .. selectedItemCount .. "/" .. itemCount .. " items), "
        .. #preview.skipped .. " skipped."
    )

    state.previewScroll:ReleaseChildren()

    if spellCount > 0 then
        AddSectionHeading(state.previewScroll, "Spells (" .. spellCount .. ")")
        for _, entry in ipairs(preview.spells) do
            AddSelectableEntryRow(state, state.previewScroll, entry)
        end
    end

    if auraCount > 0 then
        AddSectionHeading(state.previewScroll, "Auras (" .. auraCount .. ")")
        for _, entry in ipairs(preview.auras) do
            AddSelectableEntryRow(state, state.previewScroll, entry)
        end
    end

    if itemCount > 0 then
        AddSectionHeading(state.previewScroll, "Items (" .. itemCount .. ")")
        for _, entry in ipairs(preview.items) do
            AddSelectableEntryRow(state, state.previewScroll, entry)
        end
    end

    if #preview.skipped > 0 then
        AddSectionHeading(state.previewScroll, "Skipped (" .. #preview.skipped .. ")")
        for _, skipped in ipairs(preview.skipped) do
            AddSkippedRow(state.previewScroll, skipped)
        end
    end
end

local function OpenPreviewWindow(state)
    ReleaseWindowIfOpen(previewWindow)
    previewWindow = nil

    state.source = state.source or "actionbars"
    if state.source ~= "actionbars" and state.source ~= "spellbook" and state.source ~= "cdm_auras" then
        state.source = "actionbars"
    end
    if not state.selectedBars then
        state.selectedBars = CreateDefaultBarSelection()
    end

    local window = AceGUI:Create("Window")
    window:SetTitle("Auto Add Preview")
    window:SetWidth(760)
    window:SetHeight(620)
    window:SetLayout("List")
    window.frame:SetFrameStrata("FULLSCREEN_DIALOG")

    local titleLabel = AceGUI:Create("Label")
    titleLabel:SetText("")
    titleLabel:SetFullWidth(true)
    window:AddChild(titleLabel)
    state.sourceLabel = titleLabel

    local sourceRow = AceGUI:Create("SimpleGroup")
    sourceRow:SetFullWidth(true)
    sourceRow:SetLayout("Flow")

    local actionSourceBtn = AceGUI:Create("Button")
    actionSourceBtn:SetText("Action Bars")
    actionSourceBtn:SetRelativeWidth(0.33)
    sourceRow:AddChild(actionSourceBtn)

    local spellbookSourceBtn = AceGUI:Create("Button")
    spellbookSourceBtn:SetText("Spellbook")
    spellbookSourceBtn:SetRelativeWidth(0.33)
    sourceRow:AddChild(spellbookSourceBtn)

    local cdmAurasSourceBtn = AceGUI:Create("Button")
    cdmAurasSourceBtn:SetText("CDM Auras")
    cdmAurasSourceBtn:SetRelativeWidth(0.33)
    sourceRow:AddChild(cdmAurasSourceBtn)

    window:AddChild(sourceRow)

    local barsRow = AceGUI:Create("SimpleGroup")
    barsRow:SetFullWidth(true)
    barsRow:SetLayout("Flow")
    state.barCheckboxes = {}
    state.updatingBarSelection = false

    for barIndex = 1, ACTION_BAR_COUNT do
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel("Bar " .. barIndex)
        cb:SetWidth(65)
        cb:SetValue(state.selectedBars[barIndex] == true)
        cb:SetCallback("OnValueChanged", function(_, _, value)
            state.selectedBars[barIndex] = value and true or false
            if state.source == "actionbars" and not state.updatingBarSelection then
                RenderPreview(state)
            end
        end)
        state.barCheckboxes[barIndex] = cb
        barsRow:AddChild(cb)
    end

    local allBtn = AceGUI:Create("Button")
    allBtn:SetText("All")
    allBtn:SetWidth(70)
    allBtn:SetCallback("OnClick", function()
        state.updatingBarSelection = true
        for i = 1, ACTION_BAR_COUNT do
            state.selectedBars[i] = true
            local cb = state.barCheckboxes[i]
            if cb then cb:SetValue(true) end
        end
        state.updatingBarSelection = false
        if state.source == "actionbars" then
            RenderPreview(state)
        end
    end)
    barsRow:AddChild(allBtn)

    local noneBtn = AceGUI:Create("Button")
    noneBtn:SetText("None")
    noneBtn:SetWidth(70)
    noneBtn:SetCallback("OnClick", function()
        state.updatingBarSelection = true
        for i = 1, ACTION_BAR_COUNT do
            state.selectedBars[i] = false
            local cb = state.barCheckboxes[i]
            if cb then cb:SetValue(false) end
        end
        state.updatingBarSelection = false
        if state.source == "actionbars" then
            RenderPreview(state)
        end
    end)
    barsRow:AddChild(noneBtn)

    window:AddChild(barsRow)
    state.barsRow = barsRow

    local function UpdateSourceUI()
        if state.source == "actionbars" then
            state.sourceLabel:SetText("Source: Action Bars 1-6. Select bars to include, then confirm.")
            if state.barsRow and state.barsRow.frame then
                state.barsRow.frame:Show()
            end
        elseif state.source == "spellbook" then
            state.sourceLabel:SetText("Source: Spellbook (Player + Pet). Aura entries are excluded. Items are not included.")
            if state.barsRow and state.barsRow.frame then
                state.barsRow.frame:Hide()
            end
        else
            state.sourceLabel:SetText("Source: Cooldown Manager Auras (Tracked Buff + Tracked Bar, known only).")
            if state.barsRow and state.barsRow.frame then
                state.barsRow.frame:Hide()
            end
        end

        actionSourceBtn:SetDisabled(state.source == "actionbars")
        spellbookSourceBtn:SetDisabled(state.source == "spellbook")
        cdmAurasSourceBtn:SetDisabled(state.source == "cdm_auras")
    end

    local function SetSource(newSource)
        if newSource ~= "actionbars" and newSource ~= "spellbook" and newSource ~= "cdm_auras" then return end
        if state.source == newSource then return end
        state.source = newSource
        state.selectedEntries = {}
        if state.source == "actionbars" and not state.selectedBars then
            state.selectedBars = CreateDefaultBarSelection()
        end
        UpdateSourceUI()
        RenderPreview(state)
    end

    actionSourceBtn:SetCallback("OnClick", function()
        SetSource("actionbars")
    end)
    spellbookSourceBtn:SetCallback("OnClick", function()
        SetSource("spellbook")
    end)
    cdmAurasSourceBtn:SetCallback("OnClick", function()
        SetSource("cdm_auras")
    end)

    local summaryLabel = AceGUI:Create("Label")
    summaryLabel:SetText("Building preview...")
    summaryLabel:SetFullWidth(true)
    window:AddChild(summaryLabel)

    local selectRow = AceGUI:Create("SimpleGroup")
    selectRow:SetFullWidth(true)
    selectRow:SetLayout("Flow")

    local selectAllBtn = AceGUI:Create("Button")
    selectAllBtn:SetText("Select All Entries")
    selectAllBtn:SetRelativeWidth(0.5)
    selectAllBtn:SetCallback("OnClick", function()
        if not state.preview then return end
        SetAllEntriesSelected(state.preview, state.selectedEntries, true)
        RenderPreview(state)
    end)
    selectRow:AddChild(selectAllBtn)

    local selectNoneBtn = AceGUI:Create("Button")
    selectNoneBtn:SetText("Select None")
    selectNoneBtn:SetRelativeWidth(0.5)
    selectNoneBtn:SetCallback("OnClick", function()
        if not state.preview then return end
        SetAllEntriesSelected(state.preview, state.selectedEntries, false)
        RenderPreview(state)
    end)
    selectRow:AddChild(selectNoneBtn)

    window:AddChild(selectRow)

    local previewScroll = AceGUI:Create("ScrollFrame")
    previewScroll:SetLayout("List")
    previewScroll:SetFullWidth(true)
    previewScroll:SetHeight(395)
    window:AddChild(previewScroll)

    local buttonRow = AceGUI:Create("SimpleGroup")
    buttonRow:SetFullWidth(true)
    buttonRow:SetLayout("Flow")

    local confirmBtn = AceGUI:Create("Button")
    confirmBtn:SetText("Add To Selected Group")
    confirmBtn:SetRelativeWidth(0.5)
    confirmBtn:SetCallback("OnClick", function()
        if not state.preview then return end

        local _, _, _, selectedCount = CountSelectedEntries(state.preview, state.selectedEntries)
        if selectedCount == 0 then
            CooldownCompanion:Print("No selected entries to add from this preview.")
            return
        end

        if ApplyPreviewToGroup(state.groupID, state.preview, state.selectedEntries) then
            window:Hide()
        end
    end)
    buttonRow:AddChild(confirmBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetRelativeWidth(0.5)
    cancelBtn:SetCallback("OnClick", function()
        window:Hide()
    end)
    buttonRow:AddChild(cancelBtn)

    window:AddChild(buttonRow)

    state.summaryLabel = summaryLabel
    state.previewScroll = previewScroll

    window:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        if previewWindow == widget then
            previewWindow = nil
        end
    end)

    previewWindow = window
    UpdateSourceUI()
    RenderPreview(state)
end

local function OpenAutoAddFlow()
    local groupID = CS.selectedGroup
    if not groupID or not CooldownCompanion.db.profile.groups[groupID] then
        CooldownCompanion:Print("Select a group first.")
        return
    end

    OpenPreviewWindow({
        groupID = groupID,
        source = "actionbars",
        selectedBars = CreateDefaultBarSelection(),
        selectedEntries = {},
    })
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._OpenAutoAddFlow = OpenAutoAddFlow
