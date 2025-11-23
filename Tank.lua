do
--[[
██████╗  █████╗ ██████╗ ██████╗ ██╗   ██╗
██╔══██╗██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝
██████╔╝███████║██████╔╝██████╔╝ ╚████╔╝ 
██╔═══╝ ██╔══██║██╔══██╗██╔══██╗  ╚██╔╝  
██║     ██║  ██║██║  ██║██║  ██║   ██║   
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
]]
-- Tank shared functions and tables

local ADDON_NAME, ns = ...
ns.Tank = ns.Tank or {}
local Tank = ns.Tank

--==================================================
-- SavedVariables: per-account defaults + per-character bucket
--==================================================

local function CharKey()
  local name = UnitName("player") or "Player"
  local realm = GetRealmName() or "Realm"
  local class = select(2, UnitClass("player")) or "CLASS"
  return string.format("%s-%s@%s", name, realm, class)
end

local function EnsureDB()
  ParryDB = ParryDB or {}
  ParryDB.global = ParryDB.global or {
    opacity = 1.0,
    defaults = { opacity = 1.0, activeWindow = 5, historyLimit = 10 },
  }
  ParryDB.chars = ParryDB.chars or {}
  local key = CharKey()
  local ch = ParryDB.chars[key] or {}
  ParryDB.chars[key] = ch

  ch.ui = ch.ui or { btn = { x = 200, y = 200, locked = false } }
  ch.activeWindow = ch.activeWindow or 5
  ch.deaths = ch.deaths or { list = {}, idx = 0, historyLimit = 10 }
  ch.pullStreak = ch.pullStreak or 0

  -- one-time migration from old flat deaths
  if ParryDB.deaths and (not ch.deaths or (#(ch.deaths.list or {}) == 0)) then
    ch.deaths = { list = ParryDB.deaths.list or {}, idx = ParryDB.deaths.idx or 0, historyLimit = 10 }
    ParryDB.deaths = nil
  end
  return ch
end

function Tank:GetCharDB()
  return EnsureDB()
end

function Tank:GetActiveWindow()
  return self:GetCharDB().activeWindow or 5
end

--==================================================
-- History (rolling N) + Publish to UI
--==================================================

local HISTORY_HARD_MAX = 100 -- hard guard 

local function PushReport(report)
  local ch = EnsureDB()
  report = report or {}
  report.time = report.time or GetServerTime()
  local t = ch.deaths
  t.historyLimit = math.min(math.max(t.historyLimit or 10, 1), HISTORY_HARD_MAX)

  table.insert(t.list, report)
  if #t.list > t.historyLimit then
    table.remove(t.list, 1)
  end
  t.idx = #t.list
end

function Tank:Publish(report)
  PushReport(report)
  if ns and ns.UI and ns.UI.ShowDeathReport then
    ns.UI:ShowDeathReport(report)
  end
end

--==================================================
-- Streaks: "Pulls Since Last Incident"
--==================================================

function Tank:IncStreakOnPull()
  -- nothing to do at pull start; finalized on regen enabled
  self._inPull = true
end

function Tank:FinalizeStreak(noDeathThisPull)
  local ch = EnsureDB()
  if self._inPull and noDeathThisPull then
    ch.pullStreak = (ch.pullStreak or 0) + 1
  end
  self._inPull = false
end

function Tank:ResetStreakOnDeath()
  local ch = EnsureDB()
  ch.pullStreak = 0
end

--==================================================
-- Damage Ring Buffer
--==================================================

Tank.Damage = Tank.Damage or {}
do
  local buf = {}
  local TIME_WINDOW = 10 -- seconds to keep detailed hits (UI shows last <=3)

  function Tank.Damage:AddHit(name, amount, t)
    local now = t or GetTime()
    table.insert(buf, { time = now, spellName = name or "Unknown", amount = amount or 0 })
    -- trim old
    for i = #buf, 1, -1 do
      if now - (buf[i].time or 0) > TIME_WINDOW then
        table.remove(buf, i)
      end
    end
  end

  function Tank.Damage:GetLastHits(n)
    local out, count = {}, #buf
    local start = math.max(1, count - (n or 3) + 1)
    for i = start, count do
      local e = buf[i]
      out[#out+1] = { name = e.spellName or "Unknown", amount = e.amount or 0 }
    end
    return out
  end

  function Tank.Damage:Clear()
    wipe(buf)
  end
end

--==================================================
-- Aura Recency Cache (per-char)
--==================================================

local auraSeenHelpful = {}  -- [spellID] = lastSeenTime
local auraSeenHarmful = {}  -- [spellID] = lastSeenTime
local auraSeenBuff    = {}  -- [spellID] = lastSeenTime
local auraSeenDeBuff  = {}  -- [spellID] = lastSeenTime

-- Scan player auras and stamp lastSeen for any ids in provided sets
function Tank:UpdateAuraRecency(unit, helpfulIds, harmfulIds)
  unit = unit or "player"

  if helpfulIds then
    for idx = 1, 40 do
      local a = C_UnitAuras.GetAuraDataByIndex(unit, idx, "HELPFUL")
      if not a then break end
      if helpfulIds[a.spellId] or tContains(helpfulIds, a.spellId) then
        auraSeenHelpful[a.spellId] = GetTime()
      end
    end
  end

  if harmfulIds then
    for idx = 1, 40 do
      local a = C_UnitAuras.GetAuraDataByIndex(unit, idx, "HARMFUL")
      if not a then break end
      if harmfulIds[a.spellId] or tContains(harmfulIds, a.spellId) then
        auraSeenHarmful[a.spellId] = GetTime()
      end
    end
  end
end

local function inSet(ids, id)
  return (ids and (ids[id] or tContains(ids, id))) and true or false
end

local function spellNameIcon(id)
  local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id))
  local icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id))
  return name or ("SpellID:"..id), icon
end

function Tank:MitigationFromRecency(ids, windowSec)
  local out, now = {}, GetTime()
  local w = windowSec or self:GetActiveWindow() or 5
  if not ids then return out end
  for _, id in ipairs(ids) do
    local name, icon = spellNameIcon(id)
    local t = auraSeenHelpful[id]
    out[#out+1] = { id = id, name = name, icon = icon, active = (t and (now - t) <= w) or false }
  end
  return out
end

function Tank:BuffsActive(ids, windowSec)
  local out, now = {}, GetTime()
  local w = windowSec or self:GetActiveWindow() or 5
  if not ids then return out end
  for _, id in ipairs(ids) do
    local name, icon = spellNameIcon(id)
    local t = auraSeenHelpful[id]
    out[#out+1] = { id = id, name = name, icon = icon, active = (t and (now - t) <= w) or false }
  end
  return out
end

function Tank:DebuffFromRecency(ids, windowSec)
  local out, now = {}, GetTime()
  local w = windowSec or self:GetActiveWindow() or 5
  if not ids then return out end
  for _, id in ipairs(ids) do
    local name, icon = spellNameIcon(id)
    local t = auraSeenHarmful[id]
    out[#out+1] = { id = id, name = name, icon = icon, active = (t and (now - t) <= w) or false }
  end
  return out
end

--==================================================
-- GCD helpers + Cooldown Status
--==================================================

local GCD_ID, GCD_TOL = 61304, 0.06

local function gcdRemaining()
  local cd = C_Spell.GetSpellCooldown(GCD_ID)
  if cd and cd.duration and cd.duration > 0 then
    local rem = (cd.startTime + cd.duration) - GetTime()
    return (rem > 0) and rem or 0, cd.duration
  end
  return 0, 0
end

local function durationIsGCD(dur)
  local _, gcdDur = gcdRemaining()
  return gcdDur > 0 and math.abs((dur or 0) - gcdDur) < GCD_TOL
end

function Tank:CooldownStatus(idList)
  local out = {}
  if not idList then return out end

  for _, id in ipairs(idList) do
    local name, icon = spellNameIcon(id)
    local row = { id = id, name = name, icon = icon, ready = false, reason = "", remaining = 0 }

    local isKnown = C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id)
    if not isKnown then
      row.reason = "Not Talented"
    else
      local cd = C_Spell.GetSpellCooldown(id)
      if cd and (cd.duration or 0) == 0 then
        row.ready = true
      elseif cd and cd.duration and cd.duration > 0 then
        if durationIsGCD(cd.duration) then
          local gcdRem = gcdRemaining()
          row.reason, row.remaining = "Global Cool Down", gcdRem
        else
          row.reason = "On Cooldown"
          local rem = (cd.startTime + cd.duration) - GetTime()
          row.remaining = (rem > 0) and rem or 0
        end
      else
        row.reason = "Unavailable"
      end
    end
    out[#out+1] = row
  end
  return out
end

--==================================================
-- Shared Items (pots / healthstone) + Scan
--==================================================

-- Only *** (rank 3) + Healthstone for v1 icons; text recap can still show any state later.
-- (IDs current as of TWW/11.0) using tables in individual module currently before moving to shared resource
--[[
local SHARED_ITEMS = {
  { id = 211880, name = "Algari Healing Potion (R3)",  type = "potion",      rank = 3 },
  { id = 212244, name = "Cave Dwellers Delight (R3)",  type = "utility",     rank = 3 },
  { id = 5512,   name = "Healthstone",                 type = "healthstone", rank = nil },
}

local function itemCooldown(itemID)
  local start, dur = C_Item.GetItemCooldown(itemID)
  if not start or not dur then return 0, 0 end
  local rem = (start + dur) - GetTime()
  return (rem > 0) and rem or 0, dur
end

function Tank:ScanItems()
  local out = {}
  for _, it in ipairs(SHARED_ITEMS) do
    local count = C_Item.GetItemCount(it.id) or 0
    local ready, reason, CDremaining = false, "", 0

    if count <= 0 then
      ready, reason, CDremaining = false, "None in Bags", 0
    else
      local rem, dur = itemCooldown(it.id)
      if dur == 0 or rem == 0 then
        ready, reason, CDremaining = true, "", 0
      else
        if durationIsGCD(dur) then
          local gcdRem = gcdRemaining()
          ready, reason, CDremaining = false, "Global Cool Down", gcdRem
        else
          ready, reason, CDremaining = false, "On Cooldown", rem
        end
      end
    end

    out[#out+1] = {
      id = it.id, name = it.name, rank = it.rank, type = it.type,
      bags = count, ready = ready, reason = reason, CDremaining = CDremaining,
      icon = (it.id) or nil,
    }
  end
  return out
end
--]]
--==================================================
-- Loss of Control (todo still)
--==================================================

function Tank:CollectLoC(windowSec)
  return {}
end

--==================================================
-- Init hook (Core.lua should call Tank:Init() on PLAYER_LOGIN)
--==================================================

function Tank:Init()
  EnsureDB()
  -- snap UI index to newest on load so first open shows latest
  local ch = self:GetCharDB()
  ch.deaths.idx = #ch.deaths.list
end

end 
--end
