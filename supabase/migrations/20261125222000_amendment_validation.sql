
-- Require meaningful amendment text and a finite amount for new records.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.amendments'::regclass
      and conname='amendments_description_nonempty'
  ) then
    alter table public.amendments
      add constraint amendments_description_nonempty
      check (length(btrim(description)) between 1 and 10000) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.amendments'::regclass
      and conname='amendments_price_delta_not_nan'
  ) then
    alter table public.amendments
      add constraint amendments_price_delta_not_nan
      check (price_delta <> 'NaN'::numeric) not valid;
  end if;
end $$;
