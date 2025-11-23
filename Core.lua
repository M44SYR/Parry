do
--[[
██████╗  █████╗ ██████╗ ██████╗ ██╗   ██╗
██╔══██╗██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝███████║██████╔╝██████╔╝ ╚████╔╝ 
██╔═══╝ ██╔══██║██╔══██╗██╔══██╗  ╚██╔╝  
██║     ██║  ██║██║  ██║██║  ██║   ██║   
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
]]
--==================================================
-- Interface: 110205
-- Core Loader
-- Author: M44SYR
--==================================================

local ADDON_NAME, ns = ...
ns.modules = ns.modules or {}

-- Load Check
local function TryInitUI(when)
  if ns.UI and ns.UI.Init then
    if not ns.UI._inited then
      print("|cff66ccffParry|r TryInitUI at "..when)
    end
    ns.UI:Init()
  else
    print("|cff66ccffParry|r UI missing at "..when.." (ns.UI nil). Check TOC path/case and UI.lua export.")
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, evt, arg1)
  if evt == "ADDON_LOADED" and arg1 == ADDON_NAME then
    print("|cff66ccffParry|r ADDON_LOADED for", arg1)
    ParryDB = ParryDB or {}
    ns.playerClass = select(2, UnitClass("player"))
    TryInitUI("ADDON_LOADED")
  elseif evt == "PLAYER_LOGIN" then
    print("|cff66ccffParry|r PLAYER_LOGIN")
    TryInitUI("PLAYER_LOGIN")
    print("|cff66ccffParry|r core loaded for", ns.playerClass or "unknown")
  end
end)
end 
--end
