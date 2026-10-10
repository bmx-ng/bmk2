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
Check(CompareAppleDeploymentVersions("15.0", "15") = 0, "equivalent deployment versions compare equally")
Check(CompareAppleDeploymentVersions("15.1", "15.0.9") > 0, "deployment version components compare numerically")
Check(AppleDeploymentTarget("iOS", "", "", "15.0", "27.0.99", "ios-") = "15.0", "SDK minimum is the default deployment target")
Check(AppleDeploymentTarget("macOS", "13.0", "", "12.0", "27.0.99") = "13.0", "an explicit supported deployment target is retained")
Local rejectedLowTarget:Int
Try
	AppleDeploymentTarget("iOS", "14.0", "", "15.0", "27.0.99", "ios-")
Catch exception:Object
	rejectedLowTarget = True
End Try
Check(rejectedLowTarget, "deployment targets below the SDK minimum are rejected")
Local rejectedHighTarget:Int
Try
	AppleDeploymentTarget("macOS", "28.0", "", "12.0", "27.0.99")
Catch exception:Object
	rejectedHighTarget = True
End Try
Check(rejectedHighTarget, "deployment targets above the SDK maximum are rejected")
Local rejectedMalformedTarget:Int
Try
	AppleDeploymentTarget("iOS", "15.x", "", "15.0", "27.0.99", "ios-")
Catch exception:Object
	rejectedMalformedTarget = True
End Try
Check(rejectedMalformedTarget, "malformed deployment targets are rejected")
Check(IOSTargetTriple("arm64", "iphoneos", "13.0") = "arm64-apple-ios13.0", "device target triple is correct")
Check(IOSTargetTriple("arm64", "iphonesimulator", "13.0") = "arm64-apple-ios13.0-simulator", "Apple-silicon simulator target triple is correct")
Check(IOSTargetTriple("x64", "iphonesimulator", "13.0") = "x86_64-apple-ios13.0-simulator", "Intel simulator target triple is correct")
Check(IOSNativeCacheSuffix("ios", "arm64", "iphoneos", "") = ".device", "device native cache is isolated")
Check(IOSNativeCacheSuffix("ios", "arm64", "iphonesimulator", "") = ".simulator", "simulator native cache is isolated")
Check(IOSNativeCacheSuffix("ios", "arm64", "iphoneos", "", "15.0") = ".device.ios15_0", "iOS deployment targets have separate native caches")
Check(IOSNativeCacheSuffix("macos", "arm64", "", "") = "", "non-iOS cache names are unchanged")
Check(IOSOrientationValues("portrait").Contains("Portrait"), "portrait orientation is supported")
Check(IOSOrientationValues("all").Contains("LandscapeRight"), "all orientations include landscape")

Print "bmk iOS configuration tests passed"
