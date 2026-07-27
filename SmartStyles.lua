local STYLE_VERSION = "0.6.0"

local StyleBridge = CreateFrame("Frame")
StyleBridge:RegisterEvent("PLAYER_LOGIN")
StyleBridge.elapsed = 0
StyleBridge.hookInstalled = false

local PURPLE_R, PURPLE_G, PURPLE_B = 0.72, 0.28, 1
local DAILY_R, DAILY_G, DAILY_B = 0.20, 0.65, 1

local function GetQuestieModule(name)
    if not QuestieLoader or type(QuestieLoader.ImportModule) ~= "function" then
        return nil
    end

    local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
    return ok and module or nil
end

local function SafeQuestieCall(functionName, questId)
    local QuestieDB = GetQuestieModule("QuestieDB")
    local func = QuestieDB and QuestieDB[functionName]
    if type(func) ~= "function" then
        return false
    end

    local ok, result = pcall(func, questId)
    return ok and result and true or false
end

local function IsDailyQuest(quest, questId)
    if quest.IsDaily or quest.isDaily then
        return true
    end

    local frequency = tonumber(quest.frequency or quest.questFrequency or quest.Frequency)
    if frequency == 1 then
        return true
    end

    return SafeQuestieCall("IsDailyQuest", questId)
end

local function IsEliteQuest(quest)
    if tonumber(quest.groupSize or quest.suggestedGroup or 0) > 1 then
        return true
    end

    local tag = tostring(quest.tag or quest.questTag or quest.type or ""):lower()
    return tag:find("elite", 1, true) ~= nil
end

local function GetDifficultyColor(quest)
    local playerLevel = UnitLevel("player") or 1
    local questLevel = tonumber(quest.level) or tonumber(quest.requiredLevel) or playerLevel

    if type(GetQuestDifficultyColor) == "function" then
        local color = GetQuestDifficultyColor(questLevel)
        if color then
            return color.r or 1, color.g or 0.82, color.b or 0, questLevel
        end
    end

    local difference = questLevel - playerLevel
    if difference >= 5 then
        return 1, 0.1, 0.1, questLevel
    elseif difference >= 3 then
        return 1, 0.5, 0, questLevel
    elseif difference >= -2 then
        return 1, 0.82, 0, questLevel
    elseif difference >= -5 then
        return 0.25, 0.9, 0.25, questLevel
    end

    return 0.55, 0.55, 0.55, questLevel
end

local function EnsureBorder(frame)
    if frame.CQBBorder then
        return frame.CQBBorder
    end

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetPoint("CENTER", frame, "CENTER", 0, 0)
    border:SetWidth(28)
    border:SetHeight(28)
    border:Hide()
    frame.CQBBorder = border
    return border
end

local function EnsureTypeBadge(frame)
    if frame.CQBBadge and frame.CQBBadgeText then
        return frame.CQBBadge, frame.CQBBadgeText
    end

    local badge = frame:CreateTexture(nil, "OVERLAY")
    badge:SetTexture(0, 0, 0, 0.9)
    badge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    badge:SetWidth(9)
    badge:SetHeight(9)
    badge:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    text:Hide()

    frame.CQBBadge = badge
    frame.CQBBadgeText = text
    return badge, text
end

local function ResetDecorations(frame)
    if frame.CQBBorder then
        frame.CQBBorder:Hide()
    end
    if frame.CQBBadge then
        frame.CQBBadge:Hide()
    end
    if frame.CQBBadgeText then
        frame.CQBBadgeText:Hide()
    end
end

local function ApplySmartStyle(frame)
    ResetDecorations(frame)

    local marker = frame.NXData
    if frame.NXType ~= 9800 or type(marker) ~= "table" or not frame.tex then
        return
    end

    local quest = marker.questData or {}
    local questId = marker.questId
    local r, g, b, questLevel = GetDifficultyColor(quest)

    local isDaily = IsDailyQuest(quest, questId)
    local isElite = IsEliteQuest(quest)
    local isRaid = SafeQuestieCall("IsRaidQuest", questId)
    local isDungeon = not isRaid and SafeQuestieCall("IsDungeonQuest", questId)

    if isDaily then
        r, g, b = DAILY_R, DAILY_G, DAILY_B
    end

    frame.tex:SetVertexColor(r, g, b, 1)

    if isElite then
        local border = EnsureBorder(frame)
        local width = math.max((frame:GetWidth() or 16) * 1.7, 24)
        local height = math.max((frame:GetHeight() or 16) * 1.7, 24)
        border:SetWidth(width)
        border:SetHeight(height)
        border:SetVertexColor(PURPLE_R, PURPLE_G, PURPLE_B, 1)
        border:Show()
    end

    if isDungeon or isRaid then
        local badge, text = EnsureTypeBadge(frame)
        badge:Show()
        text:SetText(isRaid and "R" or "D")
        if isRaid then
            text:SetTextColor(1, 0.35, 0.75, 1)
        else
            text:SetTextColor(0.35, 0.75, 1, 1)
        end
        text:Show()
    end

    local types = {}
    if isDaily then types[#types + 1] = "Daily" end
    if isElite then types[#types + 1] = "Elite" end
    if isDungeon then types[#types + 1] = "Dungeon" end
    if isRaid then types[#types + 1] = "Raid" end
    if #types == 0 then types[1] = "Normal" end

    frame.NxT = string.format(
        "|cff33ff99Questie Available Quest|r\n%s\nLevel %s - %s\nQuest ID: %s (%.1f %.1f)",
        tostring(marker.starter or "Unknown starter"),
        tostring(questLevel or "?"),
        table.concat(types, ", "),
        tostring(questId or "?"),
        tonumber(marker.x) or 0,
        tonumber(marker.y) or 0
    )
end

local function ApplyStylesToMap(map)
    if not map or type(map.ISF1) ~= "table" then
        return
    end

    local pool = map.ISF1
    local last = math.min((tonumber(pool.Nex) or 1) - 1, 1500)
    for index = 1, last do
        local frame = pool[index]
        if frame then
            ApplySmartStyle(frame)
        end
    end
end

local function InstallHook()
    if StyleBridge.hookInstalled then
        return true
    end

    if not Nx or not Nx.Que or type(Nx.Que.UpI) ~= "function" then
        return false
    end

    hooksecurefunc(Nx.Que, "UpI", function(_, map)
        ApplyStylesToMap(map)
    end)

    StyleBridge.hookInstalled = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: smart icon styling " .. STYLE_VERSION .. " loaded.")
    return true
end

StyleBridge:SetScript("OnEvent", function()
    InstallHook()
end)

StyleBridge:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 1 then
        return
    end
    self.elapsed = 0
    InstallHook()
end)
