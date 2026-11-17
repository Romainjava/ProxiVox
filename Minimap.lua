-- ProxiVox minimap button and addon compartment entry, same pattern as
-- ShadowsightNamesize: a Button named "<Addon>MinimapButton" parented to the
-- Minimap (MinimapButtonButton collects it), dragged around the minimap edge.
-- Left click opens the settings wizard, right click toggles the addon.
local addonName, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local ICON = "Interface\\Icons\\Ability_Hunter_BeastCall"
local DEFAULT_ANGLE = 225

local button

local SHAPES = {
  ["ROUND"] = { true, true, true, true },
  ["SQUARE"] = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true },
  ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
  ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true },
  ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true },
  ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true },
  ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function Place()
  if not button or not Minimap or not ns.db then return end
  local angle = math.rad(ns.db.minimap.angle or DEFAULT_ANGLE)
  local x, y, q = math.cos(angle), math.sin(angle), 1
  if x < 0 then q = q + 1 end
  if y > 0 then q = q + 2 end
  local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
  local quad = SHAPES[shape] or SHAPES.ROUND
  local w = Minimap:GetWidth() / 2 + 5
  local h = Minimap:GetHeight() / 2 + 5
  if quad[q] then
    x, y = x * w, y * h
  else
    local diagW = math.sqrt(2 * w * w) - 10
    local diagH = math.sqrt(2 * h * h) - 10
    x = math.max(-w, math.min(x * diagW, w))
    y = math.max(-h, math.min(y * diagH, h))
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDrag()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  if not mx or not px or not scale or scale == 0 then return end
  px, py = px / scale, py / scale
  ns.db.minimap.angle = math.deg(ns.Geometry.Atan2(py - my, px - mx)) % 360
  Place()
end

-- Players within maxRange the listener can hear right now.
local function AudibleCount()
  local count = 0
  for guid in pairs(ns.Comm.peers) do
    if (ns.Voice.VolumeFor(guid) or 0) > 0 then count = count + 1 end
  end
  return count
end

function MinimapButton.ShowTooltip(owner)
  if not GameTooltip or not ns.db then return end
  local db = ns.db
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:AddLine("ProxiVox")
  if db.consent ~= true then
    GameTooltip:AddLine("Pas encore configuré", 1, 0.5, 0.3)
  elseif not db.enabled then
    GameTooltip:AddLine("Désactivé", 1, 0.5, 0.3)
  else
    GameTooltip:AddLine(ns.Voice.IsActive() and "Actif" or "Inactif ici", 0.5, 0.8, 1)
    GameTooltip:AddLine(ns.Voice.channelID and "Vocal ProxiVox : connecté" or "Vocal ProxiVox : non connecté", 0.8, 0.8, 0.8)
    GameTooltip:AddLine(string.format("Joueurs à portée : %d (max %.0f m)", AudibleCount(), db.maxRange), 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("Clic gauche : réglages", 1, 1, 1)
  GameTooltip:AddLine("Clic droit : activer / désactiver", 1, 1, 1)
  GameTooltip:AddLine("Glisser : déplacer l'icône", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end

-- Shared by the minimap button and the addon compartment.
function MinimapButton.Click(mouseButton)
  if mouseButton == "RightButton" then
    ns.SetEnabled(not ns.db.enabled)
  else
    ns.Setup.Open()
  end
end

function MinimapButton.Create()
  if button or not Minimap or type(CreateFrame) ~= "function" then return end
  local b = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
  if not b then return end
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetAllPoints()

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")

  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  b:SetScript("OnEnter", function(self) MinimapButton.ShowTooltip(self) end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  b:SetScript("OnClick", function(_, mouseButton) MinimapButton.Click(mouseButton) end)
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDrag) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  button = b
  Place()
  b:SetShown(ns.db.minimap.show ~= false)
end

function MinimapButton.SetShown(shown)
  ns.db.minimap.show = shown and true or false
  if button then button:SetShown(shown) end
end

function MinimapButton.Reset()
  ns.db.minimap.angle = DEFAULT_ANGLE
  Place()
end

-- Addon compartment (## AddonCompartmentFunc* in the toc).
function ProxiVox_OnAddonCompartmentClick(_, mouseButton)
  if ns.db then MinimapButton.Click(mouseButton) end
end

function ProxiVox_OnAddonCompartmentEnter(_, menuButton)
  MinimapButton.ShowTooltip(menuButton)
end

function ProxiVox_OnAddonCompartmentLeave()
  if GameTooltip then GameTooltip:Hide() end
end
