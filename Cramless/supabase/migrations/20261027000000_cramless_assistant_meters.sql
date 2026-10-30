-- Ask Cap's assistant meters (supabase/functions/_shared/plans.ts):
--   'drafts'   what Cap drafts for the student (flashcards, questions, a note, an exam): 3 a day on the free plan;
--   'research' web research, a Pro feature;
--   'rounds'   the rounds of an assistant reply after its first (the first is a 'tutor' message): a reply is one tutor message
--              and up to three more rounds, so the relay refuses a round when 'rounds' would pass three for each 'tutor'
--              message counted that day, which stops a forged request from skipping the tutor meter.
-- usage_counters only accepted the original six, so without this the counters for the new three would be refused.

alter table public.usage_counters drop constraint usage_counters_meter_check;
alter table public.usage_counters add constraint usage_counters_meter_check
  check (meter in ('scans', 'grades', 'tutor', 'lectures', 'extras', 'redeems', 'drafts', 'research', 'rounds'));
