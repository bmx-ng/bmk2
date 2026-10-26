SuperStrict

Framework BRL.StandardIO

Incbin "root.dat"
Include "parts/child.bmx"

If IncbinLen("root.dat") <= 0 Then RuntimeError "root Incbin registration failed"
If IncbinLen("child.dat") <= 0 Then RuntimeError "included Incbin registration failed"
If IncbinLen("grandchild.dat") <= 0 Then RuntimeError "nested included Incbin registration failed"
Print "bcc included incbin application ok"
