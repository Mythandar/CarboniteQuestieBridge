local VERSION = "0.8.6"

local Compat = CreateFrame("Frame")
Compat.elapsed = 0
Compat.installed = false
Compat.menuInstalled = false
Compat.originalTrack = nil
Compat.lastPreparedQuestId = nil
Compat.lastTrackedQuestId = nil

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

local function ResolveCarboniteMapID(marker)
    if marker.carboniteMapID then
        return marker.carboniteMapID
    end

    local C_Map = QuestieCompat and QuestieCompat.C_Map
    if not C_Map or type(C_Map.GetMapInfo) ~= "function" then
        return nil
    end

    local uiMapID = tonumber(marker.uiMapID)
    if not uiMapID then
        return nil
    end

    local ok, mapInfo = pcall(C_Map.GetMapInfo, uiMapID)
    local mapName = ok and type(mapInfo) == "table" and mapInfo.name or nil
    if not mapName then
        return nil
    end

    local wanted = NormalizeName(mapName)

    if Nx and type(Nx.MITN) == "table" then
        for mapID, name in pairs(Nx.MITN) do
            if type(mapID) == "number" and NormalizeName(name) == wanted then
                marker.carboniteMapID = mapID
                return mapID
            end
        end
    end

    if Nx and Nx.Map and type(Nx.Map.MWI) == "table" then
        for mapID, data in pairs(Nx.Map.MWI) do
            if type(mapID) == "number" and type(data) == "table"
                and NormalizeName(data.Nam) == wanted
            then
                marker.carboniteMapID = mapID
                return mapID
            end
        end
    end

    return nil
end

local function TrackSelectedMarker(que)
    local cur = que and que.IMC

    if not cur or not cur.questId then
        return Compat.originalTrack(que)
    end

    local questId = tonumber(cur.questId)
    local map = que.Map
    local mapID = ResolveCarboniteMapID(cur)

    if not questId or not mapID or not map
        or type(map.GWP) ~= "function"
        or type(map.SeT3) ~= "function"
        or type(map.GoP) ~= "function"
    then
        Print("Track failed: could not resolve this Questie marker; use Goto instead")
        return
    end

    local x = tonumber(cur.x)
    local y = tonumber(cur.y)
    if not x or not y then
        Print("Track failed: Questie marker has no coordinates; use Goto instead")
        return
    end

    local wx, wy = map:GWP(mapID, x, y)
    local title = tostring(cur.starter or ("Quest " .. questId))

    -- Available quests are not active quest-log entries, so Carbonite's native
    -- quest Watch/Track code cannot track them. Treat Track as a persistent
    -- Carbonite navigation target to the Questie-provided quest giver.
    map:SeT3("Guide", wx, wy, wx, wy, false, "CQB" .. questId, title, false, mapID)
    map:GoP()

    Compat.lastTrackedQuestId = questId
    Print("tracking Questie quest giver: " .. title .. " (" .. questId .. ")")
end

local function InstallMenu()
    if Compat.menuInstalled then
        return true
    end

    if not Nx or not Nx.Que or not Nx.Men then
        return false
    end

    local que = Nx.Que
    if not que.Map or not que.Map.Frm
        or type(Nx.Men.Cre) ~= "function"
        or type(que.M_OSQ) ~= "function"
        or type(que.M_OW1) ~= "function"
        or not que.Map.M_OAN
    then
        return false
    end

    Compat.originalTrack = Compat.originalTrack or que.M_OT1

    local men = Nx.Men:Cre(que.Map.Frm)
    que.IcM = men
    men:AdI1(0, "Track", TrackSelectedMarker, que)
    men:AdI1(0, "Show Quest Log", que.M_OSQ, que)
    que.IMIW = men:AdI1(0, "Watch", que.M_OW1, que)
    men:AdI1(0, "Add Note", que.Map.M_OAN, que.Map)

    Compat.menuInstalled = true
    Print("Questie marker Track routing " .. VERSION .. " installed.")
    return true
end

local function InstallPreparationHook()
    if Compat.installed then
        return true
    end

    if not Nx or not Nx.Que or type(Nx.Que.IOMD) ~= "function" then
        return false
    end

    local originalIOMD = Nx.Que.IOMD
    Nx.Que.IOMD = function(self, ...)
        local frame = self and self.IHC
        local cur = frame and frame.NXData
        if cur and cur.questId then
            cur.QId = tonumber(cur.questId)
            cur.QI = 0
            self.IHOI = 0
            self.IMOI = 0
            Compat.lastPreparedQuestId = cur.QId
        end
        return originalIOMD(self, ...)
    end

    Compat.installed = true
    _G.CQBTrackCompat = Compat
    return true
end

local function InstallStatusOverride()
    if Compat.statusInstalled or type(SlashCmdList.CARBONITEQUESTIEBRIDGE) ~= "function" then
        return
    end

    local original = SlashCmdList.CARBONITEQUESTIEBRIDGE
    SlashCmdList.CARBONITEQUESTIEBRIDGE = function(message)
        if string.lower(Trim(message)) == "status" then
            Print("package version " .. VERSION .. "; core bridge loaded; Guide suppression loaded; Questie Track routing loaded")
            return
        end
        return original(message)
    end
    Compat.statusInstalled = true
end

_G.CQBTrackCompat = Compat

Compat:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.5 then
        return
    end
    self.elapsed = 0

    InstallPreparationHook()
    InstallMenu()
    InstallStatusOverride()
end)
