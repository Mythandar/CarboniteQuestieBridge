local ADDON_NAME = ...
local Bridge = CreateFrame("Frame")
Bridge.elapsed = 0
Bridge.registered = false
Bridge.enabled = true
Bridge.mapNameIndex = nil
Bridge.mapCache = {}
Bridge.markerCount = 0
Bridge.unresolvedCount = 0

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
end

local function Version()
    return GetAddOnMetadata(ADDON_NAME or "CarboniteQuestieBridge", "Version") or "unknown"
end

local function Normalize(value)
    value = string.lower(tostring(value or ""))
    value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
    value = value:gsub("|r", "")
    return value:gsub("[%p%s]", "")
end

local function GetQuestieAPI()
    if type(_G.QuestieMapAPI) == "table" then return _G.QuestieMapAPI end
    if QuestieLoader and type(QuestieLoader.ImportModule) == "function" then
        local ok, api = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieMapAPI")
        if ok then return api end
    end
end

local function BuildMapIndex()
    if Bridge.mapNameIndex then return Bridge.mapNameIndex end
    if not Nx then return nil end
    local index = {}
    if type(Nx.MITN) == "table" then
        for id, name in pairs(Nx.MITN) do
            if type(id) == "number" and type(name) == "string" then
                index[Normalize(name)] = id
            end
        end
    end
    if Nx.Map and type(Nx.Map.MWI) == "table" then
        for id, data in pairs(Nx.Map.MWI) do
            if type(id) == "number" and type(data) == "table" and data.Nam then
                index[Normalize(data.Nam)] = id
            end
        end
    end
    Bridge.mapNameIndex = index
    return index
end

local EXPLICIT_MAPS = {
    [1453] = 2020, -- Stormwind City
    [1436] = 2027, -- Westfall
    [1457] = 1006, -- Darnassus
    [1438] = 1018, -- Teldrassil
}

local function ResolveMap(uiMapId)
    uiMapId = tonumber(uiMapId)
    if not uiMapId then return nil end
    if Bridge.mapCache[uiMapId] ~= nil then return Bridge.mapCache[uiMapId] or nil end
    if EXPLICIT_MAPS[uiMapId] then
        Bridge.mapCache[uiMapId] = EXPLICIT_MAPS[uiMapId]
        return EXPLICIT_MAPS[uiMapId]
    end

    local mapName
    local C_Map = QuestieCompat and QuestieCompat.C_Map
    if C_Map and type(C_Map.GetMapInfo) == "function" then
        local ok, info = pcall(C_Map.GetMapInfo, uiMapId)
        if ok and type(info) == "table" then mapName = info.name end
    end

    local index = BuildMapIndex()
    local id = index and mapName and index[Normalize(mapName)] or nil
    Bridge.mapCache[uiMapId] = id or false
    return id
end

local Provider = { enabled = true }

function Provider:GetMarkers()
    local api = GetQuestieAPI()
    local output = {}
    Bridge.unresolvedCount = 0
    if not Bridge.enabled or not api or type(api.GetAvailableQuestMarkers) ~= "function" then
        Bridge.markerCount = 0
        return output
    end

    local markers = api:GetAvailableQuestMarkers()
    for _, marker in ipairs(markers or {}) do
        local mapId = ResolveMap(marker.uiMapId)
        if mapId then
            marker.carboniteMapId = mapId
            output[#output + 1] = marker
        else
            Bridge.unresolvedCount = Bridge.unresolvedCount + 1
        end
    end
    Bridge.markerCount = #output
    return output
end

function Provider:GetTooltip(marker)
    local level = marker.level or marker.requiredLevel or "?"
    return string.format(
        "|cff33ff99Questie Available Quest|r\n%s\nQuest giver: %s\nLevel %s\nQuest ID: %s",
        tostring(marker.title or "Unknown quest"),
        tostring(marker.giverName or "Unknown"),
        tostring(level),
        tostring(marker.questId or "?")
    )
end

function Provider:GetStyle(marker)
    local level = tonumber(marker.level or marker.requiredLevel) or UnitLevel("player")
    local r, g, b = 1, .82, 0
    if type(GetQuestDifficultyColor) == "function" then
        local colour = GetQuestDifficultyColor(level)
        if colour then r, g, b = colour.r or r, colour.g or g, colour.b or b end
    end
    if marker.daily then r, g, b = .2, .55, 1 end
    if marker.repeatable then r, g, b = .25, .9, 1 end
    return { r = r, g = g, b = b, scale = 1 }
end

local function Refresh()
    local api = _G.CarboniteExternalMarkerAPI
    if api and type(api.RefreshExternalMarkers) == "function" then
        api:RefreshExternalMarkers("Questie")
    end
end

local function MarkerListener(event)
    if event == "RESET" then Refresh() end
end

local function Register()
    if Bridge.registered then return true end
    local questie = GetQuestieAPI()
    local carbonite = _G.CarboniteExternalMarkerAPI
    if not questie or not carbonite or type(carbonite.RegisterExternalMarkerProvider) ~= "function" then
        return false
    end

    carbonite:RegisterExternalMarkerProvider("Questie", Provider)
    carbonite:SetNativeAvailableQuestGiversEnabled(false)
    if type(questie.RegisterMarkerListener) == "function" then
        questie:RegisterMarkerListener(MarkerListener)
    end
    Bridge.registered = true
    Print("formal Questie/Carbonite integration " .. Version() .. " registered")
    Refresh()
    return true
end

SLASH_CARBONITEQUESTIEBRIDGE1 = "/cqb"
SlashCmdList.CARBONITEQUESTIEBRIDGE = function(message)
    local command = string.lower((tostring(message or ""):match("^%s*(.-)%s*$")))
    local carbonite = _G.CarboniteExternalMarkerAPI
    if command == "refresh" or command == "scan" then
        Bridge.mapCache = {}
        Bridge.mapNameIndex = nil
        Refresh()
        Print("external markers refreshed")
    elseif command == "icons on" then
        Bridge.enabled = true
        Provider.enabled = true
        Refresh()
    elseif command == "icons off" then
        Bridge.enabled = false
        Provider.enabled = false
        Refresh()
    elseif command == "native on" then
        if carbonite then carbonite:SetNativeAvailableQuestGiversEnabled(true) end
        Print("Carbonite native available quests enabled; reopen or move the map")
    elseif command == "native off" then
        if carbonite then carbonite:SetNativeAvailableQuestGiversEnabled(false) end
        Print("Carbonite native available quests suppressed; reopen or move the map")
    elseif command == "status" then
        Print(string.format(
            "version %s; formal API %s; markers %d; unresolved %d; icons %s; native quests %s",
            Version(),
            Bridge.registered and "registered" or "waiting",
            Bridge.markerCount,
            Bridge.unresolvedCount,
            Bridge.enabled and "on" or "off",
            carbonite and carbonite:IsNativeAvailableQuestGiversEnabled() and "on" or "off"
        ))
    else
        Print("commands: /cqb status, /cqb refresh, /cqb icons on|off, /cqb native on|off")
    end
end

Bridge:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed >= .5 then
        self.elapsed = 0
        Register()
    end
end)

_G.CarboniteQuestieBridge = Bridge
