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
-- Interface: 120000
-- UI
-- Author: M44SYR
--==================================================

local ADDON_NAME, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

--==================================================
-- TINY HELPERS & COLORS
--==================================================

local function RGB(r,g,b) return r/255,g/255,b/255 end
local GOLD   = { RGB(255,208,64) }
local RED    = { RGB(220, 64,64) }
local GRAY   = { RGB(170,170,170) }
local GREEN  = { RGB( 64,200,96) }
local ORANGE = { RGB(255,160,64) }
local YELLOW = { RGB(255,224,64) }
local CYAN   = { RGB( 64,196,255) }

local unpack = unpack or table.unpack

--==================================================
-- HISTORY (LAST 10 DEATHS, PERSISTED)
--==================================================

local HISTORY_MAX = 10

local function historydb()
  ParryDB = ParryDB or {}
  ParryDB.deaths = ParryDB.deaths or { list = {}, idx = 0 }
  return ParryDB.deaths
end

local function PushReport(report)
  local d = historydb()
  report = report or {}
  report.time = report.time or GetServerTime()
  table.insert(d.list, report)
  if #d.list > HISTORY_MAX then
    table.remove(d.list, 1)
  end
  d.idx = #d.list
end

local function CurrentReport()
  local d = historydb()
  return d.list[d.idx]
end

--==================================================
-- SavedVariables pocket for UI
--==================================================

local function db()
  ParryDB = ParryDB or {}
  ParryDB.ui = ParryDB.ui or { btn = { x = 200, y = 200, locked = false } }
  return ParryDB.ui
end

--==================================================
-- RECAP BUTTON
--==================================================

local recapButton
local pulseGroup

local function StartPulse()
  local btn = recapButton
  if not btn then return end
  if pulseGroup then pulseGroup:Stop() end
  pulseGroup = btn:CreateAnimationGroup()
  local a1 = pulseGroup:CreateAnimation("Alpha")
  a1:SetFromAlpha(1) a1:SetToAlpha(0.3) a1:SetDuration(0.6)
  local a2 = pulseGroup:CreateAnimation("Alpha")
  a2:SetFromAlpha(0.3) a2:SetToAlpha(1) a2:SetDuration(0.6)
  pulseGroup:SetLooping("REPEAT")
  pulseGroup:Play()
end

local function StopPulse()
  if pulseGroup then pulseGroup:Stop() end
  if recapButton then recapButton:SetAlpha(1) end
end

local function CreateRecapButton()
  if recapButton then return recapButton end
  local d = db()
  local btn = CreateFrame("Button", ADDON_NAME.."RecapButton", UIParent, "UIPanelButtonTemplate")
  btn:SetSize(80, 20)               
  btn:SetText("Parry")              
  btn:GetFontString():SetPoint("CENTER", 0, -1)
  btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
  btn:SetMovable(true)
  btn:EnableMouse(true)
  btn:RegisterForDrag("LeftButton")
  btn:SetClampedToScreen(true)
  btn:SetFrameStrata("MEDIUM")
  btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", d.btn.x, d.btn.y)

  btn:SetScript("OnDragStart", function(self)
    if db().btn.locked then return end
    self:StartMoving()
  end)
  btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    if x and y then
      local sx, sy = UIParent:GetLeft(), UIParent:GetBottom()
      db().btn.x = x - (sx or 0)
      db().btn.y = y - (sy or 0)
    end
  end)

  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Parry Recap", unpack(GOLD))
    GameTooltip:AddLine("Left-click: open report", 1,1,1)
    GameTooltip:AddLine(db().btn.locked and "Locked: /parryunlock" or "Lock: /parrylock", unpack(GRAY))
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetScript("OnClick", function() UI:ToggleMain() end)

  recapButton = btn
  return btn
end

--==================================================
-- MAIN WINDOW
--==================================================

local main, body, scroll, scrollChild
local nav = {}  -- NAV BUTTONS

local function CreateMain()
  if main then return main end

  main = CreateFrame("Frame", ADDON_NAME.."Main", UIParent, "BasicFrameTemplateWithInset")
  main:SetSize(420, 520)
  main:SetPoint("CENTER")
  main:EnableMouse(true)
  main:SetMovable(true)
  main:RegisterForDrag("LeftButton")
  main:SetScript("OnDragStart", main.StartMoving)
  main:SetScript("OnDragStop", main.StopMovingOrSizing)
  main:Hide()

  main.title = main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  main.title:SetPoint("TOP", 0, -3)
  main.title:SetText("Parry — Tank Coaching")

  nav.prev = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
  nav.prev:SetSize(24, 22)
  nav.prev:SetPoint("TOPLEFT", 14, 0)
  nav.prev:SetText("<")

  nav.next = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
  nav.next:SetSize(24, 22)
  nav.next:SetPoint("LEFT", nav.prev, "RIGHT", 4, 0)
  nav.next:SetText(">")

  nav.ind = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  nav.ind:SetPoint("LEFT", nav.next, "RIGHT", 8, 0)
  nav.ind:SetText("0/0")

  scroll = CreateFrame("ScrollFrame", ADDON_NAME.."Scroll", main, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -36)
  scroll:SetPoint("BOTTOMRIGHT", -30, 14)

  scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(380, 480)
  scroll:SetScrollChild(scrollChild)

  -- tracked body nodes
  body = { nodes = {} }
  local y = -4

  function body:Clear()
    for i = 1, #self.nodes do
      local fs = self.nodes[i]
      fs:Hide()
      fs:SetText("")
    end
    wipe(self.nodes)
    y = -4
    scrollChild:SetHeight(1)
  end

  local function track(fs)
    table.insert(body.nodes, fs)
    return fs
  end

  local function addSection(titleText)
    local t = track(scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"))
    t:SetPoint("TOPLEFT", 4, y)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    t:SetText(titleText or "")
    local h = t:GetStringHeight() or 20
    y = y - (h + 6)   -- header padding
    return t
  end

  local function addLine(text, r,g,b)
    local l = track(scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    l:SetPoint("TOPLEFT", 10, y)
    l:SetJustifyH("LEFT")
    l:SetWordWrap(true)
    l:SetWidth(340)
    if r then l:SetTextColor(r,g,b) end
    l:SetText(text or "")
    local h = l:GetStringHeight() or 14
    y = y - (h + 4)   -- line padding
    return l
  end

  body._addSection = addSection
  body._addLine    = addLine

  local function finalizeHeight()
    scrollChild:SetHeight(math.abs(y) + 12)
    if scroll and scroll.UpdateScrollChildRect then
      scroll:UpdateScrollChildRect()
    end
  end

  local function updateIndicator()
    local d = historydb()
    nav.ind:SetText(("%d/%d"):format(d.idx, #d.list))
  end

  local function renderCurrent()
    local rpt = CurrentReport() or { hits={}, mit={}, cooldowns={}, items={}, debuffs={} }
    body:Render(rpt)
    updateIndicator()
  end

  nav.prev:SetScript("OnClick", function()
    local d = historydb()
    if d.idx > 1 then d.idx = d.idx - 1; renderCurrent() end
  end)
  nav.next:SetScript("OnClick", function()
    local d = historydb()
    if d.idx < #d.list then d.idx = d.idx + 1; renderCurrent() end
  end)

  main:SetScript("OnShow", function() renderCurrent() end)

  function body:Render(report)
    self:Clear()

    -- normalized to avoid nil tables
    report = report or {}
    report.hits      = report.hits      or {}
    report.mit       = report.mit       or {}
    report.cooldowns = report.cooldowns or {}
    report.items     = report.items     or {}
    report.debuffs   = report.debuffs   or {}

--==================================================
-- WHAT KILLED YOU
--==================================================
    self._addSection("What Killed You")
    if #report.hits == 0 then
      self._addLine("No recent damage recorded.", unpack(GRAY))
    else
      for i, hit in ipairs(report.hits) do
        local tag = (i == #report.hits) and "Killing Blow" or ("Hit "..(i - (#report.hits-3)))
        self._addLine(("- %s: %s (%s)"):format(hit.name or "?", hit.amount or 0, tag), unpack(RED))
      end
    end

--==================================================
-- ACTIVE MITIGATION
--==================================================
    self._addSection("Active Mitigation/Buffs")
    local anyMit = false
    for _, b in ipairs(report.mit) do
      if b.active then
        anyMit = true
        self._addLine(("- %s was active"):format(b.name or "?"), unpack(GREEN))
      elseif not b.active then
        anyMit = false
        self._addLine(("- %s was not active"):format(b.name or "?"), unpack(RED))
      else
      self._addLine("No tracked mitigation was active in the last window.", unpack(GRAY))
    end
end
--==================================================
-- DEFENSIVES
--==================================================
    self._addSection("Cooldowns/Defensives")
    for _, cd in ipairs(report.cooldowns) do
      local label, r,g,b = "Unavailable", unpack(GRAY)
      if cd.ready then
        label, r,g,b = "Ready", unpack(CYAN)
      else
        if cd.reason == "On Cooldown" then
          if cd.remaining and cd.remaining > 0.05 then
            label = ("On Cooldown (%.1fs)"):format(cd.remaining)
          else label = "On Cooldown" end
          r,g,b = unpack(ORANGE)
        elseif cd.reason == "Global Cool Down" then
          label, r,g,b = "On GCD", unpack(YELLOW)
        elseif cd.reason == "Not Talented" then
          label, r,g,b = "Not Talented", unpack(GRAY)
        end
      end
      self._addLine(("- %s: %s"):format(cd.name or "?", label), r,g,b)
    end

--==================================================
-- ITEMS
--==================================================
    self._addSection("Items")
    for _, it in ipairs(report.items) do
      local have = (it.bags or 0)
      local haveTxt = have > 0 and ("x"..have) or "x0"
      local label, r,g,b = "Unavailable", unpack(GRAY)
      if have <= 0 then
        label, r,g,b = "None in Bags", unpack(GRAY)
      elseif it.ready then
        label, r,g,b = "Ready", unpack(CYAN)
      else
        if it.reason == "On Cooldown" then
          if it.CDremaining and it.CDremaining > 0.05 then
            label = ("On Cooldown (%.1fs)"):format(it.CDremaining)
          else label = "On Cooldown" end
          r,g,b = unpack(ORANGE)
        elseif it.reason == "Global Cool Down" then
          label, r,g,b = "On GCD", unpack(YELLOW)
        end
      end
      self._addLine(("- %s: %s (bags %s)"):format(it.name or "?", label, haveTxt), r,g,b)
    end

--==================================================
-- DEBUFFS
--==================================================
    self._addSection("Debuffs")
    local anyDebuff = false
    for _, d in ipairs(report.debuffs) do
      if d.active then
        anyDebuff = true
        self._addLine(("- %s"):format(d.name or "?"))
      end
    end
    if not anyDebuff then
      self._addLine("No tracked debuffs in the recent window.", unpack(GRAY))
    end

    finalizeHeight()
  end

  return main
end

--==================================================
-- PUBLIC API
--==================================================

function UI:Init()
  if self._inited then return end
  self._inited = true

  CreateRecapButton()
  CreateMain()

  SLASH_PARRY1 = "/parry"
  SlashCmdList.PARRY = function() UI:ToggleMain() end

  SLASH_PARRYLOCK1  = "/parrylock"
  SlashCmdList.PARRYLOCK = function()
    db().btn.locked = true
    print("|cff66ccffParry|r button locked.")
  end

  SLASH_PARRYUNLOCK1  = "/parryunlock"
  SlashCmdList.PARRYUNLOCK = function()
    db().btn.locked = false
    print("|cff66ccffParry|r button unlocked.")
  end

  -- snap to newest on init so first open shows latest
  local d = historydb()
  d.idx = #d.list
end

function UI:ToggleMain()
  local f = CreateMain()
  if f:IsShown() then
    f:Hide()
  else
    f:Show()      -- OnShow renders current
    StopPulse()   -- stop pulsing when user opens
  end
end

function UI:ShowDeathReport(report)
  CreateMain()
  CreateRecapButton()
  PushReport(report or {})
  StartPulse()           -- pulse to signal a new report
  -- do NOT auto-open; user clicks the button
end

end
--end
