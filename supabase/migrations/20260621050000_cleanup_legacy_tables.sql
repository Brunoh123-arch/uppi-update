-- Migration: Limpeza de tabelas legadas/mortas (messages, ratings, ride_reviews, sos_signals)
-- Garante que se o banco for reconstruído do zero, estas tabelas obsoletas serão excluídas.

DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.ratings CASCADE;
DROP TABLE IF EXISTS public.ride_reviews CASCADE;
DROP TABLE IF EXISTS public.sos_signals CASCADE;
