-- Supabase local seed file
-- Add custom SQL inserts/seeds here for local development if needed.

-- Cupom promocional inaugural CASTANHAL (R$ 5,00 de desconto fixo)
INSERT INTO public.coupons (code, discount, discount_type, is_active, max_uses)
VALUES ('CASTANHAL', 5.00, 'fixed', true, 10000)
ON CONFLICT (code) DO NOTHING;

-- Anúncio oficial de lançamento da campanha Preço Blindado
INSERT INTO public.announcements (title, description, is_active)
VALUES (
  'Baixe o Uppi hoje!', 
  'O único app da cidade com Preço Blindado (chova ou faça sol, você paga o que deu na tela). Baixe agora e a sua primeira viagem já começa com R$ 5,00 grátis na carteira usando o código CASTANHAL.', 
  true
)
ON CONFLICT DO NOTHING;

-- Estado inicial do clima (seco por padrão)
INSERT INTO public.app_settings (key, value)
VALUES ('is_raining', 'false')
ON CONFLICT (key) DO NOTHING;


-- ==============================================================================
-- 🧪 SEEDS DE HOMOLOGAÇÃO / STAGING (UPPI BRASIL)
-- ==============================================================================

-- 1. Inserir perfis de teste (Passageiros e Motoristas)
INSERT INTO public.profiles (id, role, full_name, phone_number, email, wallet_balance, status)
VALUES 
  ('test_rider_1', 'rider', 'Alice Silva (Teste)', '+5591999999991', 'alice@uppi.com', 50.00, 'active'),
  ('test_rider_2', 'rider', 'Bruno Santos (Teste)', '+5591999999992', 'bruno@uppi.com', 10.00, 'active'),
  ('test_driver_1', 'driver', 'Carlos Souza (Piloto)', '+5591999999993', 'carlos@uppi.com', 0.00, 'active'),
  ('test_driver_2', 'driver', 'Daniela Lima (Piloto)', '+5591999999994', 'daniela@uppi.com', 120.00, 'active')
ON CONFLICT (id) DO NOTHING;

-- 2. Atualizar detalhes do veículo dos motoristas
UPDATE public.profiles 
SET vehicle_details = '{"plate": "AAA-1234", "color": "Preto", "model": "Toyota Corolla", "category": "Regular"}'::jsonb
WHERE id = 'test_driver_1';

UPDATE public.profiles 
SET vehicle_details = '{"plate": "BBB-5678", "color": "Branco", "model": "Honda Civic", "category": "Regular"}'::jsonb
WHERE id = 'test_driver_2';

-- 3. Inserir localizações em tempo real dos motoristas (Castanhal - Pará)
INSERT INTO public.driver_locations (driver_id, lat, lng, heading, vehicle_type, updated_at)
VALUES
  ('test_driver_1', -1.296587, -47.925488, 90.0, 'carro', now()),
  ('test_driver_2', -1.298124, -47.921312, 180.0, 'carro', now())
ON CONFLICT (driver_id) DO NOTHING;

-- 4. Inserir histórico de corridas simulado para alimentar os gráficos do Admin Panel
INSERT INTO public.rides (id, rider_id, driver_id, status, pickup_address, pickup_location, dropoff_address, dropoff_location, fare, platform_fee, distance_meters, duration_seconds, created_at)
VALUES
  ('a1111111-1111-1111-1111-111111111111', 'test_rider_1', 'test_driver_1', 'completed', 'Praça da Matriz, Castanhal - PA', ST_SetSRID(ST_MakePoint(-47.925488, -1.296587), 4326)::geography, 'Castanhal Shopping, Castanhal - PA', ST_SetSRID(ST_MakePoint(-47.921312, -1.298124), 4326)::geography, 15.00, 2.25, 2300, 360, now() - interval '2 hours'),
  ('a2222222-2222-2222-2222-222222222222', 'test_rider_2', 'test_driver_2', 'completed', 'UFPA Castanhal, Castanhal - PA', ST_SetSRID(ST_MakePoint(-47.931221, -1.301124), 4326)::geography, 'Terminal Rodoviário, Castanhal - PA', ST_SetSRID(ST_MakePoint(-47.923122, -1.294125), 4326)::geography, 12.00, 1.80, 1900, 280, now() - interval '1 day'),
  ('a3333333-3333-3333-3333-333333333333', 'test_rider_1', 'test_driver_2', 'completed', 'Supermercado Líder, Castanhal - PA', ST_SetSRID(ST_MakePoint(-47.924211, -1.295121), 4326)::geography, 'Hospital Municipal, Castanhal - PA', ST_SetSRID(ST_MakePoint(-47.919812, -1.299120), 4326)::geography, 18.00, 2.70, 3100, 480, now() - interval '2 days')
ON CONFLICT (id) DO NOTHING;

