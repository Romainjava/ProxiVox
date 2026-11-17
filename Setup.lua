-- ProxiVox setup: first-run consent and settings wizard. The whole flow lives
-- in plain functions (Open, Accept, Refuse, SetDraft, Finish) so it can run
-- without any widget; the widgets only call them, and the saved variables are
-- written on "Terminer" only: Previous/Next work on a draft.
local addonName, ns = ...

local Setup = {}
ns.Setup = Setup

local PAGES = 4
local CONTEXT_KEYS = { world = true, dungeon = true, raid = true, pvp = true }
local CONTEXT_LABELS = { world = "Monde", dungeon = "Donjons", raid = "Raids", pvp = "JcJ" }

local WELCOME = "ProxiVox rejoint un canal de discussion caché, « ProxiVoxVoice », avec le vocal : "
  .. "tous les utilisateurs de l'addon s'y retrouvent.\n\n"
  .. "Votre position est partagée avec eux sur ce canal (toutes les 1,5 s quand vous bougez, "
  .. "toutes les 10 s à l'arrêt). Chaque personne calcule le volume des autres de son côté : "
  .. "vos réglages ne quittent jamais votre jeu.\n\n"
  .. "ProxiVox n'est pas compatible avec ForeverVoice ni Prox Voice Party."

local draft
local page = 1
local frame
local pageWidgets = {}
local syncers = {}
local syncing = false
local previousButton, nextButton, finishButton

local function Clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function ValueOf(key)
  if CONTEXT_KEYS[key] then return draft.contexts[key] end
  return draft[key]
end

function Setup.SetDraft(key, value)
  if not draft or key == nil then return end
  if CONTEXT_KEYS[key] then
    draft.contexts[key] = value and true or false
  elseif key == "maxRange" then
    draft.maxRange = Clamp(tonumber(value) or draft.maxRange, 50, 1000)
    draft.fullRange = math.min(draft.fullRange, draft.maxRange)
  elseif key == "fullRange" then
    draft.fullRange = math.min(Clamp(tonumber(value) or draft.fullRange, 0, 50), draft.maxRange)
  elseif key == "behindFactor" then
    draft.behindFactor = Clamp(tonumber(value) or draft.behindFactor, 0, 1)
  elseif key == "alert" or key == "autoActivate" then
    draft[key] = value and true or false
  end
end

-- Templates differ between clients (and some do not exist on this one): try the
-- templated frame first, then fall back to a plain widget.
local function SafeCreateFrame(kind, name, parent, template)
  if type(CreateFrame) ~= "function" then return nil end
  local ok, created = pcall(CreateFrame, kind, name, parent, template)
  if ok and created then return created end
  ok, created = pcall(CreateFrame, kind, name, parent)
  if ok and created then return created end
  return nil
end

local function SetText(widget, text)
  if widget and widget.SetText then widget:SetText(text) end
end

local function AddToPage(index, ...)
  local list = pageWidgets[index]
  if not list then
    list = {}
    pageWidgets[index] = list
  end
  for i = 1, select("#", ...) do
    local widget = select(i, ...)
    if widget then list[#list + 1] = widget end
  end
end

local function Sync()
  syncing = true
  for _, refresh in ipairs(syncers) do
    refresh()
  end
  syncing = false
end

local function AddSlider(key, label, low, high, step, describe, offset)
  local name = addonName .. "Setup" .. key
  local slider = SafeCreateFrame("Slider", name, frame, "OptionsSliderTemplate")
  if not slider then return end
  slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, offset)
  slider:SetWidth(320)
  if slider.SetMinMaxValues then slider:SetMinMaxValues(low, high) end
  if slider.SetValueStep then slider:SetValueStep(step) end
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

  local title = _G[name .. "Text"]
  if not title then
    title = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if title then
      title:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 4)
      title:SetJustifyH("LEFT")
    end
  end
  SetText(title, label)

  local value = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if value then
    value:SetPoint("LEFT", slider, "RIGHT", 12, 0)
  end

  syncers[#syncers + 1] = function()
    local current = ValueOf(key)
    if current and slider.SetValue then slider:SetValue(current) end
    SetText(value, describe(current or 0))
  end

  slider:SetScript("OnValueChanged", function(_, newValue)
    if syncing then return end
    Setup.SetDraft(key, newValue)
    Sync()
  end)

  AddToPage(2, slider, title, value)
end

local function AddCheckBox(index, key, label, offset)
  local name = addonName .. "Setup" .. key
  local check = SafeCreateFrame("CheckButton", name, frame, "UICheckButtonTemplate")
  if not check then return end
  check:SetPoint("TOPLEFT", frame, "TOPLEFT", 30, offset)
  check:SetSize(24, 24)

  local checkName = check.GetName and check:GetName()
  local text = checkName and _G[checkName .. "Text"] or nil
  if not text then
    text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if text then text:SetPoint("LEFT", check, "RIGHT", 6, 0) end
  end
  SetText(text, label)

  syncers[#syncers + 1] = function()
    if check.SetChecked then
      check:SetChecked(ValueOf(key) and true or false)
    end
  end

  check:SetScript("OnClick", function(self)
    Setup.SetDraft(key, self.GetChecked and self:GetChecked() or false)
  end)

  AddToPage(index, check, text)
end

local function CreateButton(key, label, onClick)
  local button = SafeCreateFrame("Button", addonName .. "Setup" .. key, frame, "UIPanelButtonTemplate")
  if not button then return nil end
  button:SetSize(120, 24)
  SetText(button, label)
  button:SetScript("OnClick", onClick)
  return button
end

local function Build()
  if frame or not UIParent then return end
  frame = SafeCreateFrame("Frame", addonName .. "SetupFrame", UIParent)
  if not frame then return end
  frame:SetSize(560, 400)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:Hide()

  -- a plain dark panel: the frame has no template, so without it the text sits on the 3D scene
  local background = frame:CreateTexture(nil, "BACKGROUND")
  if background and background.SetColorTexture then
    background:SetAllPoints(frame)
    background:SetColorTexture(0, 0, 0, 0.85)
  end

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  if title then
    title:SetPoint("TOP", frame, "TOP", 0, -14)
    title:SetText("ProxiVox")
  end

  -- page 1: consent
  local welcome = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if welcome then
    welcome:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -48)
    welcome:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -48)
    welcome:SetJustifyH("LEFT")
    welcome:SetWordWrap(true)
    welcome:SetText(WELCOME)
  end
  local refuse = CreateButton("Refuse", "Refuser", function() Setup.Refuse() end)
  local accept = CreateButton("Accept", "Accepter", function() Setup.Accept() end)
  if refuse then refuse:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 18) end
  if accept then accept:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 18) end
  AddToPage(1, welcome, refuse, accept)

  -- page 2: ranges, all in meters
  AddSlider("maxRange", "Portée maximale", 50, 1000, 10,
    function(value) return string.format("%.0f m", value) end, -80)
  AddSlider("fullRange", "Plein volume jusqu'à", 0, 50, 1,
    function(value) return string.format("%.0f m", value) end, -150)
  AddSlider("behindFactor", "Voix derrière toi", 0, 1, 0.05,
    function(value) return string.format("%.0f %%", value * 100) end, -220)

  -- page 3: where the addon works
  AddCheckBox(3, "world", CONTEXT_LABELS.world, -70)
  AddCheckBox(3, "dungeon", CONTEXT_LABELS.dungeon, -110)
  AddCheckBox(3, "raid", CONTEXT_LABELS.raid, -150)
  AddCheckBox(3, "pvp", CONTEXT_LABELS.pvp, -190)
  AddCheckBox(3, "alert", "Alerte quand quelqu'un arrive à portée", -236)

  -- page 4: voice
  AddCheckBox(4, "autoActivate", "Activer le vocal ProxiVox automatiquement", -80)
  local voiceNote = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if voiceNote then
    voiceNote:SetPoint("TOPLEFT", frame, "TOPLEFT", 62, -112)
    voiceNote:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -112)
    voiceNote:SetJustifyH("LEFT")
    voiceNote:SetWordWrap(true)
    voiceNote:SetText("Remplace le vocal de groupe ou de guilde actif : WoW n'en garde qu'un seul.")
  end
  AddToPage(4, voiceNote)

  previousButton = CreateButton("Previous", "Précédent", function() Setup.Previous() end)
  nextButton = CreateButton("Next", "Suivant", function() Setup.Next() end)
  finishButton = CreateButton("Finish", "Terminer", function() Setup.Finish() end)
  if previousButton then previousButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 24, 18) end
  if nextButton then nextButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 18) end
  if finishButton then finishButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 18) end
end

local function ShowPage()
  if not frame then return end
  for index = 1, PAGES do
    local list = pageWidgets[index]
    if list then
      local shown = index == page
      for _, widget in ipairs(list) do
        if shown then widget:Show() else widget:Hide() end
      end
    end
  end
  if previousButton then previousButton:SetShown(page > 1) end
  if nextButton then nextButton:SetShown(page == 2 or page == 3) end
  if finishButton then finishButton:SetShown(page == PAGES) end
  frame:Show()
end

local function Close()
  if frame then frame:Hide() end
end

function Setup.IsOpen()
  return frame ~= nil and frame:IsShown() and true or false
end

function Setup.Page()
  return page
end

function Setup.Open()
  local db = ns.db
  if not db then return end
  draft = {
    maxRange = db.maxRange,
    fullRange = db.fullRange,
    behindFactor = db.behindFactor,
    alert = db.alert and true or false,
    autoActivate = db.autoActivate and true or false,
    contexts = {
      world = db.contexts.world and true or false,
      dungeon = db.contexts.dungeon and true or false,
      raid = db.contexts.raid and true or false,
      pvp = db.contexts.pvp and true or false,
    },
  }
  page = 1
  Build()
  Sync()
  ShowPage()
end

function Setup.Accept()
  if not draft then return end
  page = 2
  ShowPage()
end

function Setup.Next()
  if not draft or page >= PAGES then return end
  page = page + 1
  ShowPage()
end

function Setup.Previous()
  if not draft or page <= 1 then return end
  page = page - 1
  ShowPage()
end

function Setup.Refuse()
  local db = ns.db
  if not db then return end
  ns.Voice.Restore()
  db.consent = false
  db.enabled = false
  db.setupDone = true
  draft = nil
  page = 1
  Close()
  ns.Print("ProxiVox reste désactivé. Lance /pvx setup quand tu voudras l'activer.")
end

function Setup.Finish()
  local db = ns.db
  if not draft then return end
  db.maxRange = draft.maxRange
  db.fullRange = draft.fullRange
  db.behindFactor = draft.behindFactor
  db.alert = draft.alert
  db.autoActivate = draft.autoActivate
  for key in pairs(CONTEXT_KEYS) do
    db.contexts[key] = draft.contexts[key] and true or false
  end
  db.consent = true
  db.enabled = true
  db.setupDone = true
  draft = nil
  page = 1
  Close()
  ns.Print("Configuration enregistrée : ProxiVox rejoint ProxiVoxVoice.")
  ns.Start()
end
