-- ProxiVox arrow: while a member speaks, an arrow sits on a circle around the
-- screen center, pointing at them, with their name. No pulsing, no animation:
-- only a 0.1 s redraw while somebody speaks.
local addonName, ns = ...

local Voice = ns.Voice

local Arrow = {}
ns.Arrow = Arrow

local THROTTLE = 0.1
local RADIUS_RATIO = 0.35
local SIZE = 32
local FALLBACK_RADIUS = 200

local frame, texture, label
local elapsed = 0
local tick

local function Radius()
  if type(UIParent) == "table" and UIParent.GetWidth and UIParent.GetHeight then
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) == "number" and type(height) == "number" then
      return math.min(width, height) * RADIUS_RATIO
    end
  end
  return FALLBACK_RADIUS
end

local function Build()
  if frame or not UIParent or type(CreateFrame) ~= "function" then return end
  frame = CreateFrame("Frame", addonName .. "Arrow", UIParent)
  if not frame then return end
  frame:SetSize(SIZE, SIZE)
  frame:Hide()
  texture = frame:CreateTexture(nil, "OVERLAY")
  if texture then
    texture:SetTexture("Interface\\Minimap\\MiniMap-DeadArrow")
    texture:SetSize(SIZE, SIZE)
    texture:SetPoint("CENTER", frame, "CENTER", 0, 0)
  end
  label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if label then
    label:SetPoint("TOP", frame, "BOTTOM", 0, -2)
  end
end

-- The nearest speaking member wins when several speak at once.
local function Pick()
  if not Voice.IsActive() then return nil end
  local best
  for _, speaker in ipairs(Voice.Speakers()) do
    if not best or speaker.distance < best.distance then
      best = speaker
    end
  end
  return best
end

function Arrow.Refresh()
  Build()
  if not frame then return end
  elapsed = 0
  local target = Pick()
  if not target then
    frame:Hide()
    frame:SetScript("OnUpdate", nil)
    return
  end
  local radius = Radius()
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", -math.sin(target.relative) * radius, math.cos(target.relative) * radius)
  if texture and texture.SetRotation then
    texture:SetRotation(target.relative)
  end
  if label then
    label:SetText(target.name or "?")
  end
  frame:Show()
  frame:SetScript("OnUpdate", tick)
end

tick = function(_, delta)
  elapsed = elapsed + delta
  if elapsed < THROTTLE then return end
  Arrow.Refresh()
end
