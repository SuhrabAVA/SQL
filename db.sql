-- ============================================================
-- Personnel & Warehouse schema setup for Supabase
-- Consolidated script without duplicates. Safe to run multiple times.
-- ============================================================

-- ------------------------------------------------------------
-- Required extensions check (enable them from Supabase dashboard)
-- ------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    RAISE EXCEPTION 'Extension "pgcrypto" must be enabled before running this script.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp') THEN
    RAISE EXCEPTION 'Extension "uuid-ossp" must be enabled before running this script.';
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- Generic helpers
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 1. PERSONNEL MODULE
-- ============================================================

-- --------------------------
-- Base tables
-- --------------------------
CREATE TABLE IF NOT EXISTS public.positions (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_positions_updated_at ON public.positions;
CREATE TRIGGER trg_positions_updated_at
  BEFORE UPDATE ON public.positions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.positions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.employees (
  id          TEXT PRIMARY KEY,
  last_name   TEXT NOT NULL,
  first_name  TEXT NOT NULL,
  patronymic  TEXT NOT NULL,
  iin         TEXT NOT NULL UNIQUE,
  photo_url   TEXT,
  is_fired    BOOLEAN NOT NULL DEFAULT FALSE,
  comments    TEXT,
  login       TEXT UNIQUE,
  password    TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_employees_updated_at ON public.employees;
CREATE TRIGGER trg_employees_updated_at
  BEFORE UPDATE ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.employee_positions (
  employee_id TEXT NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  position_id TEXT NOT NULL REFERENCES public.positions(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (employee_id, position_id)
);
ALTER TABLE public.employee_positions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.workplaces (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  description TEXT,
  has_machine BOOLEAN NOT NULL DEFAULT FALSE,
  max_concurrent_workers INT NOT NULL DEFAULT 1,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_workplaces_updated_at ON public.workplaces;
CREATE TRIGGER trg_workplaces_updated_at
  BEFORE UPDATE ON public.workplaces
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.workplaces ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.workplace_positions (
  workplace_id TEXT NOT NULL REFERENCES public.workplaces(id) ON DELETE CASCADE,
  position_id  TEXT NOT NULL REFERENCES public.positions(id) ON DELETE RESTRICT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (workplace_id, position_id)
);
ALTER TABLE public.workplace_positions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.terminals (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_terminals_updated_at ON public.terminals;
CREATE TRIGGER trg_terminals_updated_at
  BEFORE UPDATE ON public.terminals
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.terminals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.terminal_workplaces (
  terminal_id  TEXT NOT NULL REFERENCES public.terminals(id) ON DELETE CASCADE,
  workplace_id TEXT NOT NULL REFERENCES public.workplaces(id) ON DELETE RESTRICT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (terminal_id, workplace_id)
);
ALTER TABLE public.terminal_workplaces ENABLE ROW LEVEL SECURITY;

-- --------------------------
-- Views
-- --------------------------
CREATE OR REPLACE VIEW public.employees_view AS
SELECT
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
  COALESCE(ARRAY_AGG(ep.position_id)
           FILTER (WHERE ep.position_id IS NOT NULL), '{}') AS position_ids
FROM public.employees e
LEFT JOIN public.employee_positions ep ON ep.employee_id = e.id
GROUP BY e.id;

CREATE OR REPLACE VIEW public.workplaces_view AS
SELECT
  w.id,
  w.name,
  w.description,
  w.has_machine,
  w.max_concurrent_workers,
  w.created_at,
  w.updated_at,
  COALESCE(ARRAY_AGG(wp.position_id)
           FILTER (WHERE wp.position_id IS NOT NULL), '{}') AS position_ids
FROM public.workplaces w
LEFT JOIN public.workplace_positions wp ON wp.workplace_id = w.id
GROUP BY w.id;

CREATE OR REPLACE VIEW public.terminals_view AS
SELECT
  t.id,
  t.name,
  t.description,
  t.created_at,
  t.updated_at,
  COALESCE(ARRAY_AGG(tw.workplace_id)
           FILTER (WHERE tw.workplace_id IS NOT NULL), '{}') AS workplace_ids
FROM public.terminals t
LEFT JOIN public.terminal_workplaces tw ON tw.terminal_id = t.id
GROUP BY t.id;

-- --------------------------
-- User roles & helper function
-- --------------------------
CREATE TABLE IF NOT EXISTS public.user_roles (
  user_id  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  is_admin BOOLEAN NOT NULL DEFAULT FALSE,
  roles    TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_user_roles_updated_at ON public.user_roles;
CREATE TRIGGER trg_user_roles_updated_at
  BEFORE UPDATE ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.can_manage_personnel()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.user_roles ur
     WHERE ur.user_id = auth.uid()
       AND (ur.is_admin OR 'tech_leader' = ANY(COALESCE(ur.roles, '{}'::text[])))
  );
$$;

-- --------------------------
-- Seeds
-- --------------------------
INSERT INTO public.positions (id, name) VALUES
  ('bob_cutter','Бобинорезчик'),
  ('print','Печатник'),
  ('cut_sheet','Листорезчик'),
  ('bag_collector','Пакетосборщик'),
  ('cutter','Резчик'),
  ('bottom_gluer','Дносклейщик'),
  ('handle_gluer','Склейщик ручек'),
  ('die_cutter','Оператор высечки'),
  ('assembler','Сборщик'),
  ('rope_operator','Оператор верёвок'),
  ('handle_operator','Оператор ручек'),
  ('muffin_operator','Оператор маффинов'),
  ('single_point_gluer','Склейка одной точки'),
  ('manager','Менеджер'),
  ('warehouse_head','Заведующий складом'),
  ('tech_leader','Технический лидер')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.workplaces (id, name, has_machine, max_concurrent_workers) VALUES
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
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.workplace_positions (workplace_id, position_id) VALUES
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
ON CONFLICT (workplace_id, position_id) DO NOTHING;

-- Tech lead employee (update credentials as needed)
WITH payload AS (
  SELECT
    'techlead-1'::TEXT   AS id,
    'Иванов'::TEXT       AS last_name,
    'Иван'::TEXT         AS first_name,
    'Иванович'::TEXT     AS patronymic,
    '999999999999'::TEXT AS iin,
    NULL::TEXT           AS photo_url,
    FALSE::BOOLEAN       AS is_fired,
    'Технический лидер'::TEXT AS comments,
    'techlead'::TEXT     AS login,
    '1234'::TEXT         AS password
)
INSERT INTO public.employees (id,last_name,first_name,patronymic,iin,photo_url,is_fired,comments,login,password)
SELECT id,last_name,first_name,patronymic,iin,photo_url,is_fired,comments,login,password
FROM payload p
WHERE NOT EXISTS (
  SELECT 1 FROM public.employees e
  WHERE e.id = p.id OR e.iin = p.iin
);

INSERT INTO public.employee_positions (employee_id, position_id)
SELECT 'techlead-1', 'tech_leader'
WHERE EXISTS (SELECT 1 FROM public.employees WHERE id='techlead-1')
  AND EXISTS (SELECT 1 FROM public.positions  WHERE id='tech_leader')
  AND NOT EXISTS (
        SELECT 1
          FROM public.employee_positions
         WHERE employee_id='techlead-1'
           AND position_id='tech_leader'
      );

INSERT INTO public.user_roles (user_id, is_admin, roles)
SELECT
  au.id,
  TRUE,
  CASE
    WHEN 'tech_leader' = ANY(COALESCE(ur.roles, '{}'))
      THEN COALESCE(ur.roles, '{}')
    ELSE ARRAY_APPEND(COALESCE(ur.roles, '{}'), 'tech_leader')
  END
FROM auth.users au
LEFT JOIN public.user_roles ur ON ur.user_id = au.id
WHERE au.email = 'YOUR_EMAIL@EXAMPLE.COM'
ON CONFLICT (user_id) DO UPDATE
SET is_admin = TRUE,
    roles = CASE
              WHEN 'tech_leader' = ANY(public.user_roles.roles)
                THEN public.user_roles.roles
              ELSE ARRAY_APPEND(public.user_roles.roles, 'tech_leader')
            END;

-- --------------------------
-- Personnel RLS cleanup & policies
-- --------------------------
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT schemaname, tablename, policyname
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename IN (
         'positions','employees','employee_positions',
         'workplaces','workplace_positions','terminals',
         'terminal_workplaces','user_roles'
       )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', rec.policyname, rec.tablename);
  END LOOP;
END;
$$;

CREATE POLICY positions_select_auth ON public.positions
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY positions_manage_admin ON public.positions
  FOR ALL TO authenticated
  USING (public.can_manage_personnel())
  WITH CHECK (public.can_manage_personnel());

CREATE POLICY employees_select_auth ON public.employees
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY employees_manage_admin ON public.employees
  FOR ALL TO authenticated
  USING (public.can_manage_personnel())
  WITH CHECK (public.can_manage_personnel());

CREATE POLICY employee_positions_select_auth ON public.employee_positions
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY employee_positions_manage_admin ON public.employee_positions
  FOR ALL TO authenticated
  USING (public.can_manage_personnel())
  WITH CHECK (public.can_manage_personnel());

CREATE POLICY workplaces_select_auth ON public.workplaces
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY workplaces_manage_admin ON public.workplaces
  FOR ALL TO authenticated
  USING (public.can_manage_personnel())
  WITH CHECK (public.can_manage_personnel());

CREATE POLICY workplace_positions_select_auth ON public.workplace_positions
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY workplace_positions_manage_admin ON public.workplace_positions
  FOR ALL TO authenticated
  USING (public.can_manage_personnel())
  WITH CHECK (public.can_manage_personnel());

CREATE POLICY terminals_select_auth ON public.terminals
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY terminals_manage_admin ON public.terminals
  FOR ALL TO authenticated
  USING (public.can_manage_personnel())
  WITH CHECK (public.can_manage_personnel());

CREATE POLICY terminal_workplaces_select_auth ON public.terminal_workplaces
  FOR SELECT TO authenticated
  USING (TRUE);

CREATE POLICY terminal_workplaces_manage_admin ON public.terminal_workplaces
  FOR ALL TO authenticated
  USING (public.can_manage_personnel())
  WITH CHECK (public.can_manage_personnel());

CREATE POLICY user_roles_select_self ON public.user_roles
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id OR public.can_manage_personnel());

CREATE POLICY user_roles_manage_admin ON public.user_roles
  FOR ALL TO authenticated
  USING (public.can_manage_personnel())
  WITH CHECK (public.can_manage_personnel());

GRANT SELECT ON public.employees_view, public.workplaces_view, public.terminals_view TO authenticated;

-- --------------------------
-- Storage bucket for employee photos
-- --------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('employee_photos', 'employee_photos', TRUE)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

DROP POLICY IF EXISTS "employee_photos read public" ON storage.objects;
CREATE POLICY "employee_photos read public" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'employee_photos');

DROP POLICY IF EXISTS "employee_photos insert auth" ON storage.objects;
CREATE POLICY "employee_photos insert auth" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'employee_photos');

-- ============================================================
-- 2. WAREHOUSE MODULE
-- ============================================================

-- --------------------------
-- Categories (shared)
-- --------------------------
CREATE TABLE IF NOT EXISTS public.warehouse_categories (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code          TEXT NOT NULL UNIQUE,
  title         TEXT NOT NULL,
  has_subtables BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_whcat_updated_at ON public.warehouse_categories;
CREATE TRIGGER trg_whcat_updated_at
  BEFORE UPDATE ON public.warehouse_categories
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.warehouse_categories ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.warehouse_category_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL REFERENCES public.warehouse_categories(id) ON DELETE CASCADE,
  table_key   TEXT,
  description TEXT NOT NULL,
  quantity    NUMERIC(12,3) NOT NULL DEFAULT 0,
  unit        TEXT NOT NULL DEFAULT 'pcs',
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
DROP TRIGGER IF EXISTS trg_wci_updated_at ON public.warehouse_category_items;
CREATE TRIGGER trg_wci_updated_at
  BEFORE UPDATE ON public.warehouse_category_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.warehouse_category_items ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.warehouse_category_writeoffs (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id    UUID NOT NULL REFERENCES public.warehouse_category_items(id) ON DELETE CASCADE,
  qty        NUMERIC(12,3) NOT NULL,
  reason     TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.warehouse_category_writeoffs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.warehouse_category_inventories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id     UUID NOT NULL REFERENCES public.warehouse_category_items(id) ON DELETE CASCADE,
  counted_qty NUMERIC(12,3) NOT NULL,
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.warehouse_category_inventories ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_wc_code ON public.warehouse_categories(code);
CREATE INDEX IF NOT EXISTS idx_wci_category ON public.warehouse_category_items(category_id);
CREATE INDEX IF NOT EXISTS idx_wci_category_table ON public.warehouse_category_items(category_id, table_key);
CREATE INDEX IF NOT EXISTS idx_wcw_item ON public.warehouse_category_writeoffs(item_id);
CREATE INDEX IF NOT EXISTS idx_wcinv_item ON public.warehouse_category_inventories(item_id);

-- --------------------------
-- Inventory tables (paints/materials/papers/stationery)
-- --------------------------
CREATE TABLE IF NOT EXISTS public.paints (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date               TEXT,
  supplier           TEXT,
  description        TEXT NOT NULL,
  unit               TEXT NOT NULL DEFAULT 'ml',
  quantity           NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  low_threshold      NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (low_threshold >= 0),
  critical_threshold NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (critical_threshold >= 0),
  note               TEXT,
  image_url          TEXT,
  image_base64       TEXT,
  color_code         TEXT,
  manufacturer       TEXT,
  category_id        UUID REFERENCES public.warehouse_categories(id) ON DELETE SET NULL,
  created_by         UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_paints_updated_at ON public.paints;
CREATE TRIGGER trg_paints_updated_at
  BEFORE UPDATE ON public.paints
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.paints ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.paints_writeoffs (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paint_id   UUID NOT NULL REFERENCES public.paints(id) ON DELETE CASCADE,
  qty        NUMERIC(14,3) NOT NULL CHECK (qty > 0),
  reason     TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name    TEXT
);
ALTER TABLE public.paints_writeoffs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.paints_inventories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paint_id    UUID NOT NULL REFERENCES public.paints(id) ON DELETE CASCADE,
  counted_qty NUMERIC(14,3) NOT NULL CHECK (counted_qty >= 0),
  note        TEXT,
  created_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name     TEXT
);
ALTER TABLE public.paints_inventories ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.paints_arrivals (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paint_id   UUID NOT NULL REFERENCES public.paints(id) ON DELETE CASCADE,
  qty        NUMERIC(14,3) NOT NULL CHECK (qty > 0),
  note       TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name    TEXT
);
ALTER TABLE public.paints_arrivals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.materials (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date               TEXT,
  supplier           TEXT,
  description        TEXT NOT NULL,
  unit               TEXT NOT NULL DEFAULT 'kg',
  quantity           NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  low_threshold      NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (low_threshold >= 0),
  critical_threshold NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (critical_threshold >= 0),
  note               TEXT,
  image_url          TEXT,
  image_base64       TEXT,
  category_id        UUID REFERENCES public.warehouse_categories(id) ON DELETE SET NULL,
  created_by         UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_materials_updated_at ON public.materials;
CREATE TRIGGER trg_materials_updated_at
  BEFORE UPDATE ON public.materials
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.materials_writeoffs (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id UUID NOT NULL REFERENCES public.materials(id) ON DELETE CASCADE,
  qty        NUMERIC(14,3) NOT NULL CHECK (qty > 0),
  reason     TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name    TEXT
);
ALTER TABLE public.materials_writeoffs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.materials_inventories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id UUID NOT NULL REFERENCES public.materials(id) ON DELETE CASCADE,
  counted_qty NUMERIC(14,3) NOT NULL CHECK (counted_qty >= 0),
  note        TEXT,
  created_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name     TEXT
);
ALTER TABLE public.materials_inventories ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.materials_arrivals (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  material_id UUID NOT NULL REFERENCES public.materials(id) ON DELETE CASCADE,
  qty        NUMERIC(14,3) NOT NULL CHECK (qty > 0),
  note       TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name    TEXT
);
ALTER TABLE public.materials_arrivals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.papers (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date               TEXT,
  supplier           TEXT,
  description        TEXT NOT NULL,
  format             TEXT NOT NULL,
  grammage           TEXT NOT NULL,
  weight             NUMERIC(14,3),
  unit               TEXT NOT NULL DEFAULT 'sheets',
  quantity           NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  low_threshold      NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (low_threshold >= 0),
  critical_threshold NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (critical_threshold >= 0),
  note               TEXT,
  category_id        UUID REFERENCES public.warehouse_categories(id) ON DELETE SET NULL,
  created_by         UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ,
  UNIQUE (description, format, grammage)
);
DROP TRIGGER IF EXISTS trg_papers_updated_at ON public.papers;
CREATE TRIGGER trg_papers_updated_at
  BEFORE UPDATE ON public.papers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.papers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.papers_writeoffs (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paper_id  UUID NOT NULL REFERENCES public.papers(id) ON DELETE CASCADE,
  qty       NUMERIC(14,3) NOT NULL CHECK (qty > 0),
  reason    TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name   TEXT
);
ALTER TABLE public.papers_writeoffs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.papers_inventories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paper_id    UUID NOT NULL REFERENCES public.papers(id) ON DELETE CASCADE,
  counted_qty NUMERIC(14,3) NOT NULL CHECK (counted_qty >= 0),
  note        TEXT,
  created_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name     TEXT
);
ALTER TABLE public.papers_inventories ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.papers_arrivals (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  paper_id  UUID NOT NULL REFERENCES public.papers(id) ON DELETE CASCADE,
  qty       NUMERIC(14,3) NOT NULL CHECK (qty > 0),
  note      TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name   TEXT
);
ALTER TABLE public.papers_arrivals ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.stationery (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date               TEXT,
  supplier           TEXT,
  description        TEXT NOT NULL,
  unit               TEXT NOT NULL DEFAULT 'pcs',
  quantity           NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  low_threshold      NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (low_threshold >= 0),
  critical_threshold NUMERIC(14,3) NOT NULL DEFAULT 0 CHECK (critical_threshold >= 0),
  note               TEXT,
  image_url          TEXT,
  image_base64       TEXT,
  category_id        UUID REFERENCES public.warehouse_categories(id) ON DELETE SET NULL,
  created_by         UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ
);
DROP TRIGGER IF EXISTS trg_stationery_updated_at ON public.stationery;
CREATE TRIGGER trg_stationery_updated_at
  BEFORE UPDATE ON public.stationery
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.stationery ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.stationery_writeoffs (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id   UUID NOT NULL REFERENCES public.stationery(id) ON DELETE CASCADE,
  qty       NUMERIC(14,3) NOT NULL CHECK (qty > 0),
  reason    TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name   TEXT
);
ALTER TABLE public.stationery_writeoffs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.stationery_inventories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id     UUID NOT NULL REFERENCES public.stationery(id) ON DELETE CASCADE,
  counted_qty NUMERIC(14,3) NOT NULL CHECK (counted_qty >= 0),
  note        TEXT,
  created_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name     TEXT
);
ALTER TABLE public.stationery_inventories ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.stationery_arrivals (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id   UUID NOT NULL REFERENCES public.stationery(id) ON DELETE CASCADE,
  qty       NUMERIC(14,3) NOT NULL CHECK (qty > 0),
  note      TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name   TEXT
);
ALTER TABLE public.stationery_arrivals ENABLE ROW LEVEL SECURITY;

-- --------------------------
-- Warehouse stationery legacy table (table_key-based)
-- --------------------------
CREATE TABLE IF NOT EXISTS public.warehouse_stationery (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_key          TEXT NOT NULL,
  date               TEXT NOT NULL,
  supplier           TEXT,
  type               TEXT NOT NULL,
  description        TEXT NOT NULL,
  quantity           NUMERIC NOT NULL DEFAULT 0,
  unit               TEXT NOT NULL,
  format             TEXT,
  grammage           TEXT,
  weight             NUMERIC,
  note               TEXT,
  image_url          TEXT,
  image_base64       TEXT,
  low_threshold      NUMERIC,
  critical_threshold NUMERIC,
  created_by         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
DROP TRIGGER IF EXISTS trg_wh_stationery_updated_at ON public.warehouse_stationery;
CREATE TRIGGER trg_wh_stationery_updated_at
  BEFORE UPDATE ON public.warehouse_stationery
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.warehouse_stationery ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.warehouse_stationery_writeoffs (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id    UUID NOT NULL REFERENCES public.warehouse_stationery(id) ON DELETE CASCADE,
  qty        NUMERIC NOT NULL CHECK (qty > 0),
  reason     TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name    TEXT
);
ALTER TABLE public.warehouse_stationery_writeoffs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.warehouse_stationery_inventories (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id    UUID NOT NULL REFERENCES public.warehouse_stationery(id) ON DELETE CASCADE,
  factual    NUMERIC NOT NULL,
  note       TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name    TEXT
);
ALTER TABLE public.warehouse_stationery_inventories ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.warehouse_stationery_arrivals (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id    UUID NOT NULL REFERENCES public.warehouse_stationery(id) ON DELETE CASCADE,
  qty        NUMERIC NOT NULL CHECK (qty > 0),
  note       TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  by_name    TEXT
);
ALTER TABLE public.warehouse_stationery_arrivals ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_wh_stationery_table_key ON public.warehouse_stationery(table_key);
CREATE INDEX IF NOT EXISTS idx_wh_stationery_created_at ON public.warehouse_stationery(created_at);

-- --------------------------
-- Suppliers & forms series
-- --------------------------
CREATE TABLE IF NOT EXISTS public.suppliers (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  bin        TEXT,
  contact    TEXT,
  phone      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
DROP TRIGGER IF EXISTS trg_suppliers_updated_at ON public.suppliers;
CREATE TRIGGER trg_suppliers_updated_at
  BEFORE UPDATE ON public.suppliers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.forms_series (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  series      TEXT NOT NULL,
  prefix      TEXT NOT NULL DEFAULT '',
  suffix      TEXT NOT NULL DEFAULT '',
  last_number INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
DROP TRIGGER IF EXISTS trg_forms_series_updated_at ON public.forms_series;
CREATE TRIGGER trg_forms_series_updated_at
  BEFORE UPDATE ON public.forms_series
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.forms_series ENABLE ROW LEVEL SECURITY;

-- --------------------------
-- Functions for stock adjustments
-- --------------------------
CREATE OR REPLACE FUNCTION public.apply_quantity_delta(_table TEXT, _id UUID, _delta NUMERIC)
RETURNS VOID AS $$
BEGIN
  EXECUTE format('UPDATE %s SET quantity = GREATEST(0, COALESCE(quantity,0) + $2), updated_at = NOW() WHERE id = $1', _table)
    USING _id, _delta;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.apply_quantity_set(_table TEXT, _id UUID, _value NUMERIC)
RETURNS VOID AS $$
BEGIN
  EXECUTE format('UPDATE %s SET quantity = $2, updated_at = NOW() WHERE id = $1', _table)
    USING _id, _value;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.paints_apply_writeoff() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.paints', NEW.paint_id, -NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_paints_writeoff_apply ON public.paints_writeoffs;
CREATE TRIGGER trg_paints_writeoff_apply
  AFTER INSERT ON public.paints_writeoffs
  FOR EACH ROW EXECUTE FUNCTION public.paints_apply_writeoff();

CREATE OR REPLACE FUNCTION public.paints_apply_inventory() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_set('public.paints', NEW.paint_id, NEW.counted_qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_paints_inventory_apply ON public.paints_inventories;
CREATE TRIGGER trg_paints_inventory_apply
  AFTER INSERT ON public.paints_inventories
  FOR EACH ROW EXECUTE FUNCTION public.paints_apply_inventory();

CREATE OR REPLACE FUNCTION public.paints_apply_arrival() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.paints', NEW.paint_id, NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_paints_arrival_apply ON public.paints_arrivals;
CREATE TRIGGER trg_paints_arrival_apply
  AFTER INSERT ON public.paints_arrivals
  FOR EACH ROW EXECUTE FUNCTION public.paints_apply_arrival();

CREATE OR REPLACE FUNCTION public.materials_apply_writeoff() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.materials', NEW.material_id, -NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_materials_writeoff_apply ON public.materials_writeoffs;
CREATE TRIGGER trg_materials_writeoff_apply
  AFTER INSERT ON public.materials_writeoffs
  FOR EACH ROW EXECUTE FUNCTION public.materials_apply_writeoff();

CREATE OR REPLACE FUNCTION public.materials_apply_inventory() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_set('public.materials', NEW.material_id, NEW.counted_qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_materials_inventory_apply ON public.materials_inventories;
CREATE TRIGGER trg_materials_inventory_apply
  AFTER INSERT ON public.materials_inventories
  FOR EACH ROW EXECUTE FUNCTION public.materials_apply_inventory();

CREATE OR REPLACE FUNCTION public.materials_apply_arrival() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.materials', NEW.material_id, NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_materials_arrival_apply ON public.materials_arrivals;
CREATE TRIGGER trg_materials_arrival_apply
  AFTER INSERT ON public.materials_arrivals
  FOR EACH ROW EXECUTE FUNCTION public.materials_apply_arrival();

CREATE OR REPLACE FUNCTION public.papers_apply_writeoff() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.papers', NEW.paper_id, -NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_papers_writeoff_apply ON public.papers_writeoffs;
CREATE TRIGGER trg_papers_writeoff_apply
  AFTER INSERT ON public.papers_writeoffs
  FOR EACH ROW EXECUTE FUNCTION public.papers_apply_writeoff();

CREATE OR REPLACE FUNCTION public.papers_apply_inventory() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_set('public.papers', NEW.paper_id, NEW.counted_qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_papers_inventory_apply ON public.papers_inventories;
CREATE TRIGGER trg_papers_inventory_apply
  AFTER INSERT ON public.papers_inventories
  FOR EACH ROW EXECUTE FUNCTION public.papers_apply_inventory();

CREATE OR REPLACE FUNCTION public.papers_apply_arrival() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.papers', NEW.paper_id, NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_papers_arrival_apply ON public.papers_arrivals;
CREATE TRIGGER trg_papers_arrival_apply
  AFTER INSERT ON public.papers_arrivals
  FOR EACH ROW EXECUTE FUNCTION public.papers_apply_arrival();

CREATE OR REPLACE FUNCTION public.stationery_apply_writeoff() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.stationery', NEW.item_id, -NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_stationery_writeoff_apply ON public.stationery_writeoffs;
CREATE TRIGGER trg_stationery_writeoff_apply
  AFTER INSERT ON public.stationery_writeoffs
  FOR EACH ROW EXECUTE FUNCTION public.stationery_apply_writeoff();

CREATE OR REPLACE FUNCTION public.stationery_apply_inventory() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_set('public.stationery', NEW.item_id, NEW.counted_qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_stationery_inventory_apply ON public.stationery_inventories;
CREATE TRIGGER trg_stationery_inventory_apply
  AFTER INSERT ON public.stationery_inventories
  FOR EACH ROW EXECUTE FUNCTION public.stationery_apply_inventory();

CREATE OR REPLACE FUNCTION public.stationery_apply_arrival() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.stationery', NEW.item_id, NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_stationery_arrival_apply ON public.stationery_arrivals;
CREATE TRIGGER trg_stationery_arrival_apply
  AFTER INSERT ON public.stationery_arrivals
  FOR EACH ROW EXECUTE FUNCTION public.stationery_apply_arrival();

CREATE OR REPLACE FUNCTION public.wh_stationery_apply_writeoff() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.warehouse_stationery', NEW.item_id, -NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_wh_stationery_writeoff_apply ON public.warehouse_stationery_writeoffs;
CREATE TRIGGER trg_wh_stationery_writeoff_apply
  AFTER INSERT ON public.warehouse_stationery_writeoffs
  FOR EACH ROW EXECUTE FUNCTION public.wh_stationery_apply_writeoff();

CREATE OR REPLACE FUNCTION public.wh_stationery_apply_inventory() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_set('public.warehouse_stationery', NEW.item_id, NEW.factual);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_wh_stationery_inventory_apply ON public.warehouse_stationery_inventories;
CREATE TRIGGER trg_wh_stationery_inventory_apply
  AFTER INSERT ON public.warehouse_stationery_inventories
  FOR EACH ROW EXECUTE FUNCTION public.wh_stationery_apply_inventory();

CREATE OR REPLACE FUNCTION public.wh_stationery_apply_arrival() RETURNS trigger AS $$
BEGIN
  PERFORM public.apply_quantity_delta('public.warehouse_stationery', NEW.item_id, NEW.qty);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_wh_stationery_arrival_apply ON public.warehouse_stationery_arrivals;
CREATE TRIGGER trg_wh_stationery_arrival_apply
  AFTER INSERT ON public.warehouse_stationery_arrivals
  FOR EACH ROW EXECUTE FUNCTION public.wh_stationery_apply_arrival();

-- --------------------------
-- Views for stock levels
-- --------------------------
CREATE OR REPLACE VIEW public.v_paints AS
SELECT p.*,
  CASE
    WHEN p.quantity <= p.critical_threshold THEN 'очень низкий'
    WHEN p.quantity <= p.low_threshold THEN 'низкий'
    ELSE 'норма'
  END AS stock_status
FROM public.paints p;

CREATE OR REPLACE VIEW public.v_materials AS
SELECT m.*,
  CASE
    WHEN m.quantity <= m.critical_threshold THEN 'очень низкий'
    WHEN m.quantity <= m.low_threshold THEN 'низкий'
    ELSE 'норма'
  END AS stock_status
FROM public.materials m;

CREATE OR REPLACE VIEW public.v_papers AS
SELECT p.*,
  CASE
    WHEN p.quantity <= p.critical_threshold THEN 'очень низкий'
    WHEN p.quantity <= p.low_threshold THEN 'низкий'
    ELSE 'норма'
  END AS stock_status
FROM public.papers p;

CREATE OR REPLACE VIEW public.v_stationery AS
SELECT s.*,
  CASE
    WHEN s.quantity <= s.critical_threshold THEN 'очень низкий'
    WHEN s.quantity <= s.low_threshold THEN 'низкий'
    ELSE 'норма'
  END AS stock_status
FROM public.stationery s;

GRANT SELECT ON public.v_paints, public.v_materials, public.v_papers, public.v_stationery TO authenticated;

-- --------------------------
-- RLS for warehouse tables
-- --------------------------
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT schemaname, tablename, policyname
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename IN (
         'paints','paints_writeoffs','paints_inventories','paints_arrivals',
         'materials','materials_writeoffs','materials_inventories','materials_arrivals',
         'papers','papers_writeoffs','papers_inventories','papers_arrivals',
         'stationery','stationery_writeoffs','stationery_inventories','stationery_arrivals',
         'warehouse_stationery','warehouse_stationery_writeoffs','warehouse_stationery_inventories','warehouse_stationery_arrivals',
         'warehouse_categories','warehouse_category_items','warehouse_category_writeoffs','warehouse_category_inventories',
         'suppliers','forms_series'
       )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', rec.policyname, rec.tablename);
  END LOOP;
END;
$$;

-- Simple policy helpers (all authenticated users can read/write)
CREATE POLICY paints_rw_auth ON public.paints
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY paints_writeoffs_rw_auth ON public.paints_writeoffs
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY paints_inventories_rw_auth ON public.paints_inventories
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY paints_arrivals_rw_auth ON public.paints_arrivals
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY materials_rw_auth ON public.materials
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY materials_writeoffs_rw_auth ON public.materials_writeoffs
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY materials_inventories_rw_auth ON public.materials_inventories
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY materials_arrivals_rw_auth ON public.materials_arrivals
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY papers_rw_auth ON public.papers
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY papers_writeoffs_rw_auth ON public.papers_writeoffs
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY papers_inventories_rw_auth ON public.papers_inventories
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY papers_arrivals_rw_auth ON public.papers_arrivals
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY stationery_rw_auth ON public.stationery
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY stationery_writeoffs_rw_auth ON public.stationery_writeoffs
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY stationery_inventories_rw_auth ON public.stationery_inventories
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY stationery_arrivals_rw_auth ON public.stationery_arrivals
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY wh_stationery_rw_auth ON public.warehouse_stationery
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY wh_stationery_writeoffs_rw_auth ON public.warehouse_stationery_writeoffs
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY wh_stationery_inventories_rw_auth ON public.warehouse_stationery_inventories
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY wh_stationery_arrivals_rw_auth ON public.warehouse_stationery_arrivals
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY wc_rw_auth ON public.warehouse_categories
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY wci_rw_auth ON public.warehouse_category_items
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY wcw_rw_auth ON public.warehouse_category_writeoffs
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY wcinv_rw_auth ON public.warehouse_category_inventories
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY suppliers_rw_auth ON public.suppliers
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY forms_series_rw_auth ON public.forms_series
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

-- --------------------------
-- Seed warehouse categories
-- --------------------------
DELETE FROM public.warehouse_categories
 WHERE code IN ('papers','stationery','paints');

INSERT INTO public.warehouse_categories (code, title, has_subtables) VALUES
  ('п-пакет', 'П-пакет', FALSE),
  ('v-пакет', 'V-пакет', FALSE),
  ('листы',   'Листы',   FALSE),
  ('маффин',  'Маффин',  FALSE),
  ('тюльпан', 'Тюльпан', FALSE)
ON CONFLICT (code) DO NOTHING;

-- --------------------------
-- Realtime configuration
-- --------------------------
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'public.paints',
      'public.paints_writeoffs',
      'public.paints_inventories',
      'public.paints_arrivals',
      'public.materials',
      'public.materials_writeoffs',
      'public.materials_inventories',
      'public.materials_arrivals',
      'public.papers',
      'public.papers_writeoffs',
      'public.papers_inventories',
      'public.papers_arrivals',
      'public.stationery',
      'public.stationery_writeoffs',
      'public.stationery_inventories',
      'public.stationery_arrivals',
      'public.warehouse_stationery',
      'public.warehouse_stationery_writeoffs',
      'public.warehouse_stationery_inventories',
      'public.warehouse_stationery_arrivals',
      'public.warehouse_categories',
      'public.warehouse_category_items',
      'public.warehouse_category_writeoffs',
      'public.warehouse_category_inventories'
    ])
  LOOP
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %s', tbl);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END LOOP;
END;
$$;

-- --------------------------
-- Ensure by_name columns exist for legacy tables
-- --------------------------
ALTER TABLE IF EXISTS public.arrivals                            ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.paints_arrivals                     ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.materials_arrivals                  ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.papers_arrivals                     ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.stationery_arrivals                 ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.warehouse_stationery_arrivals       ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.paints_writeoffs                    ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.materials_writeoffs                 ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.papers_writeoffs                    ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.stationery_writeoffs                ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.warehouse_stationery_writeoffs      ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.paints_inventories                  ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.materials_inventories               ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.papers_inventories                  ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.stationery_inventories              ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.warehouse_stationery_inventories    ADD COLUMN IF NOT EXISTS by_name TEXT;
ALTER TABLE IF EXISTS public.analytics                           ADD COLUMN IF NOT EXISTS by_name TEXT;

-- --------------------------
-- RPC helper for arrivals
-- --------------------------
CREATE OR REPLACE FUNCTION public.arrival_add(
  _type TEXT,
  _item UUID,
  _qty NUMERIC,
  _note TEXT DEFAULT NULL,
  _by_name TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF _type = 'paint' THEN
    INSERT INTO public.paints_arrivals(paint_id, qty, note, created_by, by_name)
    VALUES (_item, _qty, _note, auth.uid(), _by_name);
  ELSIF _type = 'material' THEN
    INSERT INTO public.materials_arrivals(material_id, qty, note, created_by, by_name)
    VALUES (_item, _qty, _note, auth.uid(), _by_name);
  ELSIF _type = 'paper' THEN
    INSERT INTO public.papers_arrivals(paper_id, qty, note, created_by, by_name)
    VALUES (_item, _qty, _note, auth.uid(), _by_name);
  ELSIF _type = 'stationery' THEN
    INSERT INTO public.stationery_arrivals(item_id, qty, note, created_by, by_name)
    VALUES (_item, _qty, _note, auth.uid(), _by_name);
  ELSIF _type = 'warehouse_stationery' THEN
    INSERT INTO public.warehouse_stationery_arrivals(item_id, qty, note, created_by, by_name)
    VALUES (_item, _qty, _note, auth.uid(), _by_name);
  END IF;
END;
$$;

-- ============================================================
-- End of script
-- ============================================================
