@REM Dynatrace integration using dbWatch CLI
@REM Per Christopher Undheim, dbWatch Services (C) 2022

@REM ---------------------------------------------------------------------------
@REM  			Push_to_dyna.cmd
@REM ---------------------------------------------------------------------------
@REM This is a script for pushing warnings and alerts from 
@REM dbWatch Enterprise Manager 12 to Dynatrace
@REM For questions and support conserning this script contact: 
@REM dbWatch Services (support@dbwatch.com)
@REM ---------------------------------------------------------------------------


@echo off

REM ---------------------------------------------------------------------------
REM Setting variables 
REM ---------------------------------------------------------------------------

For /f "tokens=1-3 delims=. " %%a in ('date /t') do (set DIR_DATE=%%c%%b%%a)
For /f "tokens=1-3 delims=. " %%a in ('time /t') do (set DIR_TIME=%%a%%b%%c)

call :log "****************************************************"
call :log "* Push to dyna version 0.1 dbWatch (C) 2022 *"
call :log "* designed by Per Christopher Undheim              *"
call :log "****************************************************"

call :clean_variables


set DIR_DATE=%DIR_DATE%_%DIR_TIME%

call :log "Setting variables"


SET me=%~n0
SET parent=%~dp0
set DBW_SERVER=server1
set DBW_CLI_HOME=C:\Program Files\dbWatch\12.8.10\dbw\bin
set DBW_CLI_EXEC=dbw.exe
set OLDPATH=%PATH%
set CURL_EXEC=curl
set CURL_OPTS=-L -X POST 'https://dynatrace-tst02/e/5439528f-c145-4a8e-9de6-04a26b4c8d5d/api/v2/metrics/ingest' -H 'Authorization: Api-Token dt0c01.abc123.abcdefjhij1234567890' -H 'Content-Type: text/plain' 
set PATH=%DBW_CLI_HOME%;%PATH%
set PATH=%DBW_CLI_HOME%;C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\


%DBW_CLI_EXEC% ping -server %DBW_SERVER% > check_con.log
FOR /F "delims=" %%x in ('findstr "OK" check_con.log ') DO (@set PING_ERR=NONE)
IF "%PING_ERR%"=="" (
	call :log "Connection to server failed"
	goto :error_exit
)

IF "%PING_ERR%"=="NONE" (
	call :log "Connection to server OK"
)



%DBW_CLI_EXEC% dbwql -server %DBW_SERVER% -query "instance->i/$i/name{}/$i/task[statusnumber > 0]->t/$t/name{}/$t/status{}/$t/statusnumber{}/$t/details{}" -format dynatrace > alarmlist.log
setlocal enabledelayedexpansion
REM @echo off
set var1=0

for /F "tokens=1-5 delims=;" %%a in (alarmlist.log) do (
	set var2=0
    set array[!var1!][!var2!]=%%a
    set /a var2+=1
    set array[!var1!][!var2!]=%%b
    set /a var2+=1
	set array[!var1!][!var2!]=%%c
    set /a var2+=1
	set array[!var1!][!var2!]=%%d
    set /a var2+=1
	set array[!var1!][!var2!]=%%e
	set tempval=!array[!var1!][!var2!]:'= !
	set array[!var1!][!var2!]=tempval
    set /a var1+=1
)
set /a var1-=1
for /L %%G in (0,1,%var1%) do (
REM Remove echo to actually run curl
echo %CURL_EXEC% %CURL_OPTS% --data-raw '!array[%%G][1]: =.!,dt.entity.host=!array[%%G][0]!,!array[%%G][1]: =.!="!array[%%G][4]:~0,100!" !array[%%G][3]!'
)

goto :clean_exit


exit /b

@REM Additional subroutines are here

:clean_exit
	call :clean_variables
	call :clean_logfiles
	call :log "Clean exit"
	del /Q del.log
	goto :eof
	exit /b

:error_exit
	call :log "Problems detected, not clearing variables and logs when exiting"
	goto :eof
	exit /b

	
:clean_logfiles
	call :log "Remove logfiles"
	call :delfile alarmlist.log
	call :delfile check_con.log
	rd config
	exit /b

:dequote
	for /f "delims=" %%A in ('echo %%%1%%') do set %1=%%~A
	exit /b

:delfile
	del /Q %~1 >> del.log 2>&1
	exit /b


:clean_variables
	call :log "Unsetting variables"
	set PATH=%OLDPATH%
	exit /b


:log
	For /f "tokens=1-3 delims=. " %%a in ('date /t') do (set CUR_DATE=%%c%%b%%a)
	For /f "tokens=1-2 delims=. " %%a in ('time /t') do (set CUR_TIME=%%a:%%b)
	echo %CUR_DATE%_%CUR_TIME%:%~1
	exit /b

	
:eof
	exit /b





















