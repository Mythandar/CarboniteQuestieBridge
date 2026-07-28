local Suppressor = CreateFrame("Frame")
Suppressor.elapsed = 0
Suppressor.installed = false
Suppressor.originalUMI1 = nil

local function IsSuppressionEnabled()
    return CarboniteQuestieBridgeDB
        and CarboniteQuestieBridgeDB.suppressCarboniteQuests
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

        if IsSuppressionEnabled() and map and type(originalAIP) == "function" then
            map.AIP = function(mapSelf, iconType, ...)
                local icon = originalAIP(mapSelf, iconType, ...)
                if icon and (iconType == "!GQ" or iconType == "!GQC") then
                    icon:Hide()
                    icon.UDQGD = nil
                    icon.NxT = nil
                end
                return icon
            end
        end

        local ok, err = pcall(Suppressor.originalUMI1, self, ...)

        if map and originalAIP then
            map.AIP = originalAIP
        end

        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: Carbonite Guide icon update error: " .. tostring(err))
        end
    end

    Suppressor.installed = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CQB|r: Carbonite quest-giver Guide layer suppression installed.")
    return true
end

Suppressor:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 1 then
        return
    end
    self.elapsed = 0
    Install()
end)
