-- luacheck konfigurace pro WoW addon SUCDR
std = "lua51"
max_line_length = 140
codes = true
exclude_files = { ".luacheckrc" }

ignore = {
    "212/self", -- nepoužitý parametr self
}

-- Globály, které addon zapisuje
globals = {
    "SUCDR_DB",
    "SUCDR_Export",
    "SLASH_SUCDR1",
    "SUCDR_OnAddonCompartmentClick",
    "SlashCmdList",
    "StaticPopupDialogs",
    "UISpecialFrames",
}

-- WoW API, které addon jen čte
read_globals = {
    -- Lua rozšíření WoW
    "strsplit", "tinsert", "date", "time",
    -- Frames a UI
    "CreateFrame", "UIParent", "Minimap", "GetCursorPosition", "GetMinimapShape", "StaticPopup_Show", "PlaySound", "SOUNDKIT",
    "CreateFont", "ChatFontNormal", "GameFontNormal", "GameFontHighlight",
    "GameFontHighlightSmall", "GameFontDisable",
    -- Namespaces
    "C_ChatInfo", "C_Timer", "C_AddOns", "Enum",
    -- Jednotky a skupina
    "UnitName", "UnitFullName", "UnitExists", "UnitIsPlayer", "UnitClass", "RAID_CLASS_COLORS",
    "IsInGroup", "IsInRaid", "IsInGuild", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "C_GuildInfo", "GetNumGroupMembers", "GetNumSubgroupMembers",
    "LE_PARTY_CATEGORY_INSTANCE",
    "GetNormalizedRealmName", "GetRealmName", "Ambiguate",
    -- Chat, hody, trade
    "SendChatMessage", "RandomRoll", "RANDOM_ROLL_RESULT",
    "GetTargetTradeMoney", "GetPlayerTradeMoney", "ERR_TRADE_COMPLETE",
    -- Ostatní
    "GetTime", "BreakUpLargeNumbers", "InCombatLockdown", "GameTooltip", "tContains", "issecretvalue", "YES", "NO", "CANCEL", "geterrorhandler",
    "GetMoney", "ReloadUI", "InitiateTrade", "TradePlayerInputMoneyFrame", "MoneyInputFrame_SetCopper", "SetTradeMoney",
}
