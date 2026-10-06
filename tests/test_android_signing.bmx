SuperStrict

Framework BRL.StandardIO

Include "../bmk_android_signing.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Check(AndroidPreferredSigningValue(" environment ", "application", "custom") = "environment", "environment overrides application and custom signing values")
Check(AndroidPreferredSigningValue("", " application ", "custom") = "application", "application signing values override custom defaults")
Check(AndroidPreferredSigningValue("", "", " custom ") = "custom", "custom signing values provide the fallback")
Check(AndroidPreferredSigningValue("", "", "") = "", "unset signing values remain unset")

Print "bmk Android signing tests passed"
