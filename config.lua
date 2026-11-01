-- Single flat Config table, per-module sub-tables, a trailing comment on
-- every value -- matches kora_core/kora_lib's own config.lua convention.

Config = Config or {}

Config.police = {
    job = 'police',                    -- job name gate for every server-side check in this resource

    -- The kora_core job TYPE this resource dispatches to. Alerts target the type,
    -- not the job name, so a server that adds a `sheriff` or `statetrooper` job
    -- with `type = 'leo'` gets them on the same radio with no code change here.
    jobType = 'leo',

    -- Where an officer-down escalation goes. It is a SECOND, separate call --
    -- police and EMS keep separate feeds, wording and histories.
    emsJobType = 'ems',
}

Config.performance = {
    diagnostics = false,               -- true prints bounded spike/ALPR scan totals when their lifecycle-bound workers stop
}

Config.cuff = {
    cuffTime = 5000,                   -- ms the hard-cuff animation/progressbar takes
    distance = 2.5,                    -- max distance to cuff/uncuff/escort/drag/put-in-vehicle a target
    breakCuffsDifficulty = { 'medium', 'hard', 'medium' },  -- per-attempt Kora.minigames difficulty for a soft-cuffed suspect's escape attempt (ported qbx_police mechanic)
    breakCuffsAttempts = 3,            -- total escape attempts before the item gives up until the next use
    breakCuffsCooldown = 60000,        -- ms a suspect must wait after a failed break-cuffs try before another
}

Config.incapacitated = {
    downed = true,                     -- a last-stand/dead target can be robbed and dragged
    cuffed = true,                     -- a handcuffed target can be robbed and dragged
    ambulance = true,                  -- read kora_ambulance live state (emsDown statebag / getPatientStatus) when it is running
    pedHealthFallback = false,         -- also treat a ped at or below 100 health as downed (for medical resources that set no flag)
}

Config.jail = {
    defaultMinutes = 10,               -- fallback sentence length when a cuff-and-book flow doesn't specify one
}

Config.evidence = {
    lockerStashId = 'police-evidence', -- kora_inventory stash id backing the shared evidence locker (RegisterStash)
    lockerLabel = 'Evidence Locker',
    lockerSlots = 100,
    lockerMaxWeight = 200000,
    lockerCoords = vector4(441.9, -984.5, 30.7, 90.0),  -- MRPD evidence room, adjust per map
    lockerDistance = 2.0,
    minGradeToAccess = 1,              -- job.grade.level required to open the locker -- 1 = Cadet, everyone qualifies
    clearDistance = 10.0,              -- metres around the officer a stock blood/casing clear may remove markers
    clearMaxMarkers = 50,              -- markers one stock clear request may remove
    statusTtl = 600000,                -- ms a stock evidence:server:UpdateStatus list is kept for a player
    statuses = {                       -- stock evidence:client:SetStatus ids (the server never trusts client-supplied labels)
        fight = 'Red hands', widepupils = 'Wide Pupils', redeyes = 'Red Eyes', weedsmell = 'Smells like weed',
        gunpowder = 'Gunpowder in clothing', chemicals = 'smells chemical', heavybreath = 'Breathes heavily',
        sweat = 'Sweats a lot', handbleed = 'Blood on hands', confused = 'Confused', alcohol = 'Smells like alcohol',
        heavyalcohol = 'Smells very much like alcohol', agitated = 'Agitated - Signs of Meth Use',
    },
    statusDistance = 5.0,              -- max distance for a stock police:GetPlayerStatus lookup of another player
    drawers = {                        -- stock qb-policejob:server:evidence drawers: one entry per evidence room; the stash id is the stock '<room> | Drawer <n>'
        rooms = {
            vector3(442.1722, -996.067, 30.689),
            vector3(451.7031, -973.232, 30.689),
            vector3(455.1456, -985.462, 30.689),
        },
        maxDrawer = 20,                -- highest drawer number a request may name
        distance = 3.0,                -- metres from a room point
        slots = 500,
        maxWeight = 4000000,
    },
    worldMarkerTtl = 1800000,          -- milliseconds before an uncollected world marker expires
    maxWorldMarkers = 500,             -- hard memory/broadcast cap across all world evidence
    createCooldown = 250,              -- minimum milliseconds between marker submissions from one player
    collectDistance = 2.5,             -- server-side distance required to collect a marker
    ballistic = {
        enabled = true,                -- whether fired server-owned rounds leave collectible casings
        casingOffset = 0.75,           -- randomised distance from the shooter where a casing lands
        databaseRetentionDays = 90,    -- retained case records; cleanup can be scheduled by the server owner
        analysis = {
            requiredStages = 3,        -- microscopy, comparison, and registry confirmation
            games = { 'skillbar', 'circuit', 'pinpad' }, -- kora_lib server-validated stages in this order
        },
    },
}

Config.armory = {
    shops = {
        {
            id = 'pd-armory-patrol',
            label = 'Patrol Armory',
            coords = vector4(441.1, -981.2, 30.7, 90.0),
            distance = 2.0,
            minGrade = 1,               -- job.grade.level required to see/use this shop at all -- 1 = Cadet, everyone qualifies
            slots = 20,
            items = {
                { name = 'weapon_stungun',   price = 0,    amount = 1 },
                { name = 'weapon_nightstick', price = 0,   amount = 1 },
                { name = 'handcuffs',        price = 0,    amount = 5 },
                { name = 'pistol_ammo',      price = 0,    amount = 10 },
                { name = 'armor',            price = 0,    amount = 3 },
            },
        },
        {
            id = 'pd-armory-sergeant',
            label = 'Sergeant Armory',
            coords = vector4(443.8, -981.2, 30.7, 90.0),
            distance = 2.0,
            minGrade = 3,               -- Sergeant and above (grades are 1-based: Cadet=1, Officer=2, Sergeant=3, Lieutenant=4, Chief=5 -- see kora_core/shared/jobs.lua)
            slots = 20,
            items = {
                { name = 'weapon_combatpistol', price = 0, amount = 1 },
                { name = 'weapon_pumpshotgun',  price = 250, amount = 1 },
                { name = 'shotgun_ammo',        price = 50,  amount = 5 },
                { name = 'rifle_ammo',          price = 50,  amount = 5 },
            },
        },
        {
            id = 'pd-armory-swat',
            label = 'SWAT Armory',
            coords = vector4(446.5, -981.2, 30.7, 90.0),
            distance = 2.0,
            minGrade = 4,               -- Lieutenant and above
            slots = 20,
            items = {
                { name = 'weapon_carbinerifle', price = 500, amount = 1 },
                { name = 'rifle_ammo',          price = 0,   amount = 10 },
            },
        },
    },
}

Config.stash = {
    personal = { slots = 50, maxWeight = 400000 },     -- stock qb-policejob:server:stash ('policestash_<citizenid>')
    trash = { slots = 300, maxWeight = 4000000 },      -- stock qb-policejob:server:trash (shared 'policetrash')
    clearTrashOnStart = true,          -- stock wipes the trash stash whenever the resource starts
    distance = 5.0,                    -- metres from a point in `locations` a stock stash/trash request must be made
    locations = {},                    -- { vector3, ... }; empty = no distance check (stock has none)
}

Config.objects = {
    types = {                          -- stock police:server:spawnObject(type) props
        cone = { model = 'prop_roadcone02a', freeze = false },
        barrier = { model = 'prop_barrier_work06a', freeze = true },
        roadsign = { model = 'prop_snow_sign_road_06g', freeze = true },
        tent = { model = 'prop_gazebo_03', freeze = true },
        light = { model = 'prop_worklight_03b', freeze = true },
    },
    placeDistance = 0.5,               -- metres in front of the officer a prop is created
    deleteDistance = 5.0,              -- max officer distance for police:server:deleteObject
    maxPerOfficer = 20,                -- concurrent props per officer
    lifetime = 1800000,                -- ms before an abandoned prop is removed
    cooldown = 500,                    -- minimum ms between placements from one officer
}

Config.tracker = {
    locationCooldown = 5000,           -- minimum ms between stock police:server:SendTrackerLocation replies from one player
}

Config.heli = {
    spotlightCooldown = 500,           -- minimum ms between stock heli:server:spotlight toggles from one player
}

Config.impound = {
    fee = 500,                         -- default civilian impound fee (Core.garage.impound's `fee` argument)
    maxFee = 10000,                    -- cap on the stock police:server:Impound `price` argument
    takeOutDistance = 10.0,            -- metres from a lot a stock police:server:TakeOutImpound must be made
    progress = {
        enabled = true,                -- show a cancellable progress bar and only impound once it completes; false = instant
        duration = 5000,               -- ms
        label = 'Impounding vehicle...',
        canCancel = true,
        anim = { dict = 'missheistdockssetup1clipboard@base', clip = 'base', flag = 49 },  -- Kora.progressbar anim; nil = no animation
        prop = { model = 'p_amb_clipboard_01', bone = 18905, offset = { x = 0.16, y = 0.08, z = 0.1 }, rotation = { x = -130.0, y = -50.0, z = 0.0 } },  -- hand-held clipboard; nil = no prop
    },
    lots = {
        { id = 'mission-row', label = 'Mission Row Impound', coords = vector4(408.0, -1626.0, 29.3, 230.0) },
    },
}

Config.plateFlags = {
    mirrorToMdt = true,                -- also write/resolve an active vehicle BOLO in kora_mdt (qbmdt_bolos) so flagged plates show in the MDT; skipped when kora_mdt is not started
    days = 7,                          -- days the MDT BOLO stays active (kora_mdt may cap it with its own boloMaxDays)
}

Config.spikes = {
    model = 'p_ld_stinger_s',          -- model name string; converted via GetHashKey at the CreateObject call site
    lifetime = 120000,                 -- ms a deployed strip stays networked before auto-cleanup
    maxDeployed = 6,                   -- per-officer concurrent strip cap
    deployDistance = 5.0,              -- max server-observed distance from an officer to a requested strip position
    deflateDistance = 1.2,             -- metres from a strip's coords that pops a tyre
}

Config.cameras = {
    hideRadar = false,                 -- hide the minimap while viewing a camera
    list = {                           -- stock police:client:ActiveCamera(id) security cameras
        [1] = { label = 'Pacific Bank CAM#1', coords = vector3(257.45, 210.07, 109.08), r = { x = -25.0, y = 0.0, z = 28.05 }, canRotate = false, isOnline = true },
        [2] = { label = 'Pacific Bank CAM#2', coords = vector3(232.86, 221.46, 107.83), r = { x = -25.0, y = 0.0, z = -140.91 }, canRotate = false, isOnline = true },
        [3] = { label = 'Pacific Bank CAM#3', coords = vector3(252.27, 225.52, 103.99), r = { x = -35.0, y = 0.0, z = -74.87 }, canRotate = false, isOnline = true },
        [4] = { label = 'Limited Ltd Grove St. CAM#1', coords = vector3(-53.1433, -1746.714, 31.546), r = { x = -35.0, y = 0.0, z = -168.9182 }, canRotate = false, isOnline = true },
        [5] = { label = "Rob's Liqour Prosperity St. CAM#1", coords = vector3(-1482.9, -380.463, 42.363), r = { x = -35.0, y = 0.0, z = 79.53281 }, canRotate = false, isOnline = true },
        [6] = { label = "Rob's Liqour San Andreas Ave. CAM#1", coords = vector3(-1224.874, -911.094, 14.401), r = { x = -35.0, y = 0.0, z = -6.778894 }, canRotate = false, isOnline = true },
        [7] = { label = 'Limited Ltd Ginger St. CAM#1', coords = vector3(-718.153, -909.211, 21.49), r = { x = -35.0, y = 0.0, z = -137.1431 }, canRotate = false, isOnline = true },
        [8] = { label = '24/7 Supermarkt Innocence Blvd. CAM#1', coords = vector3(23.885, -1342.441, 31.672), r = { x = -35.0, y = 0.0, z = -142.9191 }, canRotate = false, isOnline = true },
        [9] = { label = "Rob's Liqour El Rancho Blvd. CAM#1", coords = vector3(1133.024, -978.712, 48.515), r = { x = -35.0, y = 0.0, z = -137.302 }, canRotate = false, isOnline = true },
        [10] = { label = 'Limited Ltd West Mirror Drive CAM#1', coords = vector3(1151.93, -320.389, 71.33), r = { x = -35.0, y = 0.0, z = -119.4468 }, canRotate = false, isOnline = true },
        [11] = { label = '24/7 Supermarkt Clinton Ave CAM#1', coords = vector3(383.402, 328.915, 105.541), r = { x = -35.0, y = 0.0, z = 118.585 }, canRotate = false, isOnline = true },
        [12] = { label = 'Limited Ltd Banham Canyon Dr CAM#1', coords = vector3(-1832.057, 789.389, 140.436), r = { x = -35.0, y = 0.0, z = -91.481 }, canRotate = false, isOnline = true },
        [13] = { label = "Rob's Liqour Great Ocean Hwy CAM#1", coords = vector3(-2966.15, 387.067, 17.393), r = { x = -35.0, y = 0.0, z = 32.92229 }, canRotate = false, isOnline = true },
        [14] = { label = '24/7 Supermarkt Ineseno Road CAM#1', coords = vector3(-3046.749, 592.491, 9.808), r = { x = -35.0, y = 0.0, z = -116.673 }, canRotate = false, isOnline = true },
        [15] = { label = '24/7 Supermarkt Barbareno Rd. CAM#1', coords = vector3(-3246.489, 1010.408, 14.705), r = { x = -35.0, y = 0.0, z = -135.2151 }, canRotate = false, isOnline = true },
        [16] = { label = '24/7 Supermarkt Route 68 CAM#1', coords = vector3(539.773, 2664.904, 44.056), r = { x = -35.0, y = 0.0, z = -42.947 }, canRotate = false, isOnline = true },
        [17] = { label = "Rob's Liqour Route 68 CAM#1", coords = vector3(1169.855, 2711.493, 40.432), r = { x = -35.0, y = 0.0, z = 127.17 }, canRotate = false, isOnline = true },
        [18] = { label = '24/7 Supermarkt Senora Fwy CAM#1', coords = vector3(2673.579, 3281.265, 57.541), r = { x = -35.0, y = 0.0, z = -80.242 }, canRotate = false, isOnline = true },
        [19] = { label = '24/7 Supermarkt Alhambra Dr. CAM#1', coords = vector3(1966.24, 3749.545, 34.143), r = { x = -35.0, y = 0.0, z = 163.065 }, canRotate = false, isOnline = true },
        [20] = { label = '24/7 Supermarkt Senora Fwy CAM#2', coords = vector3(1729.522, 6419.87, 37.262), r = { x = -35.0, y = 0.0, z = -160.089 }, canRotate = false, isOnline = true },
        [21] = { label = 'Fleeca Bank Hawick Ave CAM#1', coords = vector3(309.341, -281.439, 55.88), r = { x = -35.0, y = 0.0, z = -146.1595 }, canRotate = false, isOnline = true },
    },
}

Config.breach = {
    -- NEW differentiator (confirmed absent from both qb-policejob and
    -- qbx_police): a lockpick-minigame door breach. Each entry is a real GTA
    -- door object registered with FiveM's own door system (self-replicating
    -- across clients, no server round trip needed for the lock state itself).
    doors = {
        { id = 'qbpolice-breach-demo', model = 'v_ilev_gundoor01', coords = vector3(452.0, -980.0, 30.7), unlockedFor = 30000 },
    },
}

Config.minigames = {
    breach = { type = 'lockpick', opts = { pinCount = 5, attempts = 2 } },     -- door-breach minigame (new differentiator)
    breakCuffs = {
        type = 'mash',                  -- ported qbx_police-style escape skillcheck
        opts = {
            easy = { requiredPresses = 12, timeLimit = 8000, attempts = 1 },   -- server-owned easy round
            medium = { requiredPresses = 20, timeLimit = 7000, attempts = 1 }, -- server-owned medium round
            hard = { requiredPresses = 30, timeLimit = 6000, attempts = 1 },   -- server-owned hard round
        },
    },
}

Config.dispatch = {
    accent = '#3B82F6',                -- law enforcement blue, applied to this player's dispatch UI
    panicKey = 'F10',                  -- officer-down panic button (rebindable in FiveM's key settings)
    backupCooldown = 15000,            -- server-enforced interval between backup calls from one officer

    -- ms before the same officer can raise another panic alarm. One press is
    -- two calls (LEO + EMS), so an officer mashing the key while being shot at
    -- fills both services' feeds with duplicates of the incident they are
    -- already responding to -- exactly when a clean feed matters most.
    --
    -- Deliberately short: an officer who is still down a minute later, in a new
    -- position, is raising a genuinely new alarm and should be able to.
    panicCooldown = 60000,

    -- Detector throttles, in ms. These are per-player cooldowns on ALERTS, not
    -- on detection: a shootout produces one call, not one per trigger pull.
    -- Long enough that a single incident reads as a single incident; short
    -- enough that a genuinely new event a minute later still gets reported.
    shotsFiredCooldown = 20000,
    vehicleTheftCooldown = 30000,
    meleeCooldown = 30000,

    legacyAlertCooldown = 15000,       -- server-enforced interval between stock `police:server:policeAlert` calls from one player
    legacyAlertMaxLength = 120,        -- characters of the stock alert text kept (control characters are stripped)
    copCountThrottle = 2000,           -- minimum ms between stock `police:server:UpdateCurrentCops`-style cop-count broadcasts
    robberyRadius = 30.0,              -- metres, informational only -- passed through in the alert payload's `radius`
}

Config.duty = {
    actionCooldown = 1000,
    vehicleSpawnDistance = 15.0,
    -- `blip` is optional per point; omit it for a duty point that should not
    -- appear on the map. A named category groups every configured station
    -- beneath one pause-map legend heading.
    points = {
        {
            coords = vector4(441.5, -980.0, 30.7, 90.0), radius = 1.5, label = 'Police Duty',
            blip = { enabled = true, sprite = 60, color = 29, scale = 0.8, shortRange = true, category = 'Police' },
        },
    },
    vehicles = {
        { model = 'police',  label = 'Police Cruiser', coords = vector4(454.6, -1017.7, 28.7, 90.0) },
        { model = 'police2', label = 'Police Buffalo',  coords = vector4(454.6, -1013.9, 28.7, 90.0) },
    },
}

Config.fine = {
    -- Tiered fines picked via Kora.util.weightedChoice-style {value, weight} lists
    -- when a job resource wants a randomised default; the officer-entered
    -- amount from the citation UI is authoritative when supplied.
    tiers = {
        { 100, 3 }, { 250, 2 }, { 500, 1 },
    },
    account = 'bank',                  -- which money account BillPlayer/citations charge
}

-- Issued citations are stored on the recipient (player metadata `citations`)
-- until paid, so they survive relogs and restarts.
Config.Citations = {
    autoDeduct = false,                -- true = charge Config.fine.account immediately on issue (nothing stored, nothing to pay); false = store the citation and let the recipient pay it
    maxUnpaid = 25,                    -- most unpaid citations one player can hold; the oldest is dropped beyond this
    payMethods = {
        command = true,                -- /citations lists unpaid citations, /paycitation [id] pays one from Config.fine.account (command names below)
        exports = true,                -- exports.kora_police:getCitations(src) / payCitation(src, id) for a phone or bank UI to call
    },
    listCommand = 'citations',
    payCommand = 'paycitation',
}

Config.rob = {
    takeCash = true,                   -- robbing a restrained/downed player moves their cash to the robber
    openInventory = true,              -- robbing also opens the target inventory as the robber's secondary inventory
    accessSeconds = 120,               -- seconds the robber keeps inventory access after starting a rob (press Rob again to renew)
    closeDistance = 4.0,               -- metres; the robber's inventory is closed (and access revoked) beyond this distance
    checkInterval = 1000,              -- ms between server checks that the target is still restrained/downed and in range
}

Config.drag = {
    releaseKey = 'E',                -- default keyboard key (RegisterKeyMapping, rebindable in settings) that releases the player you drag; '' = no key mapping
    releaseCommand = 'releasedrag',  -- command that releases the player you drag; '' = no command
    releaseControl = 38,             -- control polled directly while dragging so release works even when the key mapping is shadowed or already bound (38 = E); 0/false = off
    releaseHint = true,              -- tell the dragger how to release when a drag starts
    autoReleaseDistance = 8.0,         -- metres between dragger and dragged before the drag is released server-side
    releaseInVehicle = true,           -- release when either player enters a vehicle
    releaseWhenRecovered = true,       -- release when the dragged player is no longer restrained or downed
    checkInterval = 1000,              -- ms between server drag checks
    bone = 0,                          -- dragger ped bone index the dragged ped is attached to (0 = ped root; 11816 = pelvis)
    offset = { x = 0.0, y = 0.5, z = 0.0 },       -- attach offset relative to the bone
    rotation = { x = 0.0, y = 0.0, z = 0.0 },     -- attach rotation in degrees
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.adopt then Config = Kora.config.adopt(Config) end
