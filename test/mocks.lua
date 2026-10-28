-- Mocks for smoke-testing kora_police's server logic under plain lua5.4 (no
-- FiveM, no other resource's real VM). Installs the FiveM natives these
-- server files touch, plus a small controllable `exports.kora_core`/
-- `exports.kora_inventory` surface backed by an in-memory `players` table --
-- kora_police is a CONSUMER resource (everything it calls crosses a real
-- exports() boundary in production), so this mock stands in for those two
-- dependencies rather than loading their real server.lua files.

local M = {}

function M.install()
    local players = {}
    local clientEvents = {}
    local eventHandlers = {}
    local netHandlers = {}
    local timeouts = {}
    local resourceStates = {}
    local clock = 0
    local nextEntity = 0
    local entities = {}
    local minigameAuthorizations, minigameProofs = {}, {}
    local nextMinigameProof = 0

    local VEC3 = {}
    VEC3.__index = VEC3
    VEC3.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, VEC3) end
    VEC3.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
    local function vec3(x, y, z) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, VEC3) end
    _G.vector3 = vec3
    _G.vector4 = function(x, y, z, w) local v = vec3(x, y, z); v.w = w; return v end

    _G.source = nil
    function _G.RegisterNetEvent(name, cb)
        if cb then netHandlers[name] = netHandlers[name] or {}; table.insert(netHandlers[name], cb) end
    end
    function _G.AddEventHandler(name, cb)
        eventHandlers[name] = eventHandlers[name] or {}; table.insert(eventHandlers[name], cb)
    end
    function _G.TriggerEvent(name, ...)
        for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end
    function _G.TriggerClientEvent(name, target, ...)
        table.insert(clientEvents, { name = name, target = target, args = { ... } })
    end
    -- Run through a first cooperative wait, matching FiveM closely enough for
    -- perpetual sweep workers without executing their infinite loop in a
    -- plain-Lua test process.
    function _G.Wait() coroutine.yield() end
    function _G.CreateThread(fn)
        local thread = coroutine.create(fn)
        local ok, err = coroutine.resume(thread)
        if not ok then print(('CreateThread error: %s'):format(tostring(err))) end
    end
    function _G.SetTimeout(_, fn) table.insert(timeouts, fn) end
    function _G.GetGameTimer() clock = clock + 16; return clock end
    function _G.GetInvokingResource() return nil end
    function _G.GetCurrentResourceName() return 'kora_police' end
    function _G.GetResourceState(name) return resourceStates[name] or 'missing' end
    function _G.GetHashKey(s) return s end
    function _G.joaat(s) return s end
    function _G.CreateObject()
        nextEntity = nextEntity + 1
        entities[nextEntity] = true
        return nextEntity
    end
    function _G.PlaceObjectOnGroundProperly() end
    function _G.NetworkGetNetworkIdFromEntity(e) return 1000 + (tonumber(e) or 0) end
    function _G.NetworkDoesNetworkIdExist() return true end
    function _G.DoesEntityExist(entity) return entities[entity] == true or players[entity] ~= nil end
    function _G.DeleteEntity(entity) entities[entity] = nil end
    _G.os = os
    _G.math = math

    function _G.GetPlayerPed(src)
        return players[src] and src or 0
    end
    function _G.GetEntityCoords(ped)
        local p = players[ped]
        return p and p.coords or vec3(0.0, 0.0, 0.0)
    end
    function _G.GetPlayerRoutingBucket(_) return 0 end
    function _G.GetEntityRoutingBucket(_) return 0 end
    function _G.GetAllVehicles() return {} end
    function _G.GetVehicleNumberPlateText(_) return '' end

    local notifications = {}
    -- Every blip client code asks kora_lib for, in creation order. Recorded rather
    -- than discarded so a restart test can assert a station blip is created
    -- once per registration pass and not duplicated on the next one.
    local blips = {}
    _G.QB = {
        util = {
            isFiniteNumber = function(value)
                return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
            end,
        },
        blips = {
            create = function(coords, options)
                blips[#blips + 1] = { coords = coords, options = options }
                return #blips
            end,
            remove = function() return true end,
            setInfo = function() return true end,
        },
        callback = {
            registry = {},
            register = function(name, handler) QB.callback.registry[name] = handler end,
            trigger = function() end,
        },
        events = {
            registry = {},
            register = function(name, handler) QB.events.registry[name] = handler end,
            trigger = function() end,
        },
        minigames = {
            authorizeProof = function(src, gameType, opts)
                nextMinigameProof = nextMinigameProof + 1
                local token = ('authorization:%d'):format(nextMinigameProof)
                minigameAuthorizations[token] = { src = src, gameType = gameType, opts = opts }
                return token
            end,
            consumeProof = function(src, token, gameType, authorization)
                local proof = minigameProofs[token]
                if not proof then return false end
                if proof.src ~= src or proof.gameType ~= gameType or proof.authorization ~= authorization then return false end
                minigameProofs[token] = nil
                return true
            end,
        },
        notify = { send = function(src, payload)
            notifications[#notifications + 1] = { src = src, payload = payload }
        end },
        commands = {
            registry = {},
            add = function(name, _, _, _, handler) QB.commands.registry[name] = handler end,
            remove = function(name) QB.commands.registry[name] = nil end,
        },
        keybind = { add = function() end },
        timers = {
            setInterval = function() return 1 end,
            clearInterval = function() return true end,
            -- Shaped like the real handles, NOT a bare function. kora_lib returns a
            -- table whose __call metamethod does not survive the export
            -- boundary, so consumers must use `.run(...)`; a mock that hands
            -- back a plain function makes `handle()` look fine here and crash in
            -- game with "attempt to call a table value". Deliberately NOT
            -- callable, so a call site that forgets `.run` fails in the tests.
            throttle = function(fn)
                return {
                    run = function(...) fn(...); return true end,
                    reset = function() end,
                    remaining = function() return 0 end,
                }
            end,
            debounce = function(fn)
                return {
                    run = function(...) fn(...) end,
                    cancel = function() return false end,
                    isPending = function() return false end,
                }
            end,
        },
    }

    -- Controllable exports.kora_core / exports.kora_inventory. Any resource name /
    -- function name not registered below resolves to a harmless no-op
    -- returning nil, same fallback convention kora_core's own test mocks use.
    local exportImpls = { kora_core = {}, kora_inventory = {} }
    _G.exports = setmetatable({}, {
        -- FiveM exposes the `exports` registrar as a callable table in a
        -- resource entry file. Evidence now publishes its ballistics API, so
        -- preserve that real shape while this mock still serves named exports.
        __call = function() end,
        __index = function(_, resourceName)
            return setmetatable({}, {
                __index = function(_, fnName)
                    return function(_, ...)
                        local impl = exportImpls[resourceName] and exportImpls[resourceName][fnName]
                        if impl then return impl(...) end
                        return nil
                    end
                end,
            })
        end,
    })

    local qbcore = exportImpls.kora_core

    -- Job types mirror kora_core/shared/jobs.lua. Dispatch alerts target the TYPE,
    -- so 'police' and a hypothetical 'sheriff' both answer to 'leo'.
    local JOB_TYPES = { police = 'leo', sheriff = 'leo', ambulance = 'ems', tow = 'recovery' }

    -- `type` is present on the returned job because real kora_core puts it on
    -- PlayerData.job (CoreInternal.player.buildJob copies it from the registry).
    -- A mock that omitted it would let a job.type check pass here and fail in
    -- game -- the exact mock-drift trap this codebase has been bitten by before.
    function qbcore.getJob(src)
        local p = players[src]
        if not p or not p.job then return nil end
        if p.job.type == nil then p.job.type = JOB_TYPES[p.job.name] or 'none' end
        return p.job
    end
    function qbcore.getPlayerData(src, path)
        local p = players[src]
        if not p then return nil end
        if not path then return p.data end
        local v = p.data
        for _, key in ipairs(path) do
            if type(v) ~= 'table' then return nil end
            v = v[key]
        end
        return v
    end
    function qbcore.getMetaData(src, key)
        local p = players[src]
        if not p then return nil end
        if key == nil then return p.data.metadata end
        return p.data.metadata[key]
    end
    function qbcore.setMetaData(src, key, value)
        local p = players[src]; if not p then return false, 'no such player' end
        p.data.metadata[key] = value
        return true
    end
    function qbcore.setJobDuty(src, onDuty)
        local p = players[src]; if not p then return false, 'no such player' end
        p.job.onduty = onDuty == true
        return true
    end
    function qbcore.incrementMetaData(src, key, delta, min, max)
        local p = players[src]; if not p then return nil, 'no such player' end
        local v = (tonumber(p.data.metadata[key]) or 0) + (tonumber(delta) or 0)
        if min and v < min then v = min end
        if max and v > max then v = max end
        p.data.metadata[key] = v
        return v
    end
    function qbcore.getMoney(src, account)
        local p = players[src]; return p and p.data.money[account]
    end
    function qbcore.addMoney(src, account, amount)
        local p = players[src]; if not p then return false, 'no such player' end
        p.data.money[account] = (p.data.money[account] or 0) + amount
        return true
    end
    function qbcore.removeMoney(src, account, amount)
        local p = players[src]; if not p then return false, 'no such player' end
        local current = p.data.money[account] or 0
        if amount > current then return false, 'insufficient funds' end
        p.data.money[account] = current - amount
        return true
    end
    function qbcore.transferMoney(fromSrc, toSrc, account, amount)
        local removed, err = qbcore.removeMoney(fromSrc, account, amount)
        if not removed then return false, err end
        local added, addErr = qbcore.addMoney(toSrc, account, amount)
        if not added then qbcore.addMoney(fromSrc, account, amount); return false, addErr end
        return true
    end
    function qbcore.getPlayers()
        local out = {}
        for src in pairs(players) do out[#out + 1] = src end
        table.sort(out)
        return out
    end
    function qbcore.getPlayersByJob(name, onDutyOnly)
        local out = {}
        for src, p in pairs(players) do
            if p.job and p.job.name == name and (not onDutyOnly or p.job.onduty) then out[#out + 1] = src end
        end
        table.sort(out)
        return out
    end
    function qbcore.getDutyCount(name)
        return #qbcore.getPlayersByJob(name, true)
    end
    function qbcore.getPlayersByJobType(jobType, onDutyOnly)
        local out = {}
        for src, p in pairs(players) do
            if p.job and JOB_TYPES[p.job.name] == jobType and (not onDutyOnly or p.job.onduty) then
                out[#out + 1] = src
            end
        end
        table.sort(out)
        return out
    end
    function qbcore.getDutyCountByType(jobType)
        return #qbcore.getPlayersByJobType(jobType, true)
    end
    function qbcore.getOnDutyRoster(filter)
        filter = filter or {}
        local out = {}
        for src, p in pairs(players) do
            local jobType = p.job and JOB_TYPES[p.job.name] or 'none'
            local ok = p.job and p.job.onduty
                and (not filter.job or filter.job == p.job.name)
                and (not filter.jobType or filter.jobType == jobType)
            if ok then
                out[#out + 1] = { src = src, citizenid = ('CID%d'):format(src), name = p.name or ('Unit %d'):format(src),
                                  callsign = p.callsign, job = p.job.name, jobType = jobType,
                                  grade = 1, gradeLabel = 'Grade', onDuty = true }
            end
        end
        table.sort(out, function(a, b) return a.src < b.src end)
        return out
    end
    function qbcore.jailPlayer(src, minutes, reason)
        if not players[src] then return false, 'no such player' end
        minutes = tonumber(minutes)
        if not minutes or minutes <= 0 then return false, 'minutes must be positive' end
        players[src].jailed = { minutes = minutes, reason = reason }
        return true
    end
    function qbcore.createUseable() end
    function qbcore.registerShared() end
    function qbcore.alert(payload)
        assert(type(payload) == 'table' and type(payload.jobs) == 'table' and #payload.jobs > 0,
            'alert requires payload.jobs as a non-empty array')
        local recipients = {}
        for _, jobName in ipairs(payload.jobs) do
            for _, src in ipairs(qbcore.getPlayersByJob(jobName, true)) do recipients[src] = true end
        end
        local count = 0
        for src in pairs(recipients) do
            TriggerClientEvent('qbcore:client:dispatchAlert', src, payload)
            count = count + 1
        end
        return count
    end
    function qbcore.getByPlate() return nil end
    function qbcore.getByOwner() return {} end
    function qbcore.impound() return true end
    function qbcore.retrieveImpound() return true end
    function qbcore.createVehicle() return true end
    function qbcore.storeVehicle() return true end
    function qbcore.spawnVehicle() return 1 end

    -- kora_dispatch owns the call lifecycle now; kora_police only raises calls through
    -- it. Recorded rather than simulated: what these tests care about is the
    -- payload kora_police builds, not kora_dispatch's own storage (which has its own
    -- suite).
    local dispatchCalls = {}
    local playerAlertDefinitions = {}
    exportImpls.kora_dispatch = {}
    local qbdispatch = exportImpls.kora_dispatch
    function qbdispatch.createCall(payload)
        dispatchCalls[#dispatchCalls + 1] = payload
        local recipients = {}
        for _, jobName in ipairs(payload.jobs or {}) do
            for _, src in ipairs(qbcore.getPlayersByJob(jobName, true)) do recipients[src] = true end
        end
        for _, jobType in ipairs(payload.jobTypes or {}) do
            for _, src in ipairs(qbcore.getPlayersByJobType(jobType, true)) do recipients[src] = true end
        end
        local count = 0
        for _ in pairs(recipients) do count = count + 1 end
        return #dispatchCalls, count
    end
    function qbdispatch.registerPlayerAlert(key, definition)
        playerAlertDefinitions[key] = definition
        return true
    end
    function qbdispatch.createPlayerCall(src, key)
        local definition = playerAlertDefinitions[key]
        if not definition then return false, 'unknown player alert type' end

        local payload = {}
        for field, value in pairs(definition) do payload[field] = value end
        payload.coords = players[src] and players[src].coords or nil
        payload.data = { incident = key, reporter = src }
        return qbdispatch.createCall(payload)
    end
    function qbdispatch.setTheme() return true end

    local qbinventory = exportImpls.kora_inventory
    function qbinventory.registerInspectionAccess() return 1 end
    function qbinventory.RegisterStash() return 'stash:mock' end
    function qbinventory.RegisterShop() return 'shop:mock' end

    return {
        players = players,
        clientEvents = clientEvents,
        eventHandlers = eventHandlers,
        netHandlers = netHandlers,
        exportImpls = exportImpls,
        resourceStates = resourceStates,
        QB = QB,
        vec3 = vec3,
        dispatchCalls = dispatchCalls,
        playerAlertDefinitions = playerAlertDefinitions,
        lastDispatchCall = function() return dispatchCalls[#dispatchCalls] end,
        blips = blips,
        addPlayer = function(src, opts)
            opts = opts or {}
            players[src] = {
                coords = opts.coords or vec3(0.0, 0.0, 0.0),
                name = opts.name,
                callsign = opts.callsign,
                job = opts.job or { name = 'unemployed', onduty = false, grade = { level = 1 } },
                data = {
                    citizenid = opts.citizenid or ('CID%d'):format(src),
                    metadata = opts.metadata or {},
                    money = opts.money or { cash = 500, bank = 5000 },
                },
            }
        end,
        setCoords = function(src, x, y, z)
            if players[src] then players[src].coords = vec3(x, y, z) end
        end,
        fireEvent = function(name, src, ...)
            local previous = _G.source
            _G.source = src
            _G.TriggerEvent(name, ...)
            _G.source = previous
        end,
        lastClient = function(name)
            for i = #clientEvents, 1, -1 do if clientEvents[i].name == name then return clientEvents[i] end end
        end,
        notifications = notifications,
        lastNotification = function() return notifications[#notifications] end,
        advanceClock = function(ms) clock = clock + ms end,
        issueMinigameProof = function(src, gameType, authorization)
            nextMinigameProof = nextMinigameProof + 1
            local token = ('proof:%d'):format(nextMinigameProof)
            minigameProofs[token] = { src = src, gameType = gameType, authorization = authorization }
            return token
        end,
        clientEventsFor = function(name)
            local out = {}
            for _, e in ipairs(clientEvents) do if e.name == name then out[#out + 1] = e end end
            return out
        end,
    }
end

return M
