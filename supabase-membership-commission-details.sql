-- Adds member details to membership commission records.
-- Safe to run on the existing attendance database: no rows are deleted.

alter table public.membership_commissions
  add column if not exists member_name text,
  add column if not exists nic_number text;

create or replace function public.sync_membership_commission(
  p_secret text,
  p_row jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_expected_hash text;
  v_source_key text;
  v_receipt text;
  v_staff text;
  v_member_name text;
  v_nic_number text;
  v_paid numeric(12,2);
  v_is_free boolean;
  v_commission numeric(12,2);
begin
  select secret_hash
    into v_expected_hash
  from public.integration_secrets
  where service_name = 'membership_commission';

  if v_expected_hash is null
     or encode(digest(coalesce(p_secret, ''), 'sha256'), 'hex') <> v_expected_hash then
    raise exception 'Invalid membership commission sync secret';
  end if;

  v_source_key := nullif(trim(p_row ->> 'source_key'), '');
  v_receipt := nullif(trim(p_row ->> 'receipt_number'), '');
  v_staff := nullif(trim(p_row ->> 'staff_name'), '');
  v_member_name := nullif(trim(p_row ->> 'member_name'), '');
  v_nic_number := nullif(trim(p_row ->> 'nic_number'), '');
  v_paid := greatest(coalesce((p_row ->> 'paid_amount')::numeric, 0), 0);
  v_is_free := lower(coalesce(v_receipt, '')) = 'free';
  v_commission := case
    when v_is_free then 0
    else round(v_paid * 0.10, 2)
  end;

  if v_source_key is null or v_receipt is null or v_staff is null then
    raise exception 'Missing required membership commission fields';
  end if;

  insert into public.membership_commissions (
    source_key,
    receipt_number,
    member_name,
    nic_number,
    registration_type,
    payment_date,
    staff_name,
    paid_amount,
    commission_rate,
    commission_amount,
    is_free,
    updated_at
  )
  values (
    v_source_key,
    v_receipt,
    v_member_name,
    v_nic_number,
    coalesce(nullif(trim(p_row ->> 'registration_type'), ''), 'Unknown'),
    (p_row ->> 'payment_date')::date,
    v_staff,
    v_paid,
    0.10,
    v_commission,
    v_is_free,
    now()
  )
  on conflict (source_key) do update set
    receipt_number = excluded.receipt_number,
    member_name = excluded.member_name,
    nic_number = excluded.nic_number,
    registration_type = excluded.registration_type,
    payment_date = excluded.payment_date,
    staff_name = excluded.staff_name,
    paid_amount = excluded.paid_amount,
    commission_rate = excluded.commission_rate,
    commission_amount = excluded.commission_amount,
    is_free = excluded.is_free,
    updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'commission_amount', v_commission,
    'is_free', v_is_free
  );
end;
$$;

revoke all on function public.sync_membership_commission(text, jsonb)
  from public;
grant execute on function public.sync_membership_commission(text, jsonb)
  to anon, authenticated;
