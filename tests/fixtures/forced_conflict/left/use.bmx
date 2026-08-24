SuperStrict

Import "../shared.bmx"

Function ForcedConflictLeftValue:Int()
	Local value:TForcedConflictValue = New TForcedConflictValue
	value.value = 41
	Local box:TForcedConflictBox<TForcedConflictValue> = New TForcedConflictBox<TForcedConflictValue>
	box.Set(value)

	' Give the test a second valid generated implementation whose bytes can be
	' transplanted over the shared specialization without needing a host-specific
	' SHA-256 utility.
	Local other:TForcedConflictOtherBox<TForcedConflictValue> = New TForcedConflictOtherBox<TForcedConflictValue>
	other.Set(value)
	Return box.Get().value + other.Get().value - 41
End Function
