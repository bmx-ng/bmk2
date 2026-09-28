SuperStrict
Module ConfigAudit.Choice
Import "child.bmx"
?config_two
Import "two.c"
?Not config_two
Import "one.c"
?
Extern
	Function NativeConfig:Int()
End Extern
Function ConfigValue:Int()
	Return NativeConfig() + ChildConfig()
End Function
