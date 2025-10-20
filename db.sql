
-- ============================================================
-- Supabase SQL: Personnel module split into dedicated tables
-- employees, positions, workplaces, terminals and relation tables.
-- Includes views for convenient reading (with arrays of relation ids),
-- RLS policies, and default seeds.
-- Safe to run multiple times.
-- ============================================================

do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pgcrypto') then
    raise exception 'Extension "pgcrypto" must be enabled before running this script. Use Supabase project settings → Database → Extensions.';
  end if;
  if not exists (select 1 from pg_extension where extname = 'uuid-ossp') then
    raise exception 'Extension "uuid-ossp" must be enabled before running this script. Use Supabase project settings → Database → Extensions.';
  end if;
end;
$$;

-- Supabase does not grant pg_read_file() privileges to non-superusers, so the script avoids
-- running CREATE EXTENSION commands directly. Ensure the required extensions above are enabled
-- from the dashboard before executing the remainder of this file.

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

-- ============================================================
-- POSITIONS
-- ============================================================
create table if not exists public.positions (
  id          text primary key,
  name        text not null unique,
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);
drop trigger if exists trg_positions_updated_at on public.positions;
create trigger trg_positions_updated_at before update on public.positions
for each row execute function public.set_updated_at();
alter table public.positions enable row level security;

-- ============================================================
-- EMPLOYEES + M:N with positions
-- ============================================================
create table if not exists public.employees (
  id          text primary key,
  last_name   text not null,
  first_name  text not null,
  patronymic  text not null,
  iin         text not null unique,
  photo_url   text,
  is_fired    boolean not null default false,
  comments    text,
  login       text unique,
  password    text, -- NOTE: currently plain text for compatibility. Consider hashing later.
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);
drop trigger if exists trg_employees_updated_at on public.employees;
create trigger trg_employees_updated_at before update on public.employees
for each row execute function public.set_updated_at();
alter table public.employees enable row level security;

create table if not exists public.employee_positions (
  employee_id text not null references public.employees(id) on delete cascade,
  position_id text not null references public.positions(id) on delete restrict,
  created_at  timestamptz not null default now(),
  primary key (employee_id, position_id)
);
alter table public.employee_positions enable row level security;

-- Convenient view with aggregated position ids
create or replace view public.employees_view as
select
  e.id,
  e.last_name,
  e.first_name,
  e.patronymic,
  e.iin,
  e.photo_url,
  e.is_fired,
  e.comments,
  e.login,
  e.password,
  e.created_at,
  e.updated_at,
  coalesce(array_agg(ep.position_id) filter (where ep.position_id is not null), '{}') as position_ids
from public.employees e
left join public.employee_positions ep on ep.employee_id = e.id
group by e.id;

-- ============================================================
-- WORKPLACES + M:N with positions
-- ============================================================
create table if not exists public.workplaces (
  id          text primary key,
  name        text not null unique,
  description text,
  has_machine boolean not null default false,
  max_concurrent_workers int not null default 1,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);
drop trigger if exists trg_workplaces_updated_at on public.workplaces;
create trigger trg_workplaces_updated_at before update on public.workplaces
for each row execute function public.set_updated_at();
alter table public.workplaces enable row level security;

create table if not exists public.workplace_positions (
  workplace_id text not null references public.workplaces(id) on delete cascade,
  position_id  text not null references public.positions(id) on delete restrict,
  created_at   timestamptz not null default now(),
  primary key (workplace_id, position_id)
);
alter table public.workplace_positions enable row level security;

create or replace view public.workplaces_view as
select
  w.id,
  w.name,
  w.description,
  w.has_machine,
  w.max_concurrent_workers,
  w.created_at,
  w.updated_at,
  coalesce(array_agg(wp.position_id) filter (where wp.position_id is not null), '{}') as position_ids
from public.workplaces w
left join public.workplace_positions wp on wp.workplace_id = w.id
group by w.id;

-- ============================================================
-- TERMINALS + M:N with workplaces
-- ============================================================
create table if not exists public.terminals (
  id          text primary key,
  name        text not null unique,
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);
drop trigger if exists trg_terminals_updated_at on public.terminals;
create trigger trg_terminals_updated_at before update on public.terminals
for each row execute function public.set_updated_at();
alter table public.terminals enable row level security;

create table if not exists public.terminal_workplaces (
  terminal_id  text not null references public.terminals(id) on delete cascade,
  workplace_id text not null references public.workplaces(id) on delete restrict,
  created_at   timestamptz not null default now(),
  primary key (terminal_id, workplace_id)
);
alter table public.terminal_workplaces enable row level security;

create or replace view public.terminals_view as
select
  t.id,
  t.name,
  t.description,
  t.created_at,
  t.updated_at,
  coalesce(array_agg(tw.workplace_id) filter (where tw.workplace_id is not null), '{}') as workplace_ids
from public.terminals t
left join public.terminal_workplaces tw on tw.terminal_id = t.id
group by t.id;

-- ============================================================
-- BASIC RLS (open to any authenticated user). Tighten later if needed.
-- ============================================================
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='positions' and policyname='positions_ro') then
    create policy positions_ro on public.positions for select to authenticated using (true);
    create policy positions_rw on public.positions for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='employees' and policyname='employees_ro') then
    create policy employees_ro on public.employees for select to authenticated using (true);
    create policy employees_rw on public.employees for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='employee_positions' and policyname='employee_positions_ro') then
    create policy employee_positions_ro on public.employee_positions for select to authenticated using (true);
    create policy employee_positions_rw on public.employee_positions for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='workplaces' and policyname='workplaces_ro') then
    create policy workplaces_ro on public.workplaces for select to authenticated using (true);
    create policy workplaces_rw on public.workplaces for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='workplace_positions' and policyname='workplace_positions_ro') then
    create policy workplace_positions_ro on public.workplace_positions for select to authenticated using (true);
    create policy workplace_positions_rw on public.workplace_positions for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='terminals' and policyname='terminals_ro') then
    create policy terminals_ro on public.terminals for select to authenticated using (true);
    create policy terminals_rw on public.terminals for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='terminal_workplaces' and policyname='terminal_workplaces_ro') then
    create policy terminal_workplaces_ro on public.terminal_workplaces for select to authenticated using (true);
    create policy terminal_workplaces_rw on public.terminal_workplaces for all to authenticated using (true) with check (true);
  end if;
end $$;

-- ============================================================
-- DEFAULT SEEDS (id + name) for positions and workplaces
-- ============================================================

-- Positions
insert into public.positions (id, name)
values
  ('bob_cutter','Бобинорезчик'),
  ('print','Печатник'),
  ('cut_sheet','Листорезчик'),
  ('bag_collector','Пакетосборщик'),
  ('cutter','Резчик'),
  ('bottom_gluer','Дносклейщик'),
  ('handle_gluer','Склейщик ручек'),
  ('die_cutter','Оператор высечки'),
  ('assembler','Сборщик'),
  ('rope_operator','Оператор веревок'),
  ('handle_operator','Оператор ручек'),
  ('muffin_operator','Оператор маффинов'),
  ('single_point_gluer','Склейка одной точки'),
  ('manager','Менеджер'),
  ('warehouse_head','Заведующий складом')
on conflict (id) do nothing;

-- Workplaces
insert into public.workplaces (id, name, has_machine, max_concurrent_workers)
values
  ('w_bobiner','Бобинорезка', false, 1),
  ('w_flexoprint','Флексопечать', false, 1),
  ('w_sheet_old','Листорезка 1 (старая)', false, 1),
  ('w_sheet_new','Листорезка 2 (новая)', false, 1),
  ('w_auto_p_assembly','Автоматическая П-сборка', false, 1),
  ('w_auto_p_pipe','Автоматическая П-сборка (труба)', false, 1),
  ('w_auto_v1','Автоматическая В-сборка 1 (фри, уголки)', false, 1),
  ('w_auto_v2','Автоматическая В-сборка 2 (окошко)', false, 1),
  ('w_cutting','Резка', false, 1),
  ('w_bottom_glue_cold','Холодная дно-склейка', false, 1),
  ('w_bottom_glue_hot','Горячая дно-склейка', false, 1),
  ('w_handle_glue_auto','Автоматическая ручка-склейка', false, 1),
  ('w_handle_glue_semi','Полуавтоматическая ручка-склейка', false, 1),
  ('w_die_cut_a1','Высечка A1', false, 1),
  ('w_die_cut_a2','Высечка A2', false, 1),
  ('w_tape_glue','Приклейка скотча', false, 1),
  ('w_two_sheet','Сборка с 2-х листов', false, 1),
  ('w_pipe_assembly','Сборка трубы', false, 1),
  ('w_bottom_card','Сборка дна + картон', false, 1),
  ('w_bottom_glue_manual','Склейка дна (ручная)', false, 1),
  ('w_card_laying','Укладка картона на дно', false, 1),
  ('w_rope_maker','Изготовление верёвок (2 шт.)', false, 1),
  ('w_rope_reel','Перемотка верёвок в бухты', false, 1),
  ('w_handle_maker','Станок для изготовления ручек', false, 1),
  ('w_press','Пресс', false, 1),
  ('w_tart_maker','Станок для изготовления тарталеток', false, 1),
  ('w_muffin_bord','Станок для маффинов с бортиками', false, 1),
  ('w_muffin_no_bord','Станок для маффинов без бортиков', false, 1),
  ('w_tulip_maker','Станок для изготовления тюльпанов', false, 1),
  ('w_single_point','Склейка одной точки', false, 1)
on conflict (id) do nothing;

-- Workplace allowed positions mapping
insert into public.workplace_positions (workplace_id, position_id)
values
  ('w_bobiner','bob_cutter'),
  ('w_flexoprint','print'),
  ('w_sheet_old','cut_sheet'),
  ('w_sheet_new','cut_sheet'),
  ('w_auto_p_assembly','bag_collector'),
  ('w_auto_p_pipe','bag_collector'),
  ('w_auto_v1','bag_collector'),
  ('w_auto_v2','bag_collector'),
  ('w_cutting','cutter'),
  ('w_bottom_glue_cold','bottom_gluer'),
  ('w_bottom_glue_hot','bottom_gluer'),
  ('w_handle_glue_auto','handle_gluer'),
  ('w_handle_glue_semi','handle_gluer'),
  ('w_die_cut_a1','die_cutter'),
  ('w_die_cut_a2','die_cutter'),
  ('w_tape_glue','assembler'),
  ('w_two_sheet','assembler'),
  ('w_pipe_assembly','assembler'),
  ('w_bottom_card','assembler'),
  ('w_bottom_glue_manual','assembler'),
  ('w_card_laying','assembler'),
  ('w_rope_maker','rope_operator'),
  ('w_rope_reel','rope_operator'),
  ('w_handle_maker','handle_operator'),
  ('w_press','cutter'),
  ('w_tart_maker','muffin_operator'),
  ('w_muffin_bord','muffin_operator'),
  ('w_muffin_no_bord','muffin_operator'),
  ('w_tulip_maker','muffin_operator'),
  ('w_single_point','single_point_gluer')
on conflict (workplace_id, position_id) do nothing;

-- NOTE: Create a storage bucket named 'employee_photos' in Supabase Storage,
-- and make it public or add policies as needed for your app.
-------------------------------------------------------------------------------------------------------------------------------
-- 1) Должность "Технический лидер"
insert into public.positions (id, name)
values ('tech_leader', 'Технический лидер')
on conflict (id) do nothing;

-- 2) Сотрудник "Технический лидер" (правь ФИО/ИИН/логин/пароль по необходимости)
--   добавим только если такого ещё нет ни по id, ни по ИИН
with ins as (
  select
    'techlead-1'::text   as id,
    'Иванов'::text       as last_name,
    'Иван'::text         as first_name,
    'Иванович'::text     as patronymic,
    '999999999999'::text as iin,               -- Укажи реальный ИИН (у нас стоит заглушка)
    null::text           as photo_url,
    false::boolean       as is_fired,
    'Технический лидер'::text as comments,
    'techlead'::text     as login,
    '1234'::text         as password
)
insert into public.employees (id,last_name,first_name,patronymic,iin,photo_url,is_fired,comments,login,password)
select id,last_name,first_name,patronymic,iin,photo_url,is_fired,comments,login,password
from ins
where not exists (
  select 1 from public.employees e
  where e.id = (select id from ins) or e.iin = (select iin from ins)
);

-- 3) Связка сотрудника с должностью "tech_leader"
insert into public.employee_positions (employee_id, position_id)
select 'techlead-1', 'tech_leader'
where exists (select 1 from public.employees where id='techlead-1')
  and exists (select 1 from public.positions  where id='tech_leader')
  and not exists (
    select 1 from public.employee_positions
    where employee_id='techlead-1' and position_id='tech_leader'
  );

-- 4) Таблица ролей (если её ещё нет)
create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_admin boolean not null default false,
  roles text[] not null default '{}'::text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_user_roles_updated_at on public.user_roles;
create trigger trg_user_roles_updated_at
  before update on public.user_roles
  for each row execute function public.set_updated_at();
alter table public.user_roles enable row level security;

-- 5) Выдать админ-права техлиду по email из auth.users
--    ВСТАВЬ СВОЙ EMAIL НИЖЕ вместо YOUR_EMAIL@EXAMPLE.COM
insert into public.user_roles (user_id, is_admin, roles)
select
  au.id as user_id,
  true  as is_admin,
  case
    when 'tech_leader' = any(coalesce(ur.roles,'{}'::text[]))
    then coalesce(ur.roles,'{}'::text[])
    else array_append(coalesce(ur.roles,'{}'::text[]), 'tech_leader')
  end as roles
from auth.users au
left join public.user_roles ur on ur.user_id = au.id
where au.email = 'YOUR_EMAIL@EXAMPLE.COM'
on conflict (user_id) do update
set is_admin = true,
    roles = case
      when 'tech_leader' = any(public.user_roles.roles)
      then public.user_roles.roles
      else array_append(public.user_roles.roles, 'tech_leader')
    end;
----------------------------------------------------------------------------------------------------------------------
alter table public.positions enable row level security;
drop policy if exists positions_select_all on public.positions;
create policy positions_select_all on public.positions
for select to anon, authenticated using (true);

drop policy if exists positions_write_all on public.positions;
create policy positions_write_all on public.positions
for all to authenticated using (true) with check (true);
-- при необходимости добавить и anon в "to ..."
------------------------------------------------------------------------------------------------------------------------------
-- ВАЖНО: включаем RLS на всех таблицах
alter table public.positions            enable row level security;
alter table public.employees            enable row level security;
alter table public.employee_positions   enable row level security;
alter table public.workplaces           enable row level security;
alter table public.workplace_positions  enable row level security;
alter table public.terminals            enable row level security;
alter table public.terminal_workplaces  enable row level security;

-- Полезное условие (вставляется в политики ниже):
-- EXISTS (select 1 from public.user_roles ur
--         where ur.user_id = auth.uid()
--           and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[]))))

/* ========== POSITIONS ========== */
drop policy if exists positions_select_auth  on public.positions;
create policy positions_select_auth  on public.positions
for select to authenticated
using (true);

drop policy if exists positions_insert_admin on public.positions;
create policy positions_insert_admin on public.positions
for insert to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists positions_update_admin on public.positions;
create policy positions_update_admin on public.positions
for update to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists positions_delete_admin on public.positions;
create policy positions_delete_admin on public.positions
for delete to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

/* ========== EMPLOYEES ========== */
drop policy if exists employees_select_auth  on public.employees;
create policy employees_select_auth  on public.employees
for select to authenticated
using (true);

drop policy if exists employees_insert_admin on public.employees;
create policy employees_insert_admin on public.employees
for insert to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists employees_update_admin on public.employees;
create policy employees_update_admin on public.employees
for update to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists employees_delete_admin on public.employees;
create policy employees_delete_admin on public.employees
for delete to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

/* ========== EMPLOYEE_POSITIONS ========== */
drop policy if exists emp_pos_select_auth  on public.employee_positions;
create policy emp_pos_select_auth  on public.employee_positions
for select to authenticated
using (true);

drop policy if exists emp_pos_insert_admin on public.employee_positions;
create policy emp_pos_insert_admin on public.employee_positions
for insert to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists emp_pos_update_admin on public.employee_positions;
create policy emp_pos_update_admin on public.employee_positions
for update to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists emp_pos_delete_admin on public.employee_positions;
create policy emp_pos_delete_admin on public.employee_positions
for delete to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

/* ========== WORKPLACES ========== */
drop policy if exists workplaces_select_auth  on public.workplaces;
create policy workplaces_select_auth  on public.workplaces
for select to authenticated
using (true);

drop policy if exists workplaces_insert_admin on public.workplaces;
create policy workplaces_insert_admin on public.workplaces
for insert to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists workplaces_update_admin on public.workplaces;
create policy workplaces_update_admin on public.workplaces
for update to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists workplaces_delete_admin on public.workplaces;
create policy workplaces_delete_admin on public.workplaces
for delete to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

/* ========== WORKPLACE_POSITIONS ========== */
drop policy if exists wp_pos_select_auth  on public.workplace_positions;
create policy wp_pos_select_auth  on public.workplace_positions
for select to authenticated
using (true);

drop policy if exists wp_pos_insert_admin on public.workplace_positions;
create policy wp_pos_insert_admin on public.workplace_positions
for insert to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists wp_pos_update_admin on public.workplace_positions;
create policy wp_pos_update_admin on public.workplace_positions
for update to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists wp_pos_delete_admin on public.workplace_positions;
create policy wp_pos_delete_admin on public.workplace_positions
for delete to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

/* ========== TERMINALS ========== */
drop policy if exists terminals_select_auth  on public.terminals;
create policy terminals_select_auth  on public.terminals
for select to authenticated
using (true);

drop policy if exists terminals_insert_admin on public.terminals;
create policy terminals_insert_admin on public.terminals
for insert to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists terminals_update_admin on public.terminals;
create policy terminals_update_admin on public.terminals
for update to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists terminals_delete_admin on public.terminals;
create policy terminals_delete_admin on public.terminals
for delete to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

/* ========== TERMINAL_WORKPLACES ========== */
drop policy if exists term_wp_select_auth  on public.terminal_workplaces;
create policy term_wp_select_auth  on public.terminal_workplaces
for select to authenticated
using (true);

drop policy if exists term_wp_insert_admin on public.terminal_workplaces;
create policy term_wp_insert_admin on public.terminal_workplaces
for insert to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists term_wp_update_admin on public.terminal_workplaces;
create policy term_wp_update_admin on public.terminal_workplaces
for update to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

drop policy if exists term_wp_delete_admin on public.terminal_workplaces;
create policy term_wp_delete_admin on public.terminal_workplaces
for delete to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);
--------------------------------------------------------------------------------------------------------------------
alter table public.workplace_positions enable row level security;

-- читать могут все залогиненные
drop policy if exists wp_pos_select_auth on public.workplace_positions;
create policy wp_pos_select_auth on public.workplace_positions
for select to authenticated
using (true);

-- вставка: только админ/техлид (только WITH CHECK!)
drop policy if exists wp_pos_insert_admin on public.workplace_positions;
create policy wp_pos_insert_admin on public.workplace_positions
for insert to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin OR 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

-- обновление
drop policy if exists wp_pos_update_admin on public.workplace_positions;
create policy wp_pos_update_admin on public.workplace_positions
for update to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin OR 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin OR 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

-- удаление
drop policy if exists wp_pos_delete_admin on public.workplace_positions;
create policy wp_pos_delete_admin on public.workplace_positions
for delete to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin OR 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);
--------------------------------------------------------------------------------------------------------------------------
alter table public.workplace_positions enable row level security;

-- Читать: всем залогиненным
drop policy if exists wp_pos_select_auth on public.workplace_positions;
create policy wp_pos_select_auth
on public.workplace_positions
for select
to authenticated
using (true);

-- Вставка: только админ/техлид
drop policy if exists wp_pos_insert_admin on public.workplace_positions;
create policy wp_pos_insert_admin
on public.workplace_positions
for insert
to authenticated
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

-- Обновление
drop policy if exists wp_pos_update_admin on public.workplace_positions;
create policy wp_pos_update_admin
on public.workplace_positions
for update
to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
)
with check (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);

-- Удаление
drop policy if exists wp_pos_delete_admin on public.workplace_positions;
create policy wp_pos_delete_admin
on public.workplace_positions
for delete
to authenticated
using (
  exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid()
      and (ur.is_admin or 'tech_leader' = any(coalesce(ur.roles,'{}'::text[])))
  )
);
-------------------------------------------------------------------------------------------------------------------------
-- WORKPLACE_POSITIONS
alter table public.workplace_positions enable row level security;

drop policy if exists wp_pos_select_any on public.workplace_positions;
drop policy if exists wp_pos_insert_any on public.workplace_positions;
drop policy if exists wp_pos_update_any on public.workplace_positions;
drop policy if exists wp_pos_delete_any on public.workplace_positions;

create policy wp_pos_select_any
on public.workplace_positions
for select
to anon, authenticated
using (true);

-- ВАЖНО: для INSERT допускается только WITH CHECK
create policy wp_pos_insert_any
on public.workplace_positions
for insert
to anon, authenticated
with check (true);

create policy wp_pos_update_any
on public.workplace_positions
for update
to anon, authenticated
using (true)
with check (true);

create policy wp_pos_delete_any
on public.workplace_positions
for delete
to anon, authenticated
using (true);

-- EMPLOYEE_POSITIONS (на будущее, чтобы не встретить ту же ошибку)
alter table public.employee_positions enable row level security;

drop policy if exists emp_pos_select_any on public.employee_positions;
drop policy if exists emp_pos_insert_any on public.employee_positions;
drop policy if exists emp_pos_update_any on public.employee_positions;
drop policy if exists emp_pos_delete_any on public.employee_positions;

create policy emp_pos_select_any
on public.employee_positions
for select
to anon, authenticated
using (true);

create policy emp_pos_insert_any
on public.employee_positions
for insert
to anon, authenticated
with check (true);

create policy emp_pos_update_any
on public.employee_positions
for update
to anon, authenticated
using (true)
with check (true);

create policy emp_pos_delete_any
on public.employee_positions
for delete
to anon, authenticated
using (true);

-- TERMINAL_WORKPLACES (аналогично)
alter table public.terminal_workplaces enable row level security;

drop policy if exists term_wp_select_any on public.terminal_workplaces;
drop policy if exists term_wp_insert_any on public.terminal_workplaces;
drop policy if exists term_wp_update_any on public.terminal_workplaces;
drop policy if exists term_wp_delete_any on public.terminal_workplaces;

create policy term_wp_select_any
on public.terminal_workplaces
for select
to anon, authenticated
using (true);

create policy term_wp_insert_any
on public.terminal_workplaces
for insert
to anon, authenticated
with check (true);

create policy term_wp_update_any
on public.terminal_workplaces
for update
to anon, authenticated
using (true)
with check (true);

create policy term_wp_delete_any
on public.terminal_workplaces
for delete
to anon, authenticated
using (true);
------------------------------------------------------------------------------------------------------------------
-- === Включаем RLS на всех таблицах модуля ===
alter table public.positions            enable row level security;
alter table public.employees            enable row level security;
alter table public.employee_positions   enable row level security;
alter table public.workplaces           enable row level security;
alter table public.workplace_positions  enable row level security;
alter table public.terminals            enable row level security;
alter table public.terminal_workplaces  enable row level security;

-- =======================
-- POSITIONS
-- =======================
drop policy if exists positions_sel_any on public.positions;
drop policy if exists positions_ins_any on public.positions;
drop policy if exists positions_upd_any on public.positions;
drop policy if exists positions_del_any on public.positions;

create policy positions_sel_any
on public.positions
for select to anon, authenticated
using (true);

create policy positions_ins_any
on public.positions
for insert to anon, authenticated
with check (true);          -- INSERT: только WITH CHECK!

create policy positions_upd_any
on public.positions
for update to anon, authenticated
using (true) with check (true);

create policy positions_del_any
on public.positions
for delete to anon, authenticated
using (true);

-- =======================
-- EMPLOYEES
-- =======================
drop policy if exists employees_sel_any on public.employees;
drop policy if exists employees_ins_any on public.employees;
drop policy if exists employees_upd_any on public.employees;
drop policy if exists employees_del_any on public.employees;

create policy employees_sel_any
on public.employees
for select to anon, authenticated
using (true);

create policy employees_ins_any
on public.employees
for insert to anon, authenticated
with check (true);

create policy employees_upd_any
on public.employees
for update to anon, authenticated
using (true) with check (true);

create policy employees_del_any
on public.employees
for delete to anon, authenticated
using (true);

-- =======================
-- EMPLOYEE_POSITIONS (M:N)
-- =======================
drop policy if exists emp_pos_sel_any on public.employee_positions;
drop policy if exists emp_pos_ins_any on public.employee_positions;
drop policy if exists emp_pos_upd_any on public.employee_positions;
drop policy if exists emp_pos_del_any on public.employee_positions;

create policy emp_pos_sel_any
on public.employee_positions
for select to anon, authenticated
using (true);

create policy emp_pos_ins_any
on public.employee_positions
for insert to anon, authenticated
with check (true);

create policy emp_pos_upd_any
on public.employee_positions
for update to anon, authenticated
using (true) with check (true);

create policy emp_pos_del_any
on public.employee_positions
for delete to anon, authenticated
using (true);

-- =======================
-- WORKPLACES
-- =======================
drop policy if exists workplaces_sel_any on public.workplaces;
drop policy if exists workplaces_ins_any on public.workplaces;
drop policy if exists workplaces_upd_any on public.workplaces;
drop policy if exists workplaces_del_any on public.workplaces;

create policy workplaces_sel_any
on public.workplaces
for select to anon, authenticated
using (true);

create policy workplaces_ins_any
on public.workplaces
for insert to anon, authenticated
with check (true);

create policy workplaces_upd_any
on public.workplaces
for update to anon, authenticated
using (true) with check (true);

create policy workplaces_del_any
on public.workplaces
for delete to anon, authenticated
using (true);

-- =======================
-- WORKPLACE_POSITIONS (M:N)
-- =======================
drop policy if exists wp_pos_sel_any on public.workplace_positions;
drop policy if exists wp_pos_ins_any on public.workplace_positions;
drop policy if exists wp_pos_upd_any on public.workplace_positions;
drop policy if exists wp_pos_del_any on public.workplace_positions;

create policy wp_pos_sel_any
on public.workplace_positions
for select to anon, authenticated
using (true);

create policy wp_pos_ins_any
on public.workplace_positions
for insert to anon, authenticated
with check (true);

create policy wp_pos_upd_any
on public.workplace_positions
for update to anon, authenticated
using (true) with check (true);

create policy wp_pos_del_any
on public.workplace_positions
for delete to anon, authenticated
using (true);

-- =======================
-- TERMINALS
-- =======================
drop policy if exists terminals_sel_any on public.terminals;
drop policy if exists terminals_ins_any on public.terminals;
drop policy if exists terminals_upd_any on public.terminals;
drop policy if exists terminals_del_any on public.terminals;

create policy terminals_sel_any
on public.terminals
for select to anon, authenticated
using (true);

create policy terminals_ins_any
on public.terminals
for insert to anon, authenticated
with check (true);

create policy terminals_upd_any
on public.terminals
for update to anon, authenticated
using (true) with check (true);

create policy terminals_del_any
on public.terminals
for delete to anon, authenticated
using (true);

-- =======================
-- TERMINAL_WORKPLACES (M:N)
-- =======================
drop policy if exists term_wp_sel_any on public.terminal_workplaces;
drop policy if exists term_wp_ins_any on public.terminal_workplaces;
drop policy if exists term_wp_upd_any on public.terminal_workplaces;
drop policy if exists term_wp_del_any on public.terminal_workplaces;

create policy term_wp_sel_any
on public.terminal_workplaces
for select to anon, authenticated
using (true);

create policy term_wp_ins_any
on public.terminal_workplaces
for insert to anon, authenticated
with check (true);

create policy term_wp_upd_any
on public.terminal_workplaces
for update to anon, authenticated
using (true) with check (true);

create policy term_wp_del_any
on public.terminal_workplaces
for delete to anon, authenticated
using (true);
-------------------------------------------------------------------------------------------------------
alter table public.positions enable row level security;
drop policy if exists positions_sel_any on public.positions;
create policy positions_sel_any
on public.positions
for select to anon, authenticated
using (true);
-------------------------------------------------------------------------------------------------------------
alter table public.positions enable row level security;
drop policy if exists positions_sel_any on public.positions;
create policy positions_sel_any
on public.positions
for select to anon, authenticated
using (true);
-------------------------------------------------------------------------------------------------------------------
-- Включаем RLS на всех таблицах (если не включён)
alter table public.positions            enable row level security;
alter table public.employees            enable row level security;
alter table public.employee_positions   enable row level security;
alter table public.workplaces           enable row level security;
alter table public.workplace_positions  enable row level security;
alter table public.terminals            enable row level security;
alter table public.terminal_workplaces  enable row level security;

-- ========== SELECT-политики (чтение) ==========
-- POSITIONS
drop policy if exists positions_sel_any on public.positions;
create policy positions_sel_any
on public.positions
for select
to anon, authenticated
using (true);

-- EMPLOYEES
drop policy if exists employees_sel_any on public.employees;
create policy employees_sel_any
on public.employees
for select
to anon, authenticated
using (true);

-- EMPLOYEE_POSITIONS
drop policy if exists emp_pos_sel_any on public.employee_positions;
create policy emp_pos_sel_any
on public.employee_positions
for select
to anon, authenticated
using (true);

-- WORKPLACES
drop policy if exists workplaces_sel_any on public.workplaces;
create policy workplaces_sel_any
on public.workplaces
for select
to anon, authenticated
using (true);

-- WORKPLACE_POSITIONS
drop policy if exists wp_pos_sel_any on public.workplace_positions;
create policy wp_pos_sel_any
on public.workplace_positions
for select
to anon, authenticated
using (true);

-- TERMINALS
drop policy if exists terminals_sel_any on public.terminals;
create policy terminals_sel_any
on public.terminals
for select
to anon, authenticated
using (true);

-- TERMINAL_WORKPLACES
drop policy if exists term_wp_sel_any on public.terminal_workplaces;
create policy term_wp_sel_any
on public.terminal_workplaces
for select
to anon, authenticated
using (true);

-- (опционально) если используешь VIEW для чтения (например employees_view / workplaces_view / terminals_view),
-- можно явно выдать права на них:
do $$
declare
  v_exists bool;
begin
  -- employees_view
  select exists (
    select 1 from pg_views where schemaname='public' and viewname='employees_view'
  ) into v_exists;
  if v_exists then
    grant select on public.employees_view to anon, authenticated;
  end if;

  -- workplaces_view
  select exists (
    select 1 from pg_views where schemaname='public' and viewname='workplaces_view'
  ) into v_exists;
  if v_exists then
    grant select on public.workplaces_view to anon, authenticated;
  end if;

  -- terminals_view
  select exists (
    select 1 from pg_views where schemaname='public' and viewname='terminals_view'
  ) into v_exists;
  if v_exists then
    grant select on public.terminals_view to anon, authenticated;
  end if;
end $$;
------------------------------------------------------------------------------------------------------------------------------------
select count(*) from public.employees;                  -- должно отработать без 42501
select count(*) from public.employee_positions;
select count(*) from public.positions;
-------------------------------------------------------------------------------------------------------------
-- пример для employee_positions (добавление связей)
drop policy if exists emp_pos_ins_any on public.employee_positions;
create policy emp_pos_ins_any
on public.employee_positions
for insert
to anon, authenticated
with check (true);  -- для INSERT допускается только WITH CHECK
-----------------------------------------------------------------------------------------------------------------------
-- создать/сделать публичным бакет
insert into storage.buckets (id, name, public)
values ('employee_photos', 'employee_photos', true)
on conflict (id) do update set public = excluded.public;

-- политики (сначала удалим на случай повтора)
drop policy if exists "employee_photos read public" on storage.objects;
create policy "employee_photos read public"
on storage.objects
for select
to public
using (bucket_id = 'employee_photos');

drop policy if exists "employee_photos insert auth" on storage.objects;
create policy "employee_photos insert auth"
on storage.objects
for insert
to authenticated
with check (bucket_id = 'employee_photos');
----------------------------------------------------------------------------------------------------------------------
-- бакет на всякий случай
insert into storage.buckets (id, name, public)
values ('employee_photos', 'employee_photos', true)
on conflict (id) do update set public = excluded.public;

-- Заменяем политику INSERT только для аутентифицированных
drop policy if exists "employee_photos insert auth" on storage.objects;

-- Разрешаем анонимным (anon) загружать только в этот бакет
drop policy if exists "employee_photos insert anon" on storage.objects;
create policy "employee_photos insert anon"
on storage.objects
for insert
to anon
with check (bucket_id = 'employee_photos');
-- END of personel.sql\n

-- ============================================================
-- SUPABASE: Склад (Warehouse) — отдельные таблицы по модулям
-- paints, materials, papers, stationery + списания/инвентаризации
-- Схема согласована с TmcModel (snake_case поля), без изменения UI.
-- ============================================================


create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

-- Унифицированный тип для порогов "низкий"/"очень низкий" остаток:
-- В формах эти статусы НЕ отображаются; статусы считаются во VIEW.

-- ===================== CATEGORIES (опционально) =====================
create table if not exists public.warehouse_categories (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
drop trigger if exists trg_whcat_updated_at on public.warehouse_categories;
create trigger trg_whcat_updated_at before update on public.warehouse_categories
for each row execute function public.set_updated_at();
alter table public.warehouse_categories enable row level security;

-- ===================== BASE TABLE TEMPLATE (комментарий) =====================
-- Общие поля в таблицах номенклатуры:
-- id, date(text), supplier(text), description(text), unit(text), quantity(numeric),
-- low_threshold(numeric), critical_threshold(numeric), note(text),
-- image_url(text), image_base64(text), created_at, updated_at, category_id(uuid)

-- ===================== PAINTS =====================
create table if not exists public.paints (
  id uuid primary key default gen_random_uuid(),
  date text,
  supplier text,
  description text not null,          -- имя/наименование краски
  unit text not null default 'ml',
  quantity numeric(14,3) not null default 0 check (quantity >= 0),
  low_threshold numeric(14,3) not null default 0 check (low_threshold >= 0),
  critical_threshold numeric(14,3) not null default 0 check (critical_threshold >= 0),
  note text,
  image_url text,
  image_base64 text,
  color_code text,
  manufacturer text,
  category_id uuid references public.warehouse_categories(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
drop trigger if exists trg_paints_updated_at on public.paints;
create trigger trg_paints_updated_at before update on public.paints
for each row execute function public.set_updated_at();
alter table public.paints enable row level security;

create table if not exists public.paints_writeoffs (
  id uuid primary key default gen_random_uuid(),
  paint_id uuid not null references public.paints(id) on delete cascade,
  qty numeric(14,3) not null check (qty > 0),
  reason text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.paints_writeoffs enable row level security;

create table if not exists public.paints_inventories (
  id uuid primary key default gen_random_uuid(),
  paint_id uuid not null references public.paints(id) on delete cascade,
  counted_qty numeric(14,3) not null check (counted_qty >= 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.paints_inventories enable row level security;

-- триггеры коррекции остатков
create or replace function public.paints_apply_writeoff() returns trigger as $$
begin
  update public.paints
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.paint_id;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_paints_writeoff_apply on public.paints_writeoffs;
create trigger trg_paints_writeoff_apply after insert on public.paints_writeoffs
for each row execute function public.paints_apply_writeoff();

create or replace function public.paints_apply_inventory() returns trigger as $$
begin
  update public.paints
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.paint_id;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_paints_inventory_apply on public.paints_inventories;
create trigger trg_paints_inventory_apply after insert on public.paints_inventories
for each row execute function public.paints_apply_inventory();

create or replace view public.v_paints as
select p.*,
  case
    when p.quantity <= p.critical_threshold then 'очень низкий'
    when p.quantity <= p.low_threshold then 'низкий'
    else 'норма'
  end as stock_status
from public.paints p;

-- ===================== MATERIALS =====================
create table if not exists public.materials (
  id uuid primary key default gen_random_uuid(),
  date text,
  supplier text,
  description text not null,
  unit text not null default 'pcs',
  quantity numeric(14,3) not null default 0 check (quantity >= 0),
  low_threshold numeric(14,3) not null default 0 check (low_threshold >= 0),
  critical_threshold numeric(14,3) not null default 0 check (critical_threshold >= 0),
  note text,
  image_url text,
  image_base64 text,
  category_id uuid references public.warehouse_categories(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
drop trigger if exists trg_materials_updated_at on public.materials;
create trigger trg_materials_updated_at before update on public.materials
for each row execute function public.set_updated_at();
alter table public.materials enable row level security;

create table if not exists public.materials_writeoffs (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.materials(id) on delete cascade,
  qty numeric(14,3) not null check (qty > 0),
  reason text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.materials_writeoffs enable row level security;

create table if not exists public.materials_inventories (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.materials(id) on delete cascade,
  counted_qty numeric(14,3) not null check (counted_qty >= 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.materials_inventories enable row level security;

create or replace function public.materials_apply_writeoff() returns trigger as $$
begin
  update public.materials
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.material_id;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_materials_writeoff_apply on public.materials_writeoffs;
create trigger trg_materials_writeoff_apply after insert on public.materials_writeoffs
for each row execute function public.materials_apply_writeoff();

create or replace function public.materials_apply_inventory() returns trigger as $$
begin
  update public.materials
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.material_id;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_materials_inventory_apply on public.materials_inventories;
create trigger trg_materials_inventory_apply after insert on public.materials_inventories
for each row execute function public.materials_apply_inventory();

create or replace view public.v_materials as
select m.*,
  case
    when m.quantity <= m.critical_threshold then 'очень низкий'
    when m.quantity <= m.low_threshold then 'низкий'
    else 'норма'
  end as stock_status
from public.materials m;

-- ===================== PAPERS =====================
create table if not exists public.papers (
  id uuid primary key default gen_random_uuid(),
  date text,
  supplier text,
  description text not null,    -- наименование бумаги
  format text not null,         -- A3/A4/...
  grammage text not null,       -- г/м2; строкой чтобы совпасть с вашей моделью
  weight numeric(14,3),         -- опционально
  unit text not null default 'sheets',
  quantity numeric(14,3) not null default 0 check (quantity >= 0),
  low_threshold numeric(14,3) not null default 0 check (low_threshold >= 0),
  critical_threshold numeric(14,3) not null default 0 check (critical_threshold >= 0),
  note text,
  category_id uuid references public.warehouse_categories(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  unique (description, format, grammage)
);
drop trigger if exists trg_papers_updated_at on public.papers;
create trigger trg_papers_updated_at before update on public.papers
for each row execute function public.set_updated_at();
alter table public.papers enable row level security;

create table if not exists public.papers_writeoffs (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers(id) on delete cascade,
  qty numeric(14,3) not null check (qty > 0),
  reason text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.papers_writeoffs enable row level security;

create table if not exists public.papers_inventories (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers(id) on delete cascade,
  counted_qty numeric(14,3) not null check (counted_qty >= 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.papers_inventories enable row level security;

create or replace function public.papers_apply_writeoff() returns trigger as $$
begin
  update public.papers
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.paper_id;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_papers_writeoff_apply on public.papers_writeoffs;
create trigger trg_papers_writeoff_apply after insert on public.papers_writeoffs
for each row execute function public.papers_apply_writeoff();

create or replace function public.papers_apply_inventory() returns trigger as $$
begin
  update public.papers
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.paper_id;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_papers_inventory_apply on public.papers_inventories;
create trigger trg_papers_inventory_apply after insert on public.papers_inventories
for each row execute function public.papers_apply_inventory();

create or replace view public.v_papers as
select p.*,
  case
    when p.quantity <= p.critical_threshold then 'очень низкий'
    when p.quantity <= p.low_threshold then 'низкий'
    else 'норма'
  end as stock_status
from public.papers p;

-- ===================== STATIONERY (канцтовары) =====================
create table if not exists public.stationery (
  id uuid primary key default gen_random_uuid(),
  date text,
  supplier text,
  description text not null,
  unit text not null default 'pcs',
  quantity numeric(14,3) not null default 0 check (quantity >= 0),
  low_threshold numeric(14,3) not null default 0 check (low_threshold >= 0),
  critical_threshold numeric(14,3) not null default 0 check (critical_threshold >= 0),
  note text,
  image_url text,
  image_base64 text,
  category_id uuid references public.warehouse_categories(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
drop trigger if exists trg_stationery_updated_at on public.stationery;
create trigger trg_stationery_updated_at before update on public.stationery
for each row execute function public.set_updated_at();
alter table public.stationery enable row level security;

create table if not exists public.stationery_writeoffs (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.stationery(id) on delete cascade,
  qty numeric(14,3) not null check (qty > 0),
  reason text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.stationery_writeoffs enable row level security;

create table if not exists public.stationery_inventories (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.stationery(id) on delete cascade,
  counted_qty numeric(14,3) not null check (counted_qty >= 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);
alter table public.stationery_inventories enable row level security;

create or replace function public.stationery_apply_writeoff() returns trigger as $$
begin
  update public.stationery
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.item_id;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_stationery_writeoff_apply on public.stationery_writeoffs;
create trigger trg_stationery_writeoff_apply after insert on public.stationery_writeoffs
for each row execute function public.stationery_apply_writeoff();

create or replace function public.stationery_apply_inventory() returns trigger as $$
begin
  update public.stationery
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.item_id;
  return new;
end; $$ language plpgsql;
drop trigger if exists trg_stationery_inventory_apply on public.stationery_inventories;
create trigger trg_stationery_inventory_apply after insert on public.stationery_inventories
for each row execute function public.stationery_apply_inventory();

create or replace view public.v_stationery as
select s.*,
  case
    when s.quantity <= s.critical_threshold then 'очень низкий'
    when s.quantity <= s.low_threshold then 'низкий'
    else 'норма'
  end as stock_status
from public.stationery s;

-- ===================== RLS =====================
do $$ begin
  -- helper proc
  perform 1;
end $$;

-- Enable RLS and open to authenticated (минимально, можно ужесточить позже)
-- paints
alter table public.paints enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='paints' and policyname='paints_all') then
    create policy paints_all on public.paints for all to authenticated using (true) with check (true);
  end if;
end $$;
alter table public.paints_writeoffs enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='paints_writeoffs' and policyname='paints_writeoffs_all') then
    create policy paints_writeoffs_all on public.paints_writeoffs for all to authenticated using (true) with check (true);
  end if;
end $$;
alter table public.paints_inventories enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='paints_inventories' and policyname='paints_inventories_all') then
    create policy paints_inventories_all on public.paints_inventories for all to authenticated using (true) with check (true);
  end if;
end $$;

-- materials
alter table public.materials enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='materials' and policyname='materials_all') then
    create policy materials_all on public.materials for all to authenticated using (true) with check (true);
  end if;
end $$;
alter table public.materials_writeoffs enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='materials_writeoffs' and policyname='materials_writeoffs_all') then
    create policy materials_writeoffs_all on public.materials_writeoffs for all to authenticated using (true) with check (true);
  end if;
end $$;
alter table public.materials_inventories enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='materials_inventories' and policyname='materials_inventories_all') then
    create policy materials_inventories_all on public.materials_inventories for all to authenticated using (true) with check (true);
  end if;
end $$;

-- papers
alter table public.papers enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='papers' and policyname='papers_all') then
    create policy papers_all on public.papers for all to authenticated using (true) with check (true);
  end if;
end $$;
alter table public.papers_writeoffs enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='papers_writeoffs' and policyname='papers_writeoffs_all') then
    create policy papers_writeoffs_all on public.papers_writeoffs for all to authenticated using (true) with check (true);
  end if;
end $$;
alter table public.papers_inventories enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='papers_inventories' and policyname='papers_inventories_all') then
    create policy papers_inventories_all on public.papers_inventories for all to authenticated using (true) with check (true);
  end if;
end $$;

-- stationery
alter table public.stationery enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='stationery' and policyname='stationery_all') then
    create policy stationery_all on public.stationery for all to authenticated using (true) with check (true);
  end if;
end $$;
alter table public.stationery_writeoffs enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='stationery_writeoffs' and policyname='stationery_writeoffs_all') then
    create policy stationery_writeoffs_all on public.stationery_writeoffs for all to authenticated using (true) with check (true);
  end if;
end $$;
alter table public.stationery_inventories enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='stationery_inventories' and policyname='stationery_inventories_all') then
    create policy stationery_inventories_all on public.stationery_inventories for all to authenticated using (true) with check (true);
  end if;
end $$;

-- ===================== STORAGE (tmc BUCKET) =====================
insert into storage.buckets (id, name, public)
select 'tmc', 'tmc', true
where not exists (select 1 from storage.buckets where id = 'tmc');

do $$ begin
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='TMC read') then
    create policy "TMC read" on storage.objects for select using (bucket_id = 'tmc');
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='TMC insert') then
    create policy "TMC insert" on storage.objects for insert to authenticated with check (bucket_id = 'tmc' and (owner = auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='TMC update') then
    create policy "TMC update" on storage.objects for update to authenticated using (bucket_id = 'tmc' and owner = auth.uid()) with check (bucket_id = 'tmc' and owner = auth.uid());
  end if;
  if not exists (select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='TMC delete') then
    create policy "TMC delete" on storage.objects for delete to authenticated using (bucket_id = 'tmc' and owner = auth.uid());
  end if;
end $$;

-- ===================== RPC HELPERS =====================
create or replace function public.writeoff(type text, item uuid, qty numeric, reason text)
returns void as $$
begin
  if type = 'paint' then
    insert into public.paints_writeoffs(paint_id, qty, reason, created_by) values (item, qty, reason, auth.uid());
  elsif type = 'material' then
    insert into public.materials_writeoffs(material_id, qty, reason, created_by) values (item, qty, reason, auth.uid());
  elsif type = 'paper' then
    insert into public.papers_writeoffs(paper_id, qty, reason, created_by) values (item, qty, reason, auth.uid());
  elsif type = 'stationery' then
    insert into public.stationery_writeoffs(item_id, qty, reason, created_by) values (item, qty, reason, auth.uid());
  end if;
end;
$$ language plpgsql security definer;

create or replace function public.inventory_set(type text, item uuid, counted numeric, note text)
returns void as $$
begin
  if type = 'paint' then
    insert into public.paints_inventories(paint_id, counted_qty, note, created_by) values (item, counted, note, auth.uid());
  elsif type = 'material' then
    insert into public.materials_inventories(material_id, counted_qty, note, created_by) values (item, counted, note, auth.uid());
  elsif type = 'paper' then
    insert into public.papers_inventories(paper_id, counted_qty, note, created_by) values (item, counted, note, auth.uid());
  elsif type = 'stationery' then
    insert into public.stationery_inventories(item_id, counted_qty, note, created_by) values (item, counted, note, auth.uid());
  end if;
end;
$$ language plpgsql security definer;
-----------------------------------------------------------------------------------------------------------------------------------------------
alter table public.papers enable row level security;

drop policy if exists papers_select_public on public.papers;
drop policy if exists papers_insert_public on public.papers;
drop policy if exists papers_update_public on public.papers;
drop policy if exists papers_delete_public on public.papers;

create policy papers_select_public on public.papers
for select to public using (true);

create policy papers_insert_public on public.papers
for insert to public with check (true);

create policy papers_update_public on public.papers
for update to public using (true) with check (true);

create policy papers_delete_public on public.papers
for delete to public using (true);
------------------------------------------------------------------------------------------------------------------
select * from public.papers_writeoffs order by created_at desc;   -- логи списаний бумаги
select * from public.papers_inventories order by created_at desc; 
---------------------------------------------------------------------------------------------------------
-- включи RLS (если вдруг выключено)
alter table public.paints_writeoffs       enable row level security;
alter table public.paints_inventories     enable row level security;
alter table public.materials_writeoffs    enable row level security;
alter table public.materials_inventories  enable row level security;
alter table public.papers_writeoffs       enable row level security;
alter table public.papers_inventories     enable row level security;
alter table public.stationery_writeoffs   enable row level security;
alter table public.stationery_inventories enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename='paints_writeoffs' and policyname='paints_writeoffs_select_public') then
    create policy paints_writeoffs_select_public on public.paints_writeoffs
      for select to public using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='paints_inventories' and policyname='paints_inventories_select_public') then
    create policy paints_inventories_select_public on public.paints_inventories
      for select to public using (true);
  end if;

  if not exists (select 1 from pg_policies where tablename='materials_writeoffs' and policyname='materials_writeoffs_select_public') then
    create policy materials_writeoffs_select_public on public.materials_writeoffs
      for select to public using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='materials_inventories' and policyname='materials_inventories_select_public') then
    create policy materials_inventories_select_public on public.materials_inventories
      for select to public using (true);
  end if;

  if not exists (select 1 from pg_policies where tablename='papers_writeoffs' and policyname='papers_writeoffs_select_public') then
    create policy papers_writeoffs_select_public on public.papers_writeoffs
      for select to public using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='papers_inventories' and policyname='papers_inventories_select_public') then
    create policy papers_inventories_select_public on public.papers_inventories
      for select to public using (true);
  end if;

  if not exists (select 1 from pg_policies where tablename='stationery_writeoffs' and policyname='stationery_writeoffs_select_public') then
    create policy stationery_writeoffs_select_public on public.stationery_writeoffs
      for select to public using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='stationery_inventories' and policyname='stationery_inventories_select_public') then
    create policy stationery_inventories_select_public on public.stationery_inventories
      for select to public using (true);
  end if;
end $$;
-----------------------------------------------------------------------------------------------------------------------
-- === Общее: функция обновления updated_at (если вдруг нет) ===
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at := now();
  return new;
end;
$$ language plpgsql;

-- ===================== PAINTS =====================
-- Спиcание → уменьшить quantity
create or replace function public.paints_apply_writeoff()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.paints
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.paint_id;
  return new;
end$$;

drop trigger if exists trg_paints_writeoff_apply on public.paints_writeoffs;
create trigger trg_paints_writeoff_apply
after insert on public.paints_writeoffs
for each row execute function public.paints_apply_writeoff();

-- Инвентаризация → установить quantity
create or replace function public.paints_apply_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.paints
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.paint_id;
  return new;
end$$;

drop trigger if exists trg_paints_inventory_apply on public.paints_inventories;
create trigger trg_paints_inventory_apply
after insert on public.paints_inventories
for each row execute function public.paints_apply_inventory();

-- Политика на UPDATE для authenticated
do $$begin
  if not exists (
    select 1 from pg_policies
    where tablename='paints' and policyname='paints_update_all'
  ) then
    create policy paints_update_all on public.paints
      for update to authenticated using (true) with check (true);
  end if;
end$$;

-- ===================== MATERIALS =====================
create or replace function public.materials_apply_writeoff()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.materials
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.material_id;
  return new;
end$$;

drop trigger if exists trg_materials_writeoff_apply on public.materials_writeoffs;
create trigger trg_materials_writeoff_apply
after insert on public.materials_writeoffs
for each row execute function public.materials_apply_writeoff();

create or replace function public.materials_apply_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.materials
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.material_id;
  return new;
end$$;

drop trigger if exists trg_materials_inventory_apply on public.materials_inventories;
create trigger trg_materials_inventory_apply
after insert on public.materials_inventories
for each row execute function public.materials_apply_inventory();

do $$begin
  if not exists (
    select 1 from pg_policies
    where tablename='materials' and policyname='materials_update_all'
  ) then
    create policy materials_update_all on public.materials
      for update to authenticated using (true) with check (true);
  end if;
end$$;

-- ===================== PAPERS =====================
create or replace function public.papers_apply_writeoff()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.papers
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.paper_id;
  return new;
end$$;

drop trigger if exists trg_papers_writeoff_apply on public.papers_writeoffs;
create trigger trg_papers_writeoff_apply
after insert on public.papers_writeoffs
for each row execute function public.papers_apply_writeoff();

create or replace function public.papers_apply_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.papers
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.paper_id;
  return new;
end$$;

drop trigger if exists trg_papers_inventory_apply on public.papers_inventories;
create trigger trg_papers_inventory_apply
after insert on public.papers_inventories
for each row execute function public.papers_apply_inventory();

do $$begin
  if not exists (
    select 1 from pg_policies
    where tablename='papers' and policyname='papers_update_all'
  ) then
    create policy papers_update_all on public.papers
      for update to authenticated using (true) with check (true);
  end if;
end$$;

-- ===================== STATIONERY =====================
create or replace function public.stationery_apply_writeoff()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.stationery
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.item_id;
  return new;
end$$;

drop trigger if exists trg_stationery_writeoff_apply on public.stationery_writeoffs;
create trigger trg_stationery_writeoff_apply
after insert on public.stationery_writeoffs
for each row execute function public.stationery_apply_writeoff();

create or replace function public.stationery_apply_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.stationery
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.item_id;
  return new;
end$$;

drop trigger if exists trg_stationery_inventory_apply on public.stationery_inventories;
create trigger trg_stationery_inventory_apply
after insert on public.stationery_inventories
for each row execute function public.stationery_apply_inventory();

do $$begin
  if not exists (
    select 1 from pg_policies
    where tablename='stationery' and policyname='stationery_update_all'
  ) then
    create policy stationery_update_all on public.stationery
      for update to authenticated using (true) with check (true);
  end if;
end$$;
------------------------------------------------------------------------------------------------------------------
-- Списания
alter publication supabase_realtime add table
  public.paints_writeoffs,
  public.materials_writeoffs,
  public.papers_writeoffs,
  public.stationery_writeoffs;

-- Инвентаризации
alter publication supabase_realtime add table
  public.paints_inventories,
  public.materials_inventories,
  public.papers_inventories,
  public.stationery_inventories;
-----------------------------------------------------------------------------------------------------------------
alter table public.stationery enable row level security;

drop policy if exists stationery_select_public on public.stationery;
drop policy if exists stationery_insert_public on public.stationery;
drop policy if exists stationery_update_public on public.stationery;
drop policy if exists stationery_delete_public on public.stationery;

create policy stationery_select_public on public.stationery
for select to public using (true);

create policy stationery_insert_public on public.stationery
for insert to public with check (true);

create policy stationery_update_public on public.stationery
for update to public using (true) with check (true);

create policy stationery_delete_public on public.stationery
for delete to public using (true);
--------------------------------------------------------------------------------------------------
alter table public.paints enable row level security;

drop policy if exists paints_select_public on public.paints;
create policy paints_select_public
  on public.paints for select
  to public
  using (true);
----------------------------------------------------------------------------------------------------
alter table public.paints enable row level security;

drop policy if exists paints_select_public on public.paints;
create policy paints_select_public
  on public.paints for select to public using (true);

-- вставка/обновление/удаление у тебя уже есть для authenticated;
-- если нет — добавь:
drop policy if exists paints_insert_auth on public.paints;
drop policy if exists paints_update_auth on public.paints;
drop policy if exists paints_delete_auth on public.paints;

create policy paints_insert_auth on public.paints
  for insert to authenticated with check (true);

create policy paints_update_auth on public.paints
  for update to authenticated using (true) with check (true);

create policy paints_delete_auth on public.paints
  for delete to authenticated using (true);
----------------------------------------------------------------------------------------------------------
create policy paints_insert_public on public.paints
  for insert to public with check (true);
--------------------------------------------------------------------------------------------------------
-- suppliers table
create table if not exists public.suppliers (
  id uuid primary key,
  name text not null,
  bin text,
  contact text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- forms_series table for numbering sequences (forms)
create table if not exists public.forms_series (
  id uuid primary key,
  series text not null,   -- label of the series
  prefix text not null default '',
  suffix text not null default '',
  last_number integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Updated-at triggers
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  NEW.updated_at = now();
  return NEW;
end; $$;

drop trigger if exists trg_suppliers_updated_at on public.suppliers;
create trigger trg_suppliers_updated_at
before update on public.suppliers
for each row execute function public.set_updated_at();

drop trigger if exists trg_forms_series_updated_at on public.forms_series;
create trigger trg_forms_series_updated_at
before update on public.forms_series
for each row execute function public.set_updated_at();

-- RLS
alter table public.suppliers enable row level security;
alter table public.forms_series enable row level security;

-- Development policies: allow authenticated users full access.
-- If you use anonymous sign-in, auth.uid() will still be non-null.
drop policy if exists "suppliers rw for auth users" on public.suppliers;
create policy "suppliers rw for auth users" on public.suppliers
  for all using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "forms_series rw for auth users" on public.forms_series;
create policy "forms_series rw for auth users" on public.forms_series
  for all using (auth.uid() is not null) with check (auth.uid() is not null);
  -------------------------------------------------------------------------------------------
  -- RLS for warehouse tables (ensure authenticated users can read/write)
alter table if exists public.paints enable row level security;
alter table if exists public.materials enable row level security;
alter table if exists public.papers enable row level security;
alter table if exists public.stationery enable row level security;

-- Allow all authenticated users (including anonymous) full access
drop policy if exists "paints rw for auth users" on public.paints;
create policy "paints rw for auth users" on public.paints
  for all using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "materials rw for auth users" on public.materials;
create policy "materials rw for auth users" on public.materials
  for all using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "papers rw for auth users" on public.papers;
create policy "papers rw for auth users" on public.papers
  for all using (auth.uid() is not null) with check (auth.uid() is not null);

drop policy if exists "stationery rw for auth users" on public.stationery;
create policy "stationery rw for auth users" on public.stationery
  for all using (auth.uid() is not null) with check (auth.uid() is not null);
--------------------------------------------------------------------------------------------------
-- =============== СКЛАД/КАНЦТОВАРЫ (совместимо с твоей TmcModel) ===============

create table if not exists public.warehouse_stationery (
  id                 uuid primary key default gen_random_uuid(),
  table_key          text not null,                  -- подтип: 'pens', 'staples' и т.п.
  date               text not null,                  -- как в модели (строка)
  supplier           text,
  type               text not null,
  description        text not null,
  quantity           numeric not null default 0,
  unit               text not null,
  format             text,
  grammage           text,
  weight             numeric,
  note               text,
  image_url          text,
  image_base64       text,
  low_threshold      numeric,
  critical_threshold numeric,
  created_by         uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table if not exists public.warehouse_stationery_writeoffs (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references public.warehouse_stationery(id) on delete cascade,
  qty         numeric not null check (qty > 0),
  reason      text,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.warehouse_stationery_inventories (
  id          uuid primary key default gen_random_uuid(),
  item_id     uuid not null references public.warehouse_stationery(id) on delete cascade,
  factual     numeric not null,
  note        text,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- updated_at триггер
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_stationery_updated_at on public.warehouse_stationery;
create trigger trg_stationery_updated_at
before update on public.warehouse_stationery
for each row execute function public.set_updated_at();

-- Включаем RLS
alter table public.warehouse_stationery enable row level security;
alter table public.warehouse_stationery_writeoffs enable row level security;
alter table public.warehouse_stationery_inventories enable row level security;

-- Политики чтения (всем)
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='warehouse_stationery' and policyname='read all') then
    create policy "read all" on public.warehouse_stationery
      for select
      using (true);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='warehouse_stationery_writeoffs' and policyname='read all') then
    create policy "read all" on public.warehouse_stationery_writeoffs
      for select
      using (true);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='warehouse_stationery_inventories' and policyname='read all') then
    create policy "read all" on public.warehouse_stationery_inventories
      for select
      using (true);
  end if;
end $$;

-- Политики записи (только authenticated). ВАЖНО: порядок: TO ... USING/WITH CHECK
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='warehouse_stationery' and policyname='insert auth') then
    create policy "insert auth" on public.warehouse_stationery
      for insert
      to authenticated
      with check (auth.uid() is not null);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='warehouse_stationery' and policyname='update auth') then
    create policy "update auth" on public.warehouse_stationery
      for update
      to authenticated
      using (auth.uid() is not null);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='warehouse_stationery' and policyname='delete auth') then
    create policy "delete auth" on public.warehouse_stationery
      for delete
      to authenticated
      using (auth.uid() is not null);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='warehouse_stationery_writeoffs' and policyname='write auth') then
    create policy "write auth" on public.warehouse_stationery_writeoffs
      for all
      to authenticated
      using (auth.uid() is not null)
      with check (auth.uid() is not null);
  end if;

  if not exists(select 1 from pg_policies where schemaname='public' and tablename='warehouse_stationery_inventories' and policyname='write auth') then
    create policy "write auth" on public.warehouse_stationery_inventories
      for all
      to authenticated
      using (auth.uid() is not null)
      with check (auth.uid() is not null);
  end if;
end $$;
-----------------------------------------------------------------------------------------------------------------------
-- 1) realtime для базовой таблицы
alter publication supabase_realtime add table public.warehouse_stationery;

-- 2) индексы, чтобы список летал
create index if not exists idx_wh_stationery_table_key on public.warehouse_stationery(table_key);
create index if not exists idx_wh_stationery_created_at on public.warehouse_stationery(created_at);

-- Политики на чтение/запись в твоём файле уже есть (read all / insert auth / update auth / delete auth). 
-- Они выглядят примерно так:
--   create policy "read all" on public.warehouse_stationery for select using (true);
--   create policy "insert auth" on public.warehouse_stationery for insert to authenticated with check (auth.uid() is not null);
-- и т.д.  (см. твой файл)  :contentReference[oaicite:2]{index=2}
-----------------------------------------------------------------------------------------------------------------------------------------------------------
alter publication supabase_realtime add table
  public.warehouse_stationery_writeoffs,
  public.warehouse_stationery_inventories;
------------------------------------------------------------------------------------------------------------
-- ===== функции под триггеры =====
create or replace function public.wh_stationery_apply_writeoff()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.warehouse_stationery s
     set quantity  = greatest(0, coalesce(s.quantity,0) - coalesce(new.qty,0)),
         updated_at = now()
   where s.id::text = new.item_id::text;
  return new;
end$$;

create or replace function public.wh_stationery_apply_inventory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_factual numeric;
begin
  v_factual := coalesce(new.factual, new.counted_qty, 0);
  update public.warehouse_stationery s
     set quantity  = v_factual,
         updated_at = now()
   where s.id::text = new.item_id::text;
  return new;
end$$;

-- на всякий — владелец postgres (обходит RLS как владелец таблицы)
alter function public.wh_stationery_apply_writeoff() owner to postgres;
alter function public.wh_stationery_apply_inventory() owner to postgres;

-- ===== триггеры на нужных таблицах логов =====
drop trigger if exists trg_wh_st_writeoff_apply on public.warehouse_stationery_writeoffs;
create trigger trg_wh_st_writeoff_apply
after insert on public.warehouse_stationery_writeoffs
for each row execute function public.wh_stationery_apply_writeoff();

drop trigger if exists trg_wh_st_inventory_apply on public.warehouse_stationery_inventories;
create trigger trg_wh_st_inventory_apply
after insert on public.warehouse_stationery_inventories
for each row execute function public.wh_stationery_apply_inventory();

-- метки времени (если колонок не было)
alter table if exists public.warehouse_stationery_writeoffs
  add column if not exists created_at timestamptz default now();
alter table if exists public.warehouse_stationery_inventories
  add column if not exists created_at timestamptz default now();
--------------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.warehouse_categories
  ADD COLUMN IF NOT EXISTS has_subtables boolean NOT NULL DEFAULT false;

---------------------------------------------------------------------------------------------------------------
-- Расширение для UUID (если ещё не включено)

-- =========================
-- Таблицы
-- =========================
create table if not exists public.warehouse_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,                -- машинный код, можно на кириллице
  title text not null,                      -- отображаемое имя
  has_subtables boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.warehouse_category_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.warehouse_categories(id) on delete cascade,
  table_key text,                           -- для под-таблиц (если нужно)
  description text not null,                -- Название
  quantity numeric(12,3) not null default 0,
  unit text not null default 'pcs',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- updated_at
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end$$;

drop trigger if exists trg_category_items_set_updated on public.warehouse_category_items;
create trigger trg_category_items_set_updated
before update on public.warehouse_category_items
for each row execute function public.tg_set_updated_at();

-- Индексы
create index if not exists idx_wc_code on public.warehouse_categories(code);
create index if not exists idx_wci_category on public.warehouse_category_items(category_id);
create index if not exists idx_wci_cat_tbl on public.warehouse_category_items(category_id, table_key);

-- =========================
-- Политики RLS (простые: всем аутентифицированным можно CRUD)
-- =========================
alter table public.warehouse_categories enable row level security;
alter table public.warehouse_category_items enable row level security;

drop policy if exists wc_sel on public.warehouse_categories;
create policy wc_sel on public.warehouse_categories for select using (true);

drop policy if exists wc_ins on public.warehouse_categories;
create policy wc_ins on public.warehouse_categories for insert with check (true);

drop policy if exists wc_upd on public.warehouse_categories;
create policy wc_upd on public.warehouse_categories for update using (true) with check (true);

drop policy if exists wc_del on public.warehouse_categories;
create policy wc_del on public.warehouse_categories for delete using (true);

drop policy if exists wci_sel on public.warehouse_category_items;
create policy wci_sel on public.warehouse_category_items for select using (true);

drop policy if exists wci_ins on public.warehouse_category_items;
create policy wci_ins on public.warehouse_category_items for insert with check (true);

drop policy if exists wci_upd on public.warehouse_category_items;
create policy wci_upd on public.warehouse_category_items for update using (true) with check (true);

drop policy if exists wci_del on public.warehouse_category_items;
create policy wci_del on public.warehouse_category_items for delete using (true);

-- =========================
-- Realtime
-- =========================
alter publication supabase_realtime add table public.warehouse_categories;
alter publication supabase_realtime add table public.warehouse_category_items;

-- =========================
-- Удаляем старые дефолты (если были) и сидим НОВЫЕ, как на скрине
-- =========================
delete from public.warehouse_categories
where code in ('papers','stationery','paints');

insert into public.warehouse_categories (code, title, has_subtables) values
  ('п-пакет', 'П-пакет', false),
  ('v-пакет', 'V-пакет', false),
  ('листы',   'Листы',   false),
  ('маффин',  'Маффин',  false),
  ('тюльпан', 'Тюльпан', false)
on conflict (code) do nothing;
------------------------------------------------------------------------------------------------------------
-- =============== Extensions ===============

-- =============== Tables ===============
-- Категории
create table if not exists public.warehouse_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  has_subtables boolean not null default false,
  created_at timestamptz not null default now()
);

-- Позиции категории (две колонки + необязательный table_key)
create table if not exists public.warehouse_category_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.warehouse_categories(id) on delete cascade,
  table_key text,
  description text not null,
  quantity numeric(12,3) not null default 0,
  unit text not null default 'pcs',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Колонка has_subtables на всякий случай (если таблица уже была без неё)
alter table public.warehouse_categories
  add column if not exists has_subtables boolean;
alter table public.warehouse_categories
  alter column has_subtables set default false;
update public.warehouse_categories
   set has_subtables = coalesce(has_subtables, false)
 where has_subtables is null;
alter table public.warehouse_categories
  alter column has_subtables set not null;

-- =============== Trigger updated_at ===============
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end$$;

drop trigger if exists trg_category_items_set_updated on public.warehouse_category_items;
create trigger trg_category_items_set_updated
before update on public.warehouse_category_items
for each row execute function public.tg_set_updated_at();

-- =============== Indexes ===============
create index if not exists idx_wc_code     on public.warehouse_categories(code);
create index if not exists idx_wci_cat     on public.warehouse_category_items(category_id);
create index if not exists idx_wci_cat_tbl on public.warehouse_category_items(category_id, table_key);

-- =============== RLS ===============
alter table public.warehouse_categories     enable row level security;
alter table public.warehouse_category_items enable row level security;

-- Сносим старые/конфликтующие политики (если были)
drop policy if exists wc_sel_all  on public.warehouse_categories;
drop policy if exists wc_ins_all  on public.warehouse_categories;
drop policy if exists wc_upd_all  on public.warehouse_categories;
drop policy if exists wc_del_all  on public.warehouse_categories;

drop policy if exists wci_sel_all on public.warehouse_category_items;
drop policy if exists wci_ins_all on public.warehouse_category_items;
drop policy if exists wci_upd_all on public.warehouse_category_items;
drop policy if exists wci_del_all on public.warehouse_category_items;

-- Простые и широкие политики (и для anon, и для authenticated)
create policy wc_sel_all on public.warehouse_categories
for select to anon, authenticated using (true);

create policy wc_ins_all on public.warehouse_categories
for insert to anon, authenticated with check (true);

create policy wc_upd_all on public.warehouse_categories
for update to anon, authenticated using (true) with check (true);

create policy wc_del_all on public.warehouse_categories
for delete to anon, authenticated using (true);

create policy wci_sel_all on public.warehouse_category_items
for select to anon, authenticated using (true);

create policy wci_ins_all on public.warehouse_category_items
for insert to anon, authenticated with check (true);

create policy wci_upd_all on public.warehouse_category_items
for update to anon, authenticated using (true) with check (true);

create policy wci_del_all on public.warehouse_category_items
for delete to anon, authenticated using (true);

-- =============== Realtime (idempotent) ===============
do $$
begin
  begin
    alter publication supabase_realtime add table public.warehouse_categories;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.warehouse_category_items;
  exception when duplicate_object then null;
  end;
end$$;

-- =============== Seed категорий "как на скрине" ===============
-- уберём старые дефолты, если вдруг были
delete from public.warehouse_categories
 where code in ('papers','stationery','paints');

-- добавим нужные
insert into public.warehouse_categories (code, title, has_subtables) values
  ('п-пакет', 'П-пакет', false),
  ('v-пакет', 'V-пакет', false),
  ('листы',   'Листы',   false),
  ('маффин',  'Маффин',  false),
  ('тюльпан', 'Тюльпан', false)
on conflict (code) do nothing;
--------------------------------------------------------------------------------------------------------------
-- =============== базовые расширения ===============

-- =============== таблицы логов ===============
create table if not exists public.warehouse_category_writeoffs (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.warehouse_category_items(id) on delete cascade,
  qty numeric(12,3) not null,
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.warehouse_category_inventories (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.warehouse_category_items(id) on delete cascade,
  counted_qty numeric(12,3) not null,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_wcw_item on public.warehouse_category_writeoffs(item_id);
create index if not exists idx_wci_item on public.warehouse_category_inventories(item_id);

-- =============== RLS (широкие политики) ===============
alter table public.warehouse_category_writeoffs  enable row level security;
alter table public.warehouse_category_inventories enable row level security;

drop policy if exists wcw_sel on public.warehouse_category_writeoffs;
drop policy if exists wcw_ins on public.warehouse_category_writeoffs;
drop policy if exists wcw_del on public.warehouse_category_writeoffs;
drop policy if exists wcw_upd on public.warehouse_category_writeoffs;

drop policy if exists wcinv_sel on public.warehouse_category_inventories;
drop policy if exists wcinv_ins on public.warehouse_category_inventories;
drop policy if exists wcinv_del on public.warehouse_category_inventories;
drop policy if exists wcinv_upd on public.warehouse_category_inventories;

create policy wcw_sel  on public.warehouse_category_writeoffs   for select to anon, authenticated using (true);
create policy wcw_ins  on public.warehouse_category_writeoffs   for insert to anon, authenticated with check (true);
create policy wcw_upd  on public.warehouse_category_writeoffs   for update to anon, authenticated using (true) with check (true);
create policy wcw_del  on public.warehouse_category_writeoffs   for delete to anon, authenticated using (true);

create policy wcinv_sel on public.warehouse_category_inventories for select to anon, authenticated using (true);
create policy wcinv_ins on public.warehouse_category_inventories for insert to anon, authenticated with check (true);
create policy wcinv_upd on public.warehouse_category_inventories for update to anon, authenticated using (true) with check (true);
create policy wcinv_del on public.warehouse_category_inventories for delete to anon, authenticated using (true);

-- =============== realtime ===============
do $$
begin
  begin alter publication supabase_realtime add table public.warehouse_category_writeoffs;    exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.warehouse_category_inventories; exception when duplicate_object then null; end;
end$$;
------------------------------------------------------------------------------------------------------------------

-- ============================================================================
-- WAREHOUSE ARRIVALS — MINIMAL PATCH (run AFTER your existing schema)
-- Generated: 2025-09-30T21:25:08.729042Z
-- Safe to re-run (idempotent).
-- This patch ONLY adds arrivals logs, triggers, RLS, realtime, and an RPC.
-- ============================================================================

-- Ensure uuid generator exists (no-op if already installed)

-- 1) ARRIVAL TABLES -----------------------------------------------------------

create table if not exists public.paints_arrivals (
  id uuid primary key default gen_random_uuid(),
  paint_id uuid not null references public.paints(id) on delete cascade,
  qty numeric(14,3) not null check (qty > 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.materials_arrivals (
  id uuid primary key default gen_random_uuid(),
  material_id uuid not null references public.materials(id) on delete cascade,
  qty numeric(14,3) not null check (qty > 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.papers_arrivals (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers(id) on delete cascade,
  qty numeric(14,3) not null check (qty > 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.warehouse_stationery_arrivals (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.warehouse_stationery(id) on delete cascade,
  qty numeric not null check (qty > 0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);

-- 2) RLS (read=public, write=authenticated) ----------------------------------
alter table public.paints_arrivals enable row level security;
alter table public.materials_arrivals enable row level security;
alter table public.papers_arrivals enable row level security;
alter table public.warehouse_stationery_arrivals enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename='paints_arrivals' and policyname='paints_arrivals_select_public') then
    create policy paints_arrivals_select_public on public.paints_arrivals for select to public using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='paints_arrivals' and policyname='paints_arrivals_all_auth') then
    create policy paints_arrivals_all_auth on public.paints_arrivals for all to authenticated using (true) with check (true);
  end if;

  if not exists (select 1 from pg_policies where tablename='materials_arrivals' and policyname='materials_arrivals_select_public') then
    create policy materials_arrivals_select_public on public.materials_arrivals for select to public using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='materials_arrivals' and policyname='materials_arrivals_all_auth') then
    create policy materials_arrivals_all_auth on public.materials_arrivals for all to authenticated using (true) with check (true);
  end if;

  if not exists (select 1 from pg_policies where tablename='papers_arrivals' and policyname='papers_arrivals_select_public') then
    create policy papers_arrivals_select_public on public.papers_arrivals for select to public using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='papers_arrivals' and policyname='papers_arrivals_all_auth') then
    create policy papers_arrivals_all_auth on public.papers_arrivals for all to authenticated using (true) with check (true);
  end if;

  if not exists (select 1 from pg_policies where tablename='warehouse_stationery_arrivals' and policyname='wh_st_arrivals_select_public') then
    create policy wh_st_arrivals_select_public on public.warehouse_stationery_arrivals for select to public using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='warehouse_stationery_arrivals' and policyname='wh_st_arrivals_all_auth') then
    create policy wh_st_arrivals_all_auth on public.warehouse_stationery_arrivals for all to authenticated using (true) with check (true);
  end if;
end $$;

-- 3) APPLY ARRIVAL TRIGGERS ---------------------------------------------------
create or replace function public.paints_apply_arrival() returns trigger as $$
begin
  update public.paints set quantity = coalesce(quantity,0) + new.qty, updated_at = now()
  where id = new.paint_id;
  return new;
end $$ language plpgsql;

drop trigger if exists trg_paints_arrival_apply on public.paints_arrivals;
create trigger trg_paints_arrival_apply after insert on public.paints_arrivals
for each row execute function public.paints_apply_arrival();

create or replace function public.materials_apply_arrival() returns trigger as $$
begin
  update public.materials set quantity = coalesce(quantity,0) + new.qty, updated_at = now()
  where id = new.material_id;
  return new;
end $$ language plpgsql;

drop trigger if exists trg_materials_arrival_apply on public.materials_arrivals;
create trigger trg_materials_arrival_apply after insert on public.materials_arrivals
for each row execute function public.materials_apply_arrival();

create or replace function public.papers_apply_arrival() returns trigger as $$
begin
  update public.papers set quantity = coalesce(quantity,0) + new.qty, updated_at = now()
  where id = new.paper_id;
  return new;
end $$ language plpgsql;

drop trigger if exists trg_papers_arrival_apply on public.papers_arrivals;
create trigger trg_papers_arrival_apply after insert on public.papers_arrivals
for each row execute function public.papers_apply_arrival();

create or replace function public.wh_stationery_apply_arrival() returns trigger as $$
begin
  update public.warehouse_stationery s
     set quantity = coalesce(s.quantity,0) + coalesce(new.qty,0), updated_at = now()
   where s.id = new.item_id;
  return new;
end $$ language plpgsql;

drop trigger if exists trg_wh_st_arrival_apply on public.warehouse_stationery_arrivals;
create trigger trg_wh_st_arrival_apply after insert on public.warehouse_stationery_arrivals
for each row execute function public.wh_stationery_apply_arrival();

-- 4) REALTIME -----------------------------------------------------------------
do $$
begin
  begin alter publication supabase_realtime add table public.paints_arrivals;                  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.materials_arrivals;               exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.papers_arrivals;                  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.warehouse_stationery_arrivals;    exception when duplicate_object then null; end;
end $$;

-- 5) RPC (optional helper to insert arrivals) --------------------------------
create or replace function public.arrival_add(_type text, _item uuid, _qty numeric, _note text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if _type = 'paint' then
    insert into public.paints_arrivals(paint_id, qty, note, created_by) values (_item, _qty, _note, auth.uid());
  elsif _type = 'material' then
    insert into public.materials_arrivals(material_id, qty, note, created_by) values (_item, _qty, _note, auth.uid());
  elsif _type = 'paper' then
    insert into public.papers_arrivals(paper_id, qty, note, created_by) values (_item, _qty, _note, auth.uid());
  elsif _type = 'stationery' then
    insert into public.warehouse_stationery_arrivals(item_id, qty, note, created_by) values (_item, _qty, _note, auth.uid());
  end if;
end $$;

-- DONE ------------------------------------------------------------------------
alter table if exists paints_arrivals                  add column if not exists by_name text;
alter table if exists materials_arrivals               add column if not exists by_name text;
alter table if exists papers_arrivals                  add column if not exists by_name text;
alter table if exists warehouse_stationery_arrivals    add column if not exists by_name text;

alter table if exists paint_writeoffs                  add column if not exists by_name text;
alter table if exists material_writeoffs               add column if not exists by_name text;
alter table if exists paper_writeoffs                  add column if not exists by_name text;
alter table if exists warehouse_stationery_writeoffs   add column if not exists by_name text;

alter table if exists paint_inventories                add column if not exists by_name text;
alter table if exists material_inventories             add column if not exists by_name text;
alter table if exists paper_inventories                add column if not exists by_name text;
alter table if exists warehouse_stationery_inventories add column if not exists by_name text;

-- если хотите видеть имя и в analytics:
alter table if exists analytics                         add column if not exists by_name text;
--------------------------------------------------------------------------------------------------------
-- Add `by_name` to all possible warehouse log tables (idempotent)
alter table if exists arrivals                            add column if not exists by_name text;
alter table if exists paints_arrivals                     add column if not exists by_name text;
alter table if exists materials_arrivals                  add column if not exists by_name text;
alter table if exists papers_arrivals                     add column if not exists by_name text;
alter table if exists warehouse_stationery_arrivals       add column if not exists by_name text;
alter table if exists stationery_arrivals                 add column if not exists by_name text;

alter table if exists paint_writeoffs                     add column if not exists by_name text;
alter table if exists material_writeoffs                  add column if not exists by_name text;
alter table if exists paper_writeoffs                     add column if not exists by_name text;
alter table if exists warehouse_stationery_writeoffs      add column if not exists by_name text;
alter table if exists paints_writeoffs                    add column if not exists by_name text;
alter table if exists materials_writeoffs                 add column if not exists by_name text;
alter table if exists papers_writeoffs                    add column if not exists by_name text;

alter table if exists paint_inventories                   add column if not exists by_name text;
alter table if exists material_inventories                add column if not exists by_name text;
alter table if exists paper_inventories                   add column if not exists by_name text;
alter table if exists warehouse_stationery_inventories    add column if not exists by_name text;
alter table if exists paints_inventories                  add column if not exists by_name text;
alter table if exists materials_inventories               add column if not exists by_name text;
alter table if exists papers_inventories                  add column if not exists by_name text;

-- (Optional) also keep analytics aligned:
alter table if exists analytics                           add column if not exists by_name text;
------------------------------------------------------------------------------------------------------
create or replace function public.arrival_add(
  _type text, _item uuid, _qty numeric, _note text default null, _by_name text default null
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if _type = 'paint' then
    insert into public.paints_arrivals(paint_id, qty, note, created_by, by_name)
    values (_item, _qty, _note, auth.uid(), _by_name);
  elsif _type = 'material' then
    insert into public.materials_arrivals(material_id, qty, note, created_by, by_name)
    values (_item, _qty, _note, auth.uid(), _by_name);
  elsif _type = 'paper' then
    insert into public.papers_arrivals(paper_id, qty, note, created_by, by_name)
    values (_item, _qty, _note, auth.uid(), _by_name);
  elsif _type = 'stationery' then
    insert into public.warehouse_stationery_arrivals(item_id, qty, note, created_by, by_name)
    values (_item, _qty, _note, auth.uid(), _by_name);
  end if;
end $$;
---------------------------------------------------------------------------------------------------------------------
create or replace function public.writeoff(
  type text, item uuid, qty numeric, reason text, by_name text default null
) returns void
language plpgsql security definer as $$
begin
  if type='paint' then
    insert into public.paints_writeoffs(paint_id, qty, reason, created_by, by_name)
    values (item, qty, reason, auth.uid(), by_name);
  elsif type='material' then
    insert into public.materials_writeoffs(material_id, qty, reason, created_by, by_name)
    values (item, qty, reason, auth.uid(), by_name);
  elsif type='paper' then
    insert into public.papers_writeoffs(paper_id, qty, reason, created_by, by_name)
    values (item, qty, reason, auth.uid(), by_name);
  elsif type='stationery' then
    insert into public.stationery_writeoffs(item_id, qty, reason, created_by, by_name)
    values (item, qty, reason, auth.uid(), by_name);
  end if;
end $$;

create or replace function public.inventory_set(
  type text, item uuid, counted numeric, note text, by_name text default null
) returns void
language plpgsql security definer as $$
begin
  if type='paint' then
    insert into public.paints_inventories(paint_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  elsif type='material' then
    insert into public.materials_inventories(material_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  elsif type='paper' then
    insert into public.papers_inventories(paper_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  elsif type='stationery' then
    insert into public.stationery_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  end if;
end $$;
-----------------------------------------------------------------------------------------------------------------------
-- Логи списаний по динамическим категориям
ALTER TABLE public.warehouse_category_writeoffs
  ADD COLUMN IF NOT EXISTS by_name text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- Логи инвентаризаций по динамическим категориям
ALTER TABLE public.warehouse_category_inventories
  ADD COLUMN IF NOT EXISTS by_name text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- (на всякий случай) Включим RLS и дадим право вставки/обновления для authenticated
ALTER TABLE public.warehouse_category_writeoffs ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY wr_cat_writeoffs_ins ON public.warehouse_category_writeoffs
  FOR INSERT TO authenticated WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.warehouse_category_inventories ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY wr_cat_inventories_ins ON public.warehouse_category_inventories
  FOR INSERT TO authenticated WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.warehouse_category_items ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY wr_cat_items_upd ON public.warehouse_category_items
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
---------------------------------------------------------------------------------------
-- 0) На всякий случай (для gen_random_uuid)

-- 1) Таблица без UNIQUE по lower(name)
create table if not exists paper_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  format text not null,
  grammage text not null,
  created_at timestamptz not null default now()
);

-- 2) Уникальный ИНДЕКС на выражение + поля
create unique index if not exists ux_paper_items_lname_fmt_gr
  on paper_items (lower(name), format, grammage);

-- 3) Журнал движений
create table if not exists paper_moves (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references paper_items(id) on delete cascade,
  qty_m numeric not null,
  reason text,
  order_id uuid,
  created_at timestamptz not null default now()
);

-- 4) Представление остатков
create or replace view paper_stock_view as
select
  i.id as item_id,
  i.name,
  i.format,
  i.grammage,
  coalesce(sum(m.qty_m), 0) as qty_m
from paper_items i
left join paper_moves m on m.item_id = i.id
group by i.id, i.name, i.format, i.grammage;

-- 5) Приход: upsert по уникальному ИНДЕКСУ (выражение поддерживается)
create or replace function paper_receive(
  p_name text,
  p_format text,
  p_grammage text,
  p_qty_m numeric,
  p_reason text default null
) returns uuid
language plpgsql
as $$
declare
  v_item_id uuid;
begin
  if p_qty_m <= 0 then
    raise exception 'Приход должен быть > 0';
  end if;

  insert into paper_items (name, format, grammage)
  values (p_name, p_format, p_grammage)
  on conflict (lower(name), format, grammage)
  do update set name = excluded.name
  returning id into v_item_id;

  insert into paper_moves (item_id, qty_m, reason)
  values (v_item_id, p_qty_m, coalesce(p_reason, 'Приход'));

  return v_item_id;
end;
$$;

-- 6) Расход: проверка на минус
create or replace function paper_consume(
  p_name text,
  p_format text,
  p_grammage text,
  p_qty_m numeric,
  p_order_id uuid default null,
  p_reason text default null
) returns uuid
language plpgsql
as $$
declare
  v_item_id uuid;
  v_stock numeric;
begin
  if p_qty_m <= 0 then
    raise exception 'Расход должен быть > 0';
  end if;

  select id into v_item_id
  from paper_items
  where lower(name) = lower(p_name)
    and format = p_format
    and grammage = p_grammage;

  if v_item_id is null then
    raise exception 'Такой бумаги (номенклатура/формат/грамаж) нет на складе';
  end if;

  select coalesce(sum(qty_m),0) into v_stock
  from paper_moves
  where item_id = v_item_id;

  if v_stock < p_qty_m then
    raise exception 'На складе не хватает материала: есть % м, нужно % м', v_stock, p_qty_m;
  end if;

  insert into paper_moves (item_id, qty_m, order_id, reason)
  values (v_item_id, -p_qty_m, p_order_id, coalesce(p_reason, 'Расход'));

  return v_item_id;
end;
$$;

-- 7) Индекс для быстрого поиска по названию
create index if not exists idx_paper_items_name on paper_items (lower(name));
--------------------------------------------------------------------------------------------------------

-- =============================================================
--  Warehouse: PENS (Ручки / ручки для пакетов)
--  Supabase/Postgres SQL
--  Creates a dedicated storage separate from stationery.
-- =============================================================

-- Extensions (Supabase usually has these enabled; keep for local dev)

-- ------------------------------
-- Base table
-- ------------------------------
create table if not exists public.warehouse_pens (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- карточка товара
  name              text        not null,     -- Наименование
  color             text        not null,     -- Цвет
  unit              text        not null default 'пар', -- Ед. изм. (по умолчанию "пар")
  quantity          numeric(14,3) not null default 0,   -- Текущий остаток (в парах)

  -- пороги остатков
  low_threshold     numeric(14,3),      -- Низкий остаток (желтый)
  critical_threshold numeric(14,3),     -- Очень низкий остаток (красный)

  note              text,               -- Заметки

  -- служебные
  unique_lower_key  text generated always as ( lower(trim(name)) || '|' || lower(trim(color)) ) stored,
  constraint uq_pens_unique_name_color unique (unique_lower_key),
  constraint ck_pens_qty_nonneg check (quantity >= 0),
  constraint ck_pens_thresholds_nonneg check (
      (low_threshold is null or low_threshold >= 0) and
      (critical_threshold is null or critical_threshold >= 0)
  )
);

-- updated_at trigger
create or replace function public.fn_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_pens_updated_at on public.warehouse_pens;
create trigger trg_pens_updated_at
before update on public.warehouse_pens
for each row execute function public.fn_set_updated_at();

-- ------------------------------
-- Movements: arrivals / writeoffs / inventories
-- ------------------------------

create table if not exists public.warehouse_pens_arrivals (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  item_id     uuid not null references public.warehouse_pens(id) on delete cascade,
  qty         numeric(14,3) not null check (qty > 0),
  note        text
);

create table if not exists public.warehouse_pens_writeoffs (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  item_id     uuid not null references public.warehouse_pens(id) on delete cascade,
  qty         numeric(14,3) not null check (qty > 0),
  reason      text,
  order_id    uuid  -- опционально, связь с заказом
);

create table if not exists public.warehouse_pens_inventories (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  item_id     uuid not null references public.warehouse_pens(id) on delete cascade,
  factual     numeric(14,3) not null check (factual >= 0),
  note        text
);

-- -------------
-- Triggers to keep quantity in sync
-- -------------

create or replace function public.fn_pens_apply_arrival()
returns trigger language plpgsql as $$
begin
  update public.warehouse_pens
     set quantity = quantity + new.qty,
         updated_at = now()
   where id = new.item_id;
  return new;
end;
$$;

drop trigger if exists trg_pens_arrival on public.warehouse_pens_arrivals;
create trigger trg_pens_arrival
after insert on public.warehouse_pens_arrivals
for each row execute function public.fn_pens_apply_arrival();


create or replace function public.fn_pens_apply_writeoff()
returns trigger language plpgsql as $$
begin
  update public.warehouse_pens
     set quantity = greatest(0, quantity - new.qty),
         updated_at = now()
   where id = new.item_id;
  return new;
end;
$$;

drop trigger if exists trg_pens_writeoff on public.warehouse_pens_writeoffs;
create trigger trg_pens_writeoff
after insert on public.warehouse_pens_writeoffs
for each row execute function public.fn_pens_apply_writeoff();


create or replace function public.fn_pens_apply_inventory()
returns trigger language plpgsql as $$
begin
  update public.warehouse_pens
     set quantity = new.factual,
         updated_at = now()
   where id = new.item_id;
  return new;
end;
$$;

drop trigger if exists trg_pens_inventory on public.warehouse_pens_inventories;
create trigger trg_pens_inventory
after insert on public.warehouse_pens_inventories
for each row execute function public.fn_pens_apply_inventory();


-- ------------------------------
-- RPC helpers (for Supabase)
-- ------------------------------

-- Добавить позицию; если name+color существует, вернём существующую
create or replace function public.pens_upsert(
  p_name text,
  p_color text,
  p_unit text default 'пар',
  p_note text default null,
  p_low_threshold numeric default null,
  p_critical_threshold numeric default null
)
returns uuid
language plpgsql
as $$
declare v_id uuid;
begin
  select id
    into v_id
    from public.warehouse_pens
   where unique_lower_key = lower(trim(p_name)) || '|' || lower(trim(p_color))
   limit 1;

  if v_id is null then
    insert into public.warehouse_pens(name, color, unit, note, low_threshold, critical_threshold)
    values (trim(p_name), trim(p_color), coalesce(nullif(trim(p_unit), ''), 'пар'), nullif(trim(coalesce(p_note,'')), ''), p_low_threshold, p_critical_threshold)
    returning id into v_id;
  else
    update public.warehouse_pens
       set unit = coalesce(nullif(trim(p_unit), ''), unit),
           note = coalesce(nullif(trim(coalesce(p_note, '')), ''), note),
           low_threshold = coalesce(p_low_threshold, low_threshold),
           critical_threshold = coalesce(p_critical_threshold, critical_threshold)
     where id = v_id;
  end if;

  return v_id;
end;
$$;


-- Приход
create or replace function public.pens_arrival(p_item_id uuid, p_qty numeric, p_note text default null)
returns void language plpgsql as $$
begin
  insert into public.warehouse_pens_arrivals(item_id, qty, note)
  values (p_item_id, p_qty, nullif(trim(coalesce(p_note,'')), ''));
end;
$$;

-- Списание (опционально с order_id)
create or replace function public.pens_writeoff(p_item_id uuid, p_qty numeric, p_reason text default null, p_order_id uuid default null)
returns void language plpgsql as $$
begin
  insert into public.warehouse_pens_writeoffs(item_id, qty, reason, order_id)
  values (p_item_id, p_qty, nullif(trim(coalesce(p_reason,'')), ''), p_order_id);
end;
$$;

-- Инвентаризация
create or replace function public.pens_inventory(p_item_id uuid, p_factual numeric, p_note text default null)
returns void language plpgsql as $$
begin
  insert into public.warehouse_pens_inventories(item_id, factual, note)
  values (p_item_id, p_factual, nullif(trim(coalesce(p_note,'')), ''));
end;
$$;


-- ------------------------------
-- Convenience view ( movements )
-- ------------------------------
create or replace view public.vw_pens_movements as
select 'arrival' as kind, a.created_at, a.item_id, a.qty as delta, a.note, null::uuid as order_id
  from public.warehouse_pens_arrivals a
union all
select 'writeoff' as kind, w.created_at, w.item_id, -w.qty as delta, w.reason as note, w.order_id
  from public.warehouse_pens_writeoffs w
union all
select 'inventory' as kind, i.created_at, i.item_id, i.factual as delta, i.note, null::uuid as order_id
  from public.warehouse_pens_inventories i;


-- ------------------------------
-- (Опционально) RLS — включите и скопируйте политики, как для других складов
-- ------------------------------
-- alter table public.warehouse_pens enable row level security;
-- alter table public.warehouse_pens_arrivals enable row level security;
-- alter table public.warehouse_pens_writeoffs enable row level security;
-- alter table public.warehouse_pens_inventories enable row level security;
-- Создайте allow policies по образцу существующих складов.
-----------------------------------------------------------------
alter table public.warehouse_pens
add column if not exists date timestamptz default now();
---------------------------------------------------------------------
alter table public.warehouse_pens
  add column if not exists date timestamptz default now(),
  add column if not exists supplier text;
----------------------------------------------------------------------
alter table public.warehouse_pens_writeoffs add column if not exists by_name text;
alter table public.warehouse_pens_arrivals add column if not exists by_name text;
------------------------------------------------------------------------------------------
create table if not exists public.warehouse_pens_inventories (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.warehouse_pens(id) on delete cascade,
  counted_qty numeric not null check (counted_qty >= 0),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function public.warehouse_pens_apply_inventory()
returns trigger
language plpgsql as $$
begin
  update public.warehouse_pens
     set quantity = new.counted_qty,
         updated_at = now()
   where id = new.item_id;
  return new;
end $$;

drop trigger if exists trg_pens_inventory_apply on public.warehouse_pens_inventories;
create trigger trg_pens_inventory_apply
after insert on public.warehouse_pens_inventories
for each row execute function public.warehouse_pens_apply_inventory();
-------------------------------------------------------------------------------------------

create table if not exists public.warehouse_deleted_records (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id text,
  payload jsonb not null default '{}'::jsonb,
  reason text,
  extra jsonb not null default '{}'::jsonb,
  deleted_by text,
  deleted_at timestamptz not null default now(),
  name text generated always as (
    nullif(coalesce(payload->>'description', payload->>'name', payload->>'title'), '')
  ) stored,
  quantity numeric generated always as (
    case
      when coalesce(payload->>'quantity', payload->>'qty', payload->>'count') ~ '^-?[0-9]+(\.[0-9]+)?$'
        then coalesce(payload->>'quantity', payload->>'qty', payload->>'count')::numeric
      else null
    end
  ) stored,
  unit text generated always as (
    nullif(coalesce(payload->>'unit', payload->>'units'), '')
  ) stored,
  paper_format text generated always as (
    nullif(coalesce(payload->>'format', payload->>'size'), '')
  ) stored,
  grammage text generated always as (
    nullif(payload->>'grammage', '')
  ) stored,
  comment text generated always as (
    nullif(coalesce(payload->>'note', payload->>'comment'), '')
  ) stored,
  employee text generated always as (
    nullif(coalesce(extra->>'employee', payload->>'by_name', deleted_by), '')
  ) stored
);

alter table public.warehouse_deleted_records enable row level security;

create index if not exists warehouse_deleted_records_entity_type_idx
  on public.warehouse_deleted_records (entity_type, deleted_at desc);

create index if not exists warehouse_deleted_records_employee_idx
  on public.warehouse_deleted_records (employee);

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'warehouse_deleted_records'
      and policyname = 'warehouse_deleted_records_select'
  ) then
    create policy warehouse_deleted_records_select on public.warehouse_deleted_records
      for select
      using (auth.uid() is not null);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'warehouse_deleted_records'
      and policyname = 'warehouse_deleted_records_insert'
  ) then
    create policy warehouse_deleted_records_insert on public.warehouse_deleted_records
      for insert
      with check (auth.uid() is not null);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'warehouse_deleted_records'
      and policyname = 'warehouse_deleted_records_update'
  ) then
    create policy warehouse_deleted_records_update on public.warehouse_deleted_records
      for update
      using (auth.uid() is not null);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'warehouse_deleted_records'
      and policyname = 'warehouse_deleted_records_delete'
  ) then
    create policy warehouse_deleted_records_delete on public.warehouse_deleted_records
      for delete
      using (auth.uid() is not null);
  end if;
end $$;
----------------------------------------------------------------------------------------------------------
alter table public.stationery_inventories
add constraint fk_stationery_inv_item
foreign key (item_id) references public.stationery(id) on delete cascade;
-----------------------------------------------------------------------------------------------------------
alter table public.stationery_inventories
add column by_name text;
--------------------------------------------------------------------------------------------------------------
drop function if exists public.inventory_set(type text, item uuid, counted numeric, note text, by_name text);
--------------------------------------------------------------------------------------------------------------------------
create or replace function public.inventory_set(
  type text,
  item uuid,
  counted numeric,
  note text,
  by_name text
)
returns void
language plpgsql
as $$
begin
  if type = 'materials' then
    insert into public.materials_inventories(material_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  ELSIF type = 'paper' then
    insert into public.warehouse_paper_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  ELSIF type = 'stationery' then
    insert into public.stationery_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  ELSIF type = 'pens' then
    insert into public.warehouse_pens_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  end if;
end;
$$;
--------------------------------------------------------------------------------------------------------------
ALTER TABLE public.forms_series
  ADD COLUMN IF NOT EXISTS is_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS disabled_comment text;

-- Обновить кэш PostgREST
NOTIFY pgrst, 'reload schema';

----------------------------------------------------------------------------------------------------------------
alter table public.warehouse_pens_inventories
  add column if not exists counted_qty numeric(14,3) not null default 0;
--------------------------------------------------------------------------------------------------------------
alter table public.warehouse_pens_inventories
  add column if not exists counted_qty numeric,
  alter column factual drop not null;
-------------------------------------------------------------------------------------------------------------------
-- 1. Убедимся, что quantity всегда существует и по умолчанию = 0
alter table public.warehouse_pens
  alter column quantity drop not null,
  alter column quantity set default 0;

-- 2. На всякий случай: исправим возможные null'ы в уже существующих строках
update public.warehouse_pens
  set quantity = 0
  where quantity is null;
---------------------------------------------------------------------------------------------------------------------
-- Добавляем колонку имени сотрудника в инвентаризацию ручек
alter table public.warehouse_pens_inventories
  add column if not exists by_name text;

-- Обновляем кеш схемы PostgREST
notify pgrst, 'reload schema';
----------------------------------------------------------------------------------------------------------------------------
-- Удаляем старый некорректный внешний ключ
alter table public.stationery_inventories
  drop constraint if exists stationery_inventories_item_id_fkey;

-- Добавляем новый, правильный внешний ключ на warehouse_stationery
alter table public.stationery_inventories
  add constraint stationery_inventories_item_id_fkey
  foreign key (item_id)
  references public.warehouse_stationery(id)
  on delete cascade;

-- Обновляем кэш схемы
notify pgrst, 'reload schema';
---------------------------------------------------------------------------------------------------------------
create or replace function public.inventory_set(
  type text, item uuid, counted numeric, note text, by_name text default null
) returns void
language plpgsql security definer as $$
begin
  if type='paint' then
    insert into public.paints_inventories(paint_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  elsif type='material' then
    insert into public.materials_inventories(material_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  elsif type='paper' then
    insert into public.papers_inventories(paper_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  elsif type='stationery' then
    insert into public.warehouse_stationery_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  elsif type='pens' then
    insert into public.warehouse_pens_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  end if;
end $$;

notify pgrst, 'reload schema';
----------------------------------------------------------------------------------------------------------------------
-- Удаляем старый внешний ключ
alter table public.stationery_inventories
  drop constraint if exists fk_stationery_inv_item;

-- Создаем правильный внешний ключ на warehouse_stationery
alter table public.stationery_inventories
  add constraint fk_stationery_inv_item
  foreign key (item_id) references public.warehouse_stationery(id)
  on delete cascade;

-- Обновляем кэш схемы
notify pgrst, 'reload schema';
----------------------------------------------------------------------------------------------------
-- Исправленная версия функции inventory_set
create or replace function public.inventory_set(
  type text,
  item uuid,
  counted numeric,
  note text,
  by_name text default null
)
returns void
language plpgsql
security definer
as $$
begin
  if type='paint' then
    insert into public.paint_inventories(paint_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  elsif type='material' then
    insert into public.material_inventories(material_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  elsif type='paper' then
    insert into public.warehouse_paper_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  elsif type='stationery' then
    -- 🔹 исправлено: теперь сохраняет в warehouse_stationery_inventories
    insert into public.warehouse_stationery_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  elsif type='pens' then
    insert into public.warehouse_pens_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  end if;
end;
$$;

-- Обновляем кэш схемы
notify pgrst, 'reload schema';
------------------------------------------------------------------------------------------------------------------------
drop function if exists public.inventory_set(text, uuid, numeric, text);
--------------------------------------------------------------------------------------------------------------------
create or replace function public.inventory_set(
  type text,
  item uuid,
  counted numeric,
  note text,
  by_name text default null
)
returns void
language plpgsql
security definer
as $$
begin
  if type='stationery' then
    insert into public.warehouse_stationery_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  elsif type='pens' then
    insert into public.warehouse_pens_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);

  elsif type='paper' then
    insert into public.warehouse_paper_inventories(item_id, counted_qty, note, created_by, by_name)
    values (item, counted, note, auth.uid(), by_name);
  end if;
end;
$$;

notify pgrst, 'reload schema';
--------------------------------------------------------------------------------------------------------------
drop table if exists public.stationery_inventories cascade;
-----------------------------------------------------------------------------------------
ALTER TABLE public.warehouse_stationery_inventories ENABLE ROW LEVEL SECURITY;
CREATE POLICY inv_ins ON public.warehouse_stationery_inventories
  FOR INSERT TO authenticated WITH CHECK (true);
-----------------------------------------------------------------------------------------------------------------
-- Ensure orders table exists before applying subsequent patches.
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid()
);

alter table public.warehouse_stationery_inventories
add column counted_qty numeric;
---------------------------------------------------------------------------------------------------------------
notify pgrst, 'reload schema';
-------------------------------------------------------------------------------------------------------------
alter table public.orders
add column if not exists shipped_at timestamptz;

notify pgrst, 'reload schema';
------------------------------------------------------------------------------------------------------------------
alter table public.orders
add column if not exists shipped_by text;

notify pgrst, 'reload schema';
-------------------------------------------------------------------------------------------------------------------
alter table public.orders
add column if not exists shipped_qty numeric;

notify pgrst, 'reload schema';
-- END of склад.sql\n

-- =============================
-- Patch: ensure created_at (and updated_at) columns exist
-- Safe to run multiple times
-- =============================

-- helper function for updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

-- -------- plan_templates --------
do $$ begin
  if to_regclass('public.plan_templates') is not null then
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='plan_templates' and column_name='created_at'
    ) then
      alter table public.plan_templates add column created_at timestamptz default now();
      update public.plan_templates set created_at = now() where created_at is null;
      alter table public.plan_templates alter column created_at set not null;
    end if;
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='plan_templates' and column_name='updated_at'
    ) then
      alter table public.plan_templates add column updated_at timestamptz default now();
      update public.plan_templates set updated_at = now() where updated_at is null;
      alter table public.plan_templates alter column updated_at set not null;
    end if;
    drop trigger if exists trg_plan_templates_updated_at on public.plan_templates;
    create trigger trg_plan_templates_updated_at
      before update on public.plan_templates
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- -------- orders --------
do $$ begin
  if to_regclass('public.orders') is not null then
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='orders' and column_name='created_at'
    ) then
      alter table public.orders add column created_at timestamptz default now();
      update public.orders set created_at = now() where created_at is null;
      alter table public.orders alter column created_at set not null;
    end if;
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='orders' and column_name='updated_at'
    ) then
      alter table public.orders add column updated_at timestamptz default now();
      update public.orders set updated_at = now() where updated_at is null;
      alter table public.orders alter column updated_at set not null;
    end if;
    drop trigger if exists trg_orders_updated_at on public.orders;
    create trigger trg_orders_updated_at
      before update on public.orders
      for each row execute procedure public.set_updated_at();

    create index if not exists idx_orders_created_at on public.orders (created_at desc);
  end if;
end $$;

-- -------- production_plans --------
do $$ begin
  if to_regclass('public.production_plans') is not null then
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='production_plans' and column_name='created_at'
    ) then
      alter table public.production_plans add column created_at timestamptz default now();
      update public.production_plans set created_at = now() where created_at is null;
      alter table public.production_plans alter column created_at set not null;
    end if;
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='production_plans' and column_name='updated_at'
    ) then
      alter table public.production_plans add column updated_at timestamptz default now();
      update public.production_plans set updated_at = now() where updated_at is null;
      alter table public.production_plans alter column updated_at set not null;
    end if;
    drop trigger if exists trg_production_plans_updated_at on public.production_plans;
    create trigger trg_production_plans_updated_at
      before update on public.production_plans
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- -------- tasks --------
do $$ begin
  if to_regclass('public.tasks') is not null then
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='tasks' and column_name='created_at'
    ) then
      alter table public.tasks add column created_at timestamptz default now();
      update public.tasks set created_at = now() where created_at is null;
      alter table public.tasks alter column created_at set not null;
    end if;
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='tasks' and column_name='updated_at'
    ) then
      alter table public.tasks add column updated_at timestamptz default now();
      update public.tasks set updated_at = now() where updated_at is null;
      alter table public.tasks alter column updated_at set not null;
    end if;
    drop trigger if exists trg_tasks_updated_at on public.tasks;
    create trigger trg_tasks_updated_at
      before update on public.tasks
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- -------- order_events --------
do $$ begin
  if to_regclass('public.order_events') is not null then
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='order_events' and column_name='created_at'
    ) then
      alter table public.order_events add column created_at timestamptz default now();
      update public.order_events set created_at = now() where created_at is null;
      alter table public.order_events alter column created_at set not null;
    end if;
    create index if not exists idx_order_events_created_at on public.order_events (created_at desc);
  end if;
end $$;

-- -------- order_files --------
do $$ begin
  if to_regclass('public.order_files') is not null then
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='order_files' and column_name='created_at'
    ) then
      alter table public.order_files add column created_at timestamptz default now();
      update public.order_files set created_at = now() where created_at is null;
      alter table public.order_files alter column created_at set not null;
    end if;
  end if;
end $$;
----------------------------------------------------------------------------------------------------------------------

-- =============================
-- Patch: ensure 'orders' has all expected columns + refresh PostgREST cache
-- Safe to run multiple times.
-- =============================


-- Helper trigger function for updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

-- Ensure table exists
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid()
);

-- Add columns if missing (with sensible defaults so we can set NOT NULL)
do $$ begin
  -- manager
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='manager') then
    alter table public.orders add column manager text not null default '';
  end if;
  -- customer
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='customer') then
    alter table public.orders add column customer text not null default '';
  end if;
  -- order_date
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='order_date') then
    alter table public.orders add column order_date timestamptz not null default now();
  end if;
  -- due_date
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='due_date') then
    alter table public.orders add column due_date timestamptz not null default now();
  end if;
  -- product
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='product') then
    alter table public.orders add column product jsonb not null default '{}'::jsonb;
  end if;
  -- additional_params
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='additional_params') then
    alter table public.orders add column additional_params text[] not null default '{}'::text[];
  end if;
  -- handle
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='handle') then
    alter table public.orders add column handle text not null default '-';
  end if;
  -- cardboard
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='cardboard') then
    alter table public.orders add column cardboard text not null default 'нет';
  end if;
  -- material
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='material') then
    alter table public.orders add column material jsonb;
  end if;
  -- makeready
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='makeready') then
    alter table public.orders add column makeready double precision not null default 0;
  end if;
  -- val
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='val') then
    alter table public.orders add column val double precision not null default 0;
  end if;
  -- pdf_url
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='pdf_url') then
    alter table public.orders add column pdf_url text;
  end if;
  -- stage_template_id
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='stage_template_id') then
    alter table public.orders add column stage_template_id uuid;
  end if;
  -- contract_signed
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='contract_signed') then
    alter table public.orders add column contract_signed boolean not null default false;
  end if;
  -- payment_done
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='payment_done') then
    alter table public.orders add column payment_done boolean not null default false;
  end if;
  -- comments
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='comments') then
    alter table public.orders add column comments text not null default '';
  end if;
  -- status
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='status') then
    alter table public.orders add column status text not null default 'newOrder';
  end if;
  -- assignment_id
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='assignment_id') then
    alter table public.orders add column assignment_id text;
  end if;
  -- assignment_created
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='assignment_created') then
    alter table public.orders add column assignment_created boolean not null default false;
  end if;
  -- created_at
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='created_at') then
    alter table public.orders add column created_at timestamptz not null default now();
  end if;
  -- updated_at
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='updated_at') then
    alter table public.orders add column updated_at timestamptz not null default now();
  end if;
end $$;

-- Ensure/refresh updated_at trigger
drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at
before update on public.orders
for each row execute procedure public.set_updated_at();

-- Useful indexes
create index if not exists idx_orders_created_at on public.orders (created_at desc);
create index if not exists idx_orders_customer on public.orders (customer);
create index if not exists idx_orders_status on public.orders (status);

-- Make sure RLS is enabled with permissive policies (adjust to your needs)
alter table public.orders enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='orders' and policyname='orders_select_all') then
    create policy orders_select_all on public.orders for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='orders' and policyname='orders_modify_auth') then
    create policy orders_modify_auth on public.orders for all to authenticated using (true) with check (true);
  end if;
end $$;

-- IMPORTANT: refresh PostgREST schema cache to avoid PGRST204 errors
-- (Supabase PostgREST listens on channel "pgrst")
notify pgrst, 'reload schema';
-----------------------------------------------------------------------------------------------------------------

-- =============================================================
-- Storage bucket fix (works even if storage.create_bucket signature differs)
-- Creates 'order-pdfs' bucket if missing and adds RLS policies.
-- Safe to run multiple times.
-- =============================================================

-- 1) Create bucket if not exists, trying multiple function signatures, else fall back to INSERT
do $$
begin
  if not exists (select 1 from storage.buckets where id = 'order-pdfs') then
    begin
      -- Try: storage.create_bucket(id) (very old)
      perform storage.create_bucket('order-pdfs');
    exception
      when undefined_function then
        begin
          -- Try: storage.create_bucket(id, name, public)
          perform storage.create_bucket('order-pdfs', 'order-pdfs', false);
        exception
          when undefined_function then
            begin
              -- Try: storage.create_bucket(id, public := false)
              perform storage.create_bucket('order-pdfs', public := false);
            exception
              when others then
                -- Last resort: direct insert (works on all versions)
                insert into storage.buckets (id, name, public)
                values ('order-pdfs', 'order-pdfs', false)
                on conflict (id) do nothing;
            end;
        end;
    end;
  end if;
end
$$;

-- 2) RLS policies on storage.objects for 'order-pdfs'
do $$ begin
  if has_table_privilege('storage.objects', 'ALTER') then
    if not exists (
      select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='order_pdfs_insert_auth'
    ) then
      create policy "order_pdfs_insert_auth" on storage.objects for insert to authenticated
        with check (bucket_id = 'order-pdfs');
    end if;

    if not exists (
      select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='order_pdfs_update_owner'
    ) then
      create policy "order_pdfs_update_owner" on storage.objects for update to authenticated
        using (bucket_id = 'order-pdfs' and owner = auth.uid())
        with check (bucket_id = 'order-pdfs' and owner = auth.uid());
    end if;

    if not exists (
      select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='order_pdfs_delete_owner'
    ) then
      create policy "order_pdfs_delete_owner" on storage.objects for delete to authenticated
        using (bucket_id = 'order-pdfs' and owner = auth.uid());
    end if;

    if not exists (
      select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='order_pdfs_select_auth'
    ) then
      create policy "order_pdfs_select_auth" on storage.objects for select to authenticated
        using (bucket_id = 'order-pdfs');
    end if;
  end if;
end $$;

-- 3) Optional: ensure bucket stays private (set public=false)
update storage.buckets set public = false where id = 'order-pdfs';

-- 4) Refresh PostgREST schema (just in case)
notify pgrst, 'reload schema';
--------------------------------------------------------------------------------------------------------------------------

-- =============================================================
-- Bootstrap for public.plan_templates (idempotent)
-- Creates table + trigger + RLS + realtime + cache refresh
-- =============================================================


-- updated_at helper
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

-- 1) Table
create table if not exists public.plan_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  stages jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Harden columns in case table existed but without defaults
alter table public.plan_templates
  alter column id set default gen_random_uuid(),
  alter column id set not null,
  alter column stages set default '[]'::jsonb,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

drop trigger if exists trg_plan_templates_updated_at on public.plan_templates;
create trigger trg_plan_templates_updated_at
before update on public.plan_templates
for each row execute procedure public.set_updated_at();

create index if not exists idx_plan_templates_created_at on public.plan_templates (created_at desc);

-- 2) RLS
alter table public.plan_templates enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='plan_templates' and policyname='plan_templates_select_all') then
    create policy plan_templates_select_all on public.plan_templates for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='plan_templates' and policyname='plan_templates_modify_auth') then
    create policy plan_templates_modify_auth on public.plan_templates for all to authenticated using (true) with check (true);
  end if;
end $$;

-- 3) Realtime
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'plan_templates'
  ) then
    alter publication supabase_realtime add table public.plan_templates;
  end if;
end $$;

-- 4) PostgREST schema cache refresh
notify pgrst, 'reload schema';

-- 5) Optional seed (uncomment to create a sample template)
/*
insert into public.plan_templates (name, stages)
values ('Базовая очередь', jsonb_build_array(
  jsonb_build_object('stageId','prepress','title','Препресс'),
  jsonb_build_object('stageId','print','title','Печать'),
  jsonb_build_object('stageId','post','title','Постобработка')
));
*/
------------------------------------------------------------------------------------------------------------------

-- === 1) Таблица очередей (если её ещё нет)
create table if not exists public.queues (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- === 2) Добавляем колонку queue_id в orders, если отсутствует
alter table public.orders
  add column if not exists queue_id uuid;

-- === 3) Внешний ключ (безопасно, не упадёт если уже есть)
do $$
begin
  alter table public.orders
    add constraint orders_queue_id_fkey
    foreign key (queue_id) references public.queues(id)
    on delete set null;
exception when duplicate_object then
  null;
end $$;

-- === 4) Индекс по queue_id
create index if not exists idx_orders_queue on public.orders(queue_id);

-- === 5) RLS для queues (минимально необходимое)
alter table public.queues enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='queues' and policyname='queues_select_all'
  ) then
    create policy queues_select_all on public.queues for select using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='queues' and policyname='queues_modify_auth'
  ) then
    create policy queues_modify_auth on public.queues for all to authenticated using (true) with check (true);
  end if;
end $$;

-- === 6) Сид начальной очереди (опционально)
insert into public.queues (name) values ('Без очереди')
on conflict (name) do nothing;

-- При желании проставим её всем старым заказам, где queue_id ещё null:
update public.orders o
set queue_id = q.id
from public.queues q
where q.name = 'Без очереди' and o.queue_id is null;

-- === 7) Обновляем кеш схемы PostgREST, чтобы клиент не ловил PGRST204/205
notify pgrst, 'reload schema';
--------------------------------------------------------------------------------------------------------------------

-- ============================================================
-- ERP • Orders module (safe to run multiple times)
-- Covers: orders, order_paints (краски), order_files (PDF),
--         queues, plan_templates (минимальный скелет),
--         Storage bucket 'order-pdfs', RLS, realtime, indices.
-- ============================================================

-- 0) Extensions

-- 1) Helpers: updated_at + created_by autofill
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create or replace function public.set_created_by_default()
returns trigger language plpgsql as $$
begin
  if new.created_by is null then
    new.created_by = auth.uid();
  end if;
  return new;
end $$;

-- 2) Reference tables used by UI (минимум, чтобы не падало)
create table if not exists public.queues (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- Нужна из-за ссылочного поля stage_template_id в orders
create table if not exists public.plan_templates (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
drop trigger if exists trg_plan_templates_updated_at on public.plan_templates;
create trigger trg_plan_templates_updated_at
  before update on public.plan_templates
  for each row execute procedure public.set_updated_at();

-- 3) Главная таблица заказов под все поля из формы
create table if not exists public.orders (
  id                  uuid primary key default gen_random_uuid(),

  -- Блок "Информация о заказе"
  manager             text not null default '',         -- Менеджер
  customer            text not null default '',         -- Заказчик
  order_date          timestamptz not null default now(),
  due_date            timestamptz not null default now(),

  -- Блок "Форма"
  is_old_form         boolean not null default false,   -- тумблер "Старая форма"
  new_form_no         integer,                          -- "Номер новой формы"
  actual_qty          numeric(18,3) not null default 0, -- "Фактическое количество"
  comments            text not null default '',         -- "Комментарии к заказу"

  contract_signed     boolean not null default false,   -- чекбокс
  payment_done        boolean not null default false,   -- чекбокс

  -- Блок "Продукт в заказе"
  product_name        text not null default '',         -- Наименование изделия (dropdown)
  run_size            integer,                          -- Тираж
  width_mm            integer,                          -- Ширина (мм)
  height_mm           integer,                          -- Высота (мм)
  depth_mm            integer,                          -- Глубина (мм)
  material_name       text,                             -- Материал (текст)
  density             text,                             -- Плотность (храним строкой: 80 г/м2, 30 мкн и т.п.)

  leftover_on_stock   text,                             -- "Лишнее на складе" (строкой)
  roll_name           text,                             -- "Ролл"
  width_b             numeric(18,3),                    -- "Ширина b"
  length_l            numeric(18,3),                    -- "Длина L"

  product_params      jsonb,                            -- "Параметры продукта" (большой свободный блок)
  handle              text not null default '-',        -- "Ручки"
  cardboard           text not null default 'нет',      -- "Картон"
  makeready           numeric(18,3) not null default 0, -- "Приладка"
  val                 numeric(18,3) not null default 0, -- "ВАЛ"

  queue_id            uuid references public.queues(id) on delete set null,
  stage_template_id   uuid references public.plan_templates(id) on delete set null,

  -- Прочее (для твоей логики)
  status              text not null default 'newOrder',
  assignment_id       text,
  assignment_created  boolean not null default false,

  -- Хвост служебный
  pdf_url             text,                             -- быстрый прямой URL (опционально)
  created_by          uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  -- Небольшие валидации
  constraint ck_qty_nonneg       check (actual_qty >= 0),
  constraint ck_run_nonneg       check (run_size is null or run_size >= 0),
  constraint ck_dims_nonneg      check (
    (width_mm  is null or width_mm  >= 0) and
    (height_mm is null or height_mm >= 0) and
    (depth_mm  is null or depth_mm  >= 0)
  ),
  constraint ck_bwll_nonneg      check (
    (width_b  is null or width_b  >= 0) and
    (length_l is null or length_l >= 0) and
    (makeready >= 0) and (val >= 0)
  )
);

-- 3.1) Триггеры на orders
drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at
  before update on public.orders
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_orders_created_by on public.orders;
create trigger trg_orders_created_by
  before insert on public.orders
  for each row execute procedure public.set_created_by_default();

-- Полезные индексы
create index if not exists idx_orders_created_at on public.orders (created_at desc);
create index if not exists idx_orders_customer   on public.orders (customer);
create index if not exists idx_orders_status     on public.orders (status);
create index if not exists idx_orders_queue      on public.orders (queue_id);

-- 4) Краски (многозначное поле формы «Краски»)
create table if not exists public.order_paints (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  name        text not null,                     -- наименование краски
  info        text,                              -- кнопка "Инфо"
  qty_kg      numeric(18,3),                     -- "Кол-во (кг)"
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
drop trigger if exists trg_order_paints_updated_at on public.order_paints;
create trigger trg_order_paints_updated_at
  before update on public.order_paints
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_order_paints_created_by on public.order_paints;
create trigger trg_order_paints_created_by
  before insert on public.order_paints
  for each row execute procedure public.set_created_by_default();

create index if not exists idx_order_paints_order on public.order_paints(order_id);

-- 5) Файлы заказа (PDF, можно и несколько)
create table if not exists public.order_files (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id) on delete cascade,
  storage_path text not null,         -- 'orders/<orderId>/<uuid>.pdf' в bucket 'order-pdfs'
  file_name    text,
  mime_type    text,
  file_size    bigint,                -- байты (если передаёшь с клиента)
  public_url   text,                  -- если генерируешь подписанный/публичный URL
  created_by   uuid,
  created_at   timestamptz not null default now()
);

create index if not exists idx_order_files_order on public.order_files(order_id);

-- 5.1) created_by autofill
create or replace function public.set_created_by_default_files()
returns trigger language plpgsql as $$
begin
  if new.created_by is null then
    new.created_by = auth.uid();
  end if;
  return new;
end $$;
drop trigger if exists trg_order_files_created_by on public.order_files;
create trigger trg_order_files_created_by
  before insert on public.order_files
  for each row execute procedure public.set_created_by_default_files();

-- 6) Storage bucket для PDF (осторожный, совместимый с разными версиями)
do $$
begin
  if not exists (select 1 from storage.buckets where id = 'order-pdfs') then
    begin
      perform storage.create_bucket('order-pdfs');                        -- very old
    exception when undefined_function then
      begin
        perform storage.create_bucket('order-pdfs', 'order-pdfs', false); -- mid
      exception when undefined_function then
        begin
          perform storage.create_bucket('order-pdfs', public := false);   -- new
        exception when others then
          insert into storage.buckets (id, name, public)
          values ('order-pdfs', 'order-pdfs', false)
          on conflict (id) do nothing;
        end;
      end;
    end;
  end if;
end $$;

-- Private bucket
update storage.buckets set public = false where id = 'order-pdfs';

-- RLS для объектов только этого bucket’а
do $$ begin
  if has_table_privilege('storage.objects', 'ALTER') then
    if not exists (
      select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='order_pdfs_insert_auth'
    ) then
      create policy "order_pdfs_insert_auth" on storage.objects for insert to authenticated
        with check (bucket_id = 'order-pdfs');
    end if;

    if not exists (
      select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='order_pdfs_update_owner'
    ) then
      create policy "order_pdfs_update_owner" on storage.objects for update to authenticated
        using (bucket_id = 'order-pdfs' and owner = auth.uid())
        with check (bucket_id = 'order-pdfs' and owner = auth.uid());
    end if;

    if not exists (
      select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='order_pdfs_delete_owner'
    ) then
      create policy "order_pdfs_delete_owner" on storage.objects for delete to authenticated
        using (bucket_id = 'order-pdfs' and owner = auth.uid());
    end if;

    if not exists (
      select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='order_pdfs_select_auth'
    ) then
      create policy "order_pdfs_select_auth" on storage.objects for select to authenticated
        using (bucket_id = 'order-pdfs');
    end if;
  end if;
end $$;

-- 7) RLS по таблицам домена «Заказы»
alter table public.orders        enable row level security;
alter table public.order_paints  enable row level security;
alter table public.order_files   enable row level security;
alter table public.queues        enable row level security;
alter table public.plan_templates enable row level security;

-- Позволяем всем авторизованным читать, а изменять — только авторизованным (без ограничений).
-- При необходимости сузим позже (например, по created_by).
do $$ begin
  -- orders
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='orders' and policyname='orders_select_all') then
    create policy orders_select_all on public.orders for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='orders' and policyname='orders_modify_auth') then
    create policy orders_modify_auth on public.orders for all to authenticated using (true) with check (true);
  end if;

  -- order_paints
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='order_paints' and policyname='order_paints_select_all') then
    create policy order_paints_select_all on public.order_paints for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='order_paints' and policyname='order_paints_modify_auth') then
    create policy order_paints_modify_auth on public.order_paints for all to authenticated using (true) with check (true);
  end if;

  -- order_files
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='order_files' and policyname='order_files_select_all') then
    create policy order_files_select_all on public.order_files for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='order_files' and policyname='order_files_modify_auth') then
    create policy order_files_modify_auth on public.order_files for all to authenticated using (true) with check (true);
  end if;

  -- queues
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='queues' and policyname='queues_select_all') then
    create policy queues_select_all on public.queues for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='queues' and policyname='queues_modify_auth') then
    create policy queues_modify_auth on public.queues for all to authenticated using (true) with check (true);
  end if;

  -- plan_templates
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='plan_templates' and policyname='plan_templates_select_all') then
    create policy plan_templates_select_all on public.plan_templates for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='plan_templates' and policyname='plan_templates_modify_auth') then
    create policy plan_templates_modify_auth on public.plan_templates for all to authenticated using (true) with check (true);
  end if;
end $$;

-- 8) Realtime publication (аккуратно добавляем таблицы, если их там нет)
do $$
declare
  pub text := 'supabase_realtime';
begin
  if exists (select 1 from pg_publication where pubname = pub) then
    -- orders
    if not exists (
      select 1 from pg_publication_tables where pubname = pub and schemaname='public' and tablename='orders'
    ) then
      execute format('alter publication %I add table public.orders', pub);
    end if;
    -- order_paints
    if not exists (
      select 1 from pg_publication_tables where pubname = pub and schemaname='public' and tablename='order_paints'
    ) then
      execute format('alter publication %I add table public.order_paints', pub);
    end if;
    -- order_files
    if not exists (
      select 1 from pg_publication_tables where pubname = pub and schemaname='public' and tablename='order_files'
    ) then
      execute format('alter publication %I add table public.order_files', pub);
    end if;
  end if;
end $$;

-- 9) Обновляем кеш схемы PostgREST (иначе PGRST204/205)
notify pgrst, 'reload schema';
-------------------------------------------------------------------------------------------------------------------

-- 1) Функции (на всякий случай переопределим)

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create or replace function public.set_created_by_default()
returns trigger language plpgsql as $$
begin
  if new.created_by is null then
    new.created_by = auth.uid();
  end if;
  return new;
end $$;

-- 2) Добавляем отсутствующие колонки
alter table public.orders        add column if not exists created_by uuid;
alter table public.orders        add column if not exists updated_at timestamptz not null default now();

alter table public.order_paints  add column if not exists created_by uuid;
alter table public.order_paints  add column if not exists updated_at timestamptz not null default now();

alter table public.order_files   add column if not exists created_by uuid;

-- 3) Пересоздаём триггеры под эти колонки
drop trigger if exists trg_orders_updated_at      on public.orders;
create trigger trg_orders_updated_at
  before update on public.orders
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_orders_created_by      on public.orders;
create trigger trg_orders_created_by
  before insert on public.orders
  for each row execute procedure public.set_created_by_default();

drop trigger if exists trg_order_paints_updated_at on public.order_paints;
create trigger trg_order_paints_updated_at
  before update on public.order_paints
  for each row execute procedure public.set_updated_at();

drop trigger if exists trg_order_paints_created_by on public.order_paints;
create trigger trg_order_paints_created_by
  before insert on public.order_paints
  for each row execute procedure public.set_created_by_default();

drop trigger if exists trg_order_files_created_by on public.order_files;
create trigger trg_order_files_created_by
  before insert on public.order_files
  for each row execute procedure public.set_created_by_default();

-- 4) Обновляем кеш PostgREST (убирает PGRST204/205 и «старую» схему у клиента)
notify pgrst, 'reload schema';
-----------------------------------------------------------------------------------------------------------
-- Генератор UUID

-- Гарантируем дефолт на всех PK-UUID
alter table public.orders
  alter column id set default gen_random_uuid();

alter table if exists public.order_paints
  alter column id set default gen_random_uuid();

alter table if exists public.order_files
  alter column id set default gen_random_uuid();

alter table if exists public.queues
  alter column id set default gen_random_uuid();

alter table if exists public.plan_templates
  alter column id set default gen_random_uuid();

-- Быстрый само-тест: сервер должен сам выдать id
-- (можно выполнить и убедиться, что вернулся UUID)
-- insert into public.orders (manager, customer) values ('test','test') returning id;

-- Обновить кеш PostgREST, чтобы клиент увидел изменения
notify pgrst, 'reload schema';
----------------------------------------------------------------------------------------------------------
-- Таблица событий по заказам

create table if not exists public.order_events (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  event_type  text not null,                 -- created / status_change / note / file_added / paint_added / ...
  message     text,                          -- произвольный комментарий
  payload     jsonb,                         -- произвольный JSON (что изменилось, значения и т.п.)
  created_by  uuid,
  created_at  timestamptz not null default now()
);

-- Индексы
create index if not exists idx_order_events_order   on public.order_events(order_id);
create index if not exists idx_order_events_type    on public.order_events(event_type);
create index if not exists idx_order_events_created on public.order_events(created_at desc);

-- created_by проставляем автоматически
create or replace function public.set_created_by_default()
returns trigger language plpgsql as $$
begin
  if new.created_by is null then
    new.created_by = auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists trg_order_events_created_by on public.order_events;
create trigger trg_order_events_created_by
  before insert on public.order_events
  for each row execute procedure public.set_created_by_default();

-- RLS
alter table public.order_events enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='order_events' and policyname='order_events_select_all'
  ) then
    create policy order_events_select_all on public.order_events
      for select using (true);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='order_events' and policyname='order_events_modify_auth'
  ) then
    create policy order_events_modify_auth on public.order_events
      for all to authenticated using (true) with check (true);
  end if;
end $$;

-- Подключим к публикации realtime (без ошибок, если уже есть)
do $$
declare pub text := 'supabase_realtime';
begin
  if exists (select 1 from pg_publication where pubname = pub) then
    if not exists (
      select 1 from pg_publication_tables where pubname = pub and schemaname='public' and tablename='order_events'
    ) then
      execute format('alter publication %I add table public.order_events', pub);
    end if;
  end if;
end $$;

-- Обновить кеш PostgREST, чтобы исчез PGRST205
notify pgrst, 'reload schema';
-----------------------------------------------------------------------------------------------------------------------

-- Безопасно добавляем таблицы в публикацию, только если их там ещё нет
do $$
declare
  pub text := 'supabase_realtime';
begin
  if exists (select 1 from pg_publication where pubname = pub) then

    -- orders
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = pub and schemaname = 'public' and tablename = 'orders'
    ) then
      execute format('alter publication %I add table public.orders', pub);
    end if;

    -- order_paints
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = pub and schemaname = 'public' and tablename = 'order_paints'
    ) then
      execute format('alter publication %I add table public.order_paints', pub);
    end if;

    -- order_files
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = pub and schemaname = 'public' and tablename = 'order_files'
    ) then
      execute format('alter publication %I add table public.order_files', pub);
    end if;

    -- order_events
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = pub and schemaname = 'public' and tablename = 'order_events'
    ) then
      execute format('alter publication %I add table public.order_events', pub);
    end if;

  end if;
end $$;

-- Обновить кеш PostgREST
notify pgrst, 'reload schema';
--------------------------------------------------------------------------------------------------------------

-- Добавим колонку description и синхронизируем кеш PostgREST
alter table public.order_events
  add column if not exists description text;

-- Для уже существующих строк — продублируем message в description (необязательно)
update public.order_events
set description = coalesce(description, message)
where description is null;

-- Обновить кеш схемы, чтобы ушёл PGRST204
notify pgrst, 'reload schema';
--------------------------------------------------------------------------------------------------------------------

alter table public.order_events add column if not exists description text;
update public.order_events set description = coalesce(description, message) where description is null;
notify pgrst, 'reload schema';
------------------------------------------------------------------------------------------------------------------
-- Присвоить человекочитаемые номера всем существующим заказам,
-- где assignment_id ещё не заполнен.
WITH ranked AS (
  SELECT
    id,
    'ЗК-' || to_char(order_date, 'YYYY.MM.DD') || '-' ||
    ROW_NUMBER() OVER (PARTITION BY order_date::date ORDER BY created_at, id) AS new_aid
  FROM public.orders
  WHERE COALESCE(assignment_id, '') = ''
)
UPDATE public.orders o
SET assignment_id = r.new_aid
FROM ranked r
WHERE o.id = r.id;
----------------------------------------------------------------------------------------------------------------


-- add_order_fk_to_production_plans.sql
-- Purpose: Ensure production.plans has order_id with ON DELETE CASCADE and is backfilled from order_code.
-- Run in Supabase SQL editor.

-- 1) Ensure column exists
ALTER TABLE IF EXISTS production.plans
  ADD COLUMN IF NOT EXISTS order_id uuid;

-- 2) Backfill from order_code -> orders.assignment_id
UPDATE production.plans p
   SET order_id = o.id
  FROM public.orders o
 WHERE p.order_id IS NULL
   AND p.order_code IS NOT NULL
   AND o.assignment_id = p.order_code;

-- 3) Recreate FK with CASCADE
ALTER TABLE IF EXISTS production.plans
  DROP CONSTRAINT IF EXISTS plans_order_id_fkey;
ALTER TABLE IF EXISTS production.plans
  ADD CONSTRAINT plans_order_id_fkey
  FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;

-- 4) Helpful index
CREATE INDEX IF NOT EXISTS idx_production_plans_order ON production.plans(order_id);

-- 5) Trigger to auto-fill order_id from order_code on future inserts/updates
CREATE OR REPLACE FUNCTION production.set_plan_order_id_from_code()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.order_id IS NULL AND NEW.order_code IS NOT NULL THEN
    SELECT id INTO NEW.order_id
    FROM public.orders
    WHERE assignment_id = NEW.order_code
    LIMIT 1;
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_plans_set_order_id ON production.plans;
CREATE TRIGGER trg_plans_set_order_id
  BEFORE INSERT OR UPDATE ON production.plans
  FOR EACH ROW EXECUTE FUNCTION production.set_plan_order_id_from_code();

-- 6) Refresh PostgREST cache
SELECT pg_notify('pgrst', 'reload schema');
-------------------------------------------------------------------------------------------------------------------

-- fix_tasks_orphan_order_ids.sql
-- Purpose: Resolve "insert/update on tasks violates foreign key tasks_order_id_fkey"
-- Strategy: Backfill tasks.order_id from linked stages (new & legacy), then show remaining orphans.
-- Safe to run multiple times.

-- 0) Inspect current orphans (rows in tasks whose order_id doesn't exist in orders)
--    Run this to see examples BEFORE fixing:
-- SELECT t.id, t.order_id, t.stage_id, t.status, t.created_at
-- FROM public.tasks t
-- LEFT JOIN public.orders o ON o.id = t.order_id
-- WHERE o.id IS NULL
-- ORDER BY t.created_at DESC
-- LIMIT 50;

-- 1) NEW schema backfill via production.plan_stages -> production.plans(order_id)
--    Only where stage_id is a valid UUID and mapping exists.
UPDATE public.tasks AS t
SET order_id = p.order_id
FROM production.plan_stages AS s
JOIN production.plans AS p ON p.id = s.plan_id
WHERE (t.order_id IS DISTINCT FROM p.order_id)
  AND t.stage_id ~ '^[0-9a-fA-F-]{8}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{12}$'
  AND s.id = t.stage_id::uuid
  AND p.order_id IS NOT NULL;

-- 2) LEGACY schema backfill via public.prod_plan_stages -> public.prod_plans(order_id)
--    Works if t.stage_id stores legacy stage UUID.
UPDATE public.tasks AS t
SET order_id = pl.order_id
FROM public.prod_plan_stages AS s
JOIN public.prod_plans AS pl ON pl.id = s.plan_id
WHERE (t.order_id IS DISTINCT FROM pl.order_id)
  AND t.stage_id ~ '^[0-9a-fA-F-]{8}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{12}$'
  AND s.id = t.stage_id::uuid;

-- 3) Show how many still orphaned AFTER backfill
SELECT count(*) AS remaining_orphans
FROM public.tasks t
LEFT JOIN public.orders o ON o.id = t.order_id
WHERE o.id IS NULL;

-- 4) (Optional) If any still remain and are bogus, you can delete them.
--    UNCOMMENT to delete dangling tasks that refer to non-existent orders.
-- DELETE FROM public.tasks t
-- WHERE NOT EXISTS (SELECT 1 FROM public.orders o WHERE o.id = t.order_id);

-- 5) (Optional) Ask PostgREST to reload schema cache (no harm to run multiple times)
SELECT pg_notify('pgrst','reload schema');
----------------------------------------------------------------------------------------------------

-- Таблица красок заказа
create table if not exists public.order_paints (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  paint_id uuid null references public.paints(id),
  paint_name text not null,
  qty_kg numeric not null default 0,
  info text,
  created_at timestamptz not null default now()
);
create index if not exists idx_order_paints_order on public.order_paints(order_id);
--------------------------------------------------------------------------------------------------------
alter table public.orders add column if not exists is_old_form boolean;
alter table public.orders add column if not exists new_form_no integer;
alter table public.orders add column if not exists form_series text;
alter table public.orders add column if not exists form_code text;
-------------------------------------------------------------------------------------------------------
update public.orders o
set form_series = f.series,
    new_form_no = f.number,
    form_code  = f.code
from public.forms f
where o.form_id = f.id
  and (o.form_series is null or o.new_form_no is null or o.form_code is null);
---------------------------------------------------------------------------------------------------------------
create or replace function public.trg_orders_sync_form_fields()
returns trigger language plpgsql as $$
declare
  v_series text; v_number int; v_code text;
begin
  if new.form_id is null then
    return new;
  end if;

  select series, number, code
    into v_series, v_number, v_code
  from public.forms
  where id = new.form_id;

  new.form_series := v_series;
  new.new_form_no := v_number;
  new.form_code   := v_code;
  return new;
end$$;

drop trigger if exists trg_orders_sync_form_fields on public.orders;
create trigger trg_orders_sync_form_fields
before insert or update of form_id on public.orders
for each row execute function public.trg_orders_sync_form_fields();
-----------------------------------------------------------------------------------------------------------
drop policy if exists orders_update_form_fields on public.orders;

create policy orders_update_form_fields
on public.orders
for update
to authenticated
using (true)
with check (true);
------------------------------------------------------------------------------------------------------
-- Create table to store per-order consumption snapshots (to make write-offs idempotent)
create table if not exists public.order_consumption_snapshots (
  order_id uuid primary key references public.orders(id) on delete cascade,
  paper_qty_m double precision not null default 0,
  paints jsonb not null default '{}'::jsonb,
  stationery jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Basic RLS (adjust to your security model)
alter table public.order_consumption_snapshots enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='order_consumption_snapshots' and policyname='ocs_select_all'
  ) then
    create policy ocs_select_all on public.order_consumption_snapshots
      for select using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='order_consumption_snapshots' and policyname='ocs_upsert_all'
  ) then
    create policy ocs_upsert_all on public.order_consumption_snapshots
      for insert with check (true);
    create policy ocs_update_all on public.order_consumption_snapshots
      for update using (true) with check (true);
  end if;
end $$;

-- Optional helper to keep updated_at fresh
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_order_consumption_snapshots_updated on public.order_consumption_snapshots;
create trigger trg_order_consumption_snapshots_updated
before update on public.order_consumption_snapshots
for each row execute function public.set_updated_at();
------------------------------------------------------------------------------------------------------------
ALTER TABLE public.prod_plans
ADD COLUMN IF NOT EXISTS status text DEFAULT 'planned';
-------------------------------------------------------------------------------------------------------------
alter table orders add column actual_qty numeric(14,3) default 0;
-- END of Заказы.sql\n

-- forms_sync_patch_v2.sql
-- Fixes nested $$ by using $do$ and $fn$ tags. Safe to re-run.

-- ========== 0) Extensions ==========

-- ========== 1) Common updated_at helper ==========
create or replace function public.set_updated_at()
returns trigger language plpgsql as $fn$
begin
  new.updated_at = now();
  return new;
end
$fn$;

-- ========== 2) Series table (exists in your dump; ensure schema & unique) ==========
create table if not exists public.forms_series (
  id uuid primary key default gen_random_uuid(),
  series text not null unique,
  prefix text not null default '',
  suffix text not null default '',
  last_number integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_forms_series_updated_at on public.forms_series;
create trigger trg_forms_series_updated_at
before update on public.forms_series
for each row execute function public.set_updated_at();

-- RLS (simple: all authenticated can read/write — tighten later if needed)
alter table public.forms_series enable row level security;
do $do$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms_series' and policyname='forms_series_all_auth') then
    create policy forms_series_all_auth on public.forms_series for all
      to authenticated using (true) with check (true);
  end if;
end
$do$;

-- ========== 3) FORMS inventory table (NEW) ==========
create table if not exists public.forms (
  id uuid primary key default gen_random_uuid(),
  series text not null default 'F',
  number integer not null,
  prefix text not null default '',
  suffix text not null default '',
  code text generated always as (coalesce(prefix,'') || lpad(number::text, 4, '0') || coalesce(suffix,'')) stored,
  title text,
  description text,
  status text not null default 'in_stock', -- in_stock / assigned / archived
  location text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create unique index if not exists ux_forms_series_number on public.forms(series, number);
create unique index if not exists ux_forms_code on public.forms(code);

drop trigger if exists trg_forms_updated_at on public.forms;
create trigger trg_forms_updated_at
before update on public.forms
for each row execute function public.set_updated_at();

alter table public.forms enable row level security;
do $do$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms' and policyname='forms_select_all') then
    create policy forms_select_all on public.forms for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms' and policyname='forms_all_auth') then
    create policy forms_all_auth on public.forms for all to authenticated using (true) with check (true);
  end if;
end
$do$;

-- Publish realtime (optional)
do $do$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.forms';
    exception when duplicate_object then
      null;
    end;
  end if;
end
$do$;

-- ========== 4) RPC: allocate next form number atomically ==========
create or replace function public.form_allocate(
  p_series text default 'F',
  p_title text default null,
  p_description text default null
)
returns table(id uuid, series text, number integer, code text) 
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_next int;
  v_prefix text;
  v_suffix text;
begin
  -- Increment existing or create series
  with upd as (
    update public.forms_series
       set last_number = last_number + 1
     where series = p_series
     returning last_number, prefix, suffix
  ), ins as (
    insert into public.forms_series (series, prefix, suffix, last_number)
    select p_series, '', '', 1
    where not exists (select 1 from upd)
    returning last_number, prefix, suffix
  )
  select last_number, coalesce(prefix,''), coalesce(suffix,'')
    into v_next, v_prefix, v_suffix
  from upd
  union all
  select last_number, prefix, suffix from ins;

  insert into public.forms(series, number, prefix, suffix, title, description, created_by)
  values (p_series, v_next, v_prefix, v_suffix, p_title, p_description, auth.uid())
  returning forms.id, forms.series, forms.number, forms.code
  into id, series, number, code;

  return;
end
$fn$;

-- ========== 5) Link ORDERS -> FORMS and keep new_form_no in sync ==========
create table if not exists public.orders (id uuid primary key default gen_random_uuid());

alter table public.orders
  add column if not exists form_id uuid references public.forms(id) on delete set null;

-- Trigger function to keep new_form_no in sync (create unconditionally)
create or replace function public.trg_orders_sync_form_no()
returns trigger language plpgsql as $fn$
declare
  v_num integer;
begin
  if new.form_id is not null then
    select number into v_num from public.forms where id = new.form_id;
    new.new_form_no := v_num;
  end if;
  return new;
end
$fn$;

-- Conditionally create trigger only if orders.new_form_no column exists
do $do$
begin
  if exists (
    select 1 from information_schema.columns 
    where table_schema='public' and table_name='orders' and column_name='new_form_no'
  ) then
    drop trigger if exists trg_orders_sync_form_no on public.orders;
    create trigger trg_orders_sync_form_no
      before insert or update of form_id on public.orders
      for each row execute function public.trg_orders_sync_form_no();
  end if;
end
$do$;

-- Optional: convenient view for UI
create or replace view public.v_orders_with_form as
select o.*,
       f.series   as form_series,
       f.number   as form_number,
       f.code     as form_code,
       f.status   as form_status
from public.orders o
left join public.forms f on f.id = o.form_id;

-- Refresh PostgREST cache
notify pgrst, 'reload schema';
------------------------------------------------------------------------------------------------------------------------

-- forms_sync_patch_v2.sql
-- Fixes nested $$ by using $do$ and $fn$ tags. Safe to re-run.

-- ========== 0) Extensions ==========

-- ========== 1) Common updated_at helper ==========
create or replace function public.set_updated_at()
returns trigger language plpgsql as $fn$
begin
  new.updated_at = now();
  return new;
end
$fn$;

-- ========== 2) Series table (exists in your dump; ensure schema & unique) ==========
create table if not exists public.forms_series (
  id uuid primary key default gen_random_uuid(),
  series text not null unique,
  prefix text not null default '',
  suffix text not null default '',
  last_number integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_forms_series_updated_at on public.forms_series;
create trigger trg_forms_series_updated_at
before update on public.forms_series
for each row execute function public.set_updated_at();

-- RLS (simple: all authenticated can read/write — tighten later if needed)
alter table public.forms_series enable row level security;
do $do$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms_series' and policyname='forms_series_all_auth') then
    create policy forms_series_all_auth on public.forms_series for all
      to authenticated using (true) with check (true);
  end if;
end
$do$;

-- ========== 3) FORMS inventory table (NEW) ==========
create table if not exists public.forms (
  id uuid primary key default gen_random_uuid(),
  series text not null default 'F',
  number integer not null,
  prefix text not null default '',
  suffix text not null default '',
  code text generated always as (coalesce(prefix,'') || lpad(number::text, 4, '0') || coalesce(suffix,'')) stored,
  title text,
  description text,
  status text not null default 'in_stock', -- in_stock / assigned / archived
  location text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create unique index if not exists ux_forms_series_number on public.forms(series, number);
create unique index if not exists ux_forms_code on public.forms(code);

drop trigger if exists trg_forms_updated_at on public.forms;
create trigger trg_forms_updated_at
before update on public.forms
for each row execute function public.set_updated_at();

alter table public.forms enable row level security;
do $do$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms' and policyname='forms_select_all') then
    create policy forms_select_all on public.forms for select using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='forms' and policyname='forms_all_auth') then
    create policy forms_all_auth on public.forms for all to authenticated using (true) with check (true);
  end if;
end
$do$;

-- Publish realtime (optional)
do $do$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.forms';
    exception when duplicate_object then
      null;
    end;
  end if;
end
$do$;

-- ========== 4) RPC: allocate next form number atomically ==========
create or replace function public.form_allocate(
  p_series text default 'F',
  p_title text default null,
  p_description text default null
)
returns table(id uuid, series text, number integer, code text) 
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_next int;
  v_prefix text;
  v_suffix text;
begin
  -- Increment existing or create series
  with upd as (
    update public.forms_series
       set last_number = last_number + 1
     where series = p_series
     returning last_number, prefix, suffix
  ), ins as (
    insert into public.forms_series (series, prefix, suffix, last_number)
    select p_series, '', '', 1
    where not exists (select 1 from upd)
    returning last_number, prefix, suffix
  )
  select last_number, coalesce(prefix,''), coalesce(suffix,'')
    into v_next, v_prefix, v_suffix
  from upd
  union all
  select last_number, prefix, suffix from ins;

  insert into public.forms(series, number, prefix, suffix, title, description, created_by)
  values (p_series, v_next, v_prefix, v_suffix, p_title, p_description, auth.uid())
  returning forms.id, forms.series, forms.number, forms.code
  into id, series, number, code;

  return;
end
$fn$;

-- ========== 5) Link ORDERS -> FORMS and keep new_form_no in sync ==========
create table if not exists public.orders (id uuid primary key default gen_random_uuid());

alter table public.orders
  add column if not exists form_id uuid references public.forms(id) on delete set null;

-- Trigger function to keep new_form_no in sync (create unconditionally)
create or replace function public.trg_orders_sync_form_no()
returns trigger language plpgsql as $fn$
declare
  v_num integer;
begin
  if new.form_id is not null then
    select number into v_num from public.forms where id = new.form_id;
    new.new_form_no := v_num;
  end if;
  return new;
end
$fn$;

-- Conditionally create trigger only if orders.new_form_no column exists
do $do$
begin
  if exists (
    select 1 from information_schema.columns 
    where table_schema='public' and table_name='orders' and column_name='new_form_no'
  ) then
    drop trigger if exists trg_orders_sync_form_no on public.orders;
    create trigger trg_orders_sync_form_no
      before insert or update of form_id on public.orders
      for each row execute function public.trg_orders_sync_form_no();
  end if;
end
$do$;

-- Optional: convenient view for UI
create or replace view public.v_orders_with_form as
select o.*,
       f.series   as form_series,
       f.number   as form_number,
       f.code     as form_code,
       f.status   as form_status
from public.orders o
left join public.forms f on f.id = o.form_id;

-- Refresh PostgREST cache
notify pgrst, 'reload schema';
-------------------------------------------------------------------------------------------------------------------
-- создаём столбец для ссылки на изображение, если его ещё нет
ALTER TABLE public.forms
  ADD COLUMN IF NOT EXISTS image_url TEXT;
-----------------------------------------------------------------------------------------------------------------
DROP VIEW IF EXISTS public.v_orders_with_form;
CREATE OR REPLACE VIEW public.v_orders_with_form AS
SELECT 
  o.*,                             -- все поля заказа
  f.series      AS forms_series,   -- переименованы, чтобы не конфликтовать
  f.number      AS forms_number,
  f.code        AS forms_code,
  f.status      AS forms_status,
  f.title       AS forms_title,
  f.description AS forms_description,
  f.image_url   AS forms_image_url
FROM public.orders o
LEFT JOIN public.forms f ON f.id = o.form_id;
------------------------------------------------------------------------------------------------------------------

-- HOTFIX: public.forms — добавить недостающие колонки и перепостроить зависящие объекты

-- 1) Колонки в public.forms (безопасно, если уже есть — пропустит)
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS size text;
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS product_type text;
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS colors text;
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS image_url text;
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS status text;
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.forms ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- 2) Уникальность по (series, number) — на случай отсутствия
CREATE UNIQUE INDEX IF NOT EXISTS ux_forms_series_number ON public.forms (series, number);

-- 3) Триггер updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END$$;

DROP TRIGGER IF EXISTS trg_forms_set_updated_at ON public.forms;
CREATE TRIGGER trg_forms_set_updated_at
BEFORE UPDATE ON public.forms
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 4) Вьюха, зависящая от size/product_type/colors
CREATE OR REPLACE VIEW public.forms_search_view AS
SELECT
  id,
  series,
  number,
  (series || ' / №' || number::text) AS label,
  size, product_type, colors, image_url
FROM public.forms;

-- 5) RPC-функции (на случай, если не были созданы / пересоздать без ошибок)

-- 5.1 Первый свободный номер в серии
CREATE OR REPLACE FUNCTION public.next_form_number(p_series text)
RETURNS integer LANGUAGE sql AS $$
  WITH mx AS (
    SELECT COALESCE(MAX(number),0) AS m FROM public.forms WHERE series = p_series
  )
  SELECT n FROM generate_series(1, (SELECT m FROM mx)+1) n
  WHERE NOT EXISTS (
    SELECT 1 FROM public.forms f WHERE f.series = p_series AND f.number = n
  )
  ORDER BY n
  LIMIT 1;
$$;

-- 5.2 UPSERT формы по (series, number)
CREATE OR REPLACE FUNCTION public.upsert_form(
  p_series        text,
  p_number        integer,
  p_title         text DEFAULT NULL,
  p_description   text DEFAULT NULL,
  p_size          text DEFAULT NULL,
  p_product_type  text DEFAULT NULL,
  p_colors        text DEFAULT NULL,
  p_image_url     text DEFAULT NULL,
  p_status        text DEFAULT NULL
) RETURNS public.forms
LANGUAGE plpgsql AS $$
DECLARE
  v public.forms;
BEGIN
  INSERT INTO public.forms (series, number, title, description, size, product_type, colors, image_url, status)
  VALUES (p_series, p_number, p_title, p_description, p_size, p_product_type, p_colors, NULLIF(p_image_url,''), p_status)
  ON CONFLICT (series, number) DO UPDATE
    SET title        = EXCLUDED.title,
        description  = EXCLUDED.description,
        size         = EXCLUDED.size,
        product_type = EXCLUDED.product_type,
        colors       = EXCLUDED.colors,
        image_url    = COALESCE(NULLIF(EXCLUDED.image_url,''), public.forms.image_url),
        status       = EXCLUDED.status,
        updated_at   = now()
  RETURNING * INTO v;
  RETURN v;
END$$;

-- 5.3 Поиск для автокомплита
CREATE OR REPLACE FUNCTION public.find_forms(q text, limit_count int DEFAULT 50)
RETURNS SETOF public.forms LANGUAGE sql STABLE AS $$
  SELECT * FROM public.forms
  WHERE series ILIKE '%'||q||'%' OR CAST(number AS text) ILIKE '%'||q||'%'
  ORDER BY series, number
  LIMIT limit_count;
$$;
-- END of Доп к формам.sql\n

-- PRODUCTION PLANNING SCHEMA (Supabase / Postgres)
-- Author: ChatGPT (GPT-5 Thinking)
-- Date: 2025-09-22
-- Purpose: Move the production planning module off of public.documents and into
--          its own dedicated relational schema with tight linkage to workplaces
--          and positions. Includes RLS, triggers, indexes, realtime publication,
--          helper functions, and storage policies for attachments.

-- ==============================
-- Extensions
-- ==============================

-- ==============================
-- Schema
-- ==============================
create schema if not exists production;

comment on schema production is 'Dedicated schema for Production Planning: templates, plans, stages, tasks, logs, and files.';

-- ==============================
-- Enumerated Types
-- ==============================
do $$ begin
  if not exists (select 1 from pg_type where typname = 'plan_status') then
    create type production.plan_status as enum ('draft','active','done','cancelled');
  end if;

  if not exists (select 1 from pg_type where typname = 'stage_status') then
    create type production.stage_status as enum ('waiting','in_progress','paused','completed','problem','cancelled');
  end if;

  if not exists (select 1 from pg_type where typname = 'task_status') then
    create type production.task_status as enum ('waiting','in_progress','paused','completed','problem','cancelled');
  end if;

  if not exists (select 1 from pg_type where typname = 'priority') then
    create type production.priority as enum ('low','normal','high','urgent');
  end if;
end $$;

-- ==============================
-- Admins & Role Helpers (for RLS)
-- ==============================
create table if not exists production.admins (
  uid uuid primary key,
  note text,
  created_at timestamptz not null default now()
);

comment on table production.admins is 'Users with admin/tech-lead rights for production module.';

create or replace function production.is_admin() returns boolean
language sql stable security definer set search_path = public, production
as $$
  select exists (
    select 1 from production.admins a where a.uid = auth.uid()
  )
  or coalesce( (auth.jwt() ->> 'role') = 'tech_lead', false );
$$;

comment on function production.is_admin() is 'Admin if in production.admins or JWT role=tech_lead.';

-- ==============================
-- Base Tables
-- ==============================

create table if not exists production.stage_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table production.stage_templates is 'Reusable stage templates. Each template has 1..N ordered steps.';

create table if not exists production.stage_template_steps (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references production.stage_templates(id) on delete cascade,
  step_no int not null check (step_no > 0),
  name text not null,
  description text,
  expected_minutes int check (expected_minutes is null or expected_minutes >= 0),
  default_workplace_id uuid,
  required_position_id uuid,
  is_required boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(template_id, step_no)
);

comment on table production.stage_template_steps is 'Ordered steps composing a template; can specify default workplace and required position.';

create table if not exists production.plans (
  id uuid primary key default gen_random_uuid(),
  order_code text,
  title text not null,
  notes text,
  priority production.priority not null default 'normal',
  status production.plan_status not null default 'draft',
  planned_start_at timestamptz,
  due_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived boolean not null default false
);

comment on table production.plans is 'Production plans linked to an order_code (or order_id) with lifecycle status.';

create table if not exists production.plan_stages (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references production.plans(id) on delete cascade,
  template_step_id uuid references production.stage_template_steps(id) on delete set null,
  step_no int not null check (step_no > 0),
  name text not null,
  description text,
  status production.stage_status not null default 'waiting',
  order_in_queue int not null default 0,
  assigned_workplace_id uuid,
  required_position_id uuid,
  assignee_auth_uid uuid,
  started_at timestamptz,
  finished_at timestamptz,
  actual_minutes int check (actual_minutes is null or actual_minutes >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(plan_id, step_no)
);

comment on table production.plan_stages is 'Materialized stages for a specific plan (usually derived from a template).';

create table if not exists production.tasks (
  id uuid primary key default gen_random_uuid(),
  plan_stage_id uuid not null references production.plan_stages(id) on delete cascade,
  name text not null,
  description text,
  status production.task_status not null default 'waiting',
  quantity numeric(12,2),
  unit text,
  assigned_workplace_id uuid,
  required_position_id uuid,
  assignee_auth_uid uuid,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table production.tasks is 'Optional finer-grained tasks within a stage.';

create table if not exists production.task_files (
  id uuid primary key default gen_random_uuid(),
  task_id uuid references production.tasks(id) on delete cascade,
  plan_stage_id uuid references production.plan_stages(id) on delete cascade,
  bucket_id text not null default 'production',
  object_path text not null,
  uploaded_by uuid,
  created_at timestamptz not null default now(),
  check ((task_id is not null) or (plan_stage_id is not null))
);

comment on table production.task_files is 'Attachments stored in Supabase Storage (bucket: production).';

create table if not exists production.stage_logs (
  id uuid primary key default gen_random_uuid(),
  plan_stage_id uuid not null references production.plan_stages(id) on delete cascade,
  event_type text not null,
  before_status production.stage_status,
  after_status production.stage_status,
  by_auth_uid uuid,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists production.task_logs (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references production.tasks(id) on delete cascade,
  event_type text not null,
  before_status production.task_status,
  after_status production.task_status,
  by_auth_uid uuid,
  note text,
  created_at timestamptz not null default now()
);

-- ==============================
-- Triggers
-- ==============================

create or replace function production.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists tg_stage_templates_updated_at on production.stage_templates;
create trigger tg_stage_templates_updated_at
before update on production.stage_templates
for each row execute function production.set_updated_at();

drop trigger if exists tg_stage_template_steps_updated_at on production.stage_template_steps;
create trigger tg_stage_template_steps_updated_at
before update on production.stage_template_steps
for each row execute function production.set_updated_at();

drop trigger if exists tg_plans_updated_at on production.plans;
create trigger tg_plans_updated_at
before update on production.plans
for each row execute function production.set_updated_at();

drop trigger if exists tg_plan_stages_updated_at on production.plan_stages;
create trigger tg_plan_stages_updated_at
before update on production.plan_stages
for each row execute function production.set_updated_at();

drop trigger if exists tg_tasks_updated_at on production.tasks;
create trigger tg_tasks_updated_at
before update on production.tasks
for each row execute function production.set_updated_at();

create or replace function production.log_plan_stage_status_change()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'UPDATE') and (new.status is distinct from old.status) then
    insert into production.stage_logs (plan_stage_id, event_type, before_status, after_status, by_auth_uid, note)
    values (old.id, 'status_change', old.status, new.status, auth.uid(), coalesce(new.notes, ''));
  end if;
  return new;
end $$;

drop trigger if exists tg_plan_stage_status_log on production.plan_stages;
create trigger tg_plan_stage_status_log
after update on production.plan_stages
for each row execute function production.log_plan_stage_status_change();

create or replace function production.log_task_status_change()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'UPDATE') and (new.status is distinct from old.status) then
    insert into production.task_logs (task_id, event_type, before_status, after_status, by_auth_uid, note)
    values (old.id, 'status_change', old.status, new.status, auth.uid(), coalesce(new.description, ''));
  end if;
  return new;
end $$;

drop trigger if exists tg_task_status_log on production.tasks;
create trigger tg_task_status_log
after update on production.tasks
for each row execute function production.log_task_status_change();

-- ==============================
-- Helper functions
-- ==============================

create or replace function production.create_plan_from_template(
  p_template_id uuid,
  p_title text,
  p_order_code text default null,
  p_priority production.priority default 'normal',
  p_planned_start_at timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public, production as $$
declare
  v_plan_id uuid := gen_random_uuid();
  v_step record;
  v_order int := 0;
begin
  insert into production.plans (id, order_code, title, priority, status, planned_start_at, created_by)
  values (v_plan_id, p_order_code, p_title, p_priority, 'active', p_planned_start_at, auth.uid());

  for v_step in
    select s.* from production.stage_template_steps s
    where s.template_id = p_template_id
    order by s.step_no
  loop
    v_order := v_order + 1;
    insert into production.plan_stages (
      plan_id, template_step_id, step_no, name, description,
      order_in_queue, assigned_workplace_id, required_position_id, status
    ) values (
      v_plan_id, v_step.id, v_step.step_no, v_step.name, v_step.description,
      v_order, v_step.default_workplace_id, v_step.required_position_id, 'waiting'
    );
  end loop;

  return v_plan_id;
end $$;

create or replace function production.move_stage_in_queue(p_plan_stage_id uuid, p_new_order int)
returns void language plpgsql security definer set search_path = public, production as $$
declare
  v_plan_id uuid;
  v_old_order int;
begin
  select plan_id, order_in_queue into v_plan_id, v_old_order from production.plan_stages where id = p_plan_stage_id;
  if v_plan_id is null then
    raise exception 'plan_stage % not found', p_plan_stage_id;
  end if;
  if p_new_order < 1 then
    raise exception 'new order must be >= 1';
  end if;

  if p_new_order = v_old_order then
    return;
  end if;

  if p_new_order < v_old_order then
    update production.plan_stages
      set order_in_queue = order_in_queue + 1
    where plan_id = v_plan_id
      and order_in_queue >= p_new_order
      and order_in_queue < v_old_order;
  else
    update production.plan_stages
      set order_in_queue = order_in_queue - 1
    where plan_id = v_plan_id
      and order_in_queue <= p_new_order
      and order_in_queue > v_old_order;
  end if;

  update production.plan_stages set order_in_queue = p_new_order where id = p_plan_stage_id;
end $$;

create or replace function production.assign_stage_to_user(p_plan_stage_id uuid, p_auth_uid uuid)
returns void language sql security definer set search_path = public, production as $$
  update production.plan_stages set assignee_auth_uid = p_auth_uid where id = p_plan_stage_id;
$$;

-- ==============================
-- Indexes
-- ==============================
create index if not exists idx_stage_template_steps_template on production.stage_template_steps(template_id);
create index if not exists idx_plans_status on production.plans(status);
create index if not exists idx_plans_priority on production.plans(priority);
create index if not exists idx_plan_stages_plan on production.plan_stages(plan_id);
create index if not exists idx_plan_stages_status on production.plan_stages(status);
create index if not exists idx_plan_stages_queue on production.plan_stages(plan_id, order_in_queue);
create index if not exists idx_tasks_stage on production.tasks(plan_stage_id);
create index if not exists idx_tasks_status on production.tasks(status);
create index if not exists idx_task_files_task on production.task_files(task_id);
create index if not exists idx_task_files_stage on production.task_files(plan_stage_id);

-- ==============================
-- Row Level Security (RLS)
-- ==============================

alter table production.stage_templates enable row level security;
alter table production.stage_template_steps enable row level security;
alter table production.plans enable row level security;
alter table production.plan_stages enable row level security;
alter table production.tasks enable row level security;
alter table production.task_files enable row level security;
alter table production.stage_logs enable row level security;
alter table production.task_logs enable row level security;

create policy "read_templates" on production.stage_templates
for select to authenticated using (true);

create policy "read_template_steps" on production.stage_template_steps
for select to authenticated using (true);

create policy "read_plans" on production.plans
for select to authenticated using (true);

create policy "read_plan_stages" on production.plan_stages
for select to authenticated using (true);

create policy "read_tasks" on production.tasks
for select to authenticated using (true);

create policy "read_task_files" on production.task_files
for select to authenticated using (true);

create policy "read_stage_logs" on production.stage_logs
for select to authenticated using (true);

create policy "read_task_logs" on production.task_logs
for select to authenticated using (true);

create policy "write_templates_admin" on production.stage_templates
for all to authenticated using (production.is_admin()) with check (production.is_admin());

create policy "write_template_steps_admin" on production.stage_template_steps
for all to authenticated using (production.is_admin()) with check (production.is_admin());

create policy "write_plans_admin" on production.plans
for all to authenticated using (production.is_admin()) with check (production.is_admin());

create policy "write_plan_stages_admin" on production.plan_stages
for all to authenticated using (production.is_admin()) with check (production.is_admin());

create policy "assignee_update_plan_stages" on production.plan_stages
for update to authenticated
using (assignee_auth_uid = auth.uid())
with check (assignee_auth_uid = auth.uid());

create policy "write_tasks_admin" on production.tasks
for all to authenticated using (production.is_admin()) with check (production.is_admin());

create policy "assignee_update_tasks" on production.tasks
for update to authenticated
using (assignee_auth_uid = auth.uid())
with check (assignee_auth_uid = auth.uid());

create policy "write_task_files_admin" on production.task_files
for all to authenticated using (production.is_admin()) with check (production.is_admin());

create policy "assignee_write_task_files" on production.task_files
for insert to authenticated
with check (
  uploaded_by = auth.uid()
  and (
    (task_id is not null and exists (select 1 from production.tasks t where t.id = task_id and t.assignee_auth_uid = auth.uid()))
    or
    (plan_stage_id is not null and exists (select 1 from production.plan_stages s where s.id = plan_stage_id and s.assignee_auth_uid = auth.uid()))
  )
);

create policy "write_stage_logs_admin" on production.stage_logs
for all to authenticated using (production.is_admin()) with check (production.is_admin());

-- FIXED: removed extra closing parenthesis here
drop policy if exists "write_task_logs_admin" on production.task_logs;
create policy "write_task_logs_admin" on production.task_logs
for all to authenticated using (production.is_admin()) with check (production.is_admin());

-- ==============================
-- Supabase Storage (bucket) for Production
-- ==============================

insert into storage.buckets (id, name, public)
values ('production','production', true)
on conflict (id) do nothing;

drop policy if exists "prod_files_read" on storage.objects;
create policy "prod_files_read"
on storage.objects for select to authenticated
using (bucket_id = 'production');

drop policy if exists "prod_files_insert_by_auth" on storage.objects;
create policy "prod_files_insert_by_auth"
on storage.objects for insert to authenticated
with check (bucket_id = 'production' and owner = auth.uid());

drop policy if exists "prod_files_update_owner_or_admin" on storage.objects;
create policy "prod_files_update_owner_or_admin"
on storage.objects for update to authenticated
using (bucket_id = 'production' and (owner = auth.uid() or production.is_admin()))
with check (bucket_id = 'production' and (owner = auth.uid() or production.is_admin()));

drop policy if exists "prod_files_delete_owner_or_admin" on storage.objects;
create policy "prod_files_delete_owner_or_admin"
on storage.objects for delete to authenticated
using (bucket_id = 'production' and (owner = auth.uid() or production.is_admin()));

-- ==============================
-- Realtime publication
-- ==============================
do $$
declare
  r record;
begin
  for r in
    select table_schema, table_name
    from information_schema.tables
    where table_schema = 'production' and table_type = 'BASE TABLE'
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = r.table_schema
        and tablename = r.table_name
    ) then
      execute format('alter publication supabase_realtime add table %I.%I', r.table_schema, r.table_name);
    end if;
  end loop;
end $$;

-- ==============================
-- Optional Foreign Keys (UNCOMMENT & EDIT to match your actual tables)
-- ==============================
-- alter table production.stage_template_steps
--   add constraint fk_step_default_workplace
--   foreign key (default_workplace_id) references personnel.workplaces(id) on delete set null;
--
-- alter table production.stage_template_steps
--   add constraint fk_step_required_position
--   foreign key (required_position_id) references personnel.positions(id) on delete set null;
--
-- alter table production.plan_stages
--   add constraint fk_stage_workplace
--   foreign key (assigned_workplace_id) references personnel.workplaces(id) on delete set null;
--
-- alter table production.plan_stages
--   add constraint fk_stage_required_position
--   foreign key (required_position_id) references personnel.positions(id) on delete set null;

-- ==============================
-- Convenience Views
-- ==============================
create or replace view production.v_plan_with_stages as
select
  p.id as plan_id,
  p.title as plan_title,
  p.order_code,
  p.priority,
  p.status as plan_status,
  p.planned_start_at,
  p.due_at,
  p.created_by,
  p.created_at as plan_created_at,
  s.id as stage_id,
  s.step_no,
  s.name as stage_name,
  s.status as stage_status,
  s.order_in_queue,
  s.assignee_auth_uid,
  s.assigned_workplace_id,
  s.required_position_id,
  s.started_at,
  s.finished_at,
  s.actual_minutes
from production.plans p
join production.plan_stages s on s.plan_id = p.id;
-- view ends normally; removed extraneous characters
--------------------------------------------------------------------------------------------------

-- =========================
-- 0) Базовые расширения
-- =========================

-- =========================
-- 1) ENUM статусов
-- =========================
do $$
begin
  if not exists (select 1 from pg_type where typname='production_status') then
    create type production_status as enum ('waiting','inProgress','paused','completed','problem');
  end if;
end$$;

-- =========================
-- 2) Таблицы модуля
-- =========================
create table if not exists public.prod_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid
);

create table if not exists public.prod_template_stages (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.prod_templates(id) on delete cascade,
  seq int not null,
  name text not null,
  note text,
  expected_minutes int,
  position_id uuid,   -- FK добавим ниже, если таблицы есть (или создадим заглушки)
  workplace_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(template_id, seq)
);

create table if not exists public.prod_plans (
  id uuid primary key default gen_random_uuid(),
  order_id uuid,      -- FK добавим ниже
  template_id uuid references public.prod_templates(id) on delete set null,
  plan_code text,
  title text,
  note text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid
);

create table if not exists public.prod_plan_stages (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.prod_plans(id) on delete cascade,
  template_stage_id uuid references public.prod_template_stages(id) on delete set null,
  seq int not null,
  name text not null,
  note text,
  status production_status not null default 'waiting',
  assigned_employee_id uuid,
  position_id uuid,
  workplace_id uuid,

  planned_start_at timestamptz,
  planned_end_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,

  expected_minutes int,
  actual_minutes int,

  -- ВАЖНО: добавляем аудит-поля, которых не хватало
  created_by uuid,
  updated_by uuid,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(plan_id, seq)
);

create table if not exists public.prod_stage_history (
  id bigserial primary key,
  stage_id uuid not null references public.prod_plan_stages(id) on delete cascade,
  old_status production_status,
  new_status production_status not null,
  changed_at timestamptz not null default now(),
  changed_by uuid
);

create table if not exists public.prod_stage_comments (
  id uuid primary key default gen_random_uuid(),
  stage_id uuid not null references public.prod_plan_stages(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  created_by uuid
);

create table if not exists public.prod_stage_files (
  id uuid primary key default gen_random_uuid(),
  stage_id uuid not null references public.prod_plan_stages(id) on delete cascade,
  storage_path text not null,  -- ключ в бакете
  file_name text,
  mime_type text,
  size_bytes bigint,
  created_at timestamptz not null default now(),
  created_by uuid
);

-- =========================
-- 3) Индексы
-- =========================
create index if not exists idx_prod_template_stages_template on public.prod_template_stages(template_id);
create index if not exists idx_prod_plans_order on public.prod_plans(order_id);
create index if not exists idx_prod_plan_stages_plan on public.prod_plan_stages(plan_id);
create index if not exists idx_prod_plan_stages_status on public.prod_plan_stages(status);
create index if not exists idx_prod_stage_history_stage on public.prod_stage_history(stage_id);
create index if not exists idx_prod_stage_comments_stage on public.prod_stage_comments(stage_id);
create index if not exists idx_prod_stage_files_stage on public.prod_stage_files(stage_id);

-- =========================
-- 4) Триггеры updated_at
-- =========================
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end$$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname='t_upd_prod_templates') then
    create trigger t_upd_prod_templates
      before update on public.prod_templates
      for each row execute function public.set_updated_at();
  end if;

  if not exists (select 1 from pg_trigger where tgname='t_upd_prod_template_stages') then
    create trigger t_upd_prod_template_stages
      before update on public.prod_template_stages
      for each row execute function public.set_updated_at();
  end if;

  if not exists (select 1 from pg_trigger where tgname='t_upd_prod_plans') then
    create trigger t_upd_prod_plans
      before update on public.prod_plans
      for each row execute function public.set_updated_at();
  end if;

  if not exists (select 1 from pg_trigger where tgname='t_upd_prod_plan_stages') then
    create trigger t_upd_prod_plan_stages
      before update on public.prod_plan_stages
      for each row execute function public.set_updated_at();
  end if;
end$$;

-- =========================
-- 5) Триггер истории статусов (исправлен)
--    changed_by = COALESCE(new.updated_by, auth.uid())
-- =========================
create or replace function public.log_prod_stage_status()
returns trigger language plpgsql as $$
begin
  if (tg_op='UPDATE') and (old.status is distinct from new.status) then
    insert into public.prod_stage_history(stage_id, old_status, new_status, changed_by)
    values (old.id, old.status, new.status, coalesce(new.updated_by, auth.uid()));
  end if;
  return new;
end$$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname='t_hist_prod_plan_stages_status') then
    create trigger t_hist_prod_plan_stages_status
      before update on public.prod_plan_stages
      for each row execute function public.log_prod_stage_status();
  end if;
end$$;

-- =========================
-- 6) RPC: развернуть план из шаблона
-- =========================
create or replace function public.prod_create_plan_from_template(
  p_order_id uuid,
  p_template_id uuid,
  p_plan_code text,
  p_title text,
  p_note text,
  p_created_by uuid
)
returns uuid
language plpgsql
as $$
declare
  v_plan_id uuid;
begin
  insert into public.prod_plans(order_id, template_id, plan_code, title, note, created_by, updated_by)
  values (p_order_id, p_template_id, p_plan_code, p_title, p_note, p_created_by, p_created_by)
  returning id into v_plan_id;

  insert into public.prod_plan_stages(
    plan_id, template_stage_id, seq, name, note,
    position_id, workplace_id, expected_minutes,
    created_by, updated_by
  )
  select
    v_plan_id, pts.id, pts.seq, pts.name, pts.note,
    pts.position_id, pts.workplace_id, pts.expected_minutes,
    p_created_by, p_created_by
  from public.prod_template_stages pts
  where pts.template_id = p_template_id
  order by pts.seq;

  return v_plan_id;
end
$$;

-- =========================
-- 7) ВКЛ RLS
-- =========================
alter table public.prod_templates        enable row level security;
alter table public.prod_template_stages  enable row level security;
alter table public.prod_plans            enable row level security;
alter table public.prod_plan_stages      enable row level security;
alter table public.prod_stage_history    enable row level security;
alter table public.prod_stage_comments   enable row level security;
alter table public.prod_stage_files      enable row level security;

-- =========================
-- 8) Сброс проблемных политик и корректное создание (по-командно)
--    ВАЖНО: для INSERT — только WITH CHECK.
-- =========================
do $$
begin
  -- prod_templates
  drop policy if exists prod_templates_sel on public.prod_templates;
  drop policy if exists prod_templates_ins on public.prod_templates;
  drop policy if exists prod_templates_upd on public.prod_templates;
  drop policy if exists prod_templates_del on public.prod_templates;

  create policy prod_templates_sel on public.prod_templates
    for select using (auth.role() = 'authenticated');
  create policy prod_templates_ins on public.prod_templates
    for insert with check (auth.role() = 'authenticated');
  create policy prod_templates_upd on public.prod_templates
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  create policy prod_templates_del on public.prod_templates
    for delete using (auth.role() = 'authenticated');

  -- prod_template_stages
  drop policy if exists prod_template_stages_sel on public.prod_template_stages;
  drop policy if exists prod_template_stages_ins on public.prod_template_stages;
  drop policy if exists prod_template_stages_upd on public.prod_template_stages;
  drop policy if exists prod_template_stages_del on public.prod_template_stages;

  create policy prod_template_stages_sel on public.prod_template_stages
    for select using (auth.role() = 'authenticated');
  create policy prod_template_stages_ins on public.prod_template_stages
    for insert with check (auth.role() = 'authenticated');
  create policy prod_template_stages_upd on public.prod_template_stages
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  create policy prod_template_stages_del on public.prod_template_stages
    for delete using (auth.role() = 'authenticated');

  -- prod_plans
  drop policy if exists prod_plans_sel on public.prod_plans;
  drop policy if exists prod_plans_ins on public.prod_plans;
  drop policy if exists prod_plans_upd on public.prod_plans;
  drop policy if exists prod_plans_del on public.prod_plans;

  create policy prod_plans_sel on public.prod_plans
    for select using (auth.role() = 'authenticated');
  create policy prod_plans_ins on public.prod_plans
    for insert with check (auth.role() = 'authenticated');
  create policy prod_plans_upd on public.prod_plans
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  create policy prod_plans_del on public.prod_plans
    for delete using (auth.role() = 'authenticated');

  -- prod_plan_stages
  drop policy if exists prod_plan_stages_sel on public.prod_plan_stages;
  drop policy if exists prod_plan_stages_ins on public.prod_plan_stages;
  drop policy if exists prod_plan_stages_upd on public.prod_plan_stages;
  drop policy if exists prod_plan_stages_del on public.prod_plan_stages;

  create policy prod_plan_stages_sel on public.prod_plan_stages
    for select using (auth.role() = 'authenticated');
  create policy prod_plan_stages_ins on public.prod_plan_stages
    for insert with check (auth.role() = 'authenticated');
  create policy prod_plan_stages_upd on public.prod_plan_stages
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  create policy prod_plan_stages_del on public.prod_plan_stages
    for delete using (auth.role() = 'authenticated');

  -- prod_stage_history (только select+insert)
  drop policy if exists prod_stage_history_sel on public.prod_stage_history;
  drop policy if exists prod_stage_history_ins on public.prod_stage_history;

  create policy prod_stage_history_sel on public.prod_stage_history
    for select using (auth.role() = 'authenticated');
  create policy prod_stage_history_ins on public.prod_stage_history
    for insert with check (auth.role() = 'authenticated');

  -- prod_stage_comments
  drop policy if exists prod_stage_comments_sel on public.prod_stage_comments;
  drop policy if exists prod_stage_comments_ins on public.prod_stage_comments;
  drop policy if exists prod_stage_comments_upd on public.prod_stage_comments;
  drop policy if exists prod_stage_comments_del on public.prod_stage_comments;

  create policy prod_stage_comments_sel on public.prod_stage_comments
    for select using (auth.role() = 'authenticated');
  create policy prod_stage_comments_ins on public.prod_stage_comments
    for insert with check (auth.role() = 'authenticated');
  create policy prod_stage_comments_upd on public.prod_stage_comments
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  create policy prod_stage_comments_del on public.prod_stage_comments
    for delete using (auth.role() = 'authenticated');

  -- prod_stage_files
  drop policy if exists prod_stage_files_sel on public.prod_stage_files;
  drop policy if exists prod_stage_files_ins on public.prod_stage_files;
  drop policy if exists prod_stage_files_upd on public.prod_stage_files;
  drop policy if exists prod_stage_files_del on public.prod_stage_files;

  create policy prod_stage_files_sel on public.prod_stage_files
    for select using (auth.role() = 'authenticated');
  create policy prod_stage_files_ins on public.prod_stage_files
    for insert with check (auth.role() = 'authenticated');
  create policy prod_stage_files_upd on public.prod_stage_files
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
  create policy prod_stage_files_del on public.prod_stage_files
    for delete using (auth.role() = 'authenticated');
end$$;

-- =========================
-- 9) Realtime публикация
-- =========================
do $$
begin
  begin
    alter publication supabase_realtime add table
      public.prod_templates,
      public.prod_template_stages,
      public.prod_plans,
      public.prod_plan_stages,
      public.prod_stage_history,
      public.prod_stage_comments,
      public.prod_stage_files;
  exception when duplicate_object then null;
  end;
end$$;

-- =========================
-- 10) Storage bucket + политики
-- =========================
insert into storage.buckets (id, name, public)
values ('production','production',false)
on conflict (id) do nothing;

do $$
begin
  drop policy if exists storage_production_read  on storage.objects;
  drop policy if exists storage_production_write on storage.objects;

  create policy storage_production_read
    on storage.objects for select
    using (bucket_id='production' and auth.role() = 'authenticated');

  create policy storage_production_write
    on storage.objects for all
    using (bucket_id='production' and auth.role() = 'authenticated')
    with check (bucket_id='production' and auth.role() = 'authenticated');
end$$;

-- =========================
-- 11) Совместимость с кадрами/раб.местами/заказами (заглушки + FK)
--     Если уже есть ваши реальные таблицы — заглушки не будут созданы,
--     FK всё равно добавятся правильно.
-- =========================
do $$
declare
  t_positions  text := 'personnel_positions';
  t_workplaces text := 'personnel_workplaces';
  t_employees  text := 'personnel_employees';
  t_orders     text := 'orders';
begin
  -- Заглушки (если нет)
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name=t_positions) then
    execute format('create table public.%I (id uuid primary key, name text)', t_positions);
  end if;
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name=t_workplaces) then
    execute format('create table public.%I (id uuid primary key, name text)', t_workplaces);
  end if;
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name=t_employees) then
    execute format('create table public.%I (id uuid primary key, name text)', t_employees);
  end if;
  if not exists (select 1 from information_schema.tables where table_schema='public' and table_name=t_orders) then
    execute format('create table public.%I (id uuid primary key, name text)', t_orders);
  end if;

  -- FK (добавляем, если ещё нет)
  if not exists (select 1 from pg_constraint where conname='fk_prod_template_stages_position') then
    execute format('alter table public.prod_template_stages add constraint fk_prod_template_stages_position
                    foreign key (position_id) references public.%I(id) on delete set null', t_positions);
  end if;

  if not exists (select 1 from pg_constraint where conname='fk_prod_template_stages_workplace') then
    execute format('alter table public.prod_template_stages add constraint fk_prod_template_stages_workplace
                    foreign key (workplace_id) references public.%I(id) on delete set null', t_workplaces);
  end if;

  if not exists (select 1 from pg_constraint where conname='fk_prod_plan_stages_position') then
    execute format('alter table public.prod_plan_stages add constraint fk_prod_plan_stages_position
                    foreign key (position_id) references public.%I(id) on delete set null', t_positions);
  end if;

  if not exists (select 1 from pg_constraint where conname='fk_prod_plan_stages_workplace') then
    execute format('alter table public.prod_plan_stages add constraint fk_prod_plan_stages_workplace
                    foreign key (workplace_id) references public.%I(id) on delete set null', t_workplaces);
  end if;

  if not exists (select 1 from pg_constraint where conname='fk_prod_plan_stages_employee') then
    execute format('alter table public.prod_plan_stages add constraint fk_prod_plan_stages_employee
                    foreign key (assigned_employee_id) references public.%I(id) on delete set null', t_employees);
  end if;

  if not exists (select 1 from pg_constraint where conname='fk_prod_plans_order') then
    execute format('alter table public.prod_plans add constraint fk_prod_plans_order
                    foreign key (order_id) references public.%I(id) on delete set null', t_orders);
  end if;
end$$;

-----------------------------------------------------------------------------------------------------------------------------------

-- 0) Базовые функции/расширения (на случай, если ещё не созданы)

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end$$;

-- 1) Совместимая таблица "documents" (универсальное хранилище)
create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  type text not null,                 -- тип записи (например: 'production_plan', 'comment', 'warehouse_writeoff' и т.д.)
  subtype text,                       -- подтип, если используется
  code text,                          -- например код заказа, ORD-... / ЗК-...
  ref_id uuid,                        -- любая внешняя ссылка (например plan_id / order_id)
  title text,
  body text,
  data jsonb not null default '{}'::jsonb,
  payload jsonb not null default '{}'::jsonb,  -- на случай, если код использовал "payload" вместо "data"
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 2) Индексы для быстрого поиска
create index if not exists idx_documents_type   on public.documents(type);
create index if not exists idx_documents_code   on public.documents(code);
create index if not exists idx_documents_ref    on public.documents(ref_id);
create index if not exists idx_documents_data   on public.documents using gin((data));
create index if not exists idx_documents_payload on public.documents using gin((payload));

-- 3) Триггер обновления updated_at
do $$
begin
  if not exists (select 1 from pg_trigger where tgname='t_upd_documents') then
    create trigger t_upd_documents
      before update on public.documents
      for each row execute function public.set_updated_at();
  end if;
end$$;

-- 4) RLS: роль authenticated может читать/писать (как и в остальных наших таблицах)
alter table public.documents enable row level security;

do $$
begin
  -- Сносим старые политики, если вдруг были от предыдущих экспериментов
  drop policy if exists documents_sel on public.documents;
  drop policy if exists documents_ins on public.documents;
  drop policy if exists documents_upd on public.documents;
  drop policy if exists documents_del on public.documents;

  create policy documents_sel on public.documents
    for select using (auth.role() = 'authenticated');

  -- ВАЖНО: для INSERT только WITH CHECK
  create policy documents_ins on public.documents
    for insert with check (auth.role() = 'authenticated');

  create policy documents_upd on public.documents
    for update using (auth.role() = 'authenticated')
    with check (auth.role() = 'authenticated');

  create policy documents_del on public.documents
    for delete using (auth.role() = 'authenticated');
end$$;

-- 5) Подключаем к Realtime (без дублей)
do $$
begin
  begin
    alter publication supabase_realtime add table public.documents;
  exception when duplicate_object then null;
  end;
end$$;

-------------------------------------------------------------------------------------------------------------

-- 1) Добавляем совместимую колонку и индекс
alter table public.documents
  add column if not exists collection text;

create index if not exists idx_documents_collection
  on public.documents(collection);

-- 2) Триггер: выравниваем поля collection и type в обе стороны
create or replace function public.documents_sync_type_collection()
returns trigger
language plpgsql
as $$
begin
  -- если код пишет только collection — подставим type
  if new.type is null and new.collection is not null then
    new.type := new.collection;
  end if;

  -- если код пишет только type — подставим collection
  if new.collection is null and new.type is not null then
    new.collection := new.type;
  end if;

  return new;
end
$$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 't_sync_documents_type_collection') then
    create trigger t_sync_documents_type_collection
      before insert or update on public.documents
      for each row execute function public.documents_sync_type_collection();
  end if;
end$$;

-- 3) Форсим перезагрузку схемы PostgREST, чтобы cache увидел новую колонку
notify pgrst, 'reload schema';
-- END of План Произв.sql\n
-- 2025-09-23 setup tasks, production_plans, documents

-- Универсальная функция для updated_at
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- documents table (generic kv)
create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  collection text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists documents_collection_idx on public.documents(collection);

-- безопасное создание триггера без IF NOT EXISTS
do $$
begin
  create trigger documents_set_updated_at
    before update on public.documents
    for each row execute function public.set_updated_at();
exception
  when duplicate_object then null;
end$$;

-- production_plans with inline stages
create table if not exists public.production_plans (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique,
  stages jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists production_plans_order_id_idx on public.production_plans(order_id);

do $$
begin
  create trigger production_plans_set_updated_at
    before update on public.production_plans
    for each row execute function public.set_updated_at();
exception
  when duplicate_object then null;
end$$;

-- tasks table
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null,
  stage_id text not null,
  status text not null default 'waiting',
  spent_seconds integer not null default 0,
  started_at bigint,
  assignees text[] not null default '{}',
  comments jsonb not null default '[]',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tasks_order_id_idx on public.tasks(order_id);
create index if not exists tasks_status_idx on public.tasks(status);

do $$
begin
  create trigger tasks_set_updated_at
    before update on public.tasks
    for each row execute function public.set_updated_at();
exception
  when duplicate_object then null;
end$$;

-- enable realtime (без падений, если уже есть)
do $$ begin
  perform 1 from pg_publication where pubname = 'supabase_realtime';
  if not found then
    create publication supabase_realtime;
  end if;
exception when others then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.tasks;
exception when others then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.documents;
exception when others then null; end $$;

do $$ begin
  alter publication supabase_realtime add table public.production_plans;
exception when others then null; end $$;
---------------------------------------------------------------------------------------------------------

-- READ для anon на production.*
drop policy if exists stage_templates_sel_any on production.stage_templates;
create policy stage_templates_sel_any
  on production.stage_templates for select
  to anon, authenticated using (true);

drop policy if exists stage_template_steps_sel_any on production.stage_template_steps;
create policy stage_template_steps_sel_any
  on production.stage_template_steps for select
  to anon, authenticated using (true);

drop policy if exists plans_sel_any on production.plans;
create policy plans_sel_any
  on production.plans for select
  to anon, authenticated using (true);

drop policy if exists plan_stages_sel_any on production.plan_stages;
create policy plan_stages_sel_any
  on production.plan_stages for select
  to anon, authenticated using (true);
---------------------------------------------------------------------------------------------------------

-- ====================================================================
-- Auto-create production plan & stages for an order when a template is chosen
-- Safe to run multiple times.
-- Creates orders.prod_template_id (FK) if missing, and trigger+function.
-- ====================================================================


-- 0) Ensure helper for updated_at exists
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- 1) Column on orders for selected production template
alter table public.orders
  add column if not exists prod_template_id uuid;

-- 1.1) FK to prod_templates (if table exists)
do $$
begin
  if to_regclass('public.prod_templates') is not null then
    begin
      alter table public.orders
        add constraint orders_prod_template_id_fkey
        foreign key (prod_template_id) references public.prod_templates(id) on delete set null;
    exception when duplicate_object then
      null;
    end;
  end if;
end $$;

-- 2) Convenience index
create index if not exists idx_orders_prod_template on public.orders(prod_template_id);

-- 3) Function: copy template stages into a plan bound to order
create or replace function public.copy_template_to_plan(p_order_id uuid, p_template_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_plan_id uuid;
begin
  if p_order_id is null or p_template_id is null then
    return null;
  end if;

  -- Ensure plan exists (one plan per order)
  select id into v_plan_id
  from public.prod_plans
  where order_id = p_order_id
  limit 1;

  if v_plan_id is null then
    insert into public.prod_plans(order_id, template_id, title, plan_code, note, created_by)
    select
      o.id,
      p_template_id,
      coalesce((o.product->>'name'), o.assignment_id, 'План для заказа'),
      o.assignment_id,
      null,
      auth.uid()
    from public.orders o
    where o.id = p_order_id
    returning id into v_plan_id;
  else
    -- If template changed, reset stages
    update public.prod_plans
      set template_id = p_template_id
    where id = v_plan_id;
    delete from public.prod_plan_stages where plan_id = v_plan_id;
  end if;

  -- Copy stages from template -> plan
  insert into public.prod_plan_stages(
    plan_id, template_stage_id, seq, name, note,
    position_id, workplace_id, expected_minutes,
    created_by
  )
  select
    v_plan_id, ts.id, ts.seq, ts.name, ts.note,
    ts.position_id, ts.workplace_id, ts.expected_minutes,
    auth.uid()
  from public.prod_template_stages ts
  where ts.template_id = p_template_id
  order by ts.seq;

  return v_plan_id;
end $$;

-- 4) Helper to infer template id from an order row (from different places)
create or replace function public._infer_template_id_from_order(o public.orders)
returns uuid
language plpgsql
as $$
declare
  v_tid uuid;
  v_txt text;
begin
  v_tid := o.prod_template_id;
  if v_tid is not null then
    return v_tid;
  end if;

  -- try product JSON keys
  v_txt := coalesce(o.product->>'template_id', o.product->>'templateId', o.product->>'prod_template_id');
  if v_txt is not null then
    begin
      v_tid := v_txt::uuid;
      return v_tid;
    exception when others then
      -- ignore cast errors
      null;
    end;
  end if;

  -- Try by template name in JSON: product.planName / templateName
  v_txt := coalesce(o.product->>'planName', o.product->>'templateName');
  if v_txt is not null then
    select id into v_tid from public.prod_templates where lower(name) = lower(v_txt) limit 1;
    if v_tid is not null then
      return v_tid;
    end if;
  end if;

  return null;
end $$;

-- 5) Main trigger: on insert & on update of prod_template_id/product - ensure plan exists
create or replace function public.tg_orders_sync_prod_plan()
returns trigger
language plpgsql
as $$
declare
  v_tid uuid;
  v_existing uuid;
begin
  -- Only for authenticated sessions to satisfy RLS of prod_* tables
  if coalesce((auth.jwt() ->> 'role') = 'authenticated', false) is not true then
    return new;
  end if;

  -- determine template id
  v_tid := public._infer_template_id_from_order(new);

  if v_tid is null then
    return new;
  end if;

  -- create/sync
  perform public.copy_template_to_plan(new.id, v_tid);

  return new;
end $$;

-- Drop & recreate triggers (idempotent)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='orders') then
    drop trigger if exists trg_orders_sync_prod_plan_ins on public.orders;
    drop trigger if exists trg_orders_sync_prod_plan_upd on public.orders;

    create trigger trg_orders_sync_prod_plan_ins
      after insert on public.orders
      for each row execute function public.tg_orders_sync_prod_plan();

    create trigger trg_orders_sync_prod_plan_upd
      after update of prod_template_id, product on public.orders
      for each row execute function public.tg_orders_sync_prod_plan();
  end if;
end $$;

-- 6) Minimal RLS safety: prod_* tables already created by previous patch with permissive policies.
--    Ensure orders has RLS enabled (Supabase default is ON), nothing to change here.

-- 7) Optional: a lightweight view to quickly display plan stages by order
create or replace view public.v_order_plan_stages as
select
  o.id as order_id,
  o.assignment_id as order_code,
  p.id as plan_id,
  s.id as stage_id,
  s.seq as step_no,
  s.name as stage_name,
  s.status,
  s.started_at,
  s.finished_at,
  s.expected_minutes,
  s.actual_minutes
from public.orders o
left join public.prod_plans p on p.order_id = o.id
left join public.prod_plan_stages s on s.plan_id = p.id;

-- Add realtime for prod tables (safe if already in publication)
do $$ begin
  perform 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='prod_plans';
  if not found then
    alter publication supabase_realtime add table public.prod_plans;
  end if;
  perform 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='prod_plan_stages';
  if not found then
    alter publication supabase_realtime add table public.prod_plan_stages;
  end if;
end $$;

-- Ask PostgREST to reload schema cache
notify pgrst, 'reload schema';
----------------------------------------------------------------------------------------------------------------

-- ====================================================================
-- Auto-create production plan & stages for an order when a template is chosen
-- Safe to run multiple times.
-- Creates orders.prod_template_id (FK) if missing, and trigger+function.
-- ====================================================================


-- 0) Ensure helper for updated_at exists
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- 1) Column on orders for selected production template
alter table public.orders
  add column if not exists prod_template_id uuid;

-- 1.1) FK to prod_templates (if table exists)
do $$
begin
  if to_regclass('public.prod_templates') is not null then
    begin
      alter table public.orders
        add constraint orders_prod_template_id_fkey
        foreign key (prod_template_id) references public.prod_templates(id) on delete set null;
    exception when duplicate_object then
      null;
    end;
  end if;
end $$;

-- 2) Convenience index
create index if not exists idx_orders_prod_template on public.orders(prod_template_id);

-- 3) Function: copy template stages into a plan bound to order
create or replace function public.copy_template_to_plan(p_order_id uuid, p_template_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_plan_id uuid;
begin
  if p_order_id is null or p_template_id is null then
    return null;
  end if;

  -- Ensure plan exists (one plan per order)
  select id into v_plan_id
  from public.prod_plans
  where order_id = p_order_id
  limit 1;

  if v_plan_id is null then
    insert into public.prod_plans(order_id, template_id, title, plan_code, note, created_by)
    select
      o.id,
      p_template_id,
      coalesce((o.product->>'name'), o.assignment_id, 'План для заказа'),
      o.assignment_id,
      null,
      auth.uid()
    from public.orders o
    where o.id = p_order_id
    returning id into v_plan_id;
  else
    -- If template changed, reset stages
    update public.prod_plans
      set template_id = p_template_id
    where id = v_plan_id;
    delete from public.prod_plan_stages where plan_id = v_plan_id;
  end if;

  -- Copy stages from template -> plan
  insert into public.prod_plan_stages(
    plan_id, template_stage_id, seq, name, note,
    position_id, workplace_id, expected_minutes,
    created_by
  )
  select
    v_plan_id, ts.id, ts.seq, ts.name, ts.note,
    ts.position_id, ts.workplace_id, ts.expected_minutes,
    auth.uid()
  from public.prod_template_stages ts
  where ts.template_id = p_template_id
  order by ts.seq;

  return v_plan_id;
end $$;

-- 4) Helper to infer template id from an order row (from different places)
create or replace function public._infer_template_id_from_order(o public.orders)
returns uuid
language plpgsql
as $$
declare
  v_tid uuid;
  v_txt text;
begin
  v_tid := o.prod_template_id;
  if v_tid is not null then
    return v_tid;
  end if;

  -- try product JSON keys
  v_txt := coalesce(o.product->>'template_id', o.product->>'templateId', o.product->>'prod_template_id');
  if v_txt is not null then
    begin
      v_tid := v_txt::uuid;
      return v_tid;
    exception when others then
      -- ignore cast errors
      null;
    end;
  end if;

  -- Try by template name in JSON: product.planName / templateName
  v_txt := coalesce(o.product->>'planName', o.product->>'templateName');
  if v_txt is not null then
    select id into v_tid from public.prod_templates where lower(name) = lower(v_txt) limit 1;
    if v_tid is not null then
      return v_tid;
    end if;
  end if;

  return null;
end $$;

-- 5) Main trigger: on insert & on update of prod_template_id/product - ensure plan exists
create or replace function public.tg_orders_sync_prod_plan()
returns trigger
language plpgsql
as $$
declare
  v_tid uuid;
begin
  -- Only for authenticated sessions to satisfy RLS of prod_* tables
  if coalesce((auth.jwt() ->> 'role') = 'authenticated', false) is not true then
    return new;
  end if;

  -- determine template id
  v_tid := public._infer_template_id_from_order(new);

  if v_tid is null then
    return new;
  end if;

  -- create/sync
  perform public.copy_template_to_plan(new.id, v_tid);

  return new;
end $$;

-- Drop & recreate triggers (idempotent)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='orders') then
    drop trigger if exists trg_orders_sync_prod_plan_ins on public.orders;
    drop trigger if exists trg_orders_sync_prod_plan_upd on public.orders;

    create trigger trg_orders_sync_prod_plan_ins
      after insert on public.orders
      for each row execute function public.tg_orders_sync_prod_plan();

    create trigger trg_orders_sync_prod_plan_upd
      after update of prod_template_id, product on public.orders
      for each row execute function public.tg_orders_sync_prod_plan();
  end if;
end $$;

-- 6) Minimal RLS safety: prod_* tables already created by previous patch with permissive policies.
--    Ensure orders has RLS enabled (Supabase default is ON), nothing to change here.

-- 7) Optional: a lightweight view to quickly display plan stages by order
create or replace view public.v_order_plan_stages as
select
  o.id as order_id,
  o.assignment_id as order_code,
  p.id as plan_id,
  s.id as stage_id,
  s.seq as step_no,
  s.name as stage_name,
  s.status,
  s.started_at,
  s.finished_at,
  s.expected_minutes,
  s.actual_minutes
from public.orders o
left join public.prod_plans p on p.order_id = o.id
left join public.prod_plan_stages s on s.plan_id = p.id;

-- Add realtime for prod tables (safe if already in publication)
do $$ begin
  perform 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='prod_plans';
  if not found then
    alter publication supabase_realtime add table public.prod_plans;
  end if;
  perform 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='prod_plan_stages';
  if not found then
    alter publication supabase_realtime add table public.prod_plan_stages;
  end if;
end $$;

-- Ask PostgREST to reload schema cache
notify pgrst, 'reload schema';
-----------------------------------------------------------------------------------------------------------------

-- backfill_all_orders_prod_plans.sql
-- Не создаёт объектов схемы. Только данные.
-- Пройдётся по всем заказам, у которых нет prod_plans, и создаст план + стадии,
-- если удастся определить шаблон (из orders.prod_template_id или JSON product).
do $$
declare
  r record;
  v_plan_id uuid;
  v_template_id uuid;
  v_by_name text;
  v_stages int;
begin
  for r in
    select o.*
    from public.orders o
    left join public.prod_plans p on p.order_id = o.id
    where p.id is null
  loop
    v_template_id := null;
    -- 1) искать UUID шаблона
    begin
      select coalesce( nullif(r.product->>'template_id','')::uuid,
                       nullif(r.product->>'templateId','')::uuid,
                       nullif(r.product->>'prod_template_id','')::uuid )
        into v_template_id;
    exception when others then
      v_template_id := null;
    end;

    -- 2) если нет UUID — попробовать по имени
    if v_template_id is null then
      v_by_name := coalesce(r.product->>'templateName', r.product->>'planName');
      if v_by_name is not null then
        select id into v_template_id
        from public.prod_templates
        where lower(name) = lower(v_by_name)
        limit 1;
      end if;
    end if;

    -- 3) если так и не нашли — пропускаем заказ
    if v_template_id is null then
      raise notice 'skip order %: template not found', r.assignment_id;
      continue;
    end if;

    -- 4) создаём план
    insert into public.prod_plans(order_id, template_id, title, plan_code, note)
    values (r.id, v_template_id, coalesce(r.product->>'name','План'), r.assignment_id, null)
    returning id into v_plan_id;

    -- 5) копируем стадии
    insert into public.prod_plan_stages(
      plan_id, template_stage_id, seq, name, note,
      position_id, workplace_id, expected_minutes
    )
    select v_plan_id, ts.id, ts.seq, ts.name, ts.note,
           ts.position_id, ts.workplace_id, ts.expected_minutes
    from public.prod_template_stages ts
    where ts.template_id = v_template_id
    order by ts.seq;

    get diagnostics v_stages = row_count;
    raise notice 'order % -> plan % with % stages', r.assignment_id, v_plan_id, v_stages;
  end loop;
end $$;
-----------------------------------------------------------------------------------------------------------------------
-- apply_template_to_order.sql
-- Server-side function to attach a template to an order:
--   - writes template_id + stages into production_plans for that order
--   - does NOT touch tasks (you may have triggers elsewhere); UI immediately sees stages

create or replace function public.apply_template_to_order(
  p_order_id uuid,
  p_template_id uuid,
  p_by_name text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stages jsonb;
  v_name   text;
begin
  select t.stages, t.name into v_stages, v_name
  from public.plan_templates t
  where t.id = p_template_id;

  if v_stages is null then
    raise exception 'Template % not found or has no stages', p_template_id;
  end if;

  -- Upsert production plan
  insert into public.production_plans(order_id, stages, template_id, template_name, by_name, updated_at)
  values (p_order_id, v_stages, p_template_id, v_name, p_by_name, now())
  on conflict (order_id) do update
    set stages       = excluded.stages,
        template_id  = excluded.template_id,
        template_name= excluded.template_name,
        by_name      = excluded.by_name,
        updated_at   = now();
end;
$$;

-- Minimal execute privilege for authenticated users
revoke all on function public.apply_template_to_order(uuid, uuid, text) from public;
grant execute on function public.apply_template_to_order(uuid, uuid, text) to authenticated, anon, service_role;
--------------------------------------------------------------------------------------------------------------------------------

-- migrate_plan_templates_existing.sql
-- Safely upgrades an existing public.plan_templates table to the expected schema.

-- 0) Extensions (safe to re-run)

-- 1) Ensure table exists
create table if not exists public.plan_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  stages jsonb not null default '[]'::jsonb
);

-- 2) Add missing columns (id/name/stages assumed above)
alter table public.plan_templates add column if not exists description text;
alter table public.plan_templates add column if not exists is_archived boolean;
alter table public.plan_templates add column if not exists created_by uuid;
alter table public.plan_templates add column if not exists created_at timestamptz;
alter table public.plan_templates add column if not exists updated_at timestamptz;

-- 3) Backfill nulls and set proper defaults / not-null where needed
update public.plan_templates set stages = '[]'::jsonb where stages is null;
alter table public.plan_templates alter column stages set default '[]'::jsonb;
alter table public.plan_templates alter column stages set not null;

update public.plan_templates set is_archived = false where is_archived is null;
alter table public.plan_templates alter column is_archived set default false;
alter table public.plan_templates alter column is_archived set not null;

update public.plan_templates set created_at = now() where created_at is null;
update public.plan_templates set updated_at = now() where updated_at is null;
alter table public.plan_templates alter column created_at set default now();
alter table public.plan_templates alter column updated_at set default now();
alter table public.plan_templates alter column created_at set not null;
alter table public.plan_templates alter column updated_at set not null;

-- (Optional) If you want FK to auth.users; skip if not needed
-- DO $$
-- BEGIN
--   IF NOT EXISTS (
--     SELECT 1 FROM pg_constraint
--     WHERE conrelid = 'public.plan_templates'::regclass
--       AND conname = 'plan_templates_created_by_fkey'
--   ) THEN
--     alter table public.plan_templates
--       add constraint plan_templates_created_by_fkey
--       foreign key (created_by) references auth.users(id) on delete set null;
--   END IF;
-- END $$;

-- 4) Indexes
create index if not exists idx_plan_templates_name on public.plan_templates using gin (to_tsvector('simple', coalesce(name,'')));
create index if not exists idx_plan_templates_archived on public.plan_templates(is_archived);

-- 5) updated_at trigger
create or replace function public.tg_set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_plan_templates_updated_at on public.plan_templates;
create trigger trg_plan_templates_updated_at
  before update on public.plan_templates
  for each row execute function public.tg_set_updated_at();

-- 6) RLS
alter table public.plan_templates enable row level security;

drop policy if exists "plan_templates read for all" on public.plan_templates;
create policy "plan_templates read for all"
  on public.plan_templates for select using (true);

drop policy if exists "plan_templates insert for owners" on public.plan_templates;
create policy "plan_templates insert for owners"
  on public.plan_templates for insert to authenticated
  with check (auth.uid() = coalesce(created_by, auth.uid()));

drop policy if exists "plan_templates update for owners" on public.plan_templates;
create policy "plan_templates update for owners"
  on public.plan_templates for update to authenticated
  using (created_by is null or auth.uid() = created_by)
  with check (created_by is null or auth.uid() = created_by);

drop policy if exists "plan_templates delete for owners" on public.plan_templates;
create policy "plan_templates delete for owners"
  on public.plan_templates for delete to authenticated
  using (created_by is null or auth.uid() = created_by);

-- 7) Verify
-- select column_name, data_type, is_nullable, column_default
-- from information_schema.columns
-- where table_schema='public' and table_name='plan_templates'
-- order by ordinal_position;

---------------------------------------------------------------------------------------------------------------------------
-- create_plan_templates.sql
-- Creates a dedicated table for production plan templates + RLS + helpers.

-- Extensions

-- Table
create table if not exists public.plan_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  stages jsonb not null default '[]'::jsonb, -- array of stage objects
  is_archived boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Indexes
create index if not exists idx_plan_templates_name on public.plan_templates using gin (to_tsvector('simple', coalesce(name,'')));
create index if not exists idx_plan_templates_archived on public.plan_templates(is_archived);

-- Trigger to keep updated_at in sync
create or replace function public.tg_set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_plan_templates_updated_at on public.plan_templates;
create trigger trg_plan_templates_updated_at
  before update on public.plan_templates
  for each row execute function public.tg_set_updated_at();

-- RLS
alter table public.plan_templates enable row level security;

-- Read for everyone (anon/auth) – adjust if you want stricter rules
drop policy if exists "plan_templates read for all" on public.plan_templates;
create policy "plan_templates read for all"
  on public.plan_templates
  for select
  using (true);

-- Insert/update for authenticated owners
drop policy if exists "plan_templates insert for owners" on public.plan_templates;
create policy "plan_templates insert for owners"
  on public.plan_templates
  for insert
  to authenticated
  with check (auth.uid() = coalesce(created_by, auth.uid()));

drop policy if exists "plan_templates update for owners" on public.plan_templates;
create policy "plan_templates update for owners"
  on public.plan_templates
  for update
  to authenticated
  using (created_by is null or auth.uid() = created_by)
  with check (created_by is null or auth.uid() = created_by);

-- Optional: delete only by owners
drop policy if exists "plan_templates delete for owners" on public.plan_templates;
create policy "plan_templates delete for owners"
  on public.plan_templates
  for delete
  to authenticated
  using (created_by is null or auth.uid() = created_by);

-- NOTE: Don't forcibly add to supabase_realtime publication here to avoid
-- 'relation is already member of publication' errors you saw previously.
-- If you need realtime, toggle it in the dashboard once.\n-- END of прочее.sql\n

-- ============================================================
-- CHAT MODULE — dedicated SQL tables (no 'public.documents')
-- Safe to run multiple times (idempotent-ish).
-- Requires: pgcrypto (for gen_random_uuid), Supabase Realtime.
-- ============================================================

-- 0) Extensions & helper

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ============================================================
-- 1) ROOMS (optional but recommended)
-- You can use arbitrary string IDs for rooms ("global", "order:ORD-2025-001", etc.)
-- ============================================================
create table if not exists public.chat_rooms (
  id          text primary key,           -- room identifier used by the app
  title       text,
  created_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);
drop trigger if exists trg_chat_rooms_updated_at on public.chat_rooms;
create trigger trg_chat_rooms_updated_at
before update on public.chat_rooms
for each row execute function public.set_updated_at();
alter table public.chat_rooms enable row level security;

-- Basic open read (optional). Tighten later if needed.
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='chat_rooms' and policyname='chat_rooms_read'
  ) then
    create policy chat_rooms_read on public.chat_rooms
      for select to authenticated using (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='chat_rooms' and policyname='chat_rooms_write'
  ) then
    create policy chat_rooms_write on public.chat_rooms
      for insert to authenticated with check (true);
  end if;
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='chat_rooms' and policyname='chat_rooms_update_own'
  ) then
    create policy chat_rooms_update_own on public.chat_rooms
      for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());
  end if;
end $$;

-- ============================================================
-- 2) MEMBERS (optional; use to restrict visibility by room membership)
-- If you don't need membership yet, keep it empty; policies below for messages
-- are "open to authenticated" by default.
-- ============================================================
create table if not exists public.chat_members (
  room_id   text references public.chat_rooms(id) on delete cascade,
  user_id   uuid not null,
  role      text check (role in ('member','admin')) default 'member',
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
alter table public.chat_members enable row level security;
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='chat_members' and policyname='chat_members_rw'
  ) then
    create policy chat_members_rw on public.chat_members
      for all to authenticated using (true) with check (true);
  end if;
end $$;

create index if not exists idx_chat_members_user on public.chat_members(user_id);
create index if not exists idx_chat_members_room on public.chat_members(room_id);

-- ============================================================
-- 3) MESSAGES (core table the app uses)
-- ============================================================
create table if not exists public.chat_messages (
  id           uuid primary key default gen_random_uuid(),
  room_id      text not null,
  sender_id    uuid,
  sender_name  text,
  kind         text not null check (kind in ('text','image','video','audio','file')),
  body         text,
  file_url     text,
  file_mime    text,
  duration_ms  integer,
  width        integer,
  height       integer,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz
);

drop trigger if exists trg_chat_messages_updated_at on public.chat_messages;
create trigger trg_chat_messages_updated_at
before update on public.chat_messages
for each row execute function public.set_updated_at();

create index if not exists idx_chat_messages_room_created
  on public.chat_messages (room_id, created_at);
create index if not exists idx_chat_messages_sender
  on public.chat_messages (sender_id);

alter table public.chat_messages enable row level security;

-- ---------- RLS (simple/open defaults) ----------
-- By default let all authenticated users read all messages.
-- Insert allowed for authenticated; the client sets sender_id.
-- Update/Delete allowed only for the original sender.
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='chat_messages' and policyname='chat_messages_read'
  ) then
    create policy chat_messages_read on public.chat_messages
      for select to authenticated using (true);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='chat_messages' and policyname='chat_messages_insert'
  ) then
    create policy chat_messages_insert on public.chat_messages
      for insert to authenticated
      with check (true);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='chat_messages' and policyname='chat_messages_update_own'
  ) then
    create policy chat_messages_update_own on public.chat_messages
      for update to authenticated
      using (sender_id = auth.uid())
      with check (sender_id = auth.uid());
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='chat_messages' and policyname='chat_messages_delete_own'
  ) then
    create policy chat_messages_delete_own on public.chat_messages
      for delete to authenticated
      using (sender_id = auth.uid());
  end if;
end $$;

-- ---------- (OPTIONAL) Membership-based policies ----------
-- When you start using chat_members, replace chat_messages_read/insert with stricter ones:
--
-- drop policy if exists chat_messages_read on public.chat_messages;
-- create policy chat_messages_read on public.chat_messages
--   for select to authenticated
--   using (exists (
--     select 1 from public.chat_members m
--     where m.room_id = chat_messages.room_id and m.user_id = auth.uid()
--   ));
--
-- drop policy if exists chat_messages_insert on public.chat_messages;
-- create policy chat_messages_insert on public.chat_messages
--   for insert to authenticated
--   with check (exists (
--     select 1 from public.chat_members m
--     where m.room_id = chat_messages.room_id and m.user_id = auth.uid()
--   ));

-- ============================================================
-- 4) STORAGE bucket for media: 'chat'
-- ============================================================
do $$ begin
  -- create public bucket if it doesn't exist
  perform storage.create_bucket('chat', public := true);
exception when others then
  -- ignore if it already exists
  null;
end $$;

-- Storage RLS (Supabase Storage uses its own 'storage.objects' table)
-- Public read for chat files:
do $$ begin
  if not exists (
    select 1 from pg_policies where tablename='objects' and schemaname='storage' and policyname='chat_public_read'
  ) then
    create policy chat_public_read on storage.objects
      for select to anon, authenticated
      using (bucket_id = 'chat');
  end if;
  if not exists (
    select 1 from pg_policies where tablename='objects' and schemaname='storage' and policyname='chat_upload_auth'
  ) then
    create policy chat_upload_auth on storage.objects
      for insert to authenticated
      with check (bucket_id = 'chat');
  end if;
  if not exists (
    select 1 from pg_policies where tablename='objects' and schemaname='storage' and policyname='chat_update_owner'
  ) then
    create policy chat_update_owner on storage.objects
      for update to authenticated
      using (bucket_id = 'chat' and owner = auth.uid())
      with check (bucket_id = 'chat' and owner = auth.uid());
  end if;
  if not exists (
    select 1 from pg_policies where tablename='objects' and schemaname='storage' and policyname='chat_delete_owner'
  ) then
    create policy chat_delete_owner on storage.objects
      for delete to authenticated
      using (bucket_id = 'chat' and owner = auth.uid());
  end if;
end $$;

-- ============================================================
-- 5) Realtime: include the chat_messages table in publication
-- ============================================================
do $$ begin
  execute 'alter publication supabase_realtime add table public.chat_messages';
exception when others then
  -- ignore if it is already part of the publication
  null;
end $$;
-- END of чат.sql\n
