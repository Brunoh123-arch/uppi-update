-- Adicionar colunas de segurança e monitoramento de rota na tabela rides
ALTER TABLE public.rides
  ADD COLUMN IF NOT EXISTS route_polyline JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS deviation_alert_sent BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.rides.route_polyline IS 'Polilinha com as coordenadas geográficas planejadas da rota da viagem';
COMMENT ON COLUMN public.rides.deviation_alert_sent IS 'Sinalizador para evitar o envio repetido do alerta de desvio de rota';
