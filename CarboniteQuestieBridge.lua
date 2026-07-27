local ADDON_NAME = ...
local VERSION = "0.5.0"

local Bridge = CreateFrame("Frame")
Bridge:RegisterEvent("ADDON_LOADED")
Bridge:RegisterEvent("PLAYER_LOGIN")
Bridge.markers = {}
Bridge.markerCount = 0
Bridge.uiMapToCarboniteMap = {}
Bridge.carboniteNameIndex = nil
Bridge.unresolvedMaps = {}
Bridge.elapsed = 0
Bridge.fadeElapsed = 0
Bridge.initialScanDone = false
Bridge.drawCount = 0
Bridge.mappedCount = 0
Bridge.activeFrames = {}
Bridge.activeMap = nil

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

local function GetQuestieModule(name)
    if not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then
        return nil
    end
    local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    return ok and module or nil
end

local function GetQuestieMap()
    return GetQuestieModule("QuestieMap")
end

local function GetQuestieZoneDB()
    return GetQuestieModule("ZoneDB")
end

local function GetQuestieDB()
    return GetQuestieModule("QuestieDB")
end

local function GetQuestieUiMapID(areaID)
    local ZoneDB = GetQuestieZoneDB()
    if ZoneDB and type(ZoneDB.GetUiMapIdByAreaId) == "function" then
        return ZoneDB:GetUiMapIdByAreaId(areaID)
    end
    return nil
end

local function GetUiMapName(uiMapID)
    local C_Map = QuestieCompat and QuestieCompat.C_Map
    if not C_Map or type(C_Map.GetMapInfo) ~= "function" then
        return nil
    end
    local ok, mapInfo = pcall(C_Map.GetMapInfo, uiMapID)
    return ok and type(mapInfo) == "table" and mapInfo.name or nil
end

local function MarkerKey(data, areaID, uiMapID, x, y)
    return table.concat({
        tostring(data and data.Id or "?"),
        tostring(areaID or "?"),
        tostring(uiMapID or "?"),
        string.format("%.3f", tonumber(x) or 0),
        string.format("%.3f", tonumber(y) or 0),
        tostring(data and data.Name or "?")
    }, ":")
end

local function CacheMarker(data, areaID, uiMapID, x, y)
    if not data or data.Type ~= "available" then
        return false
    end
    if type(areaID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end

    uiMapID = tonumber(uiMapID) or GetQuestieUiMapID(areaID)
    local key = MarkerKey(data, areaID, uiMapID, x, y)
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
        uiMapID = uiMapID,
        x = x,
        y = y,
    }
    Bridge.markerCount = Bridge.markerCount + 1
    return true
end

local function DebugPrintMarker(data, areaID, uiMapID, x, y)
    if not CarboniteQuestieBridgeDB or not CarboniteQuestieBridgeDB.debug then
        return
    end
    Print(string.format(
        "Questie marker quest=%s starter=%s icon=%s area=%s uiMap=%s x=%.2f y=%.2f",
        tostring(data and data.Id or "?"),
        tostring(data and data.Name or "?"),
        tostring(data and data.Icon or "?"),
        tostring(areaID),
        tostring(uiMapID),
        tonumber(x) or 0,
        tonumber(y) or 0
    ))
end

local function AddCarboniteName(index, name, mapID)
    if type(name) ~= "string" or type(mapID) ~= "number" then
        return
    end
    local normalized = NormalizeName(name)
    if normalized ~= "" and not index[normalized] then
        index[normalized] = mapID
    end
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
        AddCarboniteName(index, name, mapID)
    end
    if Nx.Map and type(Nx.Map.MWI) == "table" then
        for mapID, mapData in pairs(Nx.Map.MWI) do
            if type(mapData) == "table" then
                AddCarboniteName(index, mapData.Nam, mapID)
            end
        end
    end

    Bridge.carboniteNameIndex = index
    return index
end

local function ResolveCarboniteMapID(uiMapID, areaID)
    local cacheKey = tonumber(uiMapID) or ("area:" .. tostring(areaID))
    if Bridge.uiMapToCarboniteMap[cacheKey] ~= nil then
        return Bridge.uiMapToCarboniteMap[cacheKey] or nil
    end

    local index = BuildCarboniteNameIndex()
    local mapName = uiMapID and GetUiMapName(uiMapID) or nil
    if not index or not mapName then
        Bridge.uiMapToCarboniteMap[cacheKey] = false
        Bridge.unresolvedMaps[cacheKey] = {
            areaID = areaID,
            uiMapID = uiMapID,
            name = mapName or "unknown",
        }
        return nil
    end

    local mapID = index[NormalizeName(mapName)]
    Bridge.uiMapToCarboniteMap[cacheKey] = mapID or false
    if mapID then
        Bridge.unresolvedMaps[cacheKey] = nil
    else
        Bridge.unresolvedMaps[cacheKey] = {
            areaID = areaID,
            uiMapID = uiMapID,
            name = mapName,
        }
    end
    return mapID
end

local function SafeQuestieCall(functionName, questId)
    local QuestieDB = GetQuestieDB()
    local func = QuestieDB and QuestieDB[functionName]
    if type(func) ~= "function" then
        return false
    end
    local ok, result = pcall(func, questId)
    return ok and result and true or false
end

local function GetQuestStyle(marker)
    local quest = marker.questData or {}
    local questId = marker.questId
    local level = tonumber(quest.level) or tonumber(quest.requiredLevel) or UnitLevel("player")
    local r, g, b = 1, 0.82, 0

    if type(GetQuestDifficultyColor) == "function" then
        local color = GetQuestDifficultyColor(level)
        if color then
            r, g, b = color.r or r, color.g or g, color.b or b
        end
    end

    local label = "Normal"
    local scale = 1

    if SafeQuestieCall("IsRaidQuest", questId) then
        r, g, b = 1, 0.25, 0.75
        label = "Raid"
        scale = 1.2
    elseif SafeQuestieCall("IsDungeonQuest", questId) then
        r, g, b = 0.35, 0.65, 1
        label = "Dungeon"
        scale = 1.15
    elseif SafeQuestieCall("IsPvPQuest", questId) then
        r, g, b = 1, 0.45, 0.1
        label = "PvP"
        scale = 1.1
    elseif quest.IsRepeatable or SafeQuestieCall("IsRepeatable", questId) then
        r, g, b = 0.25, 0.9, 1
        label = "Repeatable"
        scale = 1.05
    elseif tonumber(quest.groupSize or 0) > 1 then
        r, g, b = 0.75, 0.45, 1
        label = "Group " .. tostring(quest.groupSize)
        scale = 1.1
    end

    return {
        r = r,
        g = g,
        b = b,
        scale = scale,
        label = label,
        level = level,
    }
end

local function GetMapFadeAlpha(map)
    if map and map.Win1 and type(map.Win1.BaF) == "number" then
        return map.Win1.BaF
    end
    return 1
end

local function ApplyActiveFrameAlpha()
    local alpha = GetMapFadeAlpha(Bridge.activeMap)
    for _, frame in ipairs(Bridge.activeFrames) do
        if frame and frame:IsShown() then
            frame:SetAlpha(alpha)
        end
    end
end

local function DrawCarboniteQuestIcons(map)
    Bridge.activeFrames = {}
    Bridge.activeMap = map

    if not CarboniteQuestieBridgeDB or not CarboniteQuestieBridgeDB.iconsEnabled then
        Bridge.drawCount = 0
        return
    end
    if not map or type(map.GWP) ~= "function" or type(map.GIS) ~= "function" or type(map.CFW) ~= "function" then
        return
    end

    local baseSize = 16 * (map.INS or 1)
    local fadeAlpha = GetMapFadeAlpha(map)
    local drawn = 0
    local mapped = 0

    for _, marker in pairs(Bridge.markers) do
        local carboniteMapID = ResolveCarboniteMapID(marker.uiMapID, marker.areaID)
        if carboniteMapID then
            mapped = mapped + 1
            local wx, wy = map:GWP(carboniteMapID, marker.x, marker.y)
            local style = GetQuestStyle(marker)
            local size = baseSize * style.scale
            local frame = map:GIS(4)

            if frame and map:CFW(frame, wx, wy, size, size, 0) then
                frame.NXType = 9800
                frame.NXData = marker
                frame.NxT = string.format(
                    "|cff33ff99Questie Available Quest|r\n%s\nLevel %s - %s\nQuest ID: %s (%.1f %.1f)",
                    tostring(marker.starter or "Unknown starter"),
                    tostring(style.level or "?"),
                    style.label,
                    tostring(marker.questId or "?"),
                    marker.x,
                    marker.y
                )
                frame.tex:SetTexture(ICON_TEXTURE)
                frame.tex:SetVertexColor(style.r, style.g, style.b, 1)
                frame:SetAlpha(fadeAlpha)
                Bridge.activeFrames[#Bridge.activeFrames + 1] = frame
                drawn = drawn + 1
            end
        end
    end

    Bridge.mappedCount = mapped
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
            local uiMapID = GetQuestieUiMapID(areaID)
            CacheMarker(data, areaID, uiMapID, x, y)
            DebugPrintMarker(data, areaID, uiMapID, x, y)
        end
    end)

    Bridge.questieHookInstalled = true
    Print("Questie-335 marker hook installed.")
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
            Print("scan failed: Questie-335 map frames are not available")
        end
        return false
    end

    Bridge.markers = {}
    Bridge.markerCount = 0
    Bridge.uiMapToCarboniteMap = {}
    Bridge.carboniteNameIndex = nil
    Bridge.unresolvedMaps = {}
    Bridge.drawCount = 0
    Bridge.mappedCount = 0
    Bridge.activeFrames = {}

    local questIds = {}
    local areas = {}

    for questId, frameNames in pairs(QuestieMap.questIdFrames) do
        if type(frameNames) == "table" then
            for frameName in pairs(frameNames) do
                local frame = _G[frameName]
                if frame and frame.data and frame.data.Type == "available" and not frame.miniMapIcon then
                    local uiMapID = frame.UiMapID or GetQuestieUiMapID(frame.AreaID)
                    if CacheMarker(frame.data, frame.AreaID, uiMapID, frame.x, frame.y) then
                        questIds[questId] = true
                        areas[frame.AreaID or "?"] = true
                    end
                end
            end
        end
    end

    local questCount = 0
    for _ in pairs(questIds) do questCount = questCount + 1 end
    local areaCount = 0
    for _ in pairs(areas) do areaCount = areaCount + 1 end

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

local function PrintUnresolvedMaps()
    local count = 0
    for _, info in pairs(Bridge.unresolvedMaps) do
        Print(string.format(
            "unresolved map area=%s uiMap=%s name=%s",
            tostring(info.areaID),
            tostring(info.uiMapID),
            tostring(info.name)
        ))
        count = count + 1
        if count >= 20 then break end
    end
    if count == 0 then
        Print("no unresolved Questie-335 maps recorded")
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
        PrintUnresolvedMaps()
    elseif command == "status" then
        Print(
            "version " .. VERSION
            .. "; Questie-335 hook " .. (Bridge.questieHookInstalled and "installed" or "not installed")
            .. "; Carbonite hook " .. (Bridge.carboniteHookInstalled and "installed" or "not installed")
            .. "; cached markers " .. tostring(Bridge.markerCount)
            .. "; mapped " .. tostring(Bridge.mappedCount)
            .. "; last drawn " .. tostring(Bridge.drawCount)
            .. "; icons " .. (CarboniteQuestieBridgeDB.iconsEnabled and "on" or "off")
            .. "; styles on"
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
    self.fadeElapsed = self.fadeElapsed + elapsed
    if self.fadeElapsed >= 0.05 then
        self.fadeElapsed = 0
        ApplyActiveFrameAlpha()
    end

    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 1 then
        return
    end
    self.elapsed = 0

    InstallQuestieHook()
    InstallCarboniteHook()

    if not self.initialScanDone and self.questieHookInstalled and self.carboniteHookInstalled then
        if ScanExistingQuestieMarkers(true) then
            self.initialScanDone = true
        end
    end
end)
