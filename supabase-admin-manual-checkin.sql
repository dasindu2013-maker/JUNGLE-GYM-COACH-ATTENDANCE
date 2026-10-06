-- Secure admin-only manual attendance entry.
-- Run this in the attendance Supabase project's SQL Editor.
-- Safe for existing attendance records: it does not delete or rewrite them.

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

drop policy if exists "Admins can update attendance"
on public.attendance;

create policy "Admins can update attendance"
on public.attendance
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.admin_add_attendance_session(
  p_coach_id uuid,
  p_check_in timestamptz,
  p_check_out timestamptz default null,
  p_total_minutes integer default null
)
returns public.attendance
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.attendance%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can add manual attendance';
  end if;

  if p_check_in is null then
    raise exception 'Check-in time is required';
  end if;

  if p_check_in > now() + interval '5 minutes' then
    raise exception 'Check-in time cannot be in the future';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = p_coach_id
      and role = 'coach'
      and active is not false
  ) then
    raise exception 'Please select an active coach';
  end if;

  if p_check_out is not null then
    if p_check_out <= p_check_in then
      raise exception 'Checkout time must be later than check-in time';
    end if;

    if p_check_out > now() + interval '5 minutes' then
      raise exception 'Checkout time cannot be in the future';
    end if;

    insert into public.attendance (
      coach_id,
      check_in_time,
      check_out_time,
      total_minutes,
      status
    )
    values (
      p_coach_id,
      p_check_in,
      p_check_out,
      greatest(coalesce(p_total_minutes, 0), 0),
      'checked_out'
    )
    returning * into v_record;
  else
    if exists (
      select 1
      from public.attendance
      where coach_id = p_coach_id
        and check_out_time is null
    ) then
      raise exception 'This coach already has an open attendance session';
    end if;

    insert into public.attendance (
      coach_id,
      check_in_time,
      status
    )
    values (
      p_coach_id,
      p_check_in,
      'checked_in'
    )
    returning * into v_record;
  end if;

  return v_record;
end;
$$;

revoke all on function public.admin_add_attendance_session(
  uuid, timestamptz, timestamptz, integer
) from public;

grant execute on function public.admin_add_attendance_session(
  uuid, timestamptz, timestamptz, integer
) to authenticated;
