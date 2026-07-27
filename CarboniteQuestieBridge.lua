local ADDON_NAME = ...
local VERSION = "0.3.0"

local Bridge = CreateFrame("Frame")
Bridge:RegisterEvent("ADDON_LOADED")
Bridge:RegisterEvent("PLAYER_LOGIN")
Bridge.markers = {}
Bridge.markerCount = 0
Bridge.areaToCarboniteMap = {}
Bridge.carboniteNameIndex = nil
Bridge.unresolvedAreas = {}
Bridge.elapsed = 0
Bridge.initialScanDone = false
Bridge.drawCount = 0

local ICON_TEXTURE = "Interface\\AddOns\\Carbonite\\Gfx\\Map\\IconExclaim"

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
end

local function Trim(value)
    return (tostring(value or ""):match("^%s*(.-)%s*$"))
end

local function NormalizeName(value)
    value = string.lower(Trim(value))
    value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
    value = value:gsub("|r", "")
    value = value:gsub("[%p%s]", "")
    return value
end

local function MarkerKey(data, areaID, x, y)
    return table.concat({
        tostring(data and data.Id or "?"),
        tostring(areaID or "?"),
        string.format("%.3f", tonumber(x) or 0),
        string.format("%.3f", tonumber(y) or 0),
        tostring(data and data.Name or "?")
    }, ":")
end

local function CacheMarker(data, areaID, x, y)
    if not data or data.Type ~= "available" then
        return false
    end

    if type(areaID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end

    local key = MarkerKey(data, areaID, x, y)
    if Bridge.markers[key] then
        return false
    end

    Bridge.markers[key] = {
        questId = data.Id,
        starter = data.Name,
        icon = data.Icon,
        markerType = data.Type,
        questData = data.QuestData,
        areaID = areaID,
        x = x,
        y = y,
    }
    Bridge.markerCount = Bridge.markerCount + 1
    return true
end

local function DebugPrintMarker(data, areaID, x, y)
    if not CarboniteQuestieBridgeDB or not CarboniteQuestieBridgeDB.debug then
        return
    end

    Print(string.format(
        "Questie marker quest=%s starter=%s icon=%s area=%s x=%.2f y=%.2f",
        tostring(data and data.Id or "?"),
        tostring(data and data.Name or "?"),
        tostring(data and data.Icon or "?"),
        tostring(areaID),
        tonumber(x) or 0,
        tonumber(y) or 0
    ))
end

local function GetQuestieMap()
    if not QuestieLoader or not QuestieLoader.ImportModule then
        return nil
    end

    local ok, QuestieMap = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieMap")
    if not ok then
        return nil
    end

    return QuestieMap
end

local function GetAreaName(areaID)
    if type(GetMapNameByID) == "function" then
        local name = GetMapNameByID(areaID)
        if name and name ~= "" then
            return name
        end
    end

    if QuestieCompat and QuestieCompat.C_Map and type(QuestieCompat.C_Map.GetAreaInfo) == "function" then
        local name = QuestieCompat.C_Map.GetAreaInfo(areaID)
        if name and name ~= "" then
            return name
        end
    end

    return nil
end

local function BuildCarboniteNameIndex()
    if Bridge.carboniteNameIndex then
        return Bridge.carboniteNameIndex
    end

    if not Nx or type(Nx.MITN) ~= "table" then
        return nil
    end

    local index = {}
    for mapID, name in pairs(Nx.MITN) do
        if type(mapID) == "number" and type(name) == "string" then
            local normalized = NormalizeName(name)
            if normalized ~= "" and not index[normalized] then
                index[normalized] = mapID
            end
        end
    end

    Bridge.carboniteNameIndex = index
    return index
end

local function ResolveCarboniteMapID(areaID)
    if Bridge.areaToCarboniteMap[areaID] ~= nil then
        return Bridge.areaToCarboniteMap[areaID] or nil
    end

    local index = BuildCarboniteNameIndex()
    local areaName = GetAreaName(areaID)
    if not index or not areaName then
        Bridge.areaToCarboniteMap[areaID] = false
        Bridge.unresolvedAreas[areaID] = areaName or "unknown"
        return nil
    end

    local normalized = NormalizeName(areaName)
    local mapID = index[normalized]

    if not mapID then
        for carboniteName, candidateID in pairs(index) do
            if carboniteName == normalized
                or carboniteName:find(normalized, 1, true)
                or normalized:find(carboniteName, 1, true) then
                mapID = candidateID
                break
            end
        end
    end

    Bridge.areaToCarboniteMap[areaID] = mapID or false
    if not mapID then
        Bridge.unresolvedAreas[areaID] = areaName
    end
    return mapID
end

local function DrawCarboniteQuestIcons(map)
    if not CarboniteQuestieBridgeDB or not CarboniteQuestieBridgeDB.iconsEnabled then
        return
    end

    if not map or type(map.GWP) ~= "function" or type(map.GIS) ~= "function" or type(map.CFW) ~= "function" then
        return
    end

    local size = 16 * (map.INS or 1)
    local drawn = 0

    for _, marker in pairs(Bridge.markers) do
        local carboniteMapID = ResolveCarboniteMapID(marker.areaID)
        if carboniteMapID then
            local wx, wy = map:GWP(carboniteMapID, marker.x, marker.y)
            if wx and wy then
                local frame = map:GIS(4)
                if frame and map:CFW(frame, wx, wy, size, size, 0) then
                    frame.NXType = 9800
                    frame.NXData = marker
                    frame.NxT = string.format(
                        "|cff33ff99Questie Available Quest|r\n%s\nQuest ID: %s (%.1f %.1f)",
                        tostring(marker.starter or "Unknown starter"),
                        tostring(marker.questId or "?"),
                        marker.x,
                        marker.y
                    )
                    frame.tex:SetVertexColor(1, 1, 1, 1)
                    frame.tex:SetTexture(ICON_TEXTURE)
                    drawn = drawn + 1
                end
            end
        end
    end

    Bridge.drawCount = drawn
end

local function InstallQuestieHook()
    if Bridge.questieHookInstalled then
        return true
    end

    local QuestieMap = GetQuestieMap()
    if not QuestieMap or type(QuestieMap.DrawWorldIcon) ~= "function" then
        return false
    end

    hooksecurefunc(QuestieMap, "DrawWorldIcon", function(_, data, areaID, x, y)
        if data and data.Type == "available" then
            CacheMarker(data, areaID, x, y)
            DebugPrintMarker(data, areaID, x, y)
        end
    end)

    Bridge.questieHookInstalled = true
    Print("Questie marker hook installed.")
    return true
end

local function InstallCarboniteHook()
    if Bridge.carboniteHookInstalled then
        return true
    end

    if not Nx or not Nx.Que or type(Nx.Que.UpI) ~= "function" then
        return false
    end

    hooksecurefunc(Nx.Que, "UpI", function(_, map)
        DrawCarboniteQuestIcons(map)
    end)

    Bridge.carboniteHookInstalled = true
    Print("Carbonite quest-icon hook installed.")
    return true
end

local function ScanExistingQuestieMarkers(quiet)
    local QuestieMap = GetQuestieMap()
    if not QuestieMap or type(QuestieMap.questIdFrames) ~= "table" then
        if not quiet then
            Print("scan failed: Questie map frames are not available")
        end
        return false
    end

    Bridge.markers = {}
    Bridge.markerCount = 0
    Bridge.areaToCarboniteMap = {}
    Bridge.unresolvedAreas = {}

    local questIds = {}
    local areas = {}

    for questId, frameNames in pairs(QuestieMap.questIdFrames) do
        if type(frameNames) == "table" then
            for frameName in pairs(frameNames) do
                local frame = _G[frameName]
                if frame and frame.data and frame.data.Type == "available" and not frame.miniMapIcon then
                    if CacheMarker(frame.data, frame.AreaID, frame.x, frame.y) then
                        questIds[questId] = true
                        areas[frame.AreaID or "?"] = true
                    end
                end
            end
        end
    end

    local questCount = 0
    for _ in pairs(questIds) do
        questCount = questCount + 1
    end

    local areaCount = 0
    for _ in pairs(areas) do
        areaCount = areaCount + 1
    end

    if not quiet then
        Print(string.format(
            "scan found %d available markers across %d quests in %d areas",
            Bridge.markerCount,
            questCount,
            areaCount
        ))
        Print("move or reopen the Carbonite map to force a redraw")
    end

    return true
end

local function SetDebug(enabled)
    CarboniteQuestieBridgeDB.debug = enabled and true or false
    Print("debug logging " .. (CarboniteQuestieBridgeDB.debug and "enabled" or "disabled"))
end

local function SetIconsEnabled(enabled)
    CarboniteQuestieBridgeDB.iconsEnabled = enabled and true or false
    Print("Carbonite quest icons " .. (CarboniteQuestieBridgeDB.iconsEnabled and "enabled" or "disabled"))
    Print("move or reopen the Carbonite map to force a redraw")
end

local function PrintUnresolvedAreas()
    local count = 0
    for areaID, name in pairs(Bridge.unresolvedAreas) do
        Print(string.format("unresolved area %s: %s", tostring(areaID), tostring(name)))
        count = count + 1
        if count >= 20 then
            break
        end
    end

    if count == 0 then
        Print("no unresolved Questie areas recorded")
    end
end

SLASH_CARBONITEQUESTIEBRIDGE1 = "/cqb"
SlashCmdList.CARBONITEQUESTIEBRIDGE = function(message)
    local command = string.lower(Trim(message))

    if command == "debug on" then
        SetDebug(true)
    elseif command == "debug off" then
        SetDebug(false)
    elseif command == "icons on" then
        SetIconsEnabled(true)
    elseif command == "icons off" then
        SetIconsEnabled(false)
    elseif command == "scan" or command == "refresh" then
        ScanExistingQuestieMarkers(false)
    elseif command == "unresolved" then
        PrintUnresolvedAreas()
    elseif command == "status" then
        Print(
            "version " .. VERSION
            .. "; Questie hook " .. (Bridge.questieHookInstalled and "installed" or "not installed")
            .. "; Carbonite hook " .. (Bridge.carboniteHookInstalled and "installed" or "not installed")
            .. "; cached markers " .. tostring(Bridge.markerCount)
            .. "; last drawn " .. tostring(Bridge.drawCount)
            .. "; icons " .. (CarboniteQuestieBridgeDB.iconsEnabled and "on" or "off")
            .. "; debug " .. (CarboniteQuestieBridgeDB.debug and "on" or "off")
        )
    else
        Print("commands: /cqb status, /cqb refresh, /cqb icons on, /cqb icons off, /cqb unresolved, /cqb debug on, /cqb debug off")
    end
end

Bridge:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        CarboniteQuestieBridgeDB = CarboniteQuestieBridgeDB or {}
        if CarboniteQuestieBridgeDB.debug == nil then
            CarboniteQuestieBridgeDB.debug = false
        end
        if CarboniteQuestieBridgeDB.iconsEnabled == nil then
            CarboniteQuestieBridgeDB.iconsEnabled = true
        end
    end

    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        InstallQuestieHook()
        InstallCarboniteHook()
    end
end)

Bridge:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 1 then
        return
    end
    self.elapsed = 0

    InstallQuestieHook()
    InstallCarboniteHook()

    if self.questieHookInstalled and not self.initialScanDone then
        if ScanExistingQuestieMarkers(true) then
            self.initialScanDone = true
        end
    end
end)
