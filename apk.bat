@echo off
echo =========================================
echo   Asistente de Despliegue GPCollector
echo =========================================
echo.

:: Preguntamos los datos de la version
set /p version="1. Que version vas a subir? (ej. v1.5.2): "
set /p notes="2. Que cambios hiciste? (ej. Se corrigio el modo claro): "

echo.
echo [1/4] Compilando la %version% en Flutter...
call flutter build apk

echo.
echo [2/4] Renombrando el archivo a GPCollector_%version%.apk...
:: Movemos y renombramos el archivo generado
move /Y "build\app\outputs\flutter-apk\app-release.apk" "build\app\outputs\flutter-apk\GPCollector_%version%.apk"

echo.
echo [3/4] Enviando la app al servidor Laravel (https://collector.gpmonitoreos.cl)...
curl --ssl-no-revoke -X POST -H "X-API-TOKEN: GPCollector_xyz" -F "apk_file=@build\app\outputs\flutter-apk\GPCollector_%version%.apk" -F "version_number=%version%" -F "release_notes=%notes%" https://collector.gpmonitoreos.cl/api/upload-apk

echo.
echo.
echo [4/4] Proceso terminado! Revisa tu panel web.
pause