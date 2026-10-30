-- Daily quests: the quests finished on a day, one bit for each kind (Cramless/Engine/Quests.swift: finishSession is
-- bit 0 … event is bit 8). The device joins two masks by OR when it merges a day, so the server stores what it is sent;
-- the check only keeps the number to the bits that exist (9 kinds, up to 511, with room for a few more).
--
-- Grants and policies are on the table, so the new column is covered by them.

alter table public.day_records
  add column quest_mask smallint not null default 0 check (quest_mask >= 0 and quest_mask < 1024);
