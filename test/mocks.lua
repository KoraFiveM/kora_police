-- Mocks for smoke-testing qbpolice's server logic under plain lua5.4 (no
-- FiveM, no other resource's real VM). Installs the FiveM natives these
-- server files touch, plus a small controllable `exports.qbcore`/
-- `exports.qbinventory` surface backed by an in-memory `players` table --
-- qbpolice is a CONSUMER resource (everything it calls crosses a real
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
    function _G.CreateThread(fn)
        local ok, err = pcall(fn)
        if not ok then print(('CreateThread error: %s'):format(tostring(err))) end
    end
    function _G.SetTimeout(_, fn) table.insert(timeouts, fn) end
    function _G.GetGameTimer() clock = clock + 16; return clock end
    function _G.GetInvokingResource() return nil end
    function _G.GetCurrentResourceName() return 'qbpolice' end
    function _G.GetResourceState(name) return resourceStates[name] or 'missing' end
    function _G.GetHashKey(s) return s end
    function _G.CreateObject() return 1 end
    function _G.PlaceObjectOnGroundProperly() end
    function _G.NetworkGetNetworkIdFromEntity(e) return 1000 + (tonumber(e) or 0) end
    function _G.NetworkDoesNetworkIdExist() return true end
    function _G.DoesEntityExist() return true end
    function _G.DeleteEntity() end
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

    _G.QB = {
        callback = { register = function() end, trigger = function() end },
    }

    -- Controllable exports.qbcore / exports.qbinventory. Any resource name /
    -- function name not registered below resolves to a harmless no-op
    -- returning nil, same fallback convention qbcore's own test mocks use.
    local exportImpls = { qbcore = {}, qbinventory = {} }
    _G.exports = setmetatable({}, {
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

    local qbcore = exportImpls.qbcore
    function qbcore.getJob(src) local p = players[src]; return p and p.job end
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

    local qbinventory = exportImpls.qbinventory
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
        vec3 = vec3,
        addPlayer = function(src, opts)
            opts = opts or {}
            players[src] = {
                coords = opts.coords or vec3(0.0, 0.0, 0.0),
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
        clientEventsFor = function(name)
            local out = {}
            for _, e in ipairs(clientEvents) do if e.name == name then out[#out + 1] = e end end
            return out
        end,
    }
end

return M
