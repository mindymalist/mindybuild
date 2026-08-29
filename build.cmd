REM @ECHO OFF
SETLOCAL ENABLEEXTENSIONS

CD %~dp0
IF NOT EXIST "bin" (
	MKDIR "bin"
	IF %ERRORLEVEL% NEQ 0 EXIT /B %ERRORLEVEL%
)

SET sourceFiles=^
	src/mindybuild/common.d ^
	src/mindybuild/database.d ^
	src/mindybuild/kapenparse.d ^
	src/mindybuild/configure.d ^
	src/mindybuild/make.d ^
	src/mindybuild/cli.d

IF [%DC%] NEQ [] (
	CALL :use_dc
	EXIT /B %ERRORLEVEL%
)
IF [%DMD%] NEQ [] (
	CALL :use_dmd
	EXIT /B %ERRORLEVEL%
)

WHERE /Q ldc2
IF %ERRORLEVEL% EQU 0 (
	SET DC=ldc2
) ELSE (
	WHERE /Q dmd
	IF %ERRORLEVEL% EQU 0 (
		SET DC=dmd
	) ELSE (
		ECHO "No suitable D compiler found."
		EXIT /B 1
	)
)
CALL :use_dc
EXIT /B %ERRORLEVEL%

REM ============================================================================
:use_dc
SET "_dmd="
IF /I [%DC%] == [dmd]   SET _dmd=1
IF /I [%DC%] == [ldmd2] SET _dmd=1
IF /I [%DC%] == [ldmd]  SET _dmd=1
IF /I [%DC%] == [gdmd]  SET _dmd=1
IF [%_dmd%] EQU 1 (
	SET DMD=%DC%
	CALL :use_dmd
	EXIT /B %ERRORLEVEL%
)

IF /I [%DC%] == [ldc2] (
	CALL :use_ldc
	EXIT /B %ERRORLEVEL%
)

ECHO "Unsupported D compiler `%%DC%%`."
EXIT /B 1

REM ============================================================================
:use_dmd
IF [%DFLAGS%] == [] SET DFLAGS=-O
%DMD% %DFLAGS%   -of"bin/mindybuild" -od"bin" -I"src"    -version="MindybuildCommandLineApp" %sourceFiles%
EXIT /B %ERRORLEVEL%

REM ============================================================================
:use_ldc
IF [%DFLAGS%] == [] SET DFLAGS=-O2
%DC%  %DFLAGS% --of="bin/mindybuild"          -I"src" --d-version="MindybuildCommandLineApp" %sourceFiles%
EXIT /B %ERRORLEVEL%