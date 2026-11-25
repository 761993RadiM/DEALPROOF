
-- Harden contract creation: all published work contracts must be created through the
-- validated atomic RPC; clients cannot insert or mutate core agreement rows directly.

create or replace function public.create_work_agreement_with_invite(
  p_title text,
  p_description text,
  p_currency text,
  p_contract_data jsonb,
  p_contract_text text,
  p_items jsonb,
  p_invitee_email text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_user uuid := auth.uid();
  v_auth_email text;
  v_email_confirmed boolean;
  v_creator_role text;
  v_creator_email text;
  v_other_email text;
  v_orderer_type text;
  v_contractor_type text;
  v_vat_mode text;
  v_price_mode text;
  v_start_text text;
  v_end_text text;
  v_start_date date;
  v_end_date date;
  v_item jsonb;
  v_description text;
  v_quantity numeric;
  v_unit text;
  v_unit_price numeric;
  v_position integer := 0;
  v_hash text;
begin
  if v_user is null then
    raise exception 'Nejprve se přihlas.';
  end if;

  select lower(btrim(u.email)), (u.email_confirmed_at is not null)
    into v_auth_email, v_email_confirmed
  from auth.users u
  where u.id = v_user;

  if v_auth_email is null or not coalesce(v_email_confirmed,false) then
    raise exception 'Před vytvořením smlouvy musí být potvrzen e-mail účtu.';
  end if;

  if nullif(btrim(p_title), '') is null or char_length(p_title) > 180 then
    raise exception 'Název smlouvy musí mít 1 až 180 znaků.';
  end if;
  if upper(coalesce(p_currency,'')) !~ '^[A-Z]{3}$' then
    raise exception 'Měna musí být zadána jako třípísmenný kód, například CZK.';
  end if;

  if p_contract_data is null or jsonb_typeof(p_contract_data) is distinct from 'object' then
    raise exception 'Chybí strukturované údaje smlouvy.';
  end if;
  if p_contract_data ->> 'template_key' is distinct from 'cz_work_contract'
     or p_contract_data ->> 'template_version' is distinct from '1' then
    raise exception 'Nepodporovaná verze vzoru smlouvy.';
  end if;

  if nullif(btrim(p_contract_text), '') is null
     or char_length(p_contract_text) < 500
     or char_length(p_contract_text) > 50000 then
    raise exception 'Text smlouvy není úplný nebo překračuje povolenou délku.';
  end if;

  if p_items is null or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Rozpočet musí být seznamem položek.';
  end if;
  if jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 100 then
    raise exception 'Smlouva musí obsahovat 1 až 100 rozpočtových položek.';
  end if;

  if coalesce(p_contract_data #>> '{orderer,role}','') <> 'objednatel'
     or coalesce(p_contract_data #>> '{contractor,role}','') <> 'zhotovitel' then
    raise exception 'Role smluvních stran nejsou správně vyplněny.';
  end if;

  v_orderer_type := coalesce(p_contract_data #>> '{orderer,type}','');
  v_contractor_type := coalesce(p_contract_data #>> '{contractor,type}','');
  if v_orderer_type not in ('person','osvc','company')
     or v_contractor_type not in ('person','osvc','company') then
    raise exception 'Vyber správný typ obou smluvních stran.';
  end if;

  if nullif(btrim(p_contract_data #>> '{orderer,name}'), '') is null
     or nullif(btrim(p_contract_data #>> '{orderer,address}'), '') is null
     or nullif(btrim(p_contract_data #>> '{orderer,email}'), '') is null
     or nullif(btrim(p_contract_data #>> '{contractor,name}'), '') is null
     or nullif(btrim(p_contract_data #>> '{contractor,address}'), '') is null
     or nullif(btrim(p_contract_data #>> '{contractor,email}'), '') is null
     or nullif(btrim(p_contract_data #>> '{work,location}'), '') is null
     or nullif(btrim(p_contract_data #>> '{work,scope}'), '') is null
     or nullif(btrim(p_contract_data #>> '{work,quality}'), '') is null
     or nullif(btrim(p_contract_data #>> '{work,materials}'), '') is null
     or nullif(btrim(p_contract_data #>> '{price,payment_schedule}'), '') is null
     or nullif(btrim(p_contract_data #>> '{price,payment_method}'), '') is null
     or nullif(btrim(p_contract_data #>> '{price,payment_due}'), '') is null
     or nullif(btrim(p_contract_data #>> '{handover,place}'), '') is null
     or nullif(btrim(p_contract_data #>> '{handover,rules}'), '') is null
     or nullif(btrim(p_contract_data #>> '{defects,contact}'), '') is null
     or nullif(btrim(p_contract_data #>> '{change_control,rule}'), '') is null then
    raise exception 'Chybí některý povinný údaj stran, díla, ceny, předání nebo změn.';
  end if;

  if v_orderer_type in ('osvc','company')
     and nullif(btrim(p_contract_data #>> '{orderer,ico}'), '') is null then
    raise exception 'U podnikajícího objednatele doplň IČO.';
  end if;
  if v_contractor_type in ('osvc','company')
     and nullif(btrim(p_contract_data #>> '{contractor,ico}'), '') is null then
    raise exception 'U podnikajícího zhotovitele doplň IČO.';
  end if;
  if v_orderer_type = 'company'
     and nullif(btrim(p_contract_data #>> '{orderer,representative}'), '') is null then
    raise exception 'Doplň osobu oprávněnou jednat za objednatele.';
  end if;
  if v_contractor_type = 'company'
     and nullif(btrim(p_contract_data #>> '{contractor,representative}'), '') is null then
    raise exception 'Doplň osobu oprávněnou jednat za zhotovitele.';
  end if;

  if p_contract_data #>> '{consumer_orderer}' is distinct from 'false' then
    raise exception 'Spotřebitelské smlouvy zatím nelze tímto vzorem uzavřít. Jejich zvláštní informační a odstupovací režim musí být doplněn samostatně.';
  end if;

  v_vat_mode := coalesce(p_contract_data #>> '{price,vat_mode}','');
  v_price_mode := coalesce(p_contract_data #>> '{price,mode}','');
  if v_vat_mode not in ('not_payer','included','extra') then
    raise exception 'Vyber platný režim DPH.';
  end if;
  if v_price_mode not in ('fixed','estimate','calculation') then
    raise exception 'Vyber platný způsob určení ceny.';
  end if;

  v_start_text := coalesce(p_contract_data #>> '{schedule,start_date}','');
  v_end_text := coalesce(p_contract_data #>> '{schedule,completion_date}','');
  if v_start_text !~ '^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{4})$'
     or v_end_text !~ '^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{4})$' then
    raise exception 'Vyplň skutečné datum zahájení a dokončení ve formátu DD.MM.RRRR.';
  end if;

  begin
    v_start_date := make_date(
      split_part(v_start_text,'.',3)::integer,
      split_part(v_start_text,'.',2)::integer,
      split_part(v_start_text,'.',1)::integer
    );
    v_end_date := make_date(
      split_part(v_end_text,'.',3)::integer,
      split_part(v_end_text,'.',2)::integer,
      split_part(v_end_text,'.',1)::integer
    );
  exception
    when others then
      raise exception 'Zadané datum neexistuje v kalendáři.';
  end;
  if v_start_date > v_end_date then
    raise exception 'Termín zahájení nesmí být později než termín dokončení.';
  end if;

  v_creator_role := p_contract_data ->> 'creator_role';
  if v_creator_role = 'zhotovitel' then
    v_creator_email := lower(btrim(p_contract_data #>> '{contractor,email}'));
    v_other_email := lower(btrim(p_contract_data #>> '{orderer,email}'));
  elsif v_creator_role = 'objednatel' then
    v_creator_email := lower(btrim(p_contract_data #>> '{orderer,email}'));
    v_other_email := lower(btrim(p_contract_data #>> '{contractor,email}'));
  else
    raise exception 'Není určeno, v jaké roli smlouvu vytváříš.';
  end if;

  if v_creator_email is distinct from v_auth_email then
    raise exception 'E-mail vaší smluvní strany musí odpovídat potvrzenému e-mailu přihlášeného účtu.';
  end if;
  if v_other_email = v_auth_email then
    raise exception 'Obě smluvní strany musí používat rozdílné e-mailové adresy.';
  end if;
  if v_other_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
     or lower(btrim(p_invitee_email)) is distinct from v_other_email then
    raise exception 'E-mail pozvané osoby musí souhlasit s platným e-mailem druhé smluvní strany.';
  end if;

  v_hash := encode(
    extensions.digest(
      convert_to(
        p_contract_text || E'\n' || p_contract_data::text || E'\n' || p_items::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.agreements (
    created_by, title, description, currency, status,
    template_key, contract_data, contract_text, content_hash
  )
  values (
    v_user, btrim(p_title), coalesce(p_description,''),
    upper(p_currency), 'draft',
    'cz_work_contract', p_contract_data, p_contract_text, v_hash
  )
  returning id into v_id;

  for v_item in select value from jsonb_array_elements(p_items) as t(value)
  loop
    if jsonb_typeof(v_item) is distinct from 'object' then
      raise exception 'Každá rozpočtová položka musí být objekt s popisem, množstvím, jednotkou a cenou.';
    end if;

    v_description := nullif(btrim(v_item ->> 'description'), '');
    v_quantity := (v_item ->> 'quantity')::numeric;
    v_unit := nullif(btrim(v_item ->> 'unit'), '');
    v_unit_price := (v_item ->> 'unit_price')::numeric;

    if v_description is null or char_length(v_description) > 5000
       or v_quantity is null or v_quantity <= 0
       or v_quantity::text in ('NaN','Infinity','-Infinity')
       or v_unit is null or char_length(v_unit) > 40
       or v_unit_price is null or v_unit_price < 0
       or v_unit_price::text in ('NaN','Infinity','-Infinity') then
      raise exception 'Každá položka musí mít popis, kladné konečné množství, jednotku a nezápornou konečnou cenu.';
    end if;

    insert into public.agreement_items (
      agreement_id, description, quantity, unit, unit_price, position
    )
    values (v_id, v_description, v_quantity, v_unit, v_unit_price, v_position);

    v_position := v_position + 1;
  end loop;

  insert into public.agreement_participants (agreement_id, email, role)
  values (v_id, v_other_email, 'participant');

  insert into public.agreement_versions (
    agreement_id, version_no, template_key, contract_data,
    contract_text, content_hash, created_by
  )
  values (v_id, 1, 'cz_work_contract', p_contract_data, p_contract_text, v_hash, v_user);

  update public.agreements
     set status = 'shared'
   where id = v_id;

  return v_id;
end;
$$;

revoke all on function public.create_work_agreement_with_invite(text,text,text,jsonb,text,jsonb,text)
  from public, anon;
grant execute on function public.create_work_agreement_with_invite(text,text,text,jsonb,text,jsonb,text)
  to authenticated;

-- Retire the older generic creation RPC: it does not create a version snapshot.
drop function if exists public.create_agreement_with_invite(text,text,text,text,numeric,text,numeric,text);

-- A client cannot bypass the validated RPC by writing directly to core tables.
revoke insert, update on public.agreements from authenticated;
revoke insert, update, delete on public.agreement_items from authenticated;
revoke insert, update, delete on public.agreement_participants from authenticated;
revoke insert, update, delete on public.agreement_versions from authenticated;

-- Leave only read access to contract rows; trigger/RPC owners perform protected writes.
grant select on public.agreements to authenticated;
grant select on public.agreement_items to authenticated;
grant select on public.agreement_participants to authenticated;
grant select on public.agreement_versions to authenticated;

drop policy if exists agreement_insert on public.agreements;
drop policy if exists agreement_update on public.agreements;
