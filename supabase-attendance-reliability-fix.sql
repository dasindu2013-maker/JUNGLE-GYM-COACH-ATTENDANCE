-- Jungle Gym attendance reliability and RLS repair
-- Run this entire file once in Supabase Dashboard > SQL Editor.
-- Safe for existing records: it does not delete or rewrite attendance data.

alter table public.attendance enable row level security;

grant select, insert, update on table public.attendance to authenticated;

-- Coaches must be able to read their own records.
drop policy if exists "Coaches can view own attendance"
on public.attendance;

create policy "Coaches can view own attendance"
on public.attendance
for select
to authenticated
using (coach_id = auth.uid());

-- Admin must be able to see every coach record.
drop policy if exists "Admins can view all attendance"
on public.attendance;

create policy "Admins can view all attendance"
on public.attendance
for select
to authenticated
using (public.is_admin());

-- Coaches may create only their own check-in record.
drop policy if exists "Coaches can create own attendance"
on public.attendance;

create policy "Coaches can create own attendance"
on public.attendance
for insert
to authenticated
with check (coach_id = auth.uid());

-- This policy is required for a coach to save checkout details.
-- USING checks ownership of the existing row.
-- WITH CHECK prevents changing the row to another coach.
drop policy if exists "Coaches can update own attendance"
on public.attendance;

create policy "Coaches can update own attendance"
on public.attendance
for update
to authenticated
using (coach_id = auth.uid())
with check (coach_id = auth.uid());

-- Preserve admin correction rights.
drop policy if exists "Admins can insert attendance"
on public.attendance;

create policy "Admins can insert attendance"
on public.attendance
for insert
to authenticated
with check (public.is_admin());

drop policy if exists "Admins can update attendance"
on public.attendance;

create policy "Admins can update attendance"
on public.attendance
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Display the active attendance policies after the repair.
select
  policyname,
  cmd,
  roles,
  qual,
  with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'attendance'
order by policyname;
