local ADDON_NAME = ...
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

local function Version()
    return GetAddOnMetadata(ADDON_NAME or "CarboniteQuestieBridge", "Version") or "unknown"
end

local function ResolveCarboniteMapID(marker)
    return tonumber(marker and (marker.carboniteMapId or marker.carboniteMapID))
end

local function TrackSelectedMarker(que)
    local cur = que and que.IMC
    if not cur or not cur.questId then
        return Compat.originalTrack and Compat.originalTrack(que)
    end

    local questId = tonumber(cur.questId)
    local map = que.Map
    local mapID = ResolveCarboniteMapID(cur)
    local x = tonumber(cur.x)
    local y = tonumber(cur.y)

    if not questId or not mapID or not x or not y or not map
        or type(map.GWP) ~= "function"
        or type(map.SeT3) ~= "function"
        or type(map.GoP) ~= "function"
    then
        Print("Track failed: could not resolve this Questie marker; use Goto instead")
        return
    end

    local wx, wy = map:GWP(mapID, x, y)
    local title = tostring(cur.title or cur.giverName or ("Quest " .. questId))
    map:SeT3("Guide", wx, wy, wx, wy, false, "CQB" .. questId, title, false, mapID)
    map:GoP()

    Compat.lastTrackedQuestId = questId
    Print("tracking Questie quest giver: " .. title .. " (" .. questId .. ")")
end

local function InstallMenu()
    if Compat.menuInstalled then return true end
    if not Nx or not Nx.Que or not Nx.Men then return false end

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
    Print("Questie marker Track routing " .. Version() .. " installed")
    return true
end

local function InstallPreparationHook()
    if Compat.installed then return true end
    if not Nx or not Nx.Que or type(Nx.Que.IOMD) ~= "function" then return false end

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

_G.CQBTrackCompat = Compat
Compat:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < .5 then return end
    self.elapsed = 0
    InstallPreparationHook()
    InstallMenu()
end)
