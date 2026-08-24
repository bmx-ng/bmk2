SuperStrict

Framework BRL.StandardIO

'@bmk addccopt bmk_pragma -DBMK_PRAGMA_ACTIVE

Function PragmaResult:String()
	'@bmk addccopt bmk_nested_pragma -DBMK_NESTED_PRAGMA_ACTIVE
	Return "pragma-ok"
End Function

Local embeddedPragmaText:String = "'@bmk addccopt embedded_pragma -DBMK_EMBEDDED_PRAGMA_MUST_NOT_RUN"
Rem
'@bmk addccopt rem_pragma -DBMK_REM_PRAGMA_MUST_NOT_RUN
End Rem

Print PragmaResult()
