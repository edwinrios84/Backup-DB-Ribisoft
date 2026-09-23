@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ============================================================================
rem SQL Server database backup and compression script
rem ============================================================================
rem Creates a native SQL Server backup for each configured database, verifies
rem the backup, compresses it as a 7z archive, tests the resulting archive, and
rem deletes the uncompressed .bak file only after all validations succeed.
rem
rem Exit codes:
rem   0 = All database backups completed successfully.
rem   1 = One or more database backups failed.
rem   2 = Configuration or prerequisite validation failed.
rem
rem Security context:
rem   sqlcmd uses Windows integrated authentication through the -E option.
rem   The Windows account executing this script must therefore have permission
rem   to back up the configured databases and write to the backup directory.
rem ============================================================================


rem ============================================================================
rem CONFIGURATION VARIABLES
rem ============================================================================

rem SQL_SERVER:
rem SQL Server instance used by sqlcmd.
rem "." means the default SQL Server instance on the local computer.
set "SQL_SERVER=."

rem BACKUP_DIRECTORY:
rem Destination directory for the compressed backup archives and execution logs.
rem Do not include a trailing backslash.
set "BACKUP_DIRECTORY=E:\RESPALDOS\SRVABA"

rem SEVEN_ZIP_EXECUTABLE:
rem Absolute path to the 7-Zip command-line executable.
set "SEVEN_ZIP_EXECUTABLE=C:\Program Files\7-Zip\7z.exe"

rem SQLCMD_EXECUTABLE:
rem sqlcmd executable name or absolute path.
rem Using only the executable name allows Windows to locate it through PATH.
set "SQLCMD_EXECUTABLE=sqlcmd.exe"

rem SQL_LOGIN_TIMEOUT_SECONDS:
rem Maximum number of seconds sqlcmd waits while establishing a connection.
set "SQL_LOGIN_TIMEOUT_SECONDS=60"

rem SQL_QUERY_TIMEOUT_SECONDS:
rem Maximum number of seconds allowed for a SQL command.
rem A value of 0 disables the query timeout, which is useful for large backups.
set "SQL_QUERY_TIMEOUT_SECONDS=0"

rem COMPRESSION_LEVEL:
rem 7-Zip compression level. Valid values range from 0 to 9.
rem Level 9 provides the highest compression but uses more CPU and memory.
set "COMPRESSION_LEVEL=9"


rem ============================================================================
rem RUNTIME VARIABLES
rem ============================================================================

rem SCRIPT_START_TIMESTAMP:
rem Date and time when the script started, formatted as yyyyMMddHHmmss.
rem PowerShell is used because WMIC is deprecated and absent from newer Windows
rem installations. The culture-independent format is safe for filenames.
set "SCRIPT_START_TIMESTAMP="
for /f "usebackq delims=" %%I in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Get-Date -Format 'yyyyMMddHHmmss'"`) do set "SCRIPT_START_TIMESTAMP=%%I"

rem FAILED_BACKUP_COUNT:
rem Number of database backup operations that did not complete successfully.
set /a "FAILED_BACKUP_COUNT=0"

rem LOG_FILE:
rem Full path to the execution log. It is assigned after prerequisites and the
rem destination directory have been validated.
set "LOG_FILE="


rem ============================================================================
rem PREREQUISITE VALIDATION
rem ============================================================================

if not defined SCRIPT_START_TIMESTAMP (
    >&2 echo ERROR: The execution timestamp could not be generated.
    exit /b 2
)

where /q "%SQLCMD_EXECUTABLE%"
if errorlevel 1 (
    >&2 echo ERROR: "%SQLCMD_EXECUTABLE%" was not found in PATH.
    >&2 echo Install Microsoft sqlcmd or assign its absolute path to SQLCMD_EXECUTABLE.
    exit /b 2
)

if not exist "%SEVEN_ZIP_EXECUTABLE%" (
    >&2 echo ERROR: 7-Zip was not found at:
    >&2 echo        "%SEVEN_ZIP_EXECUTABLE%"
    exit /b 2
)

if not exist "%BACKUP_DIRECTORY%\" (
    echo The backup directory does not exist. Creating it...
    md "%BACKUP_DIRECTORY%" 2>nul
    if errorlevel 1 (
        >&2 echo ERROR: The backup directory could not be created:
        >&2 echo        "%BACKUP_DIRECTORY%"
        exit /b 2
    )
)

rem Confirm that the destination is a directory rather than a regular file.
if not exist "%BACKUP_DIRECTORY%\NUL" (
    >&2 echo ERROR: The configured destination is not a directory:
    >&2 echo        "%BACKUP_DIRECTORY%"
    exit /b 2
)

set "LOG_FILE=%BACKUP_DIRECTORY%\Backup_%SCRIPT_START_TIMESTAMP%.log"

rem Test that the current account can create a file in the destination.
(> "%LOG_FILE%" echo SQL Server backup execution log)
if errorlevel 1 (
    >&2 echo ERROR: The log file could not be created:
    >&2 echo        "%LOG_FILE%"
    >&2 echo Verify the destination permissions and available disk space.
    exit /b 2
)


rem ============================================================================
rem BACKUP EXECUTION
rem ============================================================================

call :WriteLog "INFO" "Backup process started."
call :WriteLog "INFO" "SQL Server instance: %SQL_SERVER%"
call :WriteLog "INFO" "Destination directory: %BACKUP_DIRECTORY%"

echo Backing up database Administrativo...
call :BackupDatabase "Administrativo" >> "%LOG_FILE%" 2>&1
if errorlevel 1 set /a "FAILED_BACKUP_COUNT+=1"

echo Backing up database Auditoria...
call :BackupDatabase "Auditoria" >> "%LOG_FILE%" 2>&1
if errorlevel 1 set /a "FAILED_BACKUP_COUNT+=1"

echo Backing up database Contabilidad...
call :BackupDatabase "Contabilidad" >> "%LOG_FILE%" 2>&1
if errorlevel 1 set /a "FAILED_BACKUP_COUNT+=1"

echo Backing up database dblocalsiesa...
call :BackupDatabase "dblocalsiesa" >> "%LOG_FILE%" 2>&1
if errorlevel 1 set /a "FAILED_BACKUP_COUNT+=1"


rem ============================================================================
rem FINAL RESULT
rem ============================================================================

if %FAILED_BACKUP_COUNT% GTR 0 goto :ExecutionFailed

call :WriteLog "INFO" "All database backups completed successfully."

echo.
echo All database backups completed successfully.
echo Log file:
echo "%LOG_FILE%"

endlocal
exit /b 0


:ExecutionFailed
call :WriteLog "ERROR" "%FAILED_BACKUP_COUNT% database backup operation(s) failed."

echo.
>&2 echo ERROR: %FAILED_BACKUP_COUNT% database backup operation(s) failed.
>&2 echo Review the execution log:
>&2 echo "%LOG_FILE%"

endlocal
exit /b 1


rem ============================================================================
rem PROCEDURE: BackupDatabase
rem ============================================================================
rem Purpose:
rem   Creates, verifies, compresses, and validates the backup of one database.
rem
rem Parameter:
rem   %~1 = DATABASE_NAME
rem         Exact name of the SQL Server database to back up.
rem
rem Local variables:
rem   DATABASE_NAME = Database received through the first procedure parameter.
rem   BACKUP_FILE   = Full path to the temporary native SQL backup file.
rem   ARCHIVE_FILE  = Full path to the final compressed 7-Zip archive.
rem
rem Return codes:
rem   0 = Backup and compression completed successfully.
rem   1 = Backup, verification, compression, validation, or cleanup failed.
rem ============================================================================
:BackupDatabase
setlocal

set "DATABASE_NAME=%~1"
set "BACKUP_FILE=%BACKUP_DIRECTORY%\%DATABASE_NAME%_%SCRIPT_START_TIMESTAMP%.bak"
set "ARCHIVE_FILE=%BACKUP_DIRECTORY%\%DATABASE_NAME%_%SCRIPT_START_TIMESTAMP%.7z"

if not defined DATABASE_NAME (
    call :WriteLog "ERROR" "BackupDatabase was called without a database name."
    endlocal
    exit /b 1
)

call :WriteLog "INFO" "Starting database: %DATABASE_NAME%"

rem Refuse to overwrite an existing backup or archive. This protects prior data
rem if the script is accidentally started twice within the same second.
if exist "%BACKUP_FILE%" (
    call :WriteLog "ERROR" "The backup file already exists: %BACKUP_FILE%"
    endlocal
    exit /b 1
)

if exist "%ARCHIVE_FILE%" (
    call :WriteLog "ERROR" "The archive already exists: %ARCHIVE_FILE%"
    endlocal
    exit /b 1
)

rem The -b option makes sqlcmd return an error code when SQL Server reports an
rem error. Without it, a failed BACKUP command may appear successful to Batch.
rem The -r 1 option sends SQL error messages to the standard error stream.
"%SQLCMD_EXECUTABLE%" ^
    -S "%SQL_SERVER%" ^
    -E ^
    -b ^
    -r 1 ^
    -l %SQL_LOGIN_TIMEOUT_SECONDS% ^
    -t %SQL_QUERY_TIMEOUT_SECONDS% ^
    -Q "BACKUP DATABASE [%DATABASE_NAME%] TO DISK = N'%BACKUP_FILE%' WITH COMPRESSION, CHECKSUM, STATS = 10;"

if errorlevel 1 (
    call :WriteLog "ERROR" "SQL Server could not back up database %DATABASE_NAME%."
    endlocal
    exit /b 1
)

if not exist "%BACKUP_FILE%" (
    call :WriteLog "ERROR" "SQL Server reported success, but the .bak file was not found: %BACKUP_FILE%"
    endlocal
    exit /b 1
)

rem RESTORE VERIFYONLY checks whether SQL Server can read the complete backup set.
rem WITH CHECKSUM additionally validates checksums stored during BACKUP.
"%SQLCMD_EXECUTABLE%" ^
    -S "%SQL_SERVER%" ^
    -E ^
    -b ^
    -r 1 ^
    -l %SQL_LOGIN_TIMEOUT_SECONDS% ^
    -t %SQL_QUERY_TIMEOUT_SECONDS% ^
    -Q "RESTORE VERIFYONLY FROM DISK = N'%BACKUP_FILE%' WITH CHECKSUM;"

if errorlevel 1 (
    call :WriteLog "ERROR" "SQL Server verification failed for database %DATABASE_NAME%."
    endlocal
    exit /b 1
)

rem Compress without -sdel. The original .bak must remain available until the
rem new archive has been tested successfully.
"%SEVEN_ZIP_EXECUTABLE%" a ^
    "-mx=%COMPRESSION_LEVEL%" ^
    -t7z ^
    "%ARCHIVE_FILE%" ^
    "%BACKUP_FILE%"

if errorlevel 1 (
    call :WriteLog "ERROR" "7-Zip could not compress the backup of database %DATABASE_NAME%."
    endlocal
    exit /b 1
)

if not exist "%ARCHIVE_FILE%" (
    call :WriteLog "ERROR" "7-Zip reported success, but the archive was not found: %ARCHIVE_FILE%"
    endlocal
    exit /b 1
)

rem Test the archive before deleting the larger native backup file.
"%SEVEN_ZIP_EXECUTABLE%" t "%ARCHIVE_FILE%"

if errorlevel 1 (
    call :WriteLog "ERROR" "Archive validation failed for database %DATABASE_NAME%. The .bak file was preserved."
    endlocal
    exit /b 1
)

del /q "%BACKUP_FILE%"

if exist "%BACKUP_FILE%" (
    call :WriteLog "ERROR" "The validated archive exists, but the temporary .bak file could not be deleted: %BACKUP_FILE%"
    endlocal
    exit /b 1
)

call :WriteLog "INFO" "Database completed successfully: %DATABASE_NAME%"
endlocal
exit /b 0


rem ============================================================================
rem PROCEDURE: WriteLog
rem ============================================================================
rem Purpose:
rem   Appends one timestamped entry to the script execution log.
rem
rem Parameters:
rem   %~1 = LOG_LEVEL
rem         Severity or category of the message, such as INFO or ERROR.
rem   %~2 = LOG_MESSAGE
rem         Human-readable message written to the log.
rem
rem Local variables:
rem   LOG_LEVEL     = Level received through the first procedure parameter.
rem   LOG_MESSAGE   = Message received through the second procedure parameter.
rem   LOG_TIMESTAMP = Current local date and time in sortable ISO-like format.
rem
rem Return code:
rem   0 = Procedure completed.
rem ============================================================================
:WriteLog
setlocal

set "LOG_LEVEL=%~1"
set "LOG_MESSAGE=%~2"
set "LOG_TIMESTAMP="

for /f "usebackq delims=" %%I in (`powershell.exe -NoLogo -NoProfile -NonInteractive -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"`) do set "LOG_TIMESTAMP=%%I"

if not defined LOG_TIMESTAMP set "LOG_TIMESTAMP=Timestamp unavailable"

>> "%LOG_FILE%" echo [%LOG_TIMESTAMP%] [%LOG_LEVEL%] %LOG_MESSAGE%

endlocal
exit /b 0