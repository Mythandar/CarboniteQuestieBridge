local ADDON_NAME = ...
local Bridge = CreateFrame("Frame")
Bridge.elapsed = 0
Bridge.registered = false
Bridge.layerRegistered = false
Bridge.menuInstalled = false
Bridge.preparationInstalled = false
Bridge.mapNameIndex = nil
Bridge.mapCache = {}
Bridge.markerCount = 0
Bridge.unresolvedCount = 0
Bridge.lastTrackedQuestId = nil
Bridge.originalTrack = nil

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
end

local function Version()
    return GetAddOnMetadata(ADDON_NAME or "CarboniteQuestieBridge", "Version") or "unknown"
end

local function Settings()
    CarboniteQuestieBridgeDB = CarboniteQuestieBridgeDB or {}
    if CarboniteQuestieBridgeDB.iconsEnabled == nil then CarboniteQuestieBridgeDB.iconsEnabled = true end
    if CarboniteQuestieBridgeDB.nativeQuestGivers == nil then CarboniteQuestieBridgeDB.nativeQuestGivers = false end
    return CarboniteQuestieBridgeDB
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

local function GetQuestieModule(name)
    if not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then return nil end
    local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    return ok and module or nil
end

local function GetCarboniteAPI()
    return type(_G.CarboniteExternalMarkerAPI) == "table" and _G.CarboniteExternalMarkerAPI or nil
end

local function BuildMapIndex()
    if Bridge.mapNameIndex then return Bridge.mapNameIndex end
    if not Nx then return nil end
    local index = {}
    if type(Nx.MITN) == "table" then
        for id, name in pairs(Nx.MITN) do
            if type(id) == "number" and type(name) == "string" then index[Normalize(name)] = id end
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
    [1453] = 2020,
    [1436] = 2027,
    [1457] = 1006,
    [1438] = 1018,
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

local function SafeQuestType(functionName, questId)
    local db = GetQuestieModule("QuestieDB")
    local func = db and db[functionName]
    if type(func) ~= "function" then return false end
    local ok, result = pcall(func, questId)
    return ok and result and true or false
end

local function QuestTypeText(marker)
    local types = {}
    local questId = tonumber(marker.questId)
    if marker.daily or SafeQuestType("IsDailyQuest", questId) then types[#types + 1] = "Daily" end
    if marker.repeatable then types[#types + 1] = "Repeatable" end
    if marker.elite or tonumber(marker.groupSize or marker.suggestedGroup or 0) > 1 then types[#types + 1] = "Elite" end
    if SafeQuestType("IsDungeonQuest", questId) then types[#types + 1] = "Dungeon" end
    if SafeQuestType("IsRaidQuest", questId) then types[#types + 1] = "Raid" end
    if #types == 0 then types[1] = "Normal" end
    return table.concat(types, ", ")
end

local function DifficultyHex(level)
    level = tonumber(level) or UnitLevel("player") or 1
    if type(GetQuestDifficultyColor) == "function" then
        local colour = GetQuestDifficultyColor(level)
        if colour then
            local r = math.floor((colour.r or 1) * 255 + .5)
            local g = math.floor((colour.g or .82) * 255 + .5)
            local b = math.floor((colour.b or 0) * 255 + .5)
            return string.format("%02x%02x%02x", r, g, b)
        end
    end
    return "ffd100"
end

local Provider = {}

function Provider:GetMarkers()
    local settings = Settings()
    local api = GetQuestieAPI()
    local output = {}
    Bridge.unresolvedCount = 0
    if not settings.iconsEnabled or not api or type(api.GetAvailableQuestMarkers) ~= "function" then
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
    local title = tostring(marker.title or "Unknown quest")
    local giver = tostring(marker.giverName or marker.starter or "Unknown")
    local typeText = QuestTypeText(marker)
    local coordinates = ""
    if tonumber(marker.x) and tonumber(marker.y) then
        coordinates = string.format("\n|cff9d9d9dLocation: %.1f, %.1f|r", tonumber(marker.x), tonumber(marker.y))
    end

    return string.format(
        "|cff33ff99Questie Available Quest|r\n|cff%s%s|r\n|cffffffff%s|r\n\n|cffffd100Level %s|r  |cffb0b0b0%s|r\n|cffc0c0c0Quest giver:|r %s%s\n|cff707070Quest ID: %s|r",
        DifficultyHex(level),
        title,
        marker.objectiveText or marker.description or "Available from this quest giver",
        tostring(level),
        typeText,
        giver,
        coordinates,
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

function Provider:OnAction(action, marker, carbonite)
    if action ~= "TRACK" and action ~= "GOTO" then return nil end
    local ok = carbonite:SetExternalTarget("Questie", marker)
    if ok then
        Bridge.lastTrackedQuestId = tonumber(marker.questId)
        Print("tracking Questie quest giver: " .. tostring(marker.title or marker.giverName or marker.questId))
    end
    return ok
end

local function Refresh()
    local api = GetCarboniteAPI()
    if api and type(api.RefreshExternalMarkers) == "function" then
        return api:RefreshExternalMarkers("Questie")
    end
    return false
end

local function MarkerListener(event)
    if event == "RESET" then Refresh() end
end

local function RegisterLayerProvider()
    if Bridge.layerRegistered then return true end
    local poi = _G.CarbonitePOI
    if not poi or type(poi.RegisterLayerProvider) ~= "function" then return false end

    poi:RegisterLayerProvider("Questie", {
        name = "Questie",
        GetCategories = function()
            return {
                {
                    id = "availablequests",
                    name = "Available quests",
                    IsEnabled = function() return Settings().iconsEnabled end,
                    SetEnabled = function(_, enabled)
                        Settings().iconsEnabled = enabled and true or false
                        Refresh()
                        return true
                    end,
                },
                {
                    id = "nativequestgivers",
                    name = "Carbonite quest givers",
                    IsEnabled = function() return Settings().nativeQuestGivers end,
                    SetEnabled = function(_, enabled)
                        Settings().nativeQuestGivers = enabled and true or false
                        local carbonite = GetCarboniteAPI()
                        if carbonite then carbonite:SetNativeAvailableQuestGiversEnabled(Settings().nativeQuestGivers) end
                        return true
                    end,
                },
            }
        end,
    })
    Bridge.layerRegistered = true
    return true
end

local function TrackSelectedMarker(que)
    local marker = que and que.IMC
    local providerName = marker and marker.NxExternalProvider or "Questie"
    local carbonite = GetCarboniteAPI()
    if marker and marker.questId and carbonite and type(carbonite.DispatchExternalMarkerAction) == "function" then
        if carbonite:DispatchExternalMarkerAction(providerName, "TRACK", marker) then return end
    end
    if Bridge.originalTrack then return Bridge.originalTrack(que) end
end

local function InstallMenu()
    if Bridge.menuInstalled then return true end
    if not Nx or not Nx.Que or not Nx.Men then return false end
    local que = Nx.Que
    if not que.Map or not que.Map.Frm or type(Nx.Men.Cre) ~= "function"
        or type(que.M_OSQ) ~= "function" or type(que.M_OW1) ~= "function" or not que.Map.M_OAN
    then
        return false
    end

    Bridge.originalTrack = Bridge.originalTrack or que.M_OT1
    local men = Nx.Men:Cre(que.Map.Frm)
    que.IcM = men
    men:AdI1(0, "Track", TrackSelectedMarker, que)
    men:AdI1(0, "Show Quest Log", que.M_OSQ, que)
    que.IMIW = men:AdI1(0, "Watch", que.M_OW1, que)
    men:AdI1(0, "Add Note", que.Map.M_OAN, que.Map)
    Bridge.menuInstalled = true
    return true
end

local function InstallPreparationHook()
    if Bridge.preparationInstalled then return true end
    if not Nx or not Nx.Que or type(Nx.Que.IOMD) ~= "function" then return false end
    local originalIOMD = Nx.Que.IOMD
    Nx.Que.IOMD = function(self, ...)
        local frame = self and self.IHC
        local marker = frame and frame.NXData
        if marker and marker.questId then
            marker.QId = tonumber(marker.questId)
            marker.QI = 0
            marker.NxExternalProvider = frame.NxExternalProvider or "Questie"
            self.IHOI = 0
            self.IMOI = 0
        end
        return originalIOMD(self, ...)
    end
    Bridge.preparationInstalled = true
    return true
end

local function Register()
    if Bridge.registered then return true end
    local questie = GetQuestieAPI()
    local carbonite = GetCarboniteAPI()
    if not questie or not carbonite or type(carbonite.RegisterExternalMarkerProvider) ~= "function" then return false end
    if type(questie.GetAPIVersion) ~= "function" or questie:GetAPIVersion() < 1 then return false end
    if type(carbonite.GetAPIVersion) ~= "function" or carbonite:GetAPIVersion() < 1 then return false end

    carbonite:RegisterExternalMarkerProvider("Questie", Provider)
    carbonite:SetNativeAvailableQuestGiversEnabled(Settings().nativeQuestGivers)
    if type(questie.RegisterMarkerListener) == "function" then questie:RegisterMarkerListener(MarkerListener) end
    Bridge.registered = true
    Print("formal Questie/Carbonite integration " .. Version() .. " registered")
    Refresh()
    return true
end

SLASH_CARBONITEQUESTIEBRIDGE1 = "/cqb"
SlashCmdList.CARBONITEQUESTIEBRIDGE = function(message)
    local command = string.lower((tostring(message or ""):match("^%s*(.-)%s*$")))
    local settings = Settings()
    local carbonite = GetCarboniteAPI()
    if command == "refresh" or command == "scan" then
        Bridge.mapCache = {}
        Bridge.mapNameIndex = nil
        Refresh()
        Print("external markers refreshed")
    elseif command == "icons on" then
        settings.iconsEnabled = true
        Refresh()
    elseif command == "icons off" then
        settings.iconsEnabled = false
        Refresh()
    elseif command == "native on" then
        settings.nativeQuestGivers = true
        if carbonite then carbonite:SetNativeAvailableQuestGiversEnabled(true) end
        Print("Carbonite native available quests enabled; reopen or move the map")
    elseif command == "native off" then
        settings.nativeQuestGivers = false
        if carbonite then carbonite:SetNativeAvailableQuestGiversEnabled(false) end
        Print("Carbonite native available quests suppressed; reopen or move the map")
    elseif command == "status" then
        local questie = GetQuestieAPI()
        Print(string.format(
            "version %s; registered %s; Questie API %s; Carbonite API %s; markers %d; unresolved %d; icons %s; native quests %s",
            Version(),
            Bridge.registered and "yes" or "waiting",
            questie and questie.GetAPIVersion and questie:GetAPIVersion() or "missing",
            carbonite and carbonite.GetAPIVersion and carbonite:GetAPIVersion() or "missing",
            Bridge.markerCount,
            Bridge.unresolvedCount,
            settings.iconsEnabled and "on" or "off",
            settings.nativeQuestGivers and "on" or "off"
        ))
    else
        Print("commands: /cqb status, /cqb refresh, /cqb icons on|off, /cqb native on|off")
    end
end

Bridge:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < .5 then return end
    self.elapsed = 0
    Settings()
    Register()
    RegisterLayerProvider()
    InstallPreparationHook()
    InstallMenu()
end)

_G.CarboniteQuestieBridge = Bridge