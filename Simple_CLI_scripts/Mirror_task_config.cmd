@REM Simple scripts for dbWatch CLI
@REM Per Christopher Undheim, dbWatch Services (C) 2020

@REM ---------------------------------------------------------------------------
@REM  			Mirror_task_config.cmd
@REM ---------------------------------------------------------------------------
@REM This is a script for trying to configure the tasks and alerts 
@REM identical on one database instance as another
@REM requires a dbw.conf file locally and some variables set in this script
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
call :log "* Mirror task config version 0.1 dbWatch (C) 2020  *"
call :log "* designed by Per Christopher Undheim              *"
call :log "****************************************************"

call :clean_variables


set DIR_DATE=%DIR_DATE%_%DIR_TIME%

call :log "Setting variables"


SET me=%~n0
SET parent=%~dp0
set DBW_SERVER=server1
set DBW_CLI_HOME=C:\Program Files\dbWatch\12.7.4\dbw\bin
set DBW_CLI_EXEC=dbw.exe
set OLDPATH=%PATH%
set PATH=%DBW_CLI_HOME%;%PATH%
set PATH=%DBW_CLI_HOME%;C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\


set "FROM_INSTANCE=%1"
set "TO_INSTANCE=%2"

call :dequote FROM_INSTANCE
call :dequote TO_INSTANCE

IF ["%FROM_INSTANCE%"]==[] (goto :display_usage)
IF ["%TO_INSTANCE%"]==[] (goto :display_usage)

call :log "From instance set to %FROM_INSTANCE%"
call :log "To instance set to %TO_INSTANCE%"


%DBW_CLI_EXEC% ping -server %DBW_SERVER% > check_con.log
FOR /F "delims=" %%x in ('findstr "OK" check_con.log ') DO (@set PING_ERR=NONE)
IF "%PING_ERR%"=="" (
	call :log "Connection to server failed"
	goto :error_exit
)

IF "%PING_ERR%"=="NONE" (
	call :log "Connection to server OK"
)


%DBW_CLI_EXEC% dbwql -server %DBW_SERVER% -query "instance[name='%FROM_INSTANCE%']/task->t/$t/name{}/$t/parameter->p/$p/name{}/$p/value{}" -format csv > list1.log
%DBW_CLI_EXEC% dbwql -server %DBW_SERVER% -query "instance[name='%TO_INSTANCE%']/task->t/$t/name{}/$t/parameter->p/$p/name{}/$p/value{}" -format csv > list2.log

sort list1.log > list1s.log
sort list2.log > list2s.log
call :delfile list1.log 
call :delfile list2.log 


findstr /V /G:list1s.log list2s.log > uninstall.log
for /f "usebackq tokens=*" %%a in (`type uninstall.log`) do (call :log "Task settings to be overwritten on %TO_INSTANCE%: %%a")

findstr /V /G:list2s.log list1s.log > install.log
for /f "usebackq tokens=*" %%a in (`type install.log`) do (call :log "Task settings to be set %TO_INSTANCE%: %%a")



for /f "usebackq tokens=*" %%a in (`type install.log`) do (call :settaskvar "%%a")
@REM for /f "tokens=1-3 delims=," %%a IN ("%TASKSTRING%") do (
@REM echo %%a
@REM echo %%b
@REM echo %%c 
@REM )
@REM for /f "tokens=1-3 delims=," %%a IN ("%TASKSTRING%") do (%DBW_CLI_EXEC% settaskparameter -server %DBW_SERVER% -i '%TO_INSTANCE%' -t '%%a' -tpn '%%b' -tpv '%%c')


goto :clean_exit



exit /b

goto :error_exit



exit /b

@REM Additional subroutines are here



:clean_exit
	call :clean_variables
	call :clean_logfiles
	call :log "Clean exit"
	del /Q del.log
	set PATH=%OLDPATH%
	goto :eof
	exit /b

:error_exit
	call :log "Problems detected, not clearing variables and logs when exiting"
	set PATH=%OLDPATH%
	goto :eof
	exit /b

:display_usage
	call :log "Input variables are wrong"
	call :log "%me% 'FROMHOST' 'TOHOST'"
	call :log "%me% 'My configured host' 'My new host'"
	call :log "Exiting"
	goto :eof
	exit /b
	
:clean_logfiles
	call :log "Remove logfiles"
	call :delfile check_con.log
	call :delfile list1s.log
	call :delfile list2s.log
	call :delfile uninstall.log
	call :delfile install.log
	exit /b

:dequote
	for /f "delims=" %%A in ('echo %%%1%%') do set %1=%%~A
	exit /b

:delfile
	del /Q %~1 >> del.log 2>&1
	exit /b

:settaskvar
	call :log "Setting %~1 for %TO_INSTANCE%"
	for /f "tokens=1-3 delims=," %%a IN ("%~1") do (%DBW_CLI_EXEC% settaskparameter -server %DBW_SERVER% -i '%TO_INSTANCE%' -t '%%a' -tpn '%%b' -tpv '%%c')
	exit /b

:clean_variables
	call :log "Unsetting variables"
	set "WD="
	set "RESTORE_ERR="
	set "SECNUM="
	set "STATUS_FILE="
	set "CR_CNT="
	set PATH=%OLDPATH%
	exit /b


:log
	For /f "tokens=1-3 delims=. " %%a in ('date /t') do (set CUR_DATE=%%c%%b%%a)
	For /f "tokens=1-2 delims=. " %%a in ('time /t') do (set CUR_TIME=%%a:%%b)
	echo %CUR_DATE%_%CUR_TIME%:%~1
	exit /b

	
:eof
	exit /b





















