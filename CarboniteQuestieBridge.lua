local ADDON_NAME = ...

local Bridge = CreateFrame("Frame")
Bridge:RegisterEvent("ADDON_LOADED")
Bridge:RegisterEvent("PLAYER_LOGIN")

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
end

local function DebugPrintMarker(data, areaID, x, y)
    if not CarboniteQuestieBridgeDB or not CarboniteQuestieBridgeDB.debug then
        return
    end

    local questId = data and data.Id or "?"
    local starterName = data and data.Name or "?"
    local iconType = data and data.Icon or "?"
    local markerType = data and data.Type or "?"

    Print(string.format(
        "Questie marker quest=%s starter=%s icon=%s type=%s area=%s x=%.2f y=%.2f",
        tostring(questId),
        tostring(starterName),
        tostring(iconType),
        tostring(markerType),
        tostring(areaID),
        tonumber(x) or 0,
        tonumber(y) or 0
    ))
end

local function InstallQuestieHook()
    if Bridge.questieHookInstalled then
        return true
    end

    if not QuestieLoader or not QuestieLoader.ImportModule then
        return false
    end

    local ok, QuestieMap = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieMap")
    if not ok or not QuestieMap or type(QuestieMap.DrawWorldIcon) ~= "function" then
        return false
    end

    hooksecurefunc(QuestieMap, "DrawWorldIcon", function(_, data, areaID, x, y)
        if data and data.Type == "available" then
            DebugPrintMarker(data, areaID, x, y)
        end
    end)

    Bridge.questieHookInstalled = true
    Print("Questie marker hook installed.")
    return true
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
    elseif command == "status" then
        Print("version 0.1.1; Questie hook " .. (Bridge.questieHookInstalled and "installed" or "not installed") .. "; debug " .. (CarboniteQuestieBridgeDB.debug and "on" or "off"))
    else
        Print("commands: /cqb status, /cqb debug on, /cqb debug off")
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
