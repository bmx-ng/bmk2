SuperStrict

Type TForcedConflictValue
	Field value:Int
End Type

Type TForcedConflictBox<T>
	Field value:T

	Method Set(value:T)
		Self.value = value
	End Method

	Method Get:T()
		Return value
	End Method
End Type

Type TForcedConflictOtherBox<T>
	Field value:T

	Method Set(value:T)
		Self.value = value
	End Method

	Method Get:T()
		Return value
	End Method
End Type
