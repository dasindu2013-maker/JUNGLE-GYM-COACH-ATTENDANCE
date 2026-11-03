-- Jungle Gym: repair Ash and Hamza coach profile setup
-- Run only AFTER both email accounts exist in:
-- Supabase Dashboard > Authentication > Users
--
-- Required Authentication emails:
--   ash@junglegym.lk
--   hamza@junglegym.lk
--
-- This script does not delete or modify existing attendance history.

do $$
declare
  v_missing text;
begin
  select string_agg(required_email, ', ')
    into v_missing
  from (
    values
      ('ash@junglegym.lk'),
      ('hamza@junglegym.lk')
  ) required(required_email)
  where not exists (
    select 1
    from auth.users u
    where lower(trim(u.email)) = required.required_email
  );

  if v_missing is not null then
    raise exception
      'Authentication user(s) missing: %. Create them in Authentication > Users, enable Auto Confirm User, then run this script again.',
      v_missing;
  end if;
end;
$$;

insert into public.profiles (id, full_name, role, active)
select
  u.id,
  case lower(trim(u.email))
    when 'ash@junglegym.lk' then 'Ash'
    when 'hamza@junglegym.lk' then 'Hamza'
  end,
  'coach',
  true
from auth.users u
where lower(trim(u.email)) in (
  'ash@junglegym.lk',
  'hamza@junglegym.lk'
)
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    active = true;

insert into public.coach_payroll_settings (
  coach_id,
  base_salary,
  scheduled_hours_month,
  minimum_attendance_pct,
  overtime_multiplier,
  attendance_bonus_95_pct,
  attendance_bonus_90_pct,
  short_notice_allowance,
  team_support_threshold,
  team_support_bonus,
  active,
  updated_at
)
select
  p.id,
  20000.00,
  156.00,
  70.00,
  1.50,
  10.00,
  5.00,
  500.00,
  3,
  1000.00,
  true,
  now()
from public.profiles p
join auth.users u on u.id = p.id
where lower(trim(u.email)) in (
  'ash@junglegym.lk',
  'hamza@junglegym.lk'
)
on conflict (coach_id) do update
set base_salary = excluded.base_salary,
    scheduled_hours_month = excluded.scheduled_hours_month,
    active = true,
    updated_at = now();

select
  p.full_name,
  u.email,
  p.role,
  p.active,
  cps.base_salary,
  cps.scheduled_hours_month,
  cps.active as payroll_active
from auth.users u
join public.profiles p on p.id = u.id
left join public.coach_payroll_settings cps on cps.coach_id = p.id
where lower(trim(u.email)) in (
  'ash@junglegym.lk',
  'hamza@junglegym.lk'
)
order by p.full_name;
