-- Allow an authenticated admin to create an attendance session
-- for a coach from the admin dashboard.
--
-- Run this once in Supabase Dashboard > SQL Editor.
-- The public.is_admin() function must already exist.

drop policy if exists "Coaches can create their attendance"
on public.attendance;

drop policy if exists "Coaches and admins can create attendance"
on public.attendance;

create policy "Coaches and admins can create attendance"
on public.attendance
for insert
to authenticated
with check (
  coach_id = auth.uid()
  or public.is_admin()
);
