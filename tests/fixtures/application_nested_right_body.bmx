SuperStrict

Incbin "right.dat"

Function RightNestedValue:Int()
	If IncbinLen("right.dat") <= 0 Then RuntimeError "right nested Incbin registration failed"
	Return 21 + 1
End Function
