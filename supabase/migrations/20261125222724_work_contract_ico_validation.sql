
-- Server-side validation for Czech IČO identifiers.
create or replace function private.is_valid_czech_ico(p_ico text)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_ico ~ '^[0-9]{8}$' then
      substring(p_ico from 8 for 1)::integer =
        case (
          (
            substring(p_ico from 1 for 1)::integer * 8
            + substring(p_ico from 2 for 1)::integer * 7
            + substring(p_ico from 3 for 1)::integer * 6
            + substring(p_ico from 4 for 1)::integer * 5
            + substring(p_ico from 5 for 1)::integer * 4
            + substring(p_ico from 6 for 1)::integer * 3
            + substring(p_ico from 7 for 1)::integer * 2
          ) % 11
        )
          when 0 then 1
          when 1 then 0
          else 11 - (
            (
              substring(p_ico from 1 for 1)::integer * 8
              + substring(p_ico from 2 for 1)::integer * 7
              + substring(p_ico from 3 for 1)::integer * 6
              + substring(p_ico from 4 for 1)::integer * 5
              + substring(p_ico from 5 for 1)::integer * 4
              + substring(p_ico from 6 for 1)::integer * 3
              + substring(p_ico from 7 for 1)::integer * 2
            ) % 11
          )
        end
    else false
  end;
$$;

revoke all on function private.is_valid_czech_ico(text) from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.agreements'::regclass
      and conname = 'agreements_work_contract_valid_ico'
  ) then
    alter table public.agreements
      add constraint agreements_work_contract_valid_ico
      check (
        contract_data is null
        or template_key is distinct from 'cz_work_contract'
        or (
          (
            contract_data #>> '{orderer,type}' = 'person'
            or (
              contract_data #>> '{orderer,type}' in ('osvc','company')
              and private.is_valid_czech_ico(contract_data #>> '{orderer,ico}')
            )
          )
          and
          (
            contract_data #>> '{contractor,type}' = 'person'
            or (
              contract_data #>> '{contractor,type}' in ('osvc','company')
              and private.is_valid_czech_ico(contract_data #>> '{contractor,ico}')
            )
          )
        )
      ) not valid;
  end if;
end $$;

alter table public.agreements validate constraint agreements_work_contract_valid_ico;
