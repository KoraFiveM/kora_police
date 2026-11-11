-- Client half of server/armour.lua: the put-on progress bar and the armour apply.

Kora.callback.register("kora_police:armour:progress", function(progress)
    local ok, completed = pcall(Kora.progressbar.start, {
        label = progress.label,
        duration = progress.duration,
        canCancel = progress.canCancel,
        anim = progress.anim,
        disable = { move = false, combat = true, car = true },
    })
    return ok and completed and true or false
end)

RegisterNetEvent("kora_police:client:setArmour", function(value)
    if GetInvokingResource() ~= nil or type(value) ~= "number" then return end
    SetPedArmour(Kora.cache.ped(), math.floor(math.max(0, math.min(100, value))))
end)
