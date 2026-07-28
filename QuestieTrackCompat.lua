local VERSION = "0.8.5"

local Compat = CreateFrame("Frame")
Compat.elapsed = 0
Compat.installed = false
Compat.originalIOMD = nil
Compat.lastPreparedQuestId = nil

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
end

local function PrepareSelectedMarker(self)
    local cur = self and self.IHC
    if not cur or not cur.questId then
        return true
    end

    local questId = tonumber(cur.questId)
    if not questId then
        Print("Track compatibility: Questie marker has no numeric quest ID")
        return false
    end

    -- Carbonite's existing map-icon menu stores the original Track callback
    -- when Carbonite initializes. Replacing M_OT1 later does not change that
    -- stored callback. Prepare the selected marker before IOMD opens the menu.
    cur.QId = questId
    cur.QI = 0
    self.IHOI = 0
    self.IMOI = 0
    Compat.lastPreparedQuestId = questId

    return true
end

local function Install()
    if Compat.installed then
        return true
    end

    if not Nx or not Nx.Que or type(Nx.Que.IOMD) ~= "function" then
        return false
    end

    Compat.originalIOMD = Nx.Que.IOMD

    Nx.Que.IOMD = function(self, frm, ...)
        PrepareSelectedMarker(self)
        return Compat.originalIOMD(self, frm, ...)
    end

    Compat.installed = true
    _G.CQBTrackCompat = Compat
    Print("Questie marker Track compatibility " .. VERSION .. " installed.")
    return true
end

_G.CQBTrackCompat = Compat

Compat:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.5 then
        return
    end
    self.elapsed = 0
    Install()
end)
