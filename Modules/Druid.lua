do
--[[
██████╗  █████╗ ██████╗ ██████╗ ██╗   ██╗
██╔══██╗██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝███████║██████╔╝██████╔╝ ╚████╔╝ 
██╔═══╝ ██╔══██║██╔══██╗██╔══██╗  ╚██╔╝  
██║     ██║  ██║██║  ██║██║  ██║   ██║   
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
--]]
--==================================================
-- Interface: 110205
-- Druid Module
-- Author: M44SYR
--==================================================

--==================================================
-- LOADER
--==================================================

  local ADDON_NAME, ns = ...
  if select(2, UnitClass("player")) ~= "DRUID" then return end

  -- pull Tank API
  local Tank = ns.Tank
  if not Tank then return end

  --===============================================
  -- FRAME + EVENTS
  --===============================================

  local f = CreateFrame("Frame")
  f:RegisterUnitEvent("UNIT_HEALTH", "player")
  f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  f:RegisterUnitEvent("UNIT_AURA", "player")
  f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:RegisterEvent("PLAYER_LOGIN")

  --===============================================
  -- STATE / CONSTANTS
  --===============================================

  local damageLog = {}
  local TIME_WINDOW = 10 -- seconds to keep recent damage in memory for recap
  local ACTIVE_WINDOW = 5 -- seconds before death to still count auras as "recent"
  local lastHealth = UnitHealth("player")
  local playerGUID = UnitGUID("player")
  local deathPrinted = false

--==================================================
-- COOLDOWN TABLE
--==================================================

   local cooldowns = {
      BS_ID     = {id = 22812,    ready = false, reason = "", remaining = 0, name = "Bark Skin",             info = "Defensive cooldown"},
      SI_ID     = {id = 61336,    ready = false, reason = "", remaining = 0, name = "Survival Instincts",    info = "Defensive cooldown major damage reduction"},
      PV_ID     = {id = 80313,    ready = false, reason = "", remaining = 0, name = "Pulverize",             info = "Pulverized tragets have reduced damage output"},
      ROS_ID    = {id = 200851,   ready = false, reason = "", remaining = 0, name = "Rage of the Sleeper",   info = "Damage reduction, reflect, and healing; very strong when active"},
      FR_ID     = {id = 22842,    ready = false, reason = "", remaining = 0, name = "Frenzied Regeneration", info = "Heal over time effect"},
      RG_ID     = {id = 8936,     ready = false, reason = "", remaining = 0, name = "Regrowth",              info = "Casted Heal, use with caution, shapeshifts out of bear form"},
      RNW_ID    = {id = 108238,   ready = false, reason = "", remaining = 0, name = "Renewal",               info = "Instant self heal"},
      GOU_ID    = {id = 102558,   ready = false, reason = "", remaining = 0, name = "Gaurdian of Ursoc",     info = "Improved bear form; upgrades all defensive tools"},
    }

--===============================================
--  ITEM TABLES
--===============================================

  local items = {
      AHP1_ID = {id = 211878, bags = 0, ready = false, reason = "", CDremaining = 0, name = "Algari Healing Potion Rank 1", info = "Healing Potion"},
      AHP2_ID = {id = 211879, bags = 0, ready = false, reason = "", CDremaining = 0, name = "Algari Healing Potion Rank 2", info = "Healing Potion"},
      AHP3_ID = {id = 211880, bags = 0, ready = false, reason = "", CDremaining = 0, name = "Algari Healing Potion Rank 3", info = "Healing Potion"},
      CDD1_ID = {id = 212242, bags = 0, ready = false, reason = "", CDremaining = 0, name = "Cave Dwellers Delight Rank 1", info = "Utility Potion"},
      CDD2_ID = {id = 212243, bags = 0, ready = false, reason = "", CDremaining = 0, name = "Cave Dwellers Delight Rank 2", info = "Utility Potion"},
      CDD3_ID = {id = 212244, bags = 0, ready = false, reason = "", CDremaining = 0, name = "Cave Dwellers Delight Rank 3", info = "Utility Potion"},
      WLHS_ID = {id = 5512,   bags = 0, ready = false, reason = "", CDremaining = 0, name = "Warlock Health Stone",         info = "Health Stone"},
  }    

--===============================================
--  AURAS [1] BUFFS [2] DEBUFFS
--===============================================

-- Class buffs to mark "recently active"
  local buffs = {
      IF_ID     = {id = 192081, ready = false, reason = "", remaining = 0, name = "Iron Fur",         info = "Active mitigation, increases armour, stacks"},
      BF_ID     = {id = 5487,   ready = false, reason = "", remaining = 0, name = "Bear Form",        info = "Druid best defensive form, increases armor and stamina"},
      MOW_ID    = {id = 1126,   ready = false, reason = "", remaining = 0, name = "Mark of the Wild", info = "Versatility increase, Druid party/raid buff"},
  }

-- Harmful debuffs and spec relevant debuffs
  local dBuffs = {
    
  }

--==================================================
-- LOSS OF CONTROL TABLE
--==================================================
--Loss of control auras to mark "recently active"
  local loc = {

  }

  --===============================================
  -- HELPERS
  --===============================================

  local function coloredText(bool)
      return bool and "|cff00ff00Yes|r" or "|cffff0000No|r"
  end

  local function wasActiveRecently(lastTime)
      return lastTime and ((GetTime() - lastTime) <= ACTIVE_WINDOW)
  end

  -- Shared GCD helper (use for both spells and items)
  local GCD_ID = 61304
  local GCD_TOL = 0.06

  local function gcdRemaining()
    local gcd = C_Spell.GetSpellCooldown(GCD_ID)
    if gcd and gcd.duration and gcd.duration > 0 then
      local rem = (gcd.startTime + gcd.duration) - GetTime()
      return (rem > 0) and rem or 0, gcd.duration
    end
    return 0, 0
  end

  local function durationIsGCD(dur)
    local _, gcdDur = gcdRemaining()
    return gcdDur > 0 and math.abs((dur or 0) - gcdDur) < GCD_TOL
  end

  --===============================================
  -- UI HELPERS 
  --===============================================

  local function EnsureUI()
      if ns and ns.UI then
          if ns.UI.Init and not ns.UI._inited then
              ns.UI:Init()
          end
          return (ns.UI and ns.UI.ShowDeathReport) ~= nil
      end
      return false
  end

  local function PublishReportToUI(report)
      if EnsureUI() then
          ns.UI:ShowDeathReport(report)
      else
          -- keep it friendly; avoid spam/toxicity
          print("|cffff4444Parry UI not available to show report.|r")
      end
  end

  --===============================================
  -- UPDATERS
  --===============================================

  local function updateCooldowns() -- Cooldowns
      for key, cd in pairs(cooldowns) do
          cd.ready, cd.reason, cd.remaining = false, nil, 0 -- Reset
          local isKnown  = C_SpellBook.IsSpellKnown(cd.id)
          local cooldown = C_Spell.GetSpellCooldown(cd.id)

          if not isKnown then
              cd.reason = "Not Talented"

          elseif cooldown and cooldown.duration == 0 then
              cd.ready = true
              cd.reason = ""
              cd.remaining = 0

          elseif cooldown and cooldown.duration > 0 then
              if durationIsGCD(cooldown.duration) then
                  local gcdRem = gcdRemaining()         -- First return = remaining seconds
                  cd.ready = false
                  cd.reason = "Global Cool Down"
                  cd.remaining = gcdRem
              else
                  cd.ready = false
                  cd.reason = "On Cooldown"
                  local rem = (cooldown.startTime + cooldown.duration) - GetTime()
                  cd.remaining = (rem > 0) and rem or 0
              end

          else
              cd.ready = nil -- Debug not spec'd if API hiccups
          end
      end
  end

  local function updateInventory() -- Items in bags 
      for _, item in pairs(items) do
          item.bags, item.ready, item.reason, item.CDremaining = 0, false, "", 0 --Reset
          local count = C_Item.GetItemCount(item.id)
          local start, dur = C_Item.GetItemCooldown(item.id)  
          item.bags = count
          if count == 0 then
              item.ready = false
              item.reason = "None in Bags"
              item.CDremaining = 0

          elseif dur == 0 then
              item.ready = true
              item.reason = ""
              item.CDremaining = 0

          else
              if durationIsGCD(dur) then
                  local gcdRem = gcdRemaining()  -- First return = remaining seconds
                  item.ready = false
                  item.reason = "Global Cool Down"
                  item.CDremaining = gcdRem
              else
                  local rem = (start + dur) - GetTime()
                  item.ready = false
                  item.reason = "On Cooldown"
                  item.CDremaining = (rem > 0) and rem or 0
              end
          end
      end
  end

  local function updateAuraTracking() -- Auras active mitigation etc
      for ar = 1, 40 do
          local aura = C_UnitAuras.GetAuraDataByIndex("player", ar, "HELPFUL")
          if not aura then break end
          for _, buff in pairs(buffs) do
              if aura.spellId == buff.id then
                  buff.ready = GetTime()
              end
          end
      end
      for hAr = 1, 40 do
          local aura = C_UnitAuras.GetAuraDataByIndex("player", hAr, "HARMFUL")
          if not aura then break end
          for _, debuff in pairs(dBuffs) do
              if aura.spellId == debuff.id then
                  debuff.ready = GetTime()
              end
          end
      end
  end

  --===============================================
  -- COMBAT LOG (record last few hits)
  --===============================================

  local function handleCombatLog()
      local info = { CombatLogGetCurrentEventInfo() }
      local subevent = info[2]
      local dstGUID = info[8]
      if dstGUID ~= playerGUID then return end

      local now = GetTime()
      if subevent == "SWING_DAMAGE" then
          local swingAmount = info[12]
          table.insert(damageLog, { time = now, spellName = "Melee", amount = swingAmount or 0 })
      elseif subevent == "SPELL_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "ENVIRONMENTAL_DAMAGE" then
          local spellID = info[12]
          local spellName = info[13]
          local amount = info[15]
          table.insert(damageLog, {
              time = now,
              spellName = spellName or ("SpellID: "..(spellID or "unknown")),
              amount = amount or 0,
          })
      end

      for i = #damageLog, 1, -1 do
          if now - damageLog[i].time > TIME_WINDOW then
              table.remove(damageLog, i)
          end
      end
  end

  --===============================================
  -- HEALTH WATCHER (With Death Recap)
  --===============================================

  local function handleHealthUpdate()
      local health = UnitHealth("player")
      if health <= 0 and lastHealth > 0 then
          if deathPrinted then return end       -- Prevent double print
          deathPrinted = true                   -- Latch
          updateCooldowns()-- Refresh values
          updateInventory()-- Refresh values
          updateAuraTracking()-- Refresh values

--[[ (Commented out, left in for debugging)
          local count = #damageLog
          if count == 0 then
              print("|cffff4444Parry: You died, but no recent damage was recorded.")
          else
              print("|cffff4444Parry: You died! Here's what hit you just before:")
              for i = math.max(1, count - 3), count do
                  local entry = damageLog[i]
                  local label = (i == count) and "|cffff2222Killing Blow|r" or string.format("Hit %d", i - count + 4)
                  print(string.format(" - %s: %s (%s)", entry.spellName or "Unknown", entry.amount or 0, label))
              end
          end
--]]
  --===============================================
  -- PARRY COACHING FEEDBACK PRINT OUT (Commented out, left in for debugging)
  --===============================================

  --[[ 
          print("==Active Mitigation==")
          for _, buff in pairs(buffs) do
              if wasActiveRecently(buff.ready) then
                  print(" - " .. buff.name .." ".. "|cff00ff00was active|r")
              end
          end

          print("==Defensive Abilities==")
          for _, cd in pairs(cooldowns) do
              print(" - " .. cd.name .. " ready? - " .. coloredText(cd.ready))
          end

          print("==Other Abilities/Utility==")
          for _, itm in pairs(items) do
              print(" - " .. itm.name .. " available? - " .. coloredText(itm.ready))
          end

          print("==Active Debuffs==")
          for _, debuff in pairs(dBuffs) do
              if wasActiveRecently(debuff.ready) then
                  print(" - " .. debuff.name)
              end
          end
--]]

  --===============================================
  -- UI report 
  --===============================================

          local report = { hits = {}, mit = {}, cooldowns = {}, items = {}, debuffs = {} }

          local c = #damageLog
          for i = math.max(1, c - 3), c do
              local e = damageLog[i]
              table.insert(report.hits, { name = e.spellName or "Unknown", amount = e.amount or 0 })
          end

          for _, b in pairs(buffs) do
              table.insert(report.mit, { name = b.name, active = wasActiveRecently(b.ready) })
          end

          for _, cd in pairs(cooldowns) do
              table.insert(report.cooldowns, {
                  name = cd.name,
                  ready = cd.ready == true,
                  reason = cd.reason,
                  remaining = cd.remaining,
              })
          end

          for _, it in pairs(items) do
              table.insert(report.items, {
                  name = it.name,
                  bags = it.bags or 0,
                  ready = it.ready == true,
                  reason = it.reason,
                  CDremaining = it.CDremaining,
              })
          end

          for _, d in pairs(dBuffs) do
              table.insert(report.debuffs, { name = d.name, active = wasActiveRecently(d.ready) })
          end

          PublishReportToUI(report) -- Publish to UI

          wipe(damageLog)
      end
      if health > 0 and lastHealth <= 0 then
          deathPrinted = false
      end

      lastHealth = health
  end

  --===============================================
  -- EVENT DISPATCH
  --===============================================

  local cdTicker, invTicker, auraTicker

  f:SetScript("OnEvent", function(self, event, ...)
      if event == "PLAYER_LOGIN" then
          playerGUID = UnitGUID("player")
          EnsureUI()  -- ensure /parry + recap button initialize early

      elseif event == "PLAYER_REGEN_DISABLED" then
          updateCooldowns()
          updateInventory()
          updateAuraTracking()

          cdTicker   = C_Timer.NewTicker(1, updateCooldowns)
          invTicker  = C_Timer.NewTicker(1, updateInventory)
          auraTicker = C_Timer.NewTicker(1, updateAuraTracking)

      elseif event == "PLAYER_REGEN_ENABLED" then
          if cdTicker  then cdTicker:Cancel()  cdTicker  = nil end
          if invTicker then invTicker:Cancel() invTicker = nil end
          if auraTicker then auraTicker:Cancel() auraTicker = nil end

      elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
          handleCombatLog()

      elseif event == "UNIT_HEALTH" then
          handleHealthUpdate()

      elseif event == "UNIT_AURA" then
          updateAuraTracking()

      elseif event == "SPELL_UPDATE_COOLDOWN" then
          updateCooldowns()
      end
  end)
end
--end
