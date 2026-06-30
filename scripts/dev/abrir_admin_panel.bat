@echo off
:: ============================================================
:: 🚀 Script para abrir o Painel Admin do Uppi no Windows
:: ============================================================

setlocal enabledelayedexpansion

:: Verificar se o flutter está no PATH global, se não, buscar no caminho local detectado
where flutter >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [INFO] 'flutter' nao esta no PATH global. Buscando instalacao local...
    if exist "C:\Users\mcass\Downloads\flutter_windows_3.44.1-stable\flutter\bin" (
        set "PATH=%PATH%;C:\Users\mcass\Downloads\flutter_windows_3.44.1-stable\flutter\bin;C:\Users\mcass\Downloads\flutter_windows_3.44.1-stable\flutter\bin\cache\dart-sdk\bin"
        echo [INFO] Flutter SDK localizado e adicionado ao PATH temporariamente.
    ) else (
        echo [ERRO] O Flutter SDK nao foi encontrado no PATH nem na pasta de Downloads padrao.
        echo Por favor, adicione o Flutter SDK ao seu PATH do sistema.
        pause
        exit /b 1
    )
)

echo ==========================================
echo    UPPI - Abrindo Painel Administrativo
echo ==========================================
echo.

cd /d "%~dp0..\..\apps\admin_panel"

echo [1/2] Instalando dependencias...
call flutter pub get

echo.
echo [2/2] Iniciando Admin Panel na porta 4000...
echo    Acesse: http://localhost:4000
echo.

:: Roda em modo web-server para permitir acesso do browser do usuario de forma leve
call flutter run -d web-server --web-port 4000 --web-hostname 127.0.0.1

pause
