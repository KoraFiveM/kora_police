-- kora_police registers its own items via Core.registry.registerShared at boot,
-- rather than hand-editing kora_core/shared/items.lua's own catalog (the plan's
-- ??9 recommendation) -- keeps kora_core's seed file job-resource-agnostic.
-- registerShared is server-only (kora_core refuses a client-side call); the
-- registry replicates every record to clients automatically.

local ITEMS = {
    { name = 'handcuffs', label = 'Handcuffs', weight = 250, type = 'item', image = 'handcuffs.png', unique = false, useable = true, shouldClose = true, description = 'Restrain a suspect.' },
    { name = 'moneybag', label = 'Money Bag', weight = 500, type = 'item', image = 'moneybag.png', unique = true, useable = true, shouldClose = true, description = 'A bag of cash, ready to deposit.' },
    { name = 'armor', label = 'Bulletproof Vest', weight = 3000, type = 'item', image = 'armor.png', unique = false, useable = true, shouldClose = true, description = 'Body armor.' },
}

CreateThread(function()
    for _, item in ipairs(ITEMS) do
        exports.kora_core:registerShared('items', item.name, item)
    end
end)
