SuperStrict

Framework BRL.StandardIO

Include "../bmk_macos_signing.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Check(MacOSPreferredSigningValue(" environment ", "local", "application", "custom") = "environment", "environment overrides all macOS signing values")
Check(MacOSPreferredSigningValue("", " local ", "application", "custom") = "local", "local sidecar overrides tracked and custom macOS signing values")
Check(MacOSPreferredSigningValue("", "", " application ", "custom") = "application", "application settings override custom macOS signing values")
Check(MacOSPreferredSigningValue("", "", "", " custom ") = "custom", "custom macOS signing values provide the fallback")
Check(MacOSPreferredSigningValue("", "", "", "") = "", "unset macOS signing values remain unset")

Print "bmk macOS signing tests passed"
