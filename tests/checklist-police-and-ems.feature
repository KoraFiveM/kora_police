# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_police — Police & EMS

  @kora_police @checklist @checklist:kora_police:police-duty @cat:police-and-ems
  Scenario: Toggle police duty
    """
    Checklist test: At Police Duty point (441.5,-980.0,30.7) use target or /police-duty to go on/off duty; non-police is refused.
    """
    Given my job is "police"
    When I manually: go to the Police Duty point at the Mission Row station
    And I manually: use the target option to toggle police duty
    Then I should be on duty
    When I run the command "/police-duty"
    Then I should be off duty
    When I manually: set my job to a non-police job and try to toggle duty at the duty point
    Then I should be off duty
    And I confirm: the non-police player is refused

  @kora_police @checklist @checklist:kora_police:duty-vehicles @cat:police-and-ems
  Scenario: Take out / store patrol vehicle
    """
    Checklist test: At duty point choose Take Out Police Cruiser or Buffalo (spawn 454.6,-1017.7); use 'Store Patrol Vehicle' to return it.
    """
    Given my job is "police"
    And I am on duty
    When I manually: go to the Police Duty point and choose Take Out Police Cruiser
    Then I confirm: a Police Cruiser spawns at the patrol vehicle spawn point
    When I manually: store it using the Store Patrol Vehicle option
    Then I confirm: the cruiser is returned and removed
    When I manually: choose Take Out Buffalo at the duty point
    Then I confirm: a Buffalo spawns at the patrol vehicle spawn point

  @kora_police @checklist @checklist:kora_police:cuff-target @cat:police-and-ems
  Scenario: Cuff and uncuff player via target
    """
    Checklist test: Target a nearby player: 'Cuff' then 'Uncuff'; paired arrest animation, cuff prop on wrists, controls and targeting disabled.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to stand next to me
    And I manually: target the second player and choose Cuff
    Then I confirm: the paired arrest animation plays
    And I confirm: a cuff prop is on the second player's wrists
    And I confirm: the second player's controls and targeting are disabled
    When I manually: target the second player and choose Uncuff
    Then I confirm: the second player is freed and can move and target again

  @kora_police @checklist @checklist:kora_police:handcuffs-item @cat:police-and-ems
  Scenario: Soft-cuff with handcuffs item
    """
    Checklist test: Use the handcuffs item next to another player (anyone, not just police); they are soft-cuffed.
    """
    Given I have 1 "handcuffs"
    When I manually: ask a second player to stand next to me
    And I use the "handcuffs"
    Then I confirm: the other player is soft-cuffed

  @kora_police @checklist @checklist:kora_police:uncuff-command @cat:police-and-ems
  Scenario: /uncuff nearest player
    """
    Checklist test: Run /uncuff next to a cuffed player as officer or the soft-cuffer; they are freed.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to stand next to me, already cuffed
    And I run the command "/uncuff"
    Then I confirm: the other player is freed

  @kora_police @checklist @checklist:kora_police:breakcuffs @cat:police-and-ems
  Scenario: Escape soft cuffs with /breakcuffs
    """
    Checklist test: As soft-cuffed player run /breakcuffs; complete the mash minigame to break free. Hard cuffs cannot be escaped.
    """
    When I manually: ask a second player to soft-cuff me with the handcuffs item
    And I run the command "/breakcuffs"
    And I manually: complete the mash minigame
    Then I confirm: I break free from the soft cuffs
    When I manually: ask a second player with a police job to hard-cuff me
    And I run the command "/breakcuffs"
    Then I confirm: I cannot escape the hard cuffs

  @kora_police @checklist @checklist:kora_police:search-player @cat:police-and-ems
  Scenario: Search a cuffed player
    """
    Checklist test: Target a cuffed player and choose 'Search'; officer's inventory opens on the target's inventory.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to stand next to me, cuffed
    And I manually: target the cuffed player and choose Search
    Then I confirm: my inventory opens showing the target's inventory

  @kora_police @checklist @checklist:kora_police:rob-player @cat:police-and-ems @manual
  Scenario: Rob a restrained/downed player
    """
    Checklist test: Target a cuffed or downed player 'Rob'; cash is taken (once per cooldown) and their inventory opens.
    """
    When I manually: ask a second player with some cash to stand next to me, cuffed or downed
    And I manually: target the player and choose Rob
    Then I confirm: cash is taken from the player (only once per cooldown)
    And I confirm: the player's inventory opens

  @kora_police @checklist @checklist:kora_police:seize-cash-license @cat:police-and-ems
  Scenario: Seize cash and driver's license
    """
    Checklist test: On a cuffed player use 'Seize Cash' and 'Seize Driver's License'; cash moves to officer, licence flag removed.
    """
    Given my job is "police"
    And I am on duty
    And my cash balance is 0
    When I manually: ask a second player with cash and a driver's license to stand next to me, cuffed
    And I manually: target the player and choose Seize Cash
    And I manually: target the player and choose Seize Driver's License
    Then I confirm: the cash moved from the suspect to me
    And I confirm: the suspect's driver's license flag is removed

  @kora_police @checklist @checklist:kora_police:escort-drag @cat:police-and-ems
  Scenario: Escort and drag a suspect
    """
    Checklist test: Use 'Escort' / 'Stop Escorting' target or /escort; 'Drag' then 'Release' (E or /releasedrag); suspect follows officer.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to stand next to me, cuffed
    And I manually: target the suspect and choose Escort
    Then I confirm: the suspect follows me
    When I manually: choose Stop Escorting
    And I run the command "/escort"
    Then I confirm: the suspect follows me
    When I manually: stop escorting, then target the suspect and choose Drag
    Then I confirm: the suspect follows me while dragged
    When I manually: release with E or /releasedrag
    Then I confirm: the suspect is released

  @kora_police @checklist @checklist:kora_police:put-in-vehicle @cat:police-and-ems
  Scenario: Put suspect in / take out of vehicle
    """
    Checklist test: With a cuffed suspect near a vehicle use 'Put Suspect In Vehicle'; take out via the vehicle seat option.
    """
    Given my job is "police"
    And I am on duty
    And a "test_car" is spawned in front of me
    When I manually: ask a second player to stand next to me, cuffed
    And I manually: target the suspect and choose Put Suspect In Vehicle
    Then I confirm: the suspect is placed inside the vehicle
    When I manually: use the vehicle seat target option to take the suspect out
    Then I confirm: the suspect is taken out of the vehicle

  @kora_police @checklist @checklist:kora_police:jail-booking @cat:police-and-ems
  Scenario: Book suspect into jail
    """
    Checklist test: Target a cuffed player 'Book (Jail)', enter minutes and reason; suspect is jailed, cuffs/escort cleared.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to stand next to me, cuffed
    And I manually: target the suspect and choose Book (Jail)
    Then a menu titled "Book Suspect" opens
    When I manually: enter minutes and a reason and confirm
    Then I confirm: the suspect is jailed
    And I confirm: the suspect's cuffs and escort are cleared

  @kora_police @checklist @checklist:kora_police:issue-citation @cat:police-and-ems
  Scenario: Issue citation/fine
    """
    Checklist test: Target a player 'Issue Citation' with fine amount and reason; stored on player (or deducted if autoDeduct).
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to stand next to me
    And I manually: target the player and choose Issue Citation
    Then a menu titled "Issue Citation" opens
    When I manually: enter a fine amount and reason and confirm
    Then I confirm: the citation is stored on the player (or deducted if autoDeduct is enabled)

  @kora_police @checklist @checklist:kora_police:citations-pay @cat:police-and-ems
  Scenario: /citations and /paycitation
    """
    Checklist test: As cited player run /citations to list unpaid and /paycitation [id] to pay it from the configured account.
    """
    When I manually: ask a police officer to issue me a citation
    And I run the command "/citations"
    Then I confirm: my unpaid citations are listed
    When I manually: run /paycitation with the citation number
    Then I should see a notification containing "You paid citation"
    And I confirm: the citation is paid from the configured account

  @kora_police @checklist @checklist:kora_police:moneybag-item @cat:police-and-ems
  Scenario: Moneybag item payout
    """
    Checklist test: Use the moneybag item received from seizure; cash payout is added to the account.
    """
    When I manually: get a moneybag item from a cash seizure
    And I use the "moneybag"
    Then I confirm: the cash payout is added to my account

  @kora_police @checklist @checklist:kora_police:backup-command @cat:police-and-ems
  Scenario: /backup request
    """
    Checklist test: As on-duty LEO run /backup; call appears in kora_dispatch for all officers at your position.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/backup"
    Then I confirm: a backup call appears in kora_dispatch for all officers at my position

  @kora_police @checklist @checklist:kora_police:panic-button @cat:police-and-ems
  Scenario: Panic button F10
    """
    Checklist test: As on-duty officer press F10; 10-99 Officer Down goes to police and 10-52 to EMS; second press within 60s is blocked with a notice.
    """
    Given my job is "police"
    And I am on duty
    When I press the "F10" key
    Then I confirm: a 10-99 Officer Down alert goes to police and a 10-52 alert goes to EMS
    When I press the "F10" key
    Then I should see a notification containing "Your panic alarm is already active"

  @kora_police @checklist @checklist:kora_police:auto-dispatch-detectors @cat:police-and-ems
  Scenario: Auto dispatch for shots/theft/fights
    """
    Checklist test: As civilian fire a weapon, steal a vehicle or melee; dispatch alert reaches on-duty police (not triggered by officers).
    """
    Given my job is "unemployed"
    When I manually: fire a weapon in the open
    Then I confirm: an alert reaches on-duty police
    When I manually: steal a vehicle
    Then I confirm: a vehicle theft alert reaches on-duty police
    When I manually: start a melee fight
    Then I confirm: a fight alert reaches on-duty police
    When I manually: repeat the actions as an on-duty officer
    Then I confirm: no dispatch alert is triggered by officers

  @kora_police @checklist @checklist:kora_police:armory-shops @cat:police-and-ems
  Scenario: Armory by grade
    """
    Checklist test: Patrol (452.43,-980.19,30.69, Cadet+), Sergeant (443.8,-981.2, grade 3+), SWAT (446.5,-981.2, grade 4+); lower grades are denied.
    """
    Given my job is "police" at grade 1
    And I am on duty
    When I manually: go to the Patrol armory at 452.43, -980.19, 30.69 in the Mission Row police station and open the armory shop
    Then I confirm: the Patrol armory shop opens
    When I manually: go to the Sergeant armory at 443.8, -981.2 and try to open it at grade 1
    Then I confirm: the Sergeant armory (grade 3+) is denied at my grade
    When I manually: go to the SWAT armory at 446.5, -981.2 and try to open it at grade 1
    Then I confirm: the SWAT armory (grade 4+) is denied at my grade

  @kora_police @checklist @checklist:kora_police:armory-items @cat:police-and-ems
  Scenario: Armory items and evidence bags
    """
    Checklist test: Patrol room gives stungun, nightstick, handcuffs, pistol ammo, armor and empty_evidence_bag; stock restocks on resource start.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the Patrol armory room shop
    Then I confirm: the shop lists weapon_stungun, weapon_nightstick, handcuffs, pistol_ammo, armor and empty_evidence_bag
    When I manually: ask a dev to restart the kora_police resource and reopen the Patrol armory
    Then I confirm: the armory stock is restocked after the resource start

  @kora_police @checklist @checklist:kora_police:body-armour @cat:police-and-ems
  Scenario: Use body armour item
    """
    Checklist test: Use armor/armour/heavyarmor; cancellable progress bar then armour set to 50/100; refused when already full.
    """
    Given I have 1 "armor"
    And I have 1 "heavyarmor"
    And my armour is 0
    When I use the "armor"
    Then a progress bar should run
    When I cancel the progress bar
    Then my armour should be 0
    When I use the "armor"
    And I wait 10 seconds
    Then my armour should be 50
    When I use the "heavyarmor"
    Then I confirm: the use is refused because my armour is already full

  @kora_police @checklist @checklist:kora_police:evidence-locker @cat:police-and-ems
  Scenario: Evidence locker stash
    """
    Checklist test: At the evidence room (441.9,-984.5,30.7) open the police-evidence stash as police with minimum grade.
    """
    Given my job is "police"
    And I am on duty
    When I manually: go to the evidence room at 441.9, -984.5, 30.7 in the Mission Row police station
    And I manually: open the police-evidence stash with the target or prompt
    Then the "stash" inventory opens
    And I confirm: the Evidence Locker stash opens

  @kora_police @checklist @checklist:kora_police:collect-world-evidence @cat:police-and-ems
  Scenario: Collect blood, casing, fingerprint markers
    """
    Checklist test: After a shooting/injury evidence markers appear; target 'Collect <type> evidence' with an empty bag as on-duty officer to get a filled bag.
    """
    Given my job is "police"
    And I am on duty
    And I have 1 "empty_evidence_bag"
    When I manually: cause a shooting or injury so evidence markers appear, then go next to a marker
    Then I confirm: blood, casing or fingerprint evidence markers appear
    When I manually: use the target option 'Collect <type> evidence' on a marker
    Then I should have 1 "filled_evidence_bag"
    And I should have no "empty_evidence_bag"

  @kora_police @checklist @checklist:kora_police:evidence-drawers @cat:police-and-ems
  Scenario: Evidence drawers by slot
    """
    Checklist test: Use the evidence drawer prompt, enter slot number (1..max) to open the room's drawer; non-police denied.
    """
    Given my job is "police"
    And I am on duty
    When I manually: go to the evidence room and use the evidence drawer prompt
    And I manually: enter a drawer slot number between 1 and the maximum
    Then I confirm: the drawer for that slot opens
    When I manually: ask a non-police second player to use the evidence drawer prompt
    Then I confirm: the other player is denied access

  @kora_police @checklist @checklist:kora_police:fingerprint @cat:police-and-ems
  Scenario: Check fingerprint
    """
    Checklist test: Target a player 'Check Fingerprint'; officer receives the target's fingerprint ID.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to stand next to me
    And I select the "Check Fingerprint" target option
    Then I should see a notification containing "Fingerprint:"
    And I confirm: the notification shows the target's fingerprint ID

  @kora_police @checklist @checklist:kora_police:tracker @cat:police-and-ems
  Scenario: Attach GPS tracker
    """
    Checklist test: Target a player 'Attach Tracker'; tracker toggles and sends location to officers; tracker location shows on request.
    """
    Given my job is "police"
    And I am on duty
    When I manually: ask a second player to stand next to me
    And I select the "Attach Tracker" target option
    Then I should see a notification containing "You put on an ankle tracker"
    When I manually: request the tracker location
    Then I should see a notification containing "The location of"
    When I select the "Attach Tracker" target option
    Then I should see a notification containing "You took off"

  @kora_police @checklist @checklist:kora_police:spike-strip @cat:police-and-ems
  Scenario: Deploy and remove spike strip
    """
    Checklist test: Run /spikestrip to place a strip in front of you; vehicle tyres burst when driving over; officer can remove it.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/spikestrip"
    Then I confirm: a spike strip is placed in front of me
    When I manually: ask a second player to drive a vehicle over the strip
    Then I confirm: the other player's vehicle tyres burst
    When I manually: remove the spike strip as an officer
    Then I confirm: the spike strip is removed

  @kora_police @checklist @checklist:kora_police:road-props @cat:police-and-ems
  Scenario: Road props (cone, barrier, sign, tent, light)
    """
    Checklist test: Spawn cone/barrier/roadsign/tent/light via the police props action; capped at 20 per officer, delete within 5m.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the police props action and spawn a cone, barrier, roadsign, tent and light
    Then I confirm: each prop spawns in front of me
    When I manually: keep spawning props until 20 are placed and try one more
    Then I confirm: spawning is refused after 20 props
    When I manually: stand within 5m of a prop and delete it
    Then I confirm: the prop is deleted

  @kora_police @checklist @checklist:kora_police:plate-flag @cat:police-and-ems
  Scenario: Flag / unflag plate
    """
    Checklist test: Target a vehicle 'Flag Plate' (reason) / 'Unflag Plate'; flagged plate triggers a dispatch alert when spotted and writes a BOLO to MDT.
    """
    Given my job is "police"
    And I am on duty
    And a "test_car" is spawned in front of me
    When I select the "Flag Plate" target option
    And I manually: enter a reason for the flag
    Then I should see a notification containing "Plate flagged."
    When I manually: ask a second player to drive the flagged vehicle past an officer
    Then I confirm: a dispatch alert "Flagged plate spotted" is sent and a BOLO is written to the MDT
    When I select the "Unflag Plate" target option
    Then I should see a notification containing "Plate unflagged."

  @kora_police @checklist @checklist:kora_police:impound-vehicle @cat:police-and-ems
  Scenario: Impound a vehicle
    """
    Checklist test: Target a vehicle 'Impound Vehicle'; 'Impounding...' progress, vehicle sent to Mission Row Impound.
    """
    Given my job is "police"
    And I am on duty
    And a "test_car" is spawned in front of me
    When I select the "Impound Vehicle" target option
    Then a progress bar labelled "Impounding" should run
    When I wait 10 seconds
    Then the vehicle should be deleted
    And I confirm: the vehicle is sent to Mission Row Impound

  @kora_police @checklist @checklist:kora_police:retrieve-impound @cat:police-and-ems
  Scenario: Retrieve from impound
    """
    Checklist test: At Mission Row Impound (408.0,-1626.0,29.3) use 'Retrieve From' lot, enter plate and pay the fee.
    """
    Given my cash balance is at least 5000
    When I manually: go to Mission Row Impound at 408.0, -1626.0, 29.3
    And I manually: use the 'Retrieve From' lot option
    And I manually: enter the plate of an impounded vehicle and pay the fee
    Then I confirm: the fee is charged and the vehicle is retrieved

  @kora_police @checklist @checklist:kora_police:heli-spotlight @cat:police-and-ems
  Scenario: Helicopter spotlight
    """
    Checklist test: On-duty LEO in a helicopter toggles the spotlight; other players see it.
    """
    Given my job is "police"
    And I am on duty
    And I am in the driver seat of a "polmav"
    When I manually: toggle the helicopter spotlight
    Then I confirm: the spotlight turns on
    When I manually: ask a second player to look at my helicopter
    Then I confirm: the other player sees the spotlight

  @kora_police @checklist @checklist:kora_police:security-cameras @cat:police-and-ems @manual
  Scenario: Security camera view
    """
    Checklist test: Use camera system on configured cameras (e.g. Pacific Bank CAM#1) to view them locally.
    """
    When I manually: go to Pacific Bank and use the camera system on CAM#1
    Then I confirm: the camera view opens locally showing the camera feed

  @kora_police @checklist @checklist:kora_police:breach-door @cat:police-and-ems
  Scenario: Breach door lockpick minigame
    """
    Checklist test: If a breach door is enabled, target 'Breach Door' and complete the lockpick minigame; disabled by default.
    """
    Given my job is "police"
    And I am on duty
    When I manually: target a door and select 'Breach Door'
    And I manually: complete the lockpick minigame
    Then I should see a notification containing "Door breached."

  @kora_police @checklist @checklist:kora_police:cuffed-restrictions @cat:police-and-ems
  Scenario: Cuffed player restrictions
    """
    Checklist test: While cuffed: no inventory/emote/phone/target eye, weapon holstered, cuffs persist through death, end on relog.
    """
    Given I have a "weapon_pistol" equipped
    When I manually: ask a second player to cuff me
    Then I confirm: my weapon is holstered
    And I confirm: I cannot open my inventory, play emotes, open the phone or use the target eye
    When I manually: die while cuffed and get revived
    Then I confirm: my cuffs persist through death
    When I manually: relog
    Then I confirm: I am no longer cuffed
