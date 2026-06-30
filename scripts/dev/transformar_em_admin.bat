@echo off
title Uppi - Promover Usuario a Admin
echo ==============================================
echo        UPPI BRASIL - PROMOVER ADMIN
echo ==============================================
echo.

set /p USER_ID="Digite o ID do usuario (UUID) do Supabase: "
if "%USER_ID%"=="" (
    echo [ERRO] ID do usuario e obrigatorio.
    pause
    exit /b
)

set /p ROLE="Digite a role do admin (default: superadmin): "
if "%ROLE%"=="" set ROLE=superadmin

echo.
echo Tentando executar a query no banco de dados local/Supabase CLI...
supabase db execute "INSERT INTO public.admins (id, role) VALUES ('%USER_ID%', '%ROLE%') ON CONFLICT (id) DO UPDATE SET role = '%ROLE%';"

if %errorlevel% neq 0 (
    echo.
    echo -------------------------------------------------------------
    echo [INFO] Supabase CLI nao detectado ou erro na execucao direta.
    echo Por favor, execute a query SQL abaixo no Editor SQL do Supabase:
    echo -------------------------------------------------------------
    echo.
    echo INSERT INTO public.admins (id, role) VALUES ('%USER_ID%', '%ROLE%') ON CONFLICT (id) DO UPDATE SET role = '%ROLE%';
    echo.
    echo -------------------------------------------------------------
) else (
    echo.
    echo [SUCESSO] Usuario %USER_ID% promovido para %ROLE% com sucesso!
)
echo.
pause