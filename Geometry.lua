-- ProxiVox geometry: pure functions, no WoW API and no addon state in here.
local _, ns = ...

local Geometry = {}
ns.Geometry = Geometry

-- World coordinates come from UnitPosition, which works in yards, while every
-- setting is expressed in meters: this constant and ToMeters are the only
-- conversion point in the addon.
local YARD_TO_METER = 0.9144

local HALF_PI = math.pi / 2
local TWO_PI = math.pi * 2

-- WoW runs Lua 5.1 (math.atan2), other runtimes spell it math.atan(y, x).
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
Geometry.Atan2 = atan2

function Geometry.ToMeters(yards)
  return yards * YARD_TO_METER
end

-- Length of a world offset, in meters.
function Geometry.Length(dx, dy)
  return Geometry.ToMeters(math.sqrt(dx * dx + dy * dy))
end

-- Wraps any angle into (-pi, pi].
function Geometry.Normalize(angle)
  angle = angle % TWO_PI
  if angle > math.pi then
    angle = angle - TWO_PI
  end
  return angle
end

-- Bearing of the target minus the listener facing: 0 is straight ahead,
-- positive is on the left, +-pi is right behind.
function Geometry.RelativeAngle(facing, dx, dy)
  return Geometry.Normalize(atan2(dy, dx) - facing)
end

-- 1 up to fullRange, then (1 - t)^2 down to exactly 0 at maxRange.
function Geometry.Falloff(distance, fullRange, maxRange)
  if distance <= fullRange then return 1 end
  if maxRange <= fullRange or distance >= maxRange then return 0 end
  local t = (distance - fullRange) / (maxRange - fullRange)
  return (1 - t) * (1 - t)
end

-- 1 in front of the listener, then linear from 1 at 90 degrees to
-- behindFactor at 180 degrees.
function Geometry.Behind(relativeAngle, behindFactor)
  local angle = math.abs(relativeAngle)
  if angle <= HALF_PI then return 1 end
  local t = (angle - HALF_PI) / HALF_PI
  return 1 + t * (behindFactor - 1)
end

function Geometry.Volume(distance, relativeAngle, fullRange, maxRange, behindFactor)
  return Geometry.Falloff(distance, fullRange, maxRange) * Geometry.Behind(relativeAngle, behindFactor)
end
