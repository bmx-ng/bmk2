SuperStrict

Incbin "left.dat"

Function LeftNestedValue:Int()
	If IncbinLen("left.dat") <= 0 Then RuntimeError "left nested Incbin registration failed"
	Return 19 + 1
End Function
