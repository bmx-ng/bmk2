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
Function AppleDeploymentCacheSuffix:String(platform:String, deploymentTarget:String)
	If Not deploymentTarget Then Return ""
	Local token:String = deploymentTarget.Replace(".", "_")
	Select platform
		Case "ios"
			Return ".ios" + token
	End Select
	Return ""
End Function

Function IOSNativeCacheSuffix:String(platform:String, cpu:String, configuredSDK:String, environmentSDK:String, deploymentTarget:String = "")
	If platform <> "ios" Then Return ""
	Local suffix:String
	If IOSConfiguredSDK(cpu, configuredSDK, environmentSDK) = "iphonesimulator" Then
		suffix = ".simulator"
	Else
		suffix = ".device"
	End If
	Return suffix + AppleDeploymentCacheSuffix(platform, deploymentTarget)
End Function

Function AppleDeploymentVersionValid:Int(version:String)
	If Not version Then Return False
	Local parts:String[] = version.Split(".")
	For Local part:String = EachIn parts
		If Not part Then Return False
		For Local index:Int = 0 Until part.length
			If part[index] < Asc("0") Or part[index] > Asc("9") Then Return False
		Next
	Next
	Return True
End Function

Function CompareAppleDeploymentVersions:Int(left:String, right:String)
	Local leftParts:String[] = left.Split(".")
	Local rightParts:String[] = right.Split(".")
	For Local index:Int = 0 Until Max(leftParts.length, rightParts.length)
		Local leftValue:Int
		Local rightValue:Int
		If index < leftParts.length Then leftValue = leftParts[index].ToInt()
		If index < rightParts.length Then rightValue = rightParts[index].ToInt()
		If leftValue < rightValue Then Return -1
		If leftValue > rightValue Then Return 1
	Next
	Return 0
End Function

Function AppleDeploymentTarget:String(platformName:String, configured:String, environmentValue:String, minimum:String, maximum:String, prefix:String = "")
	Local target:String = configured.Trim()
	If Not target Then target = environmentValue.Trim()
	If prefix And target.ToLower().StartsWith(prefix.ToLower()) Then target = target[prefix.length..]
	If Not target Then target = minimum
	If Not AppleDeploymentVersionValid(target) Then
		Throw "Invalid " + platformName + " deployment target '" + target + "'; expected a numeric version such as " + minimum
	End If
	If minimum And CompareAppleDeploymentVersions(target, minimum) < 0 Then
		Throw platformName + " deployment target " + target + " is not supported by the selected SDK; minimum is " + minimum
	End If
	If maximum And CompareAppleDeploymentVersions(target, maximum) > 0 Then
		Throw platformName + " deployment target " + target + " is not supported by the selected SDK; maximum is " + maximum
	End If
	Return target
End Function

Function IOSDeploymentTarget:String(configured:String, environmentValue:String = "", minimum:String = "", maximum:String = "")
	Return AppleDeploymentTarget("iOS", configured, environmentValue, minimum, maximum, "ios-")
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
