local addonName, addon = ...
local GOW = GuildsOfWow;

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local optionsTable = {
    type = "group",
    name = "Guilds of WoW",
    args = {
        BagSettings = {
            type = "group",
            inline = true,
            name = "Settings",
            width = "full",
            args = {
                ShowMinimap = {
                    type = "toggle",
                    order = 1,
                    name = "Show minimap icon",
                    desc = "Toggle mimmimap button visibility.",
                    width = "full",
                    get = function(info) return not GOW.DB.profile.minimap.hide end,
                    set = function(info, value)
                        GOW.DB.profile.minimap.hide = not value;
                        if GOW.DB.profile.minimap.hide then
                            GOW.LDBIcon:Hide("gowicon");
                        else
                            GOW.LDBIcon:Show("gowicon");
                        end
                    end,
                },
                DisplayNewEventWarning = {
                    type = "toggle",
                    order = 2,
                    name = "Warn about new events",
                    desc = "Display a warning when new events that are not on the in-game calendar are found.",
                    width = "full",
                    get = function(info) return GOW.DB.profile.warnNewEvents end,
                    set = function(info, value)
                        GOW.DB.profile.warnNewEvents = value;
                    end,
                },
                ReduceEventNotifications = {
                    type = "toggle",
                    order = 3,
                    name = "Reduce event notifications",
                    desc = "Show only important event notifications in chat.",
                    width = "full",
                    get = function() return GOW.DB.profile.reduceEventNotifications end,
                    set = function(_, value)
                        GOW.DB.profile.reduceEventNotifications = value;
                    end,
                },
                HideInCombat = {
                    type = "toggle",
                    order = 4,
                    name = "Hide in combat",
                    desc = "Hide the Guilds of WoW window when entering combat.",
                    width = "full",
                    get = function(info) return GOW.DB.profile.hideInCombat end,
                    set = function(info, value)
                        GOW.DB.profile.hideInCombat = value;
                    end,
                }
            }
        }
    }
}

AceConfig:RegisterOptionsTable(addonName, optionsTable, nil);
AceConfigDialog:AddToBlizOptions(addonName, "Guilds of WoW");
local GetAddOnMetadataFunc = GetAddOnMetadata or C_AddOns.GetAddOnMetadata;
local OpenSettingsFunc = InterfaceOptionsFrame_OpenToCategory or Settings.OpenToCategory;

function GOW:OpenSettings()
    local title = GetAddOnMetadataFunc(addonName, "Title");
    OpenSettingsFunc(title);
end
