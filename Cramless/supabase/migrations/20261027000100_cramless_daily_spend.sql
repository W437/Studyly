-- The relay's daily cost cap (supabase/functions/_shared/cost.ts, ai/handler.ts `checkDailyCost`): before each AI request it asks what
-- the person's model calls have cost since their local midnight, and refuses the request once that reaches the cap. ai_requests
-- holds the cost of every call, never content, and its index (user_id, created_at) serves this range. The answer is in whole
-- nano-dollars (a billionth of a dollar), the unit the relay counts money in.

create or replace function public.cramless_spent_since(p_user uuid, p_since timestamptz)
returns bigint
language sql
stable
set search_path = ''
as $$
  select (coalesce(sum(cost_usd), 0) * 1000000000)::bigint
  from public.ai_requests
  where user_id = p_user and created_at >= p_since
$$;

do $$
declare
  f text;
begin
  foreach f in array array['cramless_spent_since(uuid, timestamptz)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end
$$;
