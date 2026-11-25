
-- Prevent a private individual ordering work from a business contractor
-- from being misclassified as a non-consumer contract.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.agreements'::regclass
      and conname = 'agreements_work_contract_consumer_guard'
  ) then
    alter table public.agreements
      add constraint agreements_work_contract_consumer_guard
      check (
        contract_data is null
        or template_key is distinct from 'cz_work_contract'
        or (
          contract_data #>> '{consumer_orderer}' = 'false'
          and not (
            contract_data #>> '{orderer,type}' = 'person'
            and contract_data #>> '{contractor,type}' in ('osvc','company')
          )
        )
      ) not valid;
  end if;
end $$;

alter table public.agreements
  validate constraint agreements_work_contract_consumer_guard;
