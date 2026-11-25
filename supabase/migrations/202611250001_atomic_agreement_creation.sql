-- Atomic creation of a draft, its first item, and the email invitation.
-- The function runs with the caller's privileges and respects the existing RLS policies.
create or replace function public.create_agreement_with_invite(
  p_title text,
  p_description text,
  p_currency text,
  p_item_description text,
  p_quantity numeric,
  p_unit text,
  p_unit_price numeric,
  p_invitee_email text
) returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Nejprve se přihlas.'; end if;
  if nullif(btrim(p_title), '') is null then raise exception 'Vyplň název dohody.'; end if;
  if nullif(btrim(p_item_description), '') is null then raise exception 'Vyplň položku práce nebo služby.'; end if;
  if p_invitee_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Zadej platný e-mail druhé osoby.'; end if;
  if coalesce(p_quantity,0) <= 0 or coalesce(p_unit_price,-1) < 0 then raise exception 'Množství musí být kladné a cena nesmí být záporná.'; end if;
  insert into public.agreements(title, description, currency, created_by, status)
  values (btrim(p_title), coalesce(p_description,''), upper(coalesce(nullif(btrim(p_currency),''),'CZK')), v_user, 'draft')
  returning id into v_id;
  insert into public.agreement_items(agreement_id, description, quantity, unit, unit_price)
  values (v_id, btrim(p_item_description), p_quantity, coalesce(nullif(btrim(p_unit),''),'ks'), p_unit_price);
  insert into public.agreement_participants(agreement_id, email, role)
  values (v_id, lower(btrim(p_invitee_email)), 'participant');
  update public.agreements set status='shared' where id=v_id;
  return v_id;
end;
$$;
revoke all on function public.create_agreement_with_invite(text,text,text,text,numeric,text,numeric,text) from public, anon;
grant execute on function public.create_agreement_with_invite(text,text,text,text,numeric,text,numeric,text) to authenticated;
