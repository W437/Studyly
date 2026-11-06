-- Harder questions: a question that replaces an easier one points at it (Cramless/Engine/Ladder.swift). The device resumes the easier
-- question when the harder one is deleted, so the column only records the link; it isn't a foreign key, because a sync can bring
-- the two rows in either order.
--
-- Grants and policies are on the table, so the new column is covered by them.

alter table public.items
  add column rung_of uuid;
