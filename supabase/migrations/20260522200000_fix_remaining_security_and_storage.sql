-- ============================================================
-- Migration: Fixes restantes da auditoria de segurança
-- 1. Gift cards policy permissiva (qualquer autenticado vê todos)
-- 2. Buckets avatars e documents nunca criados em migration
-- 3. SOS tables divergentes (sos_alerts vs sos_signals)
-- ============================================================

-- ============================================================
-- FIX 1: Restringir SELECT em gift_cards
-- ============================================================
-- Hoje qualquer usuário autenticado pode listar todos os códigos
-- de gift cards não resgatados. Risco: vazamento financeiro.
-- Solução: só o dono (já resgatou) ou admin pode ler.
-- Validação de código novo fica na edge function redeem-gift-card
-- com service_role (bypassa RLS).

DROP POLICY IF EXISTS "Ver gift card por codigo" ON public.gift_cards;
DROP POLICY IF EXISTS "gift_cards_select_owner_or_admin" ON public.gift_cards;

CREATE POLICY "gift_cards_select_owner_or_admin" ON public.gift_cards
  FOR SELECT TO authenticated
  USING (
    redeemed_by = auth.uid()::text
    OR EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ============================================================
-- FIX 2: Criar buckets avatars e documents (com policies)
-- ============================================================
-- O código de upload em upload_datasource.prod.dart usa esses
-- buckets mas eles nunca foram criados em migration. Em produção
-- foram criados manualmente pelo dashboard, mas isso quebra
-- ambientes novos (staging, dev).

-- Bucket de avatars: foto de perfil (PÚBLICO, 1MB, jpeg/png/webp)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  1048576,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Bucket de documents: CNH, vistoria etc (PRIVADO, 5MB, jpeg/png/pdf)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Policies do bucket avatars
-- Estrutura esperada: {user_id}/arquivo.jpg
DROP POLICY IF EXISTS "avatars_owner_all" ON storage.objects;
CREATE POLICY "avatars_owner_all" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;
CREATE POLICY "avatars_public_read" ON storage.objects
  FOR SELECT
  USING (bucket_id = 'avatars');

-- Policies do bucket documents
-- Só dono pode ler/escrever, admin pode ler tudo
DROP POLICY IF EXISTS "documents_owner_rw" ON storage.objects;
CREATE POLICY "documents_owner_rw" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "documents_admin_read" ON storage.objects;
CREATE POLICY "documents_admin_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND EXISTS (SELECT 1 FROM public.admins WHERE id = auth.uid()::text)
  );

-- ============================================================
-- FIX 3: Unificar SOS em sos_alerts com coluna submitted_by
-- ============================================================
-- Hoje send-sos sempre insere em sos_alerts (qualquer tipo de
-- usuário), mas o admin assume que sos_alerts=passageiro e
-- sos_signals=motorista. Resultado: SOS de motorista fica
-- invisível pro admin.
-- Solução: adicionar submitted_by ('rider' ou 'driver') em
-- sos_alerts, migrar dados antigos de sos_signals, e deprecar
-- sos_signals.

-- Adicionar coluna submitted_by
ALTER TABLE public.sos_alerts
  ADD COLUMN IF NOT EXISTS submitted_by TEXT;

-- Migrar dados antigos de sos_signals → sos_alerts (sem duplicar)
-- NOTA: sos_signals usa 'notes' (não 'message') e não tem user_name/user_phone
INSERT INTO public.sos_alerts (id, user_id, ride_id, lat, lng, message, status, created_at, submitted_by)
SELECT
  s.id,
  s.user_id,
  s.ride_id,
  s.lat,
  s.lng,
  COALESCE(s.notes, 'SOS de motorista'),
  COALESCE(s.status, 'active'),
  s.created_at,
  COALESCE(s.submitted_by, 'driver')
FROM public.sos_signals s
WHERE NOT EXISTS (
  SELECT 1 FROM public.sos_alerts a WHERE a.id = s.id
)
ON CONFLICT (id) DO NOTHING;

-- Index para queries por submitted_by
CREATE INDEX IF NOT EXISTS idx_sos_alerts_submitted_by
  ON public.sos_alerts (submitted_by);

-- Marcar sos_signals como deprecated (sem dropar — pode ter integrações antigas)
COMMENT ON TABLE public.sos_signals IS
  'DEPRECATED desde 2026-05-22: usar sos_alerts com coluna submitted_by. Mantida temporariamente para histórico e compatibilidade.';
