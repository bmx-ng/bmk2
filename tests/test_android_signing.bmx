SuperStrict

Framework BRL.StandardIO

Include "../bmk_android_signing.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local settings:TMap = New TMap
settings.Insert("app.package", "org.example.shared")
settings.Insert("android.application.id", "org.example.android")
Check(AndroidApplicationId(settings) = "org.example.android", "Android application identifier overrides the shared package")
settings.Insert("android.application.id", "")
Check(AndroidApplicationId(settings) = "org.example.shared", "Android application identifier falls back to the shared package")

Check(AndroidPreferredSigningValue(" environment ", "application", "custom") = "environment", "environment overrides application and custom signing values")
Check(AndroidPreferredSigningValue("", " application ", "custom") = "application", "application signing values override custom defaults")
Check(AndroidPreferredSigningValue("", "", " custom ") = "custom", "custom signing values provide the fallback")
Check(AndroidPreferredSigningValue("", "", "") = "", "unset signing values remain unset")

Print "bmk Android signing tests passed"
