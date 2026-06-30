@echo off
title Uppi - Configurar Mercado Pago
echo ==============================================
echo      UPPI BRASIL - CONFIGURAR MERCADO PAGO
echo ==============================================
echo.

set /p ACCESS_TOKEN="Digite o Mercado Pago Access Token: "
if "%ACCESS_TOKEN%"=="" (
    echo [ERRO] Access Token e obrigatorio.
    pause
    exit /b
)

set /p PUBLIC_KEY="Digite o Mercado Pago Public Key: "
if "%PUBLIC_KEY%"=="" (
    echo [ERRO] Public Key e obrigatorio.
    pause
    exit /b
)

set /p WEBHOOK_SECRET="Digite o Mercado Pago Webhook Secret (opcional): "

echo.
echo Tentando inserir no banco de dados via Supabase CLI...

(
echo INSERT INTO public.app_settings (key, value) VALUES ('mp_access_token', '%ACCESS_TOKEN%') ON CONFLICT (key) DO UPDATE SET value = '%ACCESS_TOKEN%';
echo INSERT INTO public.app_settings (key, value) VALUES ('mp_public_key', '%PUBLIC_KEY%') ON CONFLICT (key) DO UPDATE SET value = '%PUBLIC_KEY%';
if not "%WEBHOOK_SECRET%"=="" echo INSERT INTO public.app_settings (key, value) VALUES ('mp_webhook_secret', '%WEBHOOK_SECRET%') ON CONFLICT (key) DO UPDATE SET value = '%WEBHOOK_SECRET%';
) > temp_mp.sql

supabase db execute -f temp_mp.sql

if %errorlevel% neq 0 (
    echo.
    echo -------------------------------------------------------------
    echo [INFO] Supabase CLI nao detectado ou erro na execucao direta.
    echo Por favor, execute as queries SQL abaixo no Editor SQL do Supabase:
    echo -------------------------------------------------------------
    echo.
    type temp_mp.sql
    echo.
    echo -------------------------------------------------------------
) else (
    echo.
    echo [SUCESSO] Chaves do Mercado Pago salvas em app_settings no banco!
)

if exist temp_mp.sql del temp_mp.sql
echo.
pause