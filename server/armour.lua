-- Body armour items. The police armory hands out `armor`; `armour` is an alias so
-- stock already in inventories keeps working, and `heavyarmor` (the stock "Cops
-- Tools" heavy vest) is handled here too. Using one runs a cancellable progress
-- bar on the client, then the server re-validates, takes 1 item and tells the
-- client to apply the configured armour (SetPedArmour is client-only).

local cfg = Config.armour
if not cfg or cfg.enabled == false then return end

local PROGRESS_TOLERANCE = 250 -- ms of timer granularity when checking the reported duration
local using = {}               -- players with a use in flight, so uses cannot stack

local function targetArmour(current, amount, mode)
    if mode == "add" then return math.min(100, current + amount) end
    return math.min(100, amount)
end

local function useArmour(src, name, entry, item)
    if using[src] then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local amount = math.min(100, math.max(0, tonumber(entry.amount) or 0))
    local mode = entry.mode or cfg.mode
    local current = GetPedArmour(ped)
    if cfg.blockIfFull and current >= targetArmour(current, amount, mode) then
        Police.notify(src, cfg.fullMessage, "inform")
        return false
    end

    local progress = {
        label = entry.label or cfg.progress.label,
        duration = tonumber(entry.duration) or cfg.progress.duration,
        canCancel = cfg.progress.canCancel ~= false,
        anim = entry.anim or cfg.progress.anim,
    }

    using[src] = true
    local startedAt = GetGameTimer()
    local ok, finished = pcall(Kora.callback.trigger, src, "kora_police:armour:progress", progress)
    using[src] = nil
    if not ok or not finished then return false end
    -- The client reports its own result; a real use cannot finish before the duration.
    if GetGameTimer() - startedAt < progress.duration - PROGRESS_TOLERANCE then
        print(("[kora_police] %s used %s faster than its %sms duration; ignored"):format(src, name, progress.duration))
        return false
    end

    ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    current = GetPedArmour(ped)
    local slot = tonumber(item and item.slot)
    local removed = exports.kora_core:removeItem(src, name, 1, slot, "armour-use")
    if not removed then return false end

    TriggerClientEvent("kora_police:client:setArmour", src, targetArmour(current, amount, mode))
    return true
end

local function registerUseables()
    for name, entry in pairs(cfg.items) do
        exports.kora_core:createUseable(name, function(src, item)
            return useArmour(src, name, entry, item)
        end)
    end
end

registerUseables()

-- kora_inventory drops handlers registered before it (re)starts; register again.
AddEventHandler("onResourceStart", function(resource)
    if resource == "kora_inventory" then registerUseables() end
end)
