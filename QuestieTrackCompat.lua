local Compat = CreateFrame("Frame")
Compat.elapsed = 0
Compat.installed = false
Compat.originalTrack = nil

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
end

local function Install()
    if Compat.installed then
        return true
    end

    if not Nx or not Nx.Que or type(Nx.Que.M_OT1) ~= "function" then
        return false
    end

    Compat.originalTrack = Nx.Que.M_OT1

    Nx.Que.M_OT1 = function(self, ...)
        local cur = self and self.IMC

        -- Bridge markers use questId, while Carbonite's Track handler expects
        -- QId and an objective index. Carbonite derives IMOI from NXType;
        -- bridge icons use a private NXType, so force the quest-starter index.
        if cur and cur.questId then
            local questId = tonumber(cur.questId)
            if not questId then
                Print("Track failed: Questie marker has no numeric quest ID")
                return
            end

            cur.QId = questId
            cur.QI = 0
            self.IMOI = 0

            -- Carbonite can only place a quest into its watch system when its
            -- own database contains that quest. Avoid a later nil-table error
            -- and leave Goto available for Questie-only quests.
            if type(self.ITQ) ~= "table" or not self.ITQ[questId] then
                Print("Track unavailable: quest " .. questId .. " is not in Carbonite's quest database; use Goto instead")
                return
            end
        end

        return Compat.originalTrack(self, ...)
    end

    Compat.installed = true
    _G.CQBTrackCompat = Compat
    Print("Questie marker Track compatibility 0.8.4 installed.")
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
