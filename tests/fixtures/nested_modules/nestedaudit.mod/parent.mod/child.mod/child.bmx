SuperStrict

Module NestedAudit.Parent.Child

Import BRL.Blitz
Import "helper.bmx"

Global ChildInitialized:Int = 1

Type TBox<T>
	Field value:T

	Method Read:T()
		Return value
	End Method
End Type

Function ChildValue:Int()
	Return LocalLeafValue() + 2
End Function

Function Words<T>:ICloseableIterator<T>(value:T)
	Yield value
End Function

Function ExcitedWords:ICloseableIterator<String>(value:String)
	Yield From [value + "!"]
End Function

Function Reader:Closure<Int()>()
	Local value:Int = ChildValue()
	Return Function()
		Return value
	End Function
End Function
