@echo off
:: Obtener fecha y hora actuales
for /f "tokens=2 delims==" %%A in ('wmic os get localdatetime /value') do set datetime=%%A

:: Separar componentes de fecha y hora
set year=%datetime:~0,4%
set month=%datetime:~4,2%
set day=%datetime:~6,2%
set hour=%datetime:~8,2%
set minute=%datetime:~10,2%
set second=%datetime:~12,2%

:: Concatenar todo como un número
set number=%year%%month%%day%%hour%%minute%%second%

rem :: Mostrar el resultado
rem echo Fecha y hora como número: %number%
rem pause

:: EJECUTAR SCRIPT DE COPIA DE SEGURIDAD
SET DHORA=%TIME%
sqlcmd -S . -E -Q "BACKUP DATABASE Administrativo TO DISK='E:\RESPALDOS\SRVABA\Administrativo_%number%.bak'"
"C:\Program Files\7-Zip\7z.exe" a -sdel -mx=9 -t7z E:\RESPALDOS\SRVABA\Administrativo_%number%.7z E:\RESPALDOS\SRVABA\Administrativo_%number%.bak
sqlcmd -S . -E -Q "BACKUP DATABASE Auditoria TO DISK='E:\RESPALDOS\SRVABA\Auditoria_%number%.bak'"
"C:\Program Files\7-Zip\7z.exe" a -sdel -mx=9 -t7z E:\RESPALDOS\SRVABA\Auditoria_%number%.7z E:\RESPALDOS\SRVABA\Auditoria_%number%.bak
sqlcmd -S . -E -Q "BACKUP DATABASE Contabilidad TO DISK='E:\RESPALDOS\SRVABA\Contabilidad_%number%.bak'"
"C:\Program Files\7-Zip\7z.exe" a -sdel -mx=9 -t7z E:\RESPALDOS\SRVABA\Contabilidad_%number%.7z E:\RESPALDOS\SRVABA\Contabilidad_%number%.bak
sqlcmd -S . -E -Q "BACKUP DATABASE dblocalsiesa TO DISK='E:\RESPALDOS\SRVABA\dblocalsiesa_%number%.bak'"
"C:\Program Files\7-Zip\7z.exe" a -sdel -mx=9 -t7z E:\RESPALDOS\SRVABA\dblocalsiesa_%number%.7z E:\RESPALDOS\SRVABA\dblocalsiesa_%number%.bak
REM PAUSE
TIMEOUT /T 5 /NOBREAK
EXIT