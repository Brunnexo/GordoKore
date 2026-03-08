CLS
@ECHO OFF

ECHO #####################################################
ECHO ##                                                 ##
ECHO ##                 Gordao Programas                ##
ECHO ##                JSON para Storable               ##
ECHO ##      Desenvolvido por: Bruno Costa - 2026       ##
ECHO ##                                                 ##
ECHO #####################################################
ECHO.

COLOR 0E
ECHO Certifique-se de que o arquivo strings.json esteja presente na mesma pasta desse script
ECHO.
PAUSE
COLOR 07
ECHO Convertendo...
perl parse.pl

IF %ERRORLEVEL% NEQ 0 (
	CLS
	COLOR 0C
	ECHO ERRO: Falha ao executar o script Perl!
	ECHO.
	ECHO Certifique-se de que Perl esteja instalado e que strings.json exista nesta pasta.
	PAUSE
	EXIT /B 1
)

COLOR 20
ECHO Conversao concluida com sucesso!
PAUSE