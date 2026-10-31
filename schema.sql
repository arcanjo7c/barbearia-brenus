-- BRENNU’S · banco de dados (Supabase). Cole tudo no SQL Editor e clique em Run, uma única vez.
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table public.barbers (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true
);

create table public.services (
  id serial primary key,
  name text not null unique,
  price numeric(10,2) not null,
  minutes int not null,
  from_price boolean not null default false,
  only_days int[],                       -- dias da semana permitidos (0=dom ... 6=sáb); null = todos
  active boolean not null default true
);

-- quem pode entrar no painel: 'owner' (dono, vê tudo) ou 'barber' (vê só os seus)
create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','barber')),
  barber_id uuid references public.barbers(id) on delete set null
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  barber_id uuid not null references public.barbers(id),
  service_id int not null references public.services(id),
  client_name text not null,
  client_phone text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'confirmado' check (status in ('confirmado','concluido','cancelado')),
  payment text check (payment in ('pix','dinheiro','credito','debito')),   -- como o cliente pagou (preenchido ao concluir)
  created_at timestamptz not null default now(),
  check (ends_at > starts_at),
  -- o banco NUNCA aceita dois agendamentos sobrepostos para o mesmo barbeiro
  exclude using gist (barber_id with =, tstzrange(starts_at, ends_at) with &&) where (status <> 'cancelado')
);
create index on public.appointments (barber_id, starts_at);

-- funções auxiliares (usadas nas regras de acesso)
create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from profiles where user_id = auth.uid() and role = 'owner') $$;

create or replace function public.my_barber() returns uuid
language sql stable security definer set search_path = public as
$$ select barber_id from profiles where user_id = auth.uid() $$;

-- permissões explícitas: projetos novos do Supabase NÃO liberam as tabelas para o site automaticamente
grant usage on schema public to anon, authenticated;
grant select on public.barbers, public.services to anon, authenticated;
grant insert, update, delete on public.barbers, public.services to authenticated;   -- as regras abaixo deixam só o dono alterar
grant select on public.profiles to authenticated;
grant usage, select on sequence public.services_id_seq to authenticated;
grant execute on function public.is_owner() to anon, authenticated;                  -- usadas dentro das regras de acesso
grant execute on function public.my_barber() to anon, authenticated;

-- regras de acesso (Row Level Security)
alter table public.barbers enable row level security;
alter table public.services enable row level security;
alter table public.profiles enable row level security;
alter table public.appointments enable row level security;

create policy barbers_ler on public.barbers for select using (true);
create policy barbers_dono on public.barbers for all to authenticated using (is_owner()) with check (is_owner());
create policy services_ler on public.services for select using (true);
create policy services_dono on public.services for all to authenticated using (is_owner()) with check (is_owner());
create policy profiles_proprio on public.profiles for select using (user_id = auth.uid());
create policy ag_ver on public.appointments for select using (is_owner() or barber_id = my_barber());
create policy ag_atualizar on public.appointments for update
  using (is_owner() or barber_id = my_barber()) with check (is_owner() or barber_id = my_barber());

-- ninguém cria nem apaga agendamento direto; só pela função book(). No painel só dá para mudar o status e a forma de pagamento.
revoke all on public.appointments from anon, authenticated;
grant select on public.appointments to authenticated;
grant update (status, payment) on public.appointments to authenticated;

-- horários ocupados de um dia (sem dados do cliente), para o site esconder horários
create or replace function public.busy(p_day date)
returns table (barber_id uuid, starts_at timestamptz, ends_at timestamptz)
language sql stable security definer set search_path = public as
$$ select a.barber_id, a.starts_at, a.ends_at from appointments a
   where a.status <> 'cancelado'
     and a.starts_at >= (p_day::timestamp at time zone 'America/Bahia')
     and a.starts_at <  ((p_day + 1)::timestamp at time zone 'America/Bahia') $$;

-- cria o agendamento (o cliente não precisa de login). p_barber = null → escolhe um barbeiro livre
create or replace function public.book(p_barber uuid, p_service int, p_name text, p_phone text, p_start timestamptz)
returns json language plpgsql security definer set search_path = public as $$
declare sv services%rowtype; v_end timestamptz; v_ini timestamp; v_fim timestamp;
        v_barber uuid; v_id uuid; v_bname text; cand uuid;
begin
  select * into sv from services where id = p_service and active;
  if not found then raise exception 'servico invalido'; end if;
  if length(trim(coalesce(p_name,''))) < 2 or length(regexp_replace(coalesce(p_phone,''), '\D', '', 'g')) < 10 then
    raise exception 'dados invalidos';
  end if;
  if p_start <= now() then raise exception 'horario no passado'; end if;

  v_end := p_start + make_interval(mins => sv.minutes);
  v_ini := p_start at time zone 'America/Bahia';
  v_fim := v_end   at time zone 'America/Bahia';
  -- funciona de segunda a sábado, das 9h às 20h
  if extract(dow from v_ini) = 0 or v_ini::time < time '09:00' or v_fim::time > time '20:00' or v_fim::date <> v_ini::date then
    raise exception 'fora do horario de atendimento';
  end if;
  if sv.only_days is not null and not (extract(dow from v_ini)::int = any (sv.only_days)) then
    raise exception 'servico indisponivel neste dia';
  end if;

  if p_barber is not null then
    if not exists (select 1 from barbers where id = p_barber and active) then raise exception 'barbeiro invalido'; end if;
    v_barber := p_barber;
  else
    for cand in select id from barbers where active order by name loop
      if not exists (select 1 from appointments a where a.barber_id = cand and a.status <> 'cancelado'
                     and tstzrange(a.starts_at, a.ends_at) && tstzrange(p_start, v_end)) then
        v_barber := cand; exit;
      end if;
    end loop;
  end if;
  if v_barber is null then raise exception 'horario ocupado'; end if;

  begin
    insert into appointments (barber_id, service_id, client_name, client_phone, starts_at, ends_at)
    values (v_barber, p_service, trim(p_name), trim(p_phone), p_start, v_end) returning id into v_id;
  exception when exclusion_violation then
    raise exception 'horario ocupado';
  end;

  select name into v_bname from barbers where id = v_barber;
  return json_build_object('id', v_id, 'barber', v_bname);
end $$;

grant execute on function public.busy(date) to anon, authenticated;
grant execute on function public.book(uuid, int, text, text, timestamptz) to anon, authenticated;


-- ===== PRODUTOS, COMANDA E AGENDAMENTO PELO PAINEL =====
create table public.products (
  id serial primary key,
  name text not null unique,
  price numeric(10,2) not null,
  stock int not null default 0 check (stock >= 0),
  active boolean not null default true
);

-- itens extras da comanda (produtos vendidos e serviços adicionais)
create table public.appointment_items (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  product_id int references public.products(id),
  service_id int references public.services(id),
  name text not null,
  price numeric(10,2) not null,
  qty int not null default 1 check (qty > 0)
);

alter table public.products enable row level security;
alter table public.appointment_items enable row level security;
create policy prod_ver on public.products for select to authenticated using (true);
create policy prod_dono on public.products for all to authenticated using (is_owner()) with check (is_owner());
create policy it_ver on public.appointment_items for select to authenticated
  using (is_owner() or exists (select 1 from public.appointments a where a.id = appointment_id and a.barber_id = my_barber()));
revoke all on public.products from anon;
revoke all on public.appointment_items from anon, authenticated;
grant select on public.appointment_items to authenticated;
grant select, insert, update, delete on public.products to authenticated;   -- as regras acima deixam só o dono alterar
grant usage, select on sequence public.products_id_seq to authenticated;

-- adiciona item na comanda; produto desconta do estoque (e recusa se não houver)
create or replace function public.add_item(p_appt uuid, p_product int, p_service int, p_qty int default 1)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments%rowtype; pr products%rowtype; sv services%rowtype;
begin
  select * into a from appointments where id = p_appt;
  if not found or not (is_owner() or a.barber_id = my_barber()) then raise exception 'sem permissao'; end if;
  if a.status = 'cancelado' then raise exception 'comanda cancelada'; end if;
  if p_qty is null or p_qty < 1 then raise exception 'quantidade invalida'; end if;
  if p_product is not null then
    update products set stock = stock - p_qty where id = p_product and active and stock >= p_qty returning * into pr;
    if not found then raise exception 'sem estoque'; end if;
    insert into appointment_items (appointment_id, product_id, name, price, qty) values (p_appt, pr.id, pr.name, pr.price, p_qty);
  else
    select * into sv from services where id = p_service and active;
    if not found then raise exception 'servico invalido'; end if;
    insert into appointment_items (appointment_id, service_id, name, price, qty) values (p_appt, sv.id, sv.name, sv.price, p_qty);
  end if;
end $$;

-- remove item da comanda; produto volta para o estoque
create or replace function public.remove_item(p_item uuid)
returns void language plpgsql security definer set search_path = public as $$
declare it appointment_items%rowtype; a appointments%rowtype;
begin
  select * into it from appointment_items where id = p_item;
  if not found then return; end if;
  select * into a from appointments where id = it.appointment_id;
  if not (is_owner() or a.barber_id = my_barber()) then raise exception 'sem permissao'; end if;
  if it.product_id is not null then update products set stock = stock + it.qty where id = it.product_id; end if;
  delete from appointment_items where id = p_item;
end $$;

-- agendamento feito pelo próprio barbeiro/dono no painel (cliente que chegou na hora, por exemplo)
create or replace function public.book_staff(p_barber uuid, p_service int, p_name text, p_phone text, p_start timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare sv services%rowtype; v_id uuid;
begin
  if not (is_owner() or (p_barber is not null and p_barber = my_barber())) then raise exception 'sem permissao'; end if;
  select * into sv from services where id = p_service and active;
  if not found then raise exception 'servico invalido'; end if;
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'dados invalidos'; end if;
  begin
    insert into appointments (barber_id, service_id, client_name, client_phone, starts_at, ends_at)
    values (p_barber, p_service, trim(p_name), trim(coalesce(p_phone, '')), p_start, p_start + make_interval(mins => sv.minutes))
    returning id into v_id;
  exception when exclusion_violation then
    raise exception 'horario ocupado';
  end;
  return v_id;
end $$;

grant execute on function public.add_item(uuid, int, int, int) to authenticated;
grant execute on function public.remove_item(uuid) to authenticated;
grant execute on function public.book_staff(uuid, int, text, text, timestamptz) to authenticated;

-- dados iniciais
insert into public.barbers (name) values ('Breno'), ('João Paulo'), ('LK'), ('Alison Silva');

insert into public.services (name, price, minutes, from_price, only_days) values
  ('Cabelo', 25, 45, false, null),
  ('Corte de segunda a quarta', 20, 30, false, '{1,2,3}'),
  ('Lavar cabelo', 10, 15, false, null),
  ('Hidratação', 25, 30, false, null),
  ('Pezinho', 7, 15, false, null),
  ('Barba', 15, 15, false, null),
  ('Barbaterapia', 28, 45, false, null),
  ('Luzes', 45, 45, false, null),
  ('Pigmentação', 20, 30, false, null),
  ('Selagem com corte', 65, 120, true, null),
  ('Cabelo + barba', 30, 60, false, null),
  ('Luzes + cabelo + barba', 75, 60, false, null),
  ('Cabelo + luzes + hidratação', 75, 105, false, null),
  ('Cabelo + barba + platinado', 120, 195, false, null),
  ('Limpeza de pele', 70, 45, false, null);

-- produtos (confira os nomes e preços; o estoque começa em zero, o dono ajusta no painel)
insert into public.products (name, price, stock) values
  ('Balm', 30, 0), ('Buxa', 20, 0), ('Gel cola', 15, 0),
  ('Home aromatico', 199, 0), ('Homem helo', 199, 0), ('Maquina acabamento', 140, 0);
