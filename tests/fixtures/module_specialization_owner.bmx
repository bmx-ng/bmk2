SuperStrict

Module Bcc2ManifestTest.Owner

Type TArchiveBox<T>
	Field value:T

	Method Set(input:T)
		value = input
	End Method

	Method Get:T()
		Return value
	End Method
End Type

Global OwnedStrings:TArchiveBox<String> = New TArchiveBox<String>

Function SetOwned(value:String)
	OwnedStrings.Set(value)
End Function

Function GetOwned:String()
	Return OwnedStrings.Get()
End Function
