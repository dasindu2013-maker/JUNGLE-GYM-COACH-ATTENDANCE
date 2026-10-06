-- Jungle Gym coach leave request and shift-cover approval workflow.
-- Run this entire file once in the attendance Supabase project's SQL Editor.
-- Safe for existing attendance, payroll, and shift-cover records.

create extension if not exists pgcrypto;

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  coach_id uuid not null references public.profiles(id) on delete cascade,
  leave_date date not null,
  shift_start time not null,
  shift_end time not null,
  covering_coach_id uuid references public.profiles(id) on delete set null,
  coverage_option text not null default 'other'
    check (coverage_option in ('coach', 'other')),
  reason text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'declined')),
  admin_note text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint leave_shift_time_order check (shift_end > shift_start),
  constraint leave_cover_selection check (
    (coverage_option = 'coach' and covering_coach_id is not null)
    or
    (coverage_option = 'other' and covering_coach_id is null)
  ),
  constraint leave_cover_not_self check (
    covering_coach_id is null or covering_coach_id <> coach_id
  )
);

create index if not exists leave_requests_coach_date_idx
  on public.leave_requests (coach_id, leave_date desc);

create index if not exists leave_requests_status_created_idx
  on public.leave_requests (status, created_at desc);

alter table public.leave_requests enable row level security;

drop policy if exists "Coaches can view own leave requests"
  on public.leave_requests;

create policy "Coaches can view own leave requests"
on public.leave_requests
for select
to authenticated
using (coach_id = auth.uid());

drop policy if exists "Admins can view all leave requests"
  on public.leave_requests;

create policy "Admins can view all leave requests"
on public.leave_requests
for select
to authenticated
using (public.is_admin());

alter table public.shift_covers
  add column if not exists leave_request_id uuid
  references public.leave_requests(id) on delete set null;

create unique index if not exists shift_covers_leave_request_unique
  on public.shift_covers (leave_request_id)
  where leave_request_id is not null;

create or replace function public.submit_leave_request(
  p_leave_date date,
  p_shift_start time,
  p_shift_end time,
  p_covering_coach_id uuid default null,
  p_coverage_option text default 'other',
  p_reason text default null
)
returns public.leave_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_record public.leave_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'coach'
      and active is not false
  ) then
    raise exception 'Only an active coach can submit a leave request';
  end if;

  if p_leave_date < (now() at time zone 'Asia/Colombo')::date then
    raise exception 'Leave date cannot be in the past';
  end if;

  if p_shift_start is null or p_shift_end is null
     or p_shift_end <= p_shift_start then
    raise exception 'Shift end time must be later than shift start time';
  end if;

  if p_coverage_option not in ('coach', 'other') then
    raise exception 'Invalid shift-cover selection';
  end if;

  if p_coverage_option = 'coach' then
    if p_covering_coach_id is null then
      raise exception 'Select the coach who will cover the shift';
    end if;

    if p_covering_coach_id = auth.uid() then
      raise exception 'You cannot select yourself as the covering coach';
    end if;

    if not exists (
      select 1
      from public.profiles
      where id = p_covering_coach_id
        and role = 'coach'
        and active is not false
    ) then
      raise exception 'The selected covering coach is not active';
    end if;
  else
    p_covering_coach_id := null;
  end if;

  insert into public.leave_requests (
    coach_id,
    leave_date,
    shift_start,
    shift_end,
    covering_coach_id,
    coverage_option,
    reason
  )
  values (
    auth.uid(),
    p_leave_date,
    p_shift_start,
    p_shift_end,
    p_covering_coach_id,
    p_coverage_option,
    nullif(trim(coalesce(p_reason, '')), '')
  )
  returning * into v_record;

  return v_record;
end;
$$;

create or replace function public.admin_review_leave_request(
  p_request_id uuid,
  p_decision text,
  p_admin_note text default null
)
returns public.leave_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.leave_requests%rowtype;
  v_cover_minutes numeric := 0;
  v_shift_start_at timestamptz;
  v_short_notice boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can review leave requests';
  end if;

  if p_decision not in ('approved', 'declined') then
    raise exception 'Decision must be approved or declined';
  end if;

  select *
  into v_request
  from public.leave_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Leave request was not found';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'This leave request has already been reviewed';
  end if;

  update public.leave_requests
  set status = p_decision,
      admin_note = nullif(trim(coalesce(p_admin_note, '')), ''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = p_request_id
  returning * into v_request;

  if p_decision = 'approved'
     and v_request.coverage_option = 'coach'
     and v_request.covering_coach_id is not null then

    if v_request.shift_start < time '12:00'
       and v_request.shift_end > time '06:00' then
      v_cover_minutes := v_cover_minutes +
        extract(epoch from (
          least(v_request.shift_end, time '12:00') -
          greatest(v_request.shift_start, time '06:00')
        )) / 60;
    end if;

    if v_request.shift_start < time '22:00'
       and v_request.shift_end > time '14:00' then
      v_cover_minutes := v_cover_minutes +
        extract(epoch from (
          least(v_request.shift_end, time '22:00') -
          greatest(v_request.shift_start, time '14:00')
        )) / 60;
    end if;

    if v_cover_minutes <= 0 then
      raise exception 'The requested shift is outside gym operating hours';
    end if;

    v_shift_start_at :=
      (v_request.leave_date::timestamp + v_request.shift_start)
      at time zone 'Asia/Colombo';

    v_short_notice := v_request.created_at >=
      (v_shift_start_at - interval '24 hours');

    insert into public.shift_covers (
      covering_coach_id,
      absent_coach_id,
      cover_date,
      cover_hours,
      short_notice,
      approved,
      notes,
      leave_request_id
    )
    values (
      v_request.covering_coach_id,
      v_request.coach_id,
      v_request.leave_date,
      round(v_cover_minutes / 60, 2),
      v_short_notice,
      true,
      'Automatically added from approved leave request',
      v_request.id
    );
  end if;

  return v_request;
end;
$$;

revoke all on function public.submit_leave_request(
  date, time, time, uuid, text, text
) from public;

grant execute on function public.submit_leave_request(
  date, time, time, uuid, text, text
) to authenticated;

revoke all on function public.admin_review_leave_request(
  uuid, text, text
) from public;

grant execute on function public.admin_review_leave_request(
  uuid, text, text
) to authenticated;
