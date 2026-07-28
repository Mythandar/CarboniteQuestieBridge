local VERSION = "0.8.3"

local Suppressor = CreateFrame("Frame")
Suppressor.elapsed = 0
Suppressor.installed = false
Suppressor.originalUMI1 = nil
Suppressor.lastRemoved = 0
Suppressor.updateCount = 0

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
end

local function IsSuppressionEnabled()
    return CarboniteQuestieBridgeDB
        and CarboniteQuestieBridgeDB.suppressCarboniteQuests
end

local function IsQuestGiverSelection(key)
    return type(key) == "string"
        and string.byte(key, 1) == 38
end

local function RemoveQuestGiverSelections(gui)
    local removed = {}
    local count = 0

    if not gui or type(gui.ShF) ~= "table" then
        return removed, count
    end

    for key, value in pairs(gui.ShF) do
        if IsQuestGiverSelection(key) then
            removed[key] = value
            gui.ShF[key] = nil
            count = count + 1
        end
    end

    return removed, count
end

local function RestoreQuestGiverSelections(gui, removed)
    if not gui or type(gui.ShF) ~= "table" then
        return
    end

    for key, value in pairs(removed) do
        gui.ShF[key] = value
    end
end

local function Install()
    if Suppressor.installed then
        return true
    end

    if not Nx or not Nx.Map or not Nx.Map.Gui or type(Nx.Map.Gui.UMI1) ~= "function" then
        return false
    end

    Suppressor.originalUMI1 = Nx.Map.Gui.UMI1

    Nx.Map.Gui.UMI1 = function(self, ...)
        if not IsSuppressionEnabled() then
            return Suppressor.originalUMI1(self, ...)
        end

        local removed, count = RemoveQuestGiverSelections(self)
        Suppressor.lastRemoved = count

        local results = { pcall(Suppressor.originalUMI1, self, ...) }

        -- Always restore Carbonite's Guide selections, even if its renderer errors.
        RestoreQuestGiverSelections(self, removed)

        local ok = table.remove(results, 1)
        if not ok then
            Print("Carbonite Guide icon update error: " .. tostring(results[1]))
            return
        end

        Suppressor.updateCount = Suppressor.updateCount + 1
        return unpack(results)
    end

    Suppressor.installed = true
    _G.CQBGuideSuppressor = Suppressor
    Print("Carbonite Guide quest-giver suppression " .. VERSION .. " installed.")
    return true
end

_G.CQBGuideSuppressor = Suppressor

Suppressor:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.25 then
        return
    end
    self.elapsed = 0
    Install()
end)
