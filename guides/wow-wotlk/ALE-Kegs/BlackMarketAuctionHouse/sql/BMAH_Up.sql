-- BMAH_Up.sql
-- Dad's MMO Lab ALE-Kegs / BlackMarketAuctionHouse
-- Creates the Black Market Broker NPC (entry 2069430) in acore_world.
--
-- Apply to acore_world:
--   docker exec -i <db-container> mysql -u acore -pacore acore_world < BMAH_Up.sql
--
-- Uses ON DUPLICATE KEY UPDATE so it is safe to re-run:
--   • If entry 2069430 does not exist → inserts a minimal placeholder (gossip-only NPC).
--     You can adjust appearance/model in-game with .npc set model <displayId>.
--   • If entry 2069430 already exists → adds the gossip flag only; nothing else is touched.
--
-- To use a DIFFERENT NPC entry instead:
--   UPDATE creature_template SET npcflag = npcflag | 1 WHERE entry = <your_entry>;

INSERT INTO `creature_template` (`entry`, `name`, `subname`, `npcflag`)
VALUES (2069430, 'Black Market Broker', 'Rare Goods & Services', 1)
ON DUPLICATE KEY UPDATE `npcflag` = `npcflag` | 1;
