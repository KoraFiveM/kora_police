-- Automatic crime detection.
--
-- These live in kora_police, not in qbdispatch: dispatch has no idea what a crime
-- is, and should not. It transports and presents calls; deciding that a gunshot
-- in a public street is a police matter is police-resource business. The same
-- rule puts a bank robbery's alert inside the robbery script.
--
-- Every detector is THROTTLED, not debounced. A throttle fires immediately and
-- drops the rest of the window; a debounce would wait for the shooting to stop
-- before reporting it, which is precisely backwards for an emergency.

local function alert(incident)
    -- The incident key is the entire client payload. Wording, service,
    -- priority and coordinates all come from the server-owned registration.
    Kora.events.trigger('qbpolice:server:crimeDetected', incident)
end

local reportShots = Kora.timers.throttle(function(silenced)
    -- A suppressed weapon is quieter, not silent: fewer witnesses would place
    -- it precisely, so it is a distinct lower-priority allowlisted incident.
    alert(silenced and 'qbpolice:gunfire:suppressed' or 'qbpolice:gunfire')
end, Config.dispatch.shotsFiredCooldown)

local reportTheft = Kora.timers.throttle(function()
    alert('qbpolice:vehicle-theft')
end, Config.dispatch.vehicleTheftCooldown)

local reportMelee = Kora.timers.throttle(function()
    alert('qbpolice:melee')
end, Config.dispatch.meleeCooldown)

-- One loop for every detector rather than one thread each. It runs at 500ms,
-- not per frame: these are all "is this still happening" state checks, and
-- polling them sixty times a second would burn client frames to learn nothing a
-- twice-a-second check misses.
--
-- Each throttle is invoked through `.run(...)` rather than by calling the handle:
-- Kora.timers.throttle returns a table made callable by a __call metamethod, and
-- metatables do not survive the kora_lib export boundary, so from here the handle
-- arrives as a plain table and `reportMelee()` raised "attempt to call a table
-- value". See kora_lib modules/timers/docs.md.
local function tick()
    local ped = Kora.cache.ped()

    -- On-duty officers are excluded from every detector. A firearms unit
    -- returning fire must not spawn a "shots fired" call about itself, and
    -- the resulting feedback loop (alert -> officers respond -> more
    -- shooting -> more alerts) is the classic way these systems become
    -- unusable during exactly the incident they exist for.
    if not ped or Police.isOnDuty() or IsPedDeadOrDying(ped, true) then return end

    if IsPedShooting(ped) then
        reportShots.run(IsPedCurrentWeaponSilenced(ped))
    end

    if IsPedJacking(ped) or IsPedTryingToEnterALockedVehicle(ped) then
        reportTheft.run()
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
        if not ok then Kora.print.error('qbpolice detector tick failed:', err) end
    end
end)
