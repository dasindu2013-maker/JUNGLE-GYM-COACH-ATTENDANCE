-- One-time repair for the leave-request coach dropdown.
-- Run this in a completely new Supabase SQL Editor query.

create or replace function public.get_leave_cover_coaches()
returns table (
  id uuid,
  full_name text
)
language sql
stable
security definer
set search_path = public
as 'select p.id, p.full_name
    from public.profiles p
    where p.role = ''coach''
      and p.active is not false
      and p.id <> auth.uid()
      and lower(trim(p.full_name)) not like ''randy senevir%''
    order by p.full_name';

revoke all on function public.get_leave_cover_coaches()
from public;

grant execute on function public.get_leave_cover_coaches()
to authenticated;
