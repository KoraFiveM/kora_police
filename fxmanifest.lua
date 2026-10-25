fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbpolice'
author 'qbcore2'
version '0.1.0'
description 'Police/LEO job -- cuff/escort/search/evidence/armory/jail/dispatch on top of qbcore+qblib+qbinventory+qbtarget'

provide 'qb-policejob'

dependency 'qblib'
dependency 'qbsql'
dependency 'qbcore'
dependency 'qbdispatch'
dependency 'qbinventory'
dependency 'qbtarget'

shared_scripts {
    '@qblib/init.lua',
    '@qbsql/init.lua',
}

shared_scripts {
    'config.lua'
}

-- Explicit, non-globbed list -- matches every sibling resource's own
-- rationale (qbcore/qbadmin/qbinventory): alphabetic glob order would not
-- respect the real load-order dependencies between these files. core.lua
-- defines the shared `Police` table and its distance/duty helpers and must
-- load first; compat/police.lua calls into nearly every other file's
-- Police.* functions and must load last.
server_scripts {
    'server/migrate.lua',
    'server/core.lua',
    'server/items.lua',
    'server/cuff.lua',
    'server/escort.lua',
    'server/seize.lua',
    'server/bill.lua',
    'server/rob.lua',
    'server/jail.lua',
    'server/dispatch.lua',
    'server/evidence.lua',
    'server/armory.lua',
    'server/fingerprint.lua',
    'server/tracker.lua',
    'server/impound.lua',
    'server/plate_flag.lua',
    'server/duty.lua',
    'server/spikes.lua',
    'server/callbacks.lua',
    'server/compat/police.lua',
}

-- core.lua first (shared `Police` table); compat.lua last (the remaining
-- legacy listeners assume every feature file has already registered).
client_scripts {
    'client/core.lua',
    'client/cuff.lua',
    'client/cuff_escape.lua',
    'client/escort.lua',
    'client/vehicle.lua',
    'client/search.lua',
    'client/seize.lua',
    'client/rob.lua',
    'client/jail.lua',
    'client/bill.lua',
    'client/dispatch.lua',
    'client/detectors.lua',
    'client/evidence.lua',
    'client/spikes.lua',
    'client/breach_minigame.lua',
    'client/armory.lua',
    'client/fingerprint.lua',
    'client/tracker.lua',
    'client/plate_flag.lua',
    'client/duty.lua',
    'client/impound.lua',
    'client/compat.lua',
}
