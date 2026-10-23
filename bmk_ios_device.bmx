SuperStrict

Import BRL.StandardIO

Import "bmk_config.bmx"
Import "bmk_pico.bmx"
Import "bmk_ios_device_parse.bmx"

Function IOSConfiguredDevice:String()
	Local selector:String = processor.Option("ios.device", "").Trim()
	If Not selector.length Then selector = getenv_("IOS_DEVICE").Trim()
	Return selector
End Function

Function IOSXcrunCommand:String()
	Return "/usr/bin/xcrun"
End Function

Function IOSDevices:TIOSDeviceInfo[]()
	Local jsonPath:String = processor.TemporaryOutputPath(BlitzMaxPath() + "/tmp/devicectl-devices.json")
	DeleteFile jsonPath
	Local command:String = CQuote(IOSXcrunCommand()) + " devicectl list devices --quiet --json-output " + CQuote(jsonPath)
	Local result:Int = Sys(command)
	If result Or FileType(jsonPath) <> FILETYPE_FILE Then
		DeleteFile jsonPath
		Throw "Unable to list Apple devices with 'xcrun devicectl'. Check that Xcode is selected and CoreDevice is available."
	End If
	Local jsonText:String = LoadText(jsonPath)
	DeleteFile jsonPath
	Local errorMessage:String
	Local devices:TIOSDeviceInfo[] = ParseIOSDevices(jsonText, errorMessage)
	If errorMessage.length Then Throw "Unable to read the Apple device list: " + errorMessage
	Return devices
End Function

Function IOSDeviceDescription:String(device:TIOSDeviceInfo)
	Local result:String = device.name
	If Not result.length Then result = device.udid
	If device.marketingName.length Then result :+ " (" + device.marketingName + ")"
	If device.transportType.length Then result :+ " [" + IOSDeviceTransportLabel(device.transportType) + "]"
	Return result
End Function

Function IOSDeviceTransportLabel:String(transport:String)
	Select transport.ToLower()
		Case "localnetwork"
			Return "Wi-Fi"
		Case "wired"
			Return "USB"
		Case "samemachine"
			Return "local simulator"
	End Select
	Return transport
End Function

Function IOSPhysicalDeviceSummary:String(devices:TIOSDeviceInfo[])
	Local result:String
	For Local device:TIOSDeviceInfo = EachIn devices
		If Not device.IsPhysicalIOS() Then Continue
		If result.length Then result :+ ", "
		result :+ IOSDeviceDescription(device)
		If device.udid.length Then result :+ " " + device.udid
	Next
	If Not result.length Then result = "none"
	Return result
End Function

Function SelectIOSDevice:TIOSDeviceInfo(devices:TIOSDeviceInfo[])
	Local configured:String = IOSConfiguredDevice()
	If configured.length Then
		For Local device:TIOSDeviceInfo = EachIn devices
			If Not IOSDeviceMatches(device, configured) Then Continue
			If Not device.IsPhysicalIOS() Then Throw "Configured Apple device '" + configured + "' is not a physical iOS device."
			If device.pairingState.ToLower() <> "paired" Then Throw "Apple device " + IOSDeviceDescription(device) + " is not paired."
			If device.bootState.ToLower() <> "booted" Then Throw "Apple device " + IOSDeviceDescription(device) + " is not booted."
			If device.developerModeStatus.ToLower() = "disabled" Then Throw "Developer Mode is disabled on " + IOSDeviceDescription(device) + "."
			Return device
		Next
		Throw "Configured Apple device '" + configured + "' is not available. Physical iOS devices: " + IOSPhysicalDeviceSummary(devices)
	End If

	Local selected:TIOSDeviceInfo
	Local available:Int
	For Local device:TIOSDeviceInfo = EachIn devices
		If Not device.IsAvailable() Then Continue
		selected = device
		available :+ 1
	Next
	If available = 1 Then Return selected
	If available > 1 Then
		Throw "Multiple physical iOS devices are available: " + IOSPhysicalDeviceSummary(devices) + ". Set ios.device in bin/custom.bmk or IOS_DEVICE."
	End If
	If devices.length Then Throw "No paired, booted physical iOS device is available. Physical iOS devices: " + IOSPhysicalDeviceSummary(devices)
	Throw "No Apple device is available. Connect and pair an iPhone or iPad, enable Developer Mode, and confirm it appears in Xcode."
End Function

Function SelectedIOSDevice:TIOSDeviceInfo()
	Return SelectIOSDevice(IOSDevices())
End Function

Function PrintIOSDeviceInfoField(label:String, value:String)
	If value.length Then Print "  " + label + ": " + value
End Function

Function IOSDeviceAvailabilityLabel:String(device:TIOSDeviceInfo)
	If device.IsAvailable() Then Return "yes"
	If device.pairingState.ToLower() <> "paired" Then Return "no (not paired)"
	If device.bootState.ToLower() <> "booted" Then Return "no (not booted)"
	If device.developerModeStatus.ToLower() = "disabled" Then Return "no (Developer Mode disabled)"
	Return "no"
End Function

Function ReportIOSDeviceInfo()
	Local devices:TIOSDeviceInfo[] = IOSDevices()
	Local count:Int
	For Local device:TIOSDeviceInfo = EachIn devices
		If device.IsPhysicalIOS() Then count :+ 1
	Next
	If Not count Then Throw "No physical iOS device is visible to Xcode."

	Print "Physical iOS devices visible to Xcode:"
	For Local device:TIOSDeviceInfo = EachIn devices
		If Not device.IsPhysicalIOS() Then Continue
		Print ""
		Print IOSDeviceDescription(device)
		PrintIOSDeviceInfoField("UDID", device.udid)
		PrintIOSDeviceInfoField("CoreDevice identifier", device.identifier)
		PrintIOSDeviceInfoField("Product", device.productType)
		Local os:String = device.osVersion
		If device.osBuild.length Then os :+ " (" + device.osBuild + ")"
		PrintIOSDeviceInfoField("iOS", os)
		PrintIOSDeviceInfoField("Transport", IOSDeviceTransportLabel(device.transportType))
		PrintIOSDeviceInfoField("Pairing", device.pairingState)
		PrintIOSDeviceInfoField("Boot state", device.bootState)
		PrintIOSDeviceInfoField("Developer Mode", device.developerModeStatus)
		PrintIOSDeviceInfoField("Available for deployment", IOSDeviceAvailabilityLabel(device))
	Next
	If count > 1 And Not IOSConfiguredDevice().length Then
		Print ""
		Print "Set ios.device in bin/custom.bmk or IOS_DEVICE to select one for '-x'."
	End If
End Function

Function DeployIOSApplication(projectPath:String, scheme:String, appName:String, bundleIdentifier:String, derivedDataPath:String)
	Local sdk:String = IOSConfiguredSDK(processor.CPU(), processor.Option("ios.sdk", ""), getenv_("BMX_IOS_SDK"))
	If sdk <> "iphoneos" Then Throw "Automatic '-x' deployment requires the iphoneos SDK; Simulator launching is managed through Xcode."
	If FileType(projectPath) <> FILETYPE_DIR Then Throw "The generated iOS Xcode project was not found at " + projectPath
	Local device:TIOSDeviceInfo = SelectedIOSDevice()
	Local configuration:String = "Debug"
	If opt_release Then configuration = "Release"
	Print "Building " + appName + " for " + IOSDeviceDescription(device) + "..."
	Local buildCommand:String = CQuote(IOSXcrunCommand()) + " xcodebuild"
	If Not opt_verbose Then buildCommand :+ " -quiet"
	buildCommand :+ ..
		" -project " + CQuote(projectPath) + ..
		" -scheme " + CQuote(scheme) + ..
		" -configuration " + configuration + ..
		" -sdk iphoneos" + ..
		" -destination " + CQuote("id=" + device.udid) + ..
		" -derivedDataPath " + CQuote(derivedDataPath) + ..
		" -allowProvisioningUpdates build"
	If Sys(buildCommand) Then Throw "Xcode failed to build or sign the iOS application for " + IOSDeviceDescription(device)

	Local appPath:String = derivedDataPath + "/Build/Products/" + configuration + "-iphoneos/" + appName + ".app"
	If FileType(appPath) <> FILETYPE_DIR Then Throw "Xcode completed but the iOS application bundle was not found at " + appPath
	Print "Installing " + appName + " on " + IOSDeviceDescription(device) + "..."
	Local deviceArgument:String = " --device " + CQuote(device.udid)
	If Sys(CQuote(IOSXcrunCommand()) + " devicectl device install app" + deviceArgument + " " + CQuote(appPath)) Then
		Throw "The iOS application could not be installed on " + IOSDeviceDescription(device)
	End If
	Print "Starting " + bundleIdentifier + "..."
	If Sys(CQuote(IOSXcrunCommand()) + " devicectl device process launch" + deviceArgument + " --terminate-existing " + CQuote(bundleIdentifier)) Then
		Throw "The iOS application was installed but could not be launched on " + IOSDeviceDescription(device)
	End If
End Function
