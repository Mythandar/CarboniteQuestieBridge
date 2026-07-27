local ADDON_NAME = ...
local VERSION = "0.2.0"

local Bridge = CreateFrame("Frame")
Bridge:RegisterEvent("ADDON_LOADED")
Bridge:RegisterEvent("PLAYER_LOGIN")
Bridge.markers = {}
Bridge.markerCount = 0

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
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
        "Questie marker quest=%s starter=%s icon=%s type=%s area=%s x=%.2f y=%.2f",
        tostring(data and data.Id or "?"),
        tostring(data and data.Name or "?"),
        tostring(data and data.Icon or "?"),
        tostring(data and data.Type or "?"),
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

local function ScanExistingQuestieMarkers()
    local QuestieMap = GetQuestieMap()
    if not QuestieMap or type(QuestieMap.questIdFrames) ~= "table" then
        Print("scan failed: Questie map frames are not available")
        return
    end

    Bridge.markers = {}
    Bridge.markerCount = 0

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

    Print(string.format(
        "scan found %d available world-map markers across %d quests in %d areas",
        Bridge.markerCount,
        questCount,
        areaCount
    ))

    local shown = 0
    for _, marker in pairs(Bridge.markers) do
        shown = shown + 1
        Print(string.format(
            "quest=%s starter=%s icon=%s area=%s x=%.2f y=%.2f",
            tostring(marker.questId),
            tostring(marker.starter),
            tostring(marker.icon),
            tostring(marker.areaID),
            tonumber(marker.x) or 0,
            tonumber(marker.y) or 0
        ))
        if shown >= 20 then
            break
        end
    end

    if Bridge.markerCount > shown then
        Print(string.format("showing first %d markers; %d more cached", shown, Bridge.markerCount - shown))
    end
end

local function SetDebug(enabled)
    CarboniteQuestieBridgeDB.debug = enabled and true or false
    Print("debug logging " .. (CarboniteQuestieBridgeDB.debug and "enabled" or "disabled"))
end

SLASH_CARBONITEQUESTIEBRIDGE1 = "/cqb"
SlashCmdList.CARBONITEQUESTIEBRIDGE = function(message)
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))

    if command == "debug on" then
        SetDebug(true)
    elseif command == "debug off" then
        SetDebug(false)
    elseif command == "scan" then
        ScanExistingQuestieMarkers()
    elseif command == "status" then
        Print("version " .. VERSION .. "; Questie hook " .. (Bridge.questieHookInstalled and "installed" or "not installed") .. "; cached markers " .. tostring(Bridge.markerCount) .. "; debug " .. (CarboniteQuestieBridgeDB.debug and "on" or "off"))
    else
        Print("commands: /cqb status, /cqb scan, /cqb debug on, /cqb debug off")
    end
end

Bridge:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON_NAME then
        CarboniteQuestieBridgeDB = CarboniteQuestieBridgeDB or {}
        if CarboniteQuestieBridgeDB.debug == nil then
            CarboniteQuestieBridgeDB.debug = false
        end
    end

    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        InstallQuestieHook()
    end
end)
