SuperStrict

Incbin "left.dat"

Function LeftNestedValue:Long()
	If IncbinLen("left.dat") <= 0 Then RuntimeError "left nested Incbin registration failed"
	Return 20
End Function
