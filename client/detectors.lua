-- Automatic crime detection.
--
-- These live in qbpolice, not in qbdispatch: dispatch has no idea what a crime
-- is, and should not. It transports and presents calls; deciding that a gunshot
-- in a public street is a police matter is police-resource business. The same
-- rule puts a bank robbery's alert inside the robbery script.
--
-- Every detector is THROTTLED, not debounced. A throttle fires immediately and
-- drops the rest of the window; a debounce would wait for the shooting to stop
-- before reporting it, which is precisely backwards for an emergency.

local function alert(payload)
    payload.coords = QB.cache.coords()
    TriggerServerEvent('qbpolice:server:crimeDetected', payload)
end

---Street name for the current position, so the call reads "Vespucci Boulevard"
---rather than a pair of coordinates. Real qb-policejob did this; the rewrite
---lost it.
---@return string|nil
local function street()
    local first, second = QB.world.getStreetNames()
    if not first then return nil end
    return second and second ~= '' and ('%s / %s'):format(first, second) or first
end

---@return table|nil
local function vehicleDetails(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    return {
        vehicle = QB.vehicle.label(vehicle) or nil,
        plate = QB.vehicle.plate(vehicle) or nil,
    }
end

---QB.lookup resolves a weapon hash to its record; a hash the catalog doesn't
---know returns nil rather than erroring, so an unknown weapon simply omits the
---field instead of blocking the alert.
---@param hash integer
---@return string|nil
local function weaponLabel(hash)
    local record = QB.lookup.weapon(hash)
    return record and (record.label or record.name) or nil
end

local reportShots = QB.timers.throttle(function(silenced, weapon)
    local details = vehicleDetails(QB.cache.vehicle()) or {}
    local at = street()

    alert({
        code = '10-31',
        title = silenced and 'Suppressed Gunfire' or 'Shots Fired',
        message = ('Gunfire reported%s.'):format(at and (' near ' .. at) or ''),
        -- A suppressed weapon is quieter, not silent: fewer witnesses would
        -- place it precisely, so it is reported at a lower priority rather than
        -- not reported at all.
        priority = silenced and 2 or 1,
        icon = 'crosshair',
        data = {
            street = at,
            weapon = weaponLabel(weapon),
            vehicle = details.vehicle,
            plate = details.plate,
        },
    })
end, Config.dispatch.shotsFiredCooldown)

local reportTheft = QB.timers.throttle(function(vehicle)
    local details = vehicleDetails(vehicle) or {}

    alert({
        code = '10-16',
        title = 'Vehicle Theft',
        message = ('A vehicle is being stolen%s.'):format(street() and (' near ' .. street()) or ''),
        priority = 2,
        icon = 'car',
        data = { street = street(), vehicle = details.vehicle, plate = details.plate },
    })
end, Config.dispatch.vehicleTheftCooldown)

local reportMelee = QB.timers.throttle(function()
    alert({
        code = '10-10',
        title = 'Fight in Progress',
        message = ('A fight was reported%s.'):format(street() and (' near ' .. street()) or ''),
        priority = 3,
        icon = 'person',
        data = { street = street() },
    })
end, Config.dispatch.meleeCooldown)

-- One loop for every detector rather than one thread each. It runs at 500ms,
-- not per frame: these are all "is this still happening" state checks, and
-- polling them sixty times a second would burn client frames to learn nothing a
-- twice-a-second check misses.
--
-- Each throttle is invoked through `.run(...)` rather than by calling the handle:
-- QB.timers.throttle returns a table made callable by a __call metamethod, and
-- metatables do not survive the qblib export boundary, so from here the handle
-- arrives as a plain table and `reportMelee()` raised "attempt to call a table
-- value". See qblib modules/timers/docs.md.
local function tick()
    local ped = QB.cache.ped()

    -- On-duty officers are excluded from every detector. A firearms unit
    -- returning fire must not spawn a "shots fired" call about itself, and
    -- the resulting feedback loop (alert -> officers respond -> more
    -- shooting -> more alerts) is the classic way these systems become
    -- unusable during exactly the incident they exist for.
    if not ped or Police.isOnDuty() or IsPedDeadOrDying(ped, true) then return end

    if IsPedShooting(ped) then
        reportShots.run(IsPedCurrentWeaponSilenced(ped), GetSelectedPedWeapon(ped))
    end

    if IsPedJacking(ped) or IsPedTryingToEnterALockedVehicle(ped) then
        reportTheft.run(GetVehiclePedIsTryingToEnter(ped))
    end

    if IsPedInMeleeCombat(ped) then
        reportMelee.run()
    end
end

CreateThread(function()
    while true do
        Wait(500)

        -- pcall so one throwing detector cannot kill the loop. A dead detector
        -- thread is silent -- no alerts, and no second error to notice -- which
        -- is the worst failure mode for a reporting system, so the error is
        -- surfaced instead of ending the thread.
        local ok, err = pcall(tick)
        if not ok then QB.print.error('qbpolice detector tick failed:', err) end
    end
end)
