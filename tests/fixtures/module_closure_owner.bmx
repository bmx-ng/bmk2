SuperStrict

Module Bcc2ManifestTest.ClosureOwner

Function Remember<T>:Closure<T()>(value:T)
	Return Function()
		Return value
	End Function
End Function

Function Apply<T, R>:R(value:T, operation:Closure<R(value:T)>)
	Return operation(value)
End Function

Function MakeAdder:Closure<Int(value:Int)>(amount:Int)
	Return Function(value:Int)
		Return value + amount
	End Function
End Function

Function Invoke:Int(value:Int, operation:Closure<Int(value:Int)>)
	Return operation(value)
End Function

Global OwnedReader:Closure<String()> = Remember<String>("module-owned")

Function ReadOwned:String()
	Return OwnedReader()
End Function
