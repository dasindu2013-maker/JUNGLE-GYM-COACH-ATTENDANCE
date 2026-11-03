-- Jungle Gym coach account change: November 2026
-- Safe for existing data: no attendance, leave, commission or payroll history is deleted.
--
-- IMPORTANT:
-- 1. In Supabase Dashboard > Authentication > Users, create these users first:
--      ash@junglegym.lk
--      hamza@junglegym.lk
--    Use the temporary passwords supplied privately by the administrator.
-- 2. Then run this entire file in Supabase Dashboard > SQL Editor.
-- 3. Do not put passwords in this SQL file or in GitHub.

-- Block Malika and Harshana from the coach application.
update public.profiles
set active = false
where role = 'coach'
  and (
    lower(trim(full_name)) like 'malika%'
    or lower(trim(full_name)) like 'harshana%'
  );

-- Remove blocked coaches from active payroll processing while preserving history.
update public.coach_payroll_settings cps
set active = false,
    updated_at = now()
from public.profiles p
where p.id = cps.coach_id
  and p.role = 'coach'
  and (
    lower(trim(p.full_name)) like 'malika%'
    or lower(trim(p.full_name)) like 'harshana%'
  );

-- Create or update Ash and Hamza's coach profiles from their Supabase Auth users.
insert into public.profiles (id, full_name, role, active)
select
  u.id,
  case lower(u.email)
    when 'ash@junglegym.lk' then 'Ash'
    when 'hamza@junglegym.lk' then 'Hamza'
  end,
  'coach',
  true
from auth.users u
where lower(u.email) in (
  'ash@junglegym.lk',
  'hamza@junglegym.lk'
)
on conflict (id) do update
set full_name = excluded.full_name,
    role = 'coach',
    active = true;

-- Payroll: Rs. 20,000 basic salary and 156 scheduled hours per month.
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
where p.role = 'coach'
  and lower(trim(p.full_name)) in ('ash', 'hamza')
on conflict (coach_id) do update
set base_salary = excluded.base_salary,
    scheduled_hours_month = excluded.scheduled_hours_month,
    active = true,
    updated_at = now();

-- Verification result.
-- Ash and Hamza will be absent here if their Authentication users were not created first.
select
  p.full_name,
  u.email,
  p.role,
  p.active,
  cps.base_salary,
  cps.scheduled_hours_month,
  cps.active as payroll_active
from public.profiles p
left join auth.users u on u.id = p.id
left join public.coach_payroll_settings cps on cps.coach_id = p.id
where lower(trim(p.full_name)) like 'malika%'
   or lower(trim(p.full_name)) like 'harshana%'
   or lower(trim(p.full_name)) in ('ash', 'hamza')
order by p.full_name;
