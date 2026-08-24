SuperStrict

Framework BRL.StandardIO

'@bmk push cc_opts
'@bmk addccopt imported_pragma -DBMK_IMPORTED_PRAGMA_ACTIVE
'@bmk addccopt removed_pragma -DBMK_REMOVED_PRAGMA_MUST_NOT_REACH_IMPORT
'@bmk rmccopt removed_pragma
?Win32
'@bmk addccopt imported_platform -DBMK_IMPORTED_PRAGMA_WIN32
?Not Win32
'@bmk addccopt imported_platform -DBMK_IMPORTED_PRAGMA_NOT_WIN32
?
Import "pragma_import_child.bmx"
'@bmk pop cc_opts

Import "pragma_import_sibling.c"

If ImportedPragmaValue() <> 42 Then Throw "imported pragma failed"
Print "pragma-import-ok"
