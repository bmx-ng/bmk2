SuperStrict

Function IOSConfiguredSDK:String(cpu:String, configured:String, environmentValue:String = "")
	Local sdk:String = configured.Trim().ToLower()
	If Not sdk Then sdk = environmentValue.Trim().ToLower()
	If sdk = "simulator" Or sdk = "sim" Then sdk = "iphonesimulator"
	If sdk = "device" Or sdk = "iphone" Then sdk = "iphoneos"
	If Not sdk Or sdk = "auto" Then
		If cpu = "x86" Or cpu = "x64" Then
			Return "iphonesimulator"
		End If
		Return "iphoneos"
	End If
	If sdk <> "iphoneos" And sdk <> "iphonesimulator" Then
		Throw "Invalid iOS SDK '" + sdk + "'; expected iphoneos or iphonesimulator"
	End If
	Return sdk
End Function

Function IOSArchitecture:String(cpu:String)
	Select cpu
		Case "x64"
			Return "x86_64"
		Case "arm64"
			Return "arm64"
	End Select
	Throw "Unsupported architecture '" + cpu + "' for current iOS tooling; use arm64, or x64 for an Intel simulator"
End Function

' bcc2 discovers BlitzMax interfaces using the traditional platform/CPU name,
' so that identity must remain stable. Native iOS objects and archives need an
' additional SDK discriminator because arm64 is valid for both destinations.
Function IOSNativeCacheSuffix:String(platform:String, cpu:String, configuredSDK:String, environmentSDK:String)
	If platform <> "ios" Then Return ""
	If IOSConfiguredSDK(cpu, configuredSDK, environmentSDK) = "iphonesimulator" Then Return ".simulator"
	Return ".device"
End Function

Function IOSDeploymentTarget:String(configured:String, environmentValue:String = "", fallback:String = "13.0")
	Local target:String = configured.Trim()
	If Not target Then target = environmentValue.Trim()
	If target.StartsWith("ios-") Then target = target[4..]
	If Not target Then target = fallback
	Return target
End Function

Function IOSTargetTriple:String(cpu:String, sdk:String, deploymentTarget:String)
	Local triple:String = IOSArchitecture(cpu) + "-apple-ios" + deploymentTarget
	If sdk = "iphonesimulator" Then triple :+ "-simulator"
	Return triple
End Function

Function IOSOrientationValues:String(orientation:String)
	Select orientation.Trim().ToLower()
		Case "portrait"
			Return "<string>UIInterfaceOrientationPortrait</string>"
		Case "all"
			Return "<string>UIInterfaceOrientationPortrait</string>~n~t~t<string>UIInterfaceOrientationPortraitUpsideDown</string>~n~t~t<string>UIInterfaceOrientationLandscapeLeft</string>~n~t~t<string>UIInterfaceOrientationLandscapeRight</string>"
		Default
			Return "<string>UIInterfaceOrientationLandscapeLeft</string>~n~t~t<string>UIInterfaceOrientationLandscapeRight</string>"
	End Select
End Function
