SuperStrict

Framework BRL.StandardIO

Type TVariantBox<T>
	Field value:T

	Method Get:T()
		Return value
	End Method
End Type

Local box:TVariantBox<String> = New TVariantBox<String>
box.value = "variant"
If box.Get() <> "variant" Then RuntimeError "generic build variant"
