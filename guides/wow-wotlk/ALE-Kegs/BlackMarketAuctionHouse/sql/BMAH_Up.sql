-- BMAH_Up.sql
-- Dad's MMO Lab ALE-Kegs / BlackMarketAuctionHouse
-- Creates the Black Market Broker NPC (entry 2069430) in acore_world.
--
-- Apply to acore_world:
--   docker exec -i <db-container> mysql -u acore -pacore acore_world < BMAH_Up.sql
--
-- All statements use INSERT IGNORE / UPDATE so it is safe to re-run.
-- After applying, reload templates in-game (GM): .reload creature_template
-- Then spawn: .npc add 2069430
-- To change appearance: .npc set model <displayId>

-- 1. Create NPC template if it does not exist (no modelid columns — uses creature_template_model).
INSERT IGNORE INTO `creature_template` (`entry`, `name`, `subname`)
VALUES (2069430, 'Black Market Broker', 'Rare Goods & Services');

-- 2. Set faction=35 (Friendly) and gossip npcflag — always applied regardless of above.
UPDATE `creature_template`
    SET `npcflag` = `npcflag` | 1,
        `faction` = 35
WHERE `entry` = 2069430;

-- 3. Display model — newer AzerothCore keeps models in creature_template_model.
--    Display ID 6557 is a standard auctioneer appearance.
--    Safe to change: .npc set model <displayId>  or edit this line and re-run.
INSERT IGNORE INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`)
VALUES (2069430, 0, 6557, 1.0, 1.0, 0);

-- 4. Custom gossip text (ID matches NPC entry to stay unique).
DELETE FROM `npc_text` WHERE `ID` = 2069430;
INSERT INTO `npc_text` (`ID`, `text0_0`, `BroadcastTextID0`, `lang0`, `Probability0`,
    `em0_0`, `em0_1`, `em0_2`, `em0_3`, `em0_4`, `em0_5`)
VALUES (2069430, 'Welcome to the Black Market.$B$BOnly the finest goods, procured at great risk.',
    0, 0, 1, 0, 0, 0, 0, 0, 0);
