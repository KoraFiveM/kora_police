-- Handcuffs on the wrists of every cuffed player this client can see
-- (Config.cuff.prop), the local player included.
--
-- Every client creates its own copy from the replicated `koraCuffed` player bag
-- instead of the suspect spawning one networked object: a client-created
-- networked object is refused under sv_entityLockdown, and a local copy cannot
-- be left behind by a crash or a disconnect. kora_lib's Kora.anim.attachProp
-- owns the objects, so a stop of this resource deletes them as well.
--
-- client/cuff.lua drives the local player (from Police.cuffed) and passes on the
-- bag changes of everyone else.

Police.cuffProps = Police.cuffProps or {}
local CuffProps = Police.cuffProps

local cuffed = {}  -- serverId -> true while that player is cuffed
local props = {}   -- serverId -> { prop = entity, ped = ped }
local loading = {} -- serverId -> true while the cuffs model streams in
local heard = {}   -- serverId -> true once a bag change or the server said anything about them
local watching = false

---@return table|nil
local function settings()
    local cfg = Config.cuff.prop
    if type(cfg) ~= 'table' or cfg.enabled == false or type(cfg.model) ~= 'string' or cfg.model == '' then return nil end
    return cfg
end

local function ownServerId()
    return GetPlayerServerId(Kora.cache.playerId())
end

local function removeProp(serverId)
    local entry = props[serverId]
    if not entry then return end
    props[serverId] = nil
    pcall(Kora.anim.detachProp, entry.prop)
end

---The ped of `serverId` while it is in scope on this client, else nil.
local function pedOf(serverId, own)
    local ped
    if serverId == own then
        ped = Kora.cache.ped()
    else
        local player = GetPlayerFromServerId(serverId)
        if not player or player == -1 then return nil end
        ped = GetPlayerPed(player)
    end
    if type(ped) ~= 'number' or ped == 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

---Whether `serverId` is still cuffed: the local player's own state, or the bag
---of anyone else (read outside a change handler, so it is current).
local function holdsCuff(serverId, own)
    if serverId == own then return Police.cuffed == true end
    local player = Player(serverId)
    return player ~= nil and player.state ~= nil and player.state.koraCuffed == true
end

---Puts the cuffs on the ped of a cuffed player in scope, takes them off a ped
---that is gone (left scope, respawned, changed model). Yields while the model
---streams in. The prop is cosmetic: an error here never reaches the cuff state.
local function ensureProp(serverId)
    local cfg = settings()
    local own = ownServerId()
    local ped = cfg and cuffed[serverId] and pedOf(serverId, own)
    if not ped then return removeProp(serverId) end
    local entry = props[serverId]
    if entry then
        if entry.ped == ped and DoesEntityExist(entry.prop) and IsEntityAttachedToEntity(entry.prop, ped) then return end
        removeProp(serverId)
    end
    if loading[serverId] then return end
    loading[serverId] = true
    local ok, prop = pcall(Kora.anim.attachProp, ped, cfg.model, cfg.bone or 'SKEL_L_Hand', cfg.offset, cfg.rotation)
    loading[serverId] = nil
    if not ok or not prop then return end
    -- Uncuffed, or given a new ped, while the model streamed in.
    if not cuffed[serverId] or props[serverId] or pedOf(serverId, own) ~= ped then
        pcall(Kora.anim.detachProp, prop)
        return
    end
    props[serverId] = { prop = prop, ped = ped }
end

-- Players come into and out of scope and get new peds without any event this
-- resource sees, so while anyone is cuffed their props are checked every
-- Config.cuff.prop.checkInterval ms (never below 250). No cuffed player, no loop.
local function startWatch()
    if watching then return end
    watching = true
    CreateThread(function()
        while next(cuffed) do
            local cfg = settings()
            Wait(math.max(250, tonumber(cfg and cfg.checkInterval) or 1000))
            local own = ownServerId()
            local ids = {}
            for serverId in pairs(cuffed) do ids[#ids + 1] = serverId end
            for _, serverId in ipairs(ids) do
                if cuffed[serverId] then
                    -- In scope with a bag that no longer says cuffed: an uncuff this client missed.
                    if pedOf(serverId, own) and not holdsCuff(serverId, own) then
                        CuffProps.set(serverId, false)
                    else
                        ensureProp(serverId)
                    end
                end
            end
        end
        watching = false
    end)
end

---Shows or removes the handcuffs on a player.
---@param serverId integer
---@param isCuffed boolean
function CuffProps.set(serverId, isCuffed)
    serverId = tonumber(serverId)
    if not serverId then return end
    heard[serverId] = true
    if not isCuffed or not settings() then
        cuffed[serverId] = nil
        return removeProp(serverId)
    end
    cuffed[serverId] = true
    CreateThread(function() ensureProp(serverId) end)
    startWatch()
end

---@param serverId integer
---@return integer|nil prop
function CuffProps.get(serverId)
    local entry = props[tonumber(serverId)]
    return entry and entry.prop or nil
end

function CuffProps.clearAll()
    for serverId in pairs(props) do removeProp(serverId) end
    cuffed = {}
end

-- Someone left this client's scope: their cuffs go with them now, not at the
-- next check, and come back with the watch when they return.
AddEventHandler('onPlayerDropped', function(serverId)
    removeProp(tonumber(serverId))
end)

-- A cuffed player disconnected without the logout that clears their bag.
RegisterNetEvent('kora_police:client:cuffedPlayerGone', function(serverId)
    CuffProps.set(serverId, false)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then CuffProps.clearAll() end
end)

-- Players who were already cuffed when this client loaded: their bags hold the
-- value, so no change handler fires for them.
CreateThread(function()
    local ok, list = pcall(function() return Kora.callback.trigger('kora_police:server:cuffedPlayers') end)
    if not ok or type(list) ~= 'table' then return end
    local own = ownServerId()
    for _, serverId in ipairs(list) do
        serverId = tonumber(serverId)
        -- A bag change that already arrived is newer than this list.
        if serverId and serverId ~= own and not heard[serverId] then CuffProps.set(serverId, true) end
    end
end)
