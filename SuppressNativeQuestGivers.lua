local Suppressor = CreateFrame("Frame")
Suppressor.elapsed = 0
Suppressor.installed = false
Suppressor.originalUMI1 = nil
Suppressor.capturedIcons = {}

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: " .. tostring(message))
end

local function IsSuppressionEnabled()
    return CarboniteQuestieBridgeDB
        and CarboniteQuestieBridgeDB.suppressCarboniteQuests
end

local function HideCapturedIcons()
    if not IsSuppressionEnabled() then
        return
    end

    for _, icon in ipairs(Suppressor.capturedIcons) do
        if icon then
            icon:Hide()
            icon.UDQGD = nil
            icon.NxT = nil
        end
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
        local map = self and self.Map
        local originalAIP = map and map.AIP
        local captured = {}

        if map and type(originalAIP) == "function" then
            map.AIP = function(mapSelf, iconType, ...)
                local icon = originalAIP(mapSelf, iconType, ...)
                if icon and (iconType == "!GQ" or iconType == "!GQC") then
                    captured[#captured + 1] = icon
                end
                return icon
            end
        end

        local ok, err = pcall(Suppressor.originalUMI1, self, ...)

        if map and originalAIP then
            map.AIP = originalAIP
        end

        Suppressor.capturedIcons = captured
        HideCapturedIcons()

        if not ok then
            Print("Carbonite Guide icon update error: " .. tostring(err))
        end
    end

    Suppressor.installed = true
    Print("Carbonite quest-giver Guide suppression 0.8.1 installed.")
    return true
end

-- Expose a tiny diagnostic object for /run testing.
_G.CQBGuideSuppressor = Suppressor

Suppressor:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.10 then
        return
    end
    self.elapsed = 0

    Install()
    HideCapturedIcons()
end)
