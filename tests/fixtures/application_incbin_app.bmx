SuperStrict

Framework BRL.StandardIO

Incbin "application_incbin.dat"

If IncbinLen("application_incbin.dat") <= 0 Then RuntimeError "root Incbin registration failed"
Print "bcc root incbin application ok"
