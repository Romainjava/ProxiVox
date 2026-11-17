-- ProxiVox voices: turns peer positions into per member volumes, handles the
-- instance rules, death rules and the range alert.
local _, ns = ...

local Geometry = ns.Geometry
local Comm = ns.Comm

local Voice = {}
ns.Voice = Voice

-- SetMemberVolume expects either 0..1 or 0..100: the API does not say which,
-- and it is not verifiable outside the game. Change this single constant only.
local VOLUME_MAX = 1
local STALE_SECONDS = 30

Voice.channelID = nil

local members = {}   -- guid -> true, members of our voice channel
local speaking = {}  -- guid -> true while the member speaks
local locations = {} -- guid -> cached playerLocation
local applied = {}   -- guid -> last volume sent to the API

function Voice.IsActive()
  local db = ns.db
  if not db or not db.enabled then return false end
  return db.contexts[ns.ContextKey()] ~= false
end

local function SyncMembers()
  members = {}
  speaking = {}
  local api = C_VoiceChat
  if type(api) ~= "table" or type(api.GetChannel) ~= "function" or not Voice.channelID then return end
  if type(api.GetMemberGUID) ~= "function" then return end
  local ok, channel = pcall(api.GetChannel, Voice.channelID)
  if not ok or type(channel) ~= "table" or type(channel.members) ~= "table" then return end
  for _, member in ipairs(channel.members) do
    local got, guid = pcall(api.GetMemberGUID, member.memberID, Voice.channelID)
    if got and type(guid) == "string" and guid ~= "" then
      members[guid] = true
      if member.isSpeaking then speaking[guid] = true end
    end
  end
end

-- The chat channel name can come back decorated by the client
-- ("ProxiVoxVoice 7"), so the lookup is a plain substring find.
local function MatchesChannel(channel)
  return type(channel) == "table"
    and type(channel.name) == "string"
    and channel.name:find(Comm.CHANNEL_NAME, 1, true) ~= nil
end

local function ChannelFromAPI(channelID)
  local api = C_VoiceChat
  if type(api) ~= "table" or type(api.GetChannel) ~= "function" or type(channelID) ~= "number" then return nil end
  local ok, channel = pcall(api.GetChannel, channelID)
  if ok and MatchesChannel(channel) then return channelID end
  return nil
end

local function ActiveChannelID()
  local api = C_VoiceChat
  if type(api) ~= "table" or type(api.GetActiveChannelID) ~= "function" then return nil end
  local ok, channelID = pcall(api.GetActiveChannelID)
  if ok and type(channelID) == "number" then return channelID end
  return nil
end

local function CustomChannelID()
  local api = C_VoiceChat
  if type(api) ~= "table" or type(api.GetChannelForChannelType) ~= "function" then return nil end
  local channelType = Enum and Enum.ChatChannelType and Enum.ChatChannelType.Custom
  if channelType == nil then return nil end
  local ok, result = pcall(api.GetChannelForChannelType, channelType)
  if not ok then return nil end
  if type(result) == "table" then
    if MatchesChannel(result) and type(result.channelID) == "number" then return result.channelID end
    return nil
  end
  return ChannelFromAPI(result)
end

-- Activating our channel replaces the group or guild voice channel: do it once
-- per session, and never for a channel that is already active.
local activatedChannelID

local function Activate(channelID)
  local db = ns.db
  if not db or not db.autoActivate or activatedChannelID == channelID then return end
  local api = C_VoiceChat
  if type(api) ~= "table" or type(api.ActivateChannel) ~= "function" then return end
  if ActiveChannelID() == channelID then
    activatedChannelID = channelID
    return
  end
  if pcall(api.ActivateChannel, channelID) then
    activatedChannelID = channelID
  end
end

local function MemberGUID(memberID)
  local api = C_VoiceChat
  if type(api) ~= "table" or type(api.GetMemberGUID) ~= "function" or not Voice.channelID then return nil end
  local ok, guid = pcall(api.GetMemberGUID, memberID, Voice.channelID)
  if ok and type(guid) == "string" and guid ~= "" then return guid end
  return nil
end

local function Location(guid)
  if not PlayerLocation or type(PlayerLocation.CreateFromGUID) ~= "function" then return nil end
  local location = locations[guid]
  if not location then
    local ok, created = pcall(PlayerLocation.CreateFromGUID, PlayerLocation, guid)
    if not ok or type(created) ~= "table" then return nil end
    location = created
    locations[guid] = location
  end
  return location
end

local function SetVolume(guid, volume)
  if applied[guid] == volume then return end
  local api = C_VoiceChat
  if type(api) ~= "table" or type(api.SetMemberVolume) ~= "function" then return end
  local location = Location(guid)
  if not location then return end
  local ok = pcall(api.SetMemberVolume, location, volume)
  if ok then applied[guid] = volume end
end

-- Distance in meters and relative angle of a peer, nil when either side of the
-- couple has no usable position.
local function Localize(guid, px, py, facing)
  local peer = Comm.peers[guid]
  if not peer or type(peer.x) ~= "number" or type(peer.y) ~= "number" then return nil end
  if type(px) ~= "number" or type(py) ~= "number" then return nil end
  local dx, dy = peer.x - px, peer.y - py
  return Geometry.Length(dx, dy), Geometry.RelativeAngle(facing, dx, dy)
end

local function Alert(peer, distance)
  local inRange = distance <= ns.db.maxRange
  if not inRange then
    peer.alerted = false
    return
  end
  if peer.alerted then return end
  peer.alerted = true
  ns.Print(string.format("%s est à portée de voix", peer.name or "Un allié"))
  local sound = (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081
  if type(PlaySound) == "function" then
    pcall(PlaySound, sound)
  end
end

-- One snapshot of the listener side per refresh: the status and debug commands
-- reuse the same evaluation without side effects.
local function Snapshot()
  local inInstance = ns.InstanceInfo()
  local env = {
    guid = ns.PlayerGUID(),
    now = GetTime(),
    alive = not ns.PlayerDead(),
    inInstance = inInstance,
    active = Voice.IsActive(),
    group = inInstance and ns.GroupGuids() or nil,
  }
  env.px, env.py = ns.PlayerPosition()
  env.facing = ns.PlayerFacing() or 0
  return env
end

-- Volume for one member, plus its distance when the peer is locatable here.
local function Evaluate(guid, env)
  if not env.active then return VOLUME_MAX end
  if env.inInstance then
    return env.group[guid] and VOLUME_MAX or 0
  end
  local peer = Comm.peers[guid]
  if not peer or type(peer.lastSeen) ~= "number" or env.now - peer.lastSeen > STALE_SECONDS then
    return 0
  end
  local distance, relative = Localize(guid, env.px, env.py, env.facing)
  if not distance then return 0 end
  local db = ns.db
  local volume = Geometry.Volume(distance, relative, db.fullRange, db.maxRange, db.behindFactor)
  if env.alive and peer.dead then
    volume = 0
  end
  return volume, distance
end

function Voice.Apply()
  local db = ns.db
  if not db or db.consent ~= true then return end
  if not Voice.channelID then return end
  local env = Snapshot()
  for guid in pairs(members) do
    if guid ~= env.guid then
      local volume, distance = Evaluate(guid, env)
      SetVolume(guid, volume)
      -- Evaluate only returns a distance for a peer we can localise here, so the
      -- guard is also the "no alert in an instance or with the context off" rule.
      if distance and db.alert then
        Alert(Comm.peers[guid], distance)
      end
    end
  end
end

function Voice.VolumeFor(guid)
  return Evaluate(guid, Snapshot())
end

-- Hands every member back to the game at normal volume: used when a context or
-- the addon is switched off, and when the user refuses after having accepted.
function Voice.Restore()
  local me = ns.PlayerGUID()
  for guid in pairs(members) do
    if guid ~= me then
      SetVolume(guid, VOLUME_MAX)
    end
  end
end

function Voice.Measure(guid)
  local px, py = ns.PlayerPosition()
  return Localize(guid, px, py, ns.PlayerFacing() or 0)
end

function Voice.Speakers()
  local list = {}
  if not Voice.channelID then return list end
  local px, py = ns.PlayerPosition()
  local facing = ns.PlayerFacing() or 0
  local me = ns.PlayerGUID()
  for guid in pairs(speaking) do
    if guid ~= me then
      local distance, relative = Localize(guid, px, py, facing)
      if distance then
        list[#list + 1] = {
          guid = guid,
          name = Comm.PeerName(guid),
          distance = distance,
          relative = relative,
        }
      end
    end
  end
  return list
end

local function RefreshArrow()
  if ns.Arrow then ns.Arrow.Refresh() end
end

-- After a /reload or a relog the chat channel is already joined and
-- VOICE_CHAT_CHANNEL_JOINED may never fire: look the voice channel up.
function Voice.FindChannel()
  local found = ChannelFromAPI(ActiveChannelID()) or CustomChannelID()
  if not found then return nil end
  local changed = Voice.channelID ~= found
  Voice.channelID = found
  SyncMembers()
  Activate(found)
  if changed then RefreshArrow() end
  return found
end

local function OnChannelJoined(_status, channelID)
  local api = C_VoiceChat
  if type(api) ~= "table" or type(api.GetChannel) ~= "function" then return end
  local ok, channel = pcall(api.GetChannel, channelID)
  if not ok or not MatchesChannel(channel) then return end
  Voice.channelID = channelID
  SyncMembers()
  RefreshArrow()
end

local function OnMembership(_memberID, channelID)
  if channelID ~= Voice.channelID then return end
  SyncMembers()
  RefreshArrow()
end

local function OnSpeaking(memberID, channelID, isSpeaking)
  if channelID ~= Voice.channelID then return end
  local guid = MemberGUID(memberID)
  if not guid then return end
  speaking[guid] = isSpeaking and true or nil
  RefreshArrow()
end

ns.OnEvent("VOICE_CHAT_CHANNEL_JOINED", OnChannelJoined)
ns.OnEvent("VOICE_CHAT_CHANNEL_MEMBER_ADDED", OnMembership)
ns.OnEvent("VOICE_CHAT_CHANNEL_MEMBER_GUID_UPDATED", OnMembership)
ns.OnEvent("VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED", OnSpeaking)
