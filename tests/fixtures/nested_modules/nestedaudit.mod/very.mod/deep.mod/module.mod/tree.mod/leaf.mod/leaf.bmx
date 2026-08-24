SuperStrict

Module NestedAudit.Very.Deep.Module.Tree.Leaf

Type TMyDeepType
	Method Value:Int()
		Return 6
	End Method
End Type

Function DeepValue:Int()
	Return (New TMyDeepType).Value()
End Function
