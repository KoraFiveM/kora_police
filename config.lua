-- Single flat Config table, per-module sub-tables, a trailing comment on
-- every value -- matches qbcore/qblib's own config.lua convention.

Config = Config or {}

Config.police = {
    job = 'police',                    -- job name gate for every server-side check in this resource

    -- The qbcore job TYPE this resource dispatches to. Alerts target the type,
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
    breakCuffsDifficulty = { 'medium', 'hard', 'medium' },  -- per-attempt QB.minigames difficulty for a soft-cuffed suspect's escape attempt (ported qbx_police mechanic)
    breakCuffsAttempts = 3,            -- total escape attempts before the item gives up until the next use
    breakCuffsCooldown = 60000,        -- ms a suspect must wait after a failed break-cuffs try before another
}

Config.jail = {
    defaultMinutes = 10,               -- fallback sentence length when a cuff-and-book flow doesn't specify one
}

Config.evidence = {
    lockerStashId = 'police-evidence', -- qbinventory stash id backing the shared evidence locker (RegisterStash)
    lockerLabel = 'Evidence Locker',
    lockerSlots = 100,
    lockerMaxWeight = 200000,
    lockerCoords = vector4(441.9, -984.5, 30.7, 90.0),  -- MRPD evidence room, adjust per map
    lockerDistance = 2.0,
    minGradeToAccess = 1,              -- job.grade.level required to open the locker -- 1 = Cadet, everyone qualifies
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
            games = { 'skillbar', 'circuit', 'pinpad' }, -- qblib server-validated stages in this order
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
            minGrade = 3,               -- Sergeant and above (grades are 1-based: Cadet=1, Officer=2, Sergeant=3, Lieutenant=4, Chief=5 -- see qbcore/shared/jobs.lua)
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

Config.impound = {
    fee = 500,                         -- default civilian impound fee (Core.garage.impound's `fee` argument)
    lots = {
        { id = 'mission-row', label = 'Mission Row Impound', coords = vector4(408.0, -1626.0, 29.3, 230.0) },
    },
}

Config.spikes = {
    model = 'p_ld_stinger_s',          -- model name string; converted via GetHashKey at the CreateObject call site
    lifetime = 120000,                 -- ms a deployed strip stays networked before auto-cleanup
    maxDeployed = 6,                   -- per-officer concurrent strip cap
    deployDistance = 5.0,              -- max server-observed distance from an officer to a requested strip position
    deflateDistance = 1.2,             -- metres from a strip's coords that pops a tyre
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

    robberyRadius = 30.0,              -- metres, informational only -- passed through in the alert payload's `radius`
}

Config.duty = {
    actionCooldown = 1000,
    vehicleSpawnDistance = 15.0,
    -- `blip` is optional per point; omit it for a duty point that should not
    -- appear on the map. Category 2 lists the station by name instead of
    -- placing it in GTA's built-in "Owned Property" category (11).
    points = {
        {
            coords = vector4(441.5, -980.0, 30.7, 90.0), radius = 1.5, label = 'Police Duty',
            blip = { enabled = true, sprite = 60, color = 29, scale = 0.8, shortRange = true, label = 'Police Station', category = 2 },
        },
    },
    vehicles = {
        { model = 'police',  label = 'Police Cruiser', coords = vector4(454.6, -1017.7, 28.7, 90.0) },
        { model = 'police2', label = 'Police Buffalo',  coords = vector4(454.6, -1013.9, 28.7, 90.0) },
    },
}

Config.fine = {
    -- Tiered fines picked via QB.util.weightedChoice-style {value, weight} lists
    -- when a job resource wants a randomised default; the officer-entered
    -- amount from the citation UI is authoritative when supplied.
    tiers = {
        { 100, 3 }, { 250, 2 }, { 500, 1 },
    },
    account = 'bank',                  -- which money account BillPlayer/citations charge
}
