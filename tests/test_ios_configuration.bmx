SuperStrict

Framework BRL.StandardIO

Include "../bmk_ios.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Check(IOSConfiguredSDK("arm64", "", "") = "iphoneos", "arm64 defaults to the device SDK")
Check(IOSConfiguredSDK("x64", "", "") = "iphonesimulator", "x64 defaults to the simulator SDK")
Check(IOSConfiguredSDK("arm64", "simulator", "") = "iphonesimulator", "simulator alias selects the simulator SDK")
Check(IOSConfiguredSDK("arm64", "", "device") = "iphoneos", "environment device alias selects the device SDK")
Check(IOSDeploymentTarget(" ios-15.0 ", "") = "15.0", "deployment target normalises an ios- prefix")
Check(IOSTargetTriple("arm64", "iphoneos", "13.0") = "arm64-apple-ios13.0", "device target triple is correct")
Check(IOSTargetTriple("arm64", "iphonesimulator", "13.0") = "arm64-apple-ios13.0-simulator", "Apple-silicon simulator target triple is correct")
Check(IOSTargetTriple("x64", "iphonesimulator", "13.0") = "x86_64-apple-ios13.0-simulator", "Intel simulator target triple is correct")
Check(IOSNativeCacheSuffix("ios", "arm64", "iphoneos", "") = ".device", "device native cache is isolated")
Check(IOSNativeCacheSuffix("ios", "arm64", "iphonesimulator", "") = ".simulator", "simulator native cache is isolated")
Check(IOSNativeCacheSuffix("macos", "arm64", "", "") = "", "non-iOS cache names are unchanged")
Check(IOSOrientationValues("portrait").Contains("Portrait"), "portrait orientation is supported")
Check(IOSOrientationValues("all").Contains("LandscapeRight"), "all orientations include landscape")

Print "bmk iOS configuration tests passed"
