
-- Require explicit warranty mode and post-termination settlement wording for all new work contracts.
-- NOT VALID preserves pre-existing historical rows while enforcing all new and changed rows.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.agreements'::regclass
      and conname='agreements_work_contract_required_terms'
  ) then
    alter table public.agreements
      add constraint agreements_work_contract_required_terms
      check (
        contract_data is null
        or template_key is distinct from 'cz_work_contract'
        or (
          contract_data #>> '{warranty,mode}' in ('none','agreed')
          and nullif(btrim(contract_data #>> '{termination,terms}'),'') is not null
          and (
            contract_data #>> '{warranty,mode}' <> 'agreed'
            or nullif(btrim(contract_data #>> '{warranty,description}'),'') is not null
          )
        )
      ) not valid;
  end if;
end $$;
