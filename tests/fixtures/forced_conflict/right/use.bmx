SuperStrict

Import "../shared.bmx"

Function ForcedConflictRightValue:Int()
	Local value:TForcedConflictValue = New TForcedConflictValue
	value.value = 42
	Local box:TForcedConflictBox<TForcedConflictValue> = New TForcedConflictBox<TForcedConflictValue>
	box.Set(value)
	Return box.Get().value
End Function
