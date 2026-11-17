-- ProxiVox transport: everyone using the addon meets in one custom voice
-- channel and exchanges positions as hidden addon messages on it.
local _, ns = ...

local Geometry = ns.Geometry

local Comm = {}
ns.Comm = Comm

Comm.CHANNEL_NAME = "ProxiVoxVoice"
Comm.PREFIX = "ProxiVox"

-- guid -> { guid, name, x, y, instanceID, dead, lastSeen, alerted }
Comm.peers = {}

local MOVE_INTERVAL = 1.5
local STILL_INTERVAL = 10
local MOVE_YARDS = 1

local lastSentAt = 0
local lastSentX, lastSentY

function Comm.PeerName(guid)
  local peer = Comm.peers[guid]
  return peer and peer.name or nil
end

function Comm.ChannelIndex()
  if type(GetChannelName) ~= "function" then return nil end
  local ok, index = pcall(GetChannelName, Comm.CHANNEL_NAME)
  if not ok or type(index) ~= "number" or index <= 0 then return nil end
  return index
end

function Comm.IsRestricted()
  local api = C_ChatInfo
  if type(api) ~= "table" or type(api.AreOutgoingAddonChatMessagesRestricted) ~= "function" then
    return false
  end
  local ok, restricted = pcall(api.AreOutgoingAddonChatMessagesRestricted)
  return ok and restricted and true or false
end

function Comm.Register()
  local api = C_ChatInfo
  if type(api) ~= "table" or type(api.RegisterAddonMessagePrefix) ~= "function" then return false end
  local ok = pcall(api.RegisterAddonMessagePrefix, Comm.PREFIX)
  return ok
end

function Comm.HideFromChatFrame()
  if type(ChatFrame_RemoveChannel) ~= "function" or not DEFAULT_CHAT_FRAME then return end
  pcall(ChatFrame_RemoveChannel, DEFAULT_CHAT_FRAME, Comm.CHANNEL_NAME)
end

function Comm.JoinChannel()
  if not ns.IsAllowed() then return false end
  if Comm.ChannelIndex() then
    Comm.HideFromChatFrame()
    return true
  end
  if type(JoinChannelByName) ~= "function" then return false end
  local ok = pcall(JoinChannelByName, Comm.CHANNEL_NAME, nil, nil, true)
  if not ok then return false end
  Comm.HideFromChatFrame()
  return true
end

-- "P1<TAB>guid<TAB>instance<TAB>x<TAB>y<TAB>dead", x and y are "-" when the
-- client hides positions (instances): peers still learn who is around.
local function Encode(guid, x, y, instanceID, dead)
  local flag = dead and 1 or 0
  if type(x) == "number" and type(y) == "number" then
    return string.format("P1\t%s\t%d\t%.1f\t%.1f\t%d", guid, instanceID or 0, x, y, flag)
  end
  return string.format("P1\t%s\t%d\t-\t-\t%d", guid, instanceID or 0, flag)
end

local function Decode(text)
  if type(text) ~= "string" then return nil end
  local fields = {}
  for field in string.gmatch(text, "[^\t]+") do
    fields[#fields + 1] = field
  end
  if fields[1] ~= "P1" or #fields ~= 6 then return nil end
  local guid = fields[2]
  if guid == "" then return nil end
  return guid, tonumber(fields[3]), tonumber(fields[4]), tonumber(fields[5]), fields[6] == "1"
end

function Comm.Send()
  if not ns.IsAllowed() then return false end
  local api = C_ChatInfo
  if type(api) ~= "table" or type(api.SendAddonMessage) ~= "function" then return false end
  if Comm.IsRestricted() then return false end
  local index = Comm.ChannelIndex()
  local guid = ns.PlayerGUID()
  if not index or not guid then return false end
  local x, y, instanceID = ns.PlayerPosition()
  local ok = pcall(api.SendAddonMessage, Comm.PREFIX, Encode(guid, x, y, instanceID, ns.PlayerDead()), "CHANNEL", index)
  return ok
end

function Comm.OnAddonMessage(prefix, text, _channel, sender)
  if prefix ~= Comm.PREFIX then return end
  local guid, instanceID, x, y, dead = Decode(text)
  if not guid or guid == ns.PlayerGUID() then return end
  local peer = Comm.peers[guid]
  if not peer then
    peer = { guid = guid }
    Comm.peers[guid] = peer
  end
  if type(sender) == "string" and sender ~= "" then
    peer.name = sender
  end
  peer.instanceID = instanceID
  peer.x = x
  peer.y = y
  peer.dead = dead
  peer.lastSeen = GetTime()
end

-- Sends every 1.5 s while actually moving, every 10 s when standing still.
function Comm.Tick()
  if not ns.IsAllowed() then return end
  local x, y = ns.PlayerPosition()
  local moved = type(x) == "number" and type(lastSentX) == "number"
    and Geometry.Length(x - lastSentX, y - lastSentY) > Geometry.ToMeters(MOVE_YARDS)
  if GetTime() - lastSentAt < (moved and MOVE_INTERVAL or STILL_INTERVAL) then return end
  if not Comm.Send() then return end
  lastSentAt = GetTime()
  lastSentX, lastSentY = x, y
end

ns.OnEvent("CHAT_MSG_ADDON", Comm.OnAddonMessage)
