-- ProxiVox: proximity voice chat for WoW Forever 1.60.1.
-- Core owns the namespace, the saved settings, the player sensors, the event
-- frame, the update driver and the /pvx command.
local addonName, ns = ...

local DB_NAME = "ProxiVoxDB"
local REFRESH_INTERVAL = 0.5
local CHAT_PREFIX = "[ProxiVox] "

-- Both addons drive the same voice member volumes: running them together makes
-- the two of them fight over every member.
local CONFLICTS = { "ForeverVoice", "ProxVoiceParty" }

local CONTEXT_LABELS = {
  world = "monde",
  dungeon = "donjon",
  raid = "raid",
  pvp = "JcJ",
}

-- consent and setupDone are deliberately absent: a fresh install must start
-- with both nil so the setup wizard runs, and the database merge must not
-- invent an agreement the user never gave.
local defaults = {
  enabled = true,
  maxRange = 400,
  fullRange = 10,
  behindFactor = 0.6,
  alert = true,
  autoActivate = true,
  debug = false,
  minimap = {
    angle = 225,
    show = true,
  },
  contexts = {
    world = true,
    dungeon = true,
    raid = true,
    pvp = true,
  },
}
ns.defaults = defaults

-- Every event the addon listens to: the frame registers this list once, while
-- the modules only map their handler onto an event name.
local EVENTS = {
  "ADDON_LOADED",
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "GROUP_ROSTER_UPDATE",
  "CHAT_MSG_ADDON",
  "VOICE_CHAT_CHANNEL_JOINED",
  "VOICE_CHAT_CHANNEL_MEMBER_ADDED",
  "VOICE_CHAT_CHANNEL_MEMBER_GUID_UPDATED",
  "VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED",
}

local handlers = {}
local refreshAccumulator = 0

function ns.Print(message)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(message))
  end
end

function ns.OnEvent(event, handler)
  handlers[event] = handler
end

-- Nothing leaves the client before the user accepted the setup wizard: joining,
-- sending positions and driving volumes all go through this.
function ns.IsAllowed()
  local db = ns.db
  return db ~= nil and db.consent == true and db.enabled == true
end

-- Join the meeting channel, look up its voice channel and apply the volumes.
function ns.Start()
  if not ns.IsAllowed() then return end
  ns.Comm.JoinChannel()
  ns.Voice.FindChannel()
  ns.Voice.Apply()
end

-- Some 1.60 values can be "secret": reading them is allowed but any comparison
-- or formatting throws, so every numeric API result goes through this guard.
function ns.IsSecret(value)
  return issecretvalue ~= nil and issecretvalue(value) and true or false
end

function ns.PlayerGUID()
  if type(UnitGUID) ~= "function" then return nil end
  local ok, guid = pcall(UnitGUID, "player")
  if not ok or type(guid) ~= "string" or guid == "" then return nil end
  return guid
end

-- World position in yards: nil when the client hides it (instances, secret).
function ns.PlayerPosition()
  if type(UnitPosition) ~= "function" then return nil end
  local ok, x, y, z, instanceID = pcall(UnitPosition, "player")
  if not ok or ns.IsSecret(x) or ns.IsSecret(y) then return nil end
  return x, y, instanceID
end

-- Radians, 0 = north, growing counter-clockwise towards west.
function ns.PlayerFacing()
  if type(GetPlayerFacing) ~= "function" then return nil end
  local ok, facing = pcall(GetPlayerFacing)
  if not ok or ns.IsSecret(facing) then return nil end
  return facing
end

function ns.PlayerDead()
  if type(UnitIsDeadOrGhost) ~= "function" then return false end
  local ok, dead = pcall(UnitIsDeadOrGhost, "player")
  return ok and dead and true or false
end

function ns.InstanceInfo()
  if type(IsInInstance) ~= "function" then return false, "none" end
  local ok, inInstance, instanceType = pcall(IsInInstance)
  if not ok then return false, "none" end
  return inInstance and true or false, instanceType or "none"
end

function ns.ContextKey()
  local inInstance, instanceType = ns.InstanceInfo()
  if not inInstance or instanceType == "none" then return "world" end
  if instanceType == "raid" then return "raid" end
  if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
  return "dungeon"
end

function ns.GroupGuids()
  local guids = {}
  if type(UnitGUID) ~= "function" then return guids end
  for i = 1, 40 do
    local guid = UnitGUID("raid" .. i)
    if guid then guids[guid] = true end
  end
  for i = 1, 4 do
    local guid = UnitGUID("party" .. i)
    if guid then guids[guid] = true end
  end
  return guids
end

local function MergeDefaults(target, source)
  for key, value in pairs(source) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then target[key] = {} end
      MergeDefaults(target[key], value)
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

local function EnsureDB()
  if type(_G[DB_NAME]) ~= "table" then
    _G[DB_NAME] = {}
  end
  MergeDefaults(_G[DB_NAME], defaults)
  ns.db = _G[DB_NAME]
end

local function WarnConflicts()
  local api = C_AddOns
  if type(api) ~= "table" or type(api.IsAddOnLoaded) ~= "function" then return end
  for _, name in ipairs(CONFLICTS) do
    local ok, loaded = pcall(api.IsAddOnLoaded, name)
    if ok and loaded then
      ns.Print(string.format("%s est chargé et pilote aussi les volumes vocaux : ProxiVox ne peut pas cohabiter avec lui.", name))
    end
  end
end

local function ToggleContext(key, rest)
  local value = string.lower(rest or "")
  if value ~= "on" and value ~= "off" then
    ns.Print(string.format("Usage : /pvx %s on|off", key))
    return
  end
  local enabled = value == "on"
  ns.db.contexts[key] = enabled
  ns.Print(string.format("Contexte %s %s.", CONTEXT_LABELS[key] or key, enabled and "activé" or "désactivé"))
  ns.Voice.Apply()
  ns.Arrow.Refresh()
end

local function PrintStatus()
  local channelIndex = ns.Comm.ChannelIndex()
  if channelIndex then
    ns.Print(string.format("Canal %s : rejoint (index %d).", ns.Comm.CHANNEL_NAME, channelIndex))
  else
    ns.Print(string.format("Canal %s : non rejoint.", ns.Comm.CHANNEL_NAME))
  end
  if ns.Voice.channelID then
    ns.Print(string.format("Canal vocal : %s.", tostring(ns.Voice.channelID)))
  else
    ns.Print("Canal vocal : aucun (vocal inactif ou canal non rejoint).")
  end
  ns.Print(string.format(
    "Addon %s, contexte %s %s, portée %.0f m, plein régime %.0f m, atténuation arrière %.2f, alerte %s.",
    ns.db.enabled and "activé" or "désactivé",
    CONTEXT_LABELS[ns.ContextKey()] or ns.ContextKey(),
    ns.Voice.IsActive() and "actif" or "inactif",
    ns.db.maxRange, ns.db.fullRange, ns.db.behindFactor,
    ns.db.alert and "activée" or "désactivée"))
  if ns.db.consent == true then
    ns.Print("Accord : donné.")
  elseif ns.db.setupDone == true then
    ns.Print("Accord : refusé (lance /pvx setup pour le modifier).")
  else
    ns.Print("Accord : pas encore donné (lance /pvx setup).")
  end
  if ns.Comm.IsRestricted() then
    ns.Print("Les messages addon sortants sont restreints : aucune position n'est envoyée.")
  end
  local found = false
  for guid in pairs(ns.Comm.peers) do
    found = true
    local name = ns.Comm.PeerName(guid) or guid
    local volume = ns.Voice.VolumeFor(guid) or 0
    local distance = ns.Voice.Measure(guid)
    if distance then
      ns.Print(string.format("%s : %.1f m, volume %.2f", name, distance, volume))
    else
      ns.Print(string.format("%s : position inconnue, volume %.2f", name, volume))
    end
  end
  if not found then
    ns.Print("Aucun pair pour le moment.")
  end
end

local function PrintDebug()
  local x, y, instanceID = ns.PlayerPosition()
  local facing = ns.PlayerFacing() or 0
  ns.Print(string.format("Pilote : x=%s y=%s instance=%s facing=%.0f° (%s).",
    x and string.format("%.1f", x) or "inconnu",
    y and string.format("%.1f", y) or "inconnu",
    tostring(instanceID or "inconnu"),
    math.deg(facing),
    CONTEXT_LABELS[ns.ContextKey()] or ns.ContextKey()))
  for guid in pairs(ns.Comm.peers) do
    local distance, relative = ns.Voice.Measure(guid)
    if distance then
      ns.Print(string.format("%s : %.1f m, angle relatif %.0f°", ns.Comm.PeerName(guid) or guid, distance, math.deg(relative)))
    else
      ns.Print(string.format("%s : position inconnue", ns.Comm.PeerName(guid) or guid))
    end
  end
end

local commands = {}

-- Shared by /pvx on|off, the minimap button and the addon compartment.
function ns.SetEnabled(enabled)
  if enabled and ns.db.consent ~= true then
    ns.Print("ProxiVox a besoin de votre accord : la configuration s'ouvre.")
    ns.Setup.Open()
    return
  end
  ns.db.enabled = enabled and true or false
  if enabled then
    ns.Print("Addon activé.")
    ns.Start()
  else
    ns.Print("Addon désactivé, volumes vocaux rendus à la normale.")
    ns.Voice.Apply()
  end
  ns.Arrow.Refresh()
end

commands.on = function() ns.SetEnabled(true) end
commands.off = function() ns.SetEnabled(false) end

commands.minimap = function(rest)
  local value = string.lower(rest or "")
  if value == "on" or value == "off" then
    ns.MinimapButton.SetShown(value == "on")
  elseif value == "reset" then
    ns.MinimapButton.Reset()
  else
    ns.Print("Usage : /pvx minimap on|off|reset")
  end
end

commands.range = function(rest)
  local meters = tonumber(rest)
  if not meters or meters <= 0 then
    ns.Print("Usage : /pvx range <mètres>")
    return
  end
  ns.db.maxRange = meters
  if ns.db.fullRange > meters then
    ns.db.fullRange = meters
  end
  ns.Print(string.format("Portée maximale : %.0f m.", meters))
  ns.Voice.Apply()
end

commands.full = function(rest)
  local meters = tonumber(rest)
  if not meters or meters < 0 or meters > ns.db.maxRange then
    ns.Print(string.format("Usage : /pvx full <mètres> (0 à %.0f)", ns.db.maxRange))
    return
  end
  ns.db.fullRange = meters
  ns.Print(string.format("Plein régime jusqu'à %.0f m.", meters))
  ns.Voice.Apply()
end

commands.behind = function(rest)
  local factor = tonumber(rest)
  if not factor or factor < 0 or factor > 1 then
    ns.Print("Usage : /pvx behind <0 à 1>")
    return
  end
  ns.db.behindFactor = factor
  ns.Print(string.format("Atténuation arrière : %.2f.", factor))
  ns.Voice.Apply()
end

commands.alert = function(rest)
  local value = string.lower(rest or "")
  if value ~= "on" and value ~= "off" then
    ns.Print("Usage : /pvx alert on|off")
    return
  end
  ns.db.alert = value == "on"
  ns.Print(string.format("Alerte de portée %s.", ns.db.alert and "activée" or "désactivée"))
end

commands.world = function(rest) ToggleContext("world", rest) end
commands.dungeon = function(rest) ToggleContext("dungeon", rest) end
commands.raid = function(rest) ToggleContext("raid", rest) end
commands.pvp = function(rest) ToggleContext("pvp", rest) end

commands.status = function() PrintStatus() end
commands.debug = function() PrintDebug() end
commands.setup = function() ns.Setup.Open() end

local function ShowHelp()
  ns.Print("Commandes : setup, status, on, off, range <m>, full <m>, behind <0-1>, world|dungeon|raid|pvp on|off, alert on|off, minimap on|off|reset, debug.")
end

ns.OnEvent("ADDON_LOADED", function(name)
  if name == addonName then
    EnsureDB()
  end
end)

ns.OnEvent("PLAYER_LOGIN", function()
  WarnConflicts()
  ns.MinimapButton.Create()
  ns.Comm.Register()
  if ns.db.setupDone ~= true then
    ns.Setup.Open()
    return
  end
  ns.Start()
end)

ns.OnEvent("PLAYER_ENTERING_WORLD", function()
  if ns.IsAllowed() then
    ns.Voice.FindChannel()
    ns.Voice.Apply()
    ns.Arrow.Refresh()
  end
end)

ns.OnEvent("GROUP_ROSTER_UPDATE", function()
  ns.Voice.Apply()
end)

local function Drive(_, elapsed)
  refreshAccumulator = refreshAccumulator + elapsed
  if refreshAccumulator < REFRESH_INTERVAL then return end
  refreshAccumulator = 0
  if not ns.db then return end
  ns.Comm.Tick()
  ns.Voice.Apply()
  ns.Arrow.Refresh()
end

if type(CreateFrame) == "function" then
  local frame = CreateFrame("Frame", addonName .. "EventFrame")
  if frame then
    for _, event in ipairs(EVENTS) do
      frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
      local handler = handlers[event]
      if handler then handler(...) end
    end)
    frame:SetScript("OnUpdate", Drive)
  end
end

if SlashCmdList then
  SLASH_PROXIVOX1 = "/pvx"
  SlashCmdList["PROXIVOX"] = function(input)
    if not ns.db then
      ns.Print("Réglages pas encore chargés, réessaie dans un instant.")
      return
    end
    local command, rest = string.match(input or "", "^(%S*)%s*(.-)%s*$")
    command = string.lower(command or "")
    local handler = commands[command]
    if not handler then
      ShowHelp()
      return
    end
    handler(rest)
  end
end
