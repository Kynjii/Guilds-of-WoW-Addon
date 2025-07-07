local RCLootAddon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil");
local GoWLoot = RCLootAddon:NewModule("GoWLoot", "AceComm-3.0", "AceHook-3.0", "AceEvent-3.0", "AceTimer-3.0", "AceSerializer-3.0", "AceBucket-3.0");
local GOW = GuildsOfWow;
GOW.GoWLoot = GoWLoot;



function GoWLoot:OnInitialize()
    local RCLootAddonVersion = "3.16.0"

    if RCLootAddon:VersionCompare(RCLootAddon.version, RCLootAddonVersion) then
        LibDialog:Spawn("RCWOWAUDIT_OUTDATED_MESSAGE")
    end
end
