SuperStrict

Import BRL.StandardIO

Import "bmk_config.bmx"
Import "bmk_pico.bmx"
Import "bmk_deviceinfo_parse.bmx"

Function AndroidSdkPath:String()
	Local sdk:String = processor.Option("android.sdk", "").Trim()
	If Not sdk.length Then sdk = getenv_("ANDROID_SDK_ROOT").Trim()
	If Not sdk.length Then sdk = getenv_("ANDROID_HOME").Trim()
	If Not sdk.length Then sdk = getenv_("ANDROID_SDK").Trim()
	If Not sdk.length Then Throw "Android SDK not configured; set android.sdk in bin/custom.bmk, or ANDROID_SDK_ROOT/ANDROID_HOME"
	Return sdk
End Function

Function AndroidAdbPath:String()
	Local path:String = AndroidSdkPath() + "/platform-tools/adb"
?win32
	path :+ ".exe"
?
	If FileType(path) <> FILETYPE_FILE Then Throw "Android platform tools not found at " + path
	Return path
End Function

Function AndroidConfiguredDevice:String()
	Local serial:String = processor.Option("android.device", "").Trim()
	If Not serial.length Then serial = getenv_("ANDROID_SERIAL").Trim()
	Return serial
End Function

Function AndroidDevices:TAndroidDeviceInfo[]()
	Return ParseAndroidDevices(PicoCaptureCommand(CQuote(AndroidAdbPath()) + " devices -l"))
End Function

Function AndroidDeviceDescription:String(device:TAndroidDeviceInfo)
	Local result:String = device.serial
	If device.model.length Then result :+ " (" + device.model + ")"
	Return result
End Function

Function AndroidAvailableDeviceSummary:String(devices:TAndroidDeviceInfo[])
	Local result:String
	For Local device:TAndroidDeviceInfo = EachIn devices
		If result.length Then result :+ ", "
		result :+ AndroidDeviceDescription(device) + " [" + device.state + "]"
	Next
	If Not result.length Then result = "none"
	Return result
End Function

Function SelectAndroidDevice:TAndroidDeviceInfo(devices:TAndroidDeviceInfo[])
	Local configured:String = AndroidConfiguredDevice()
	If configured.length Then
		For Local device:TAndroidDeviceInfo = EachIn devices
			If device.serial <> configured Then Continue
			If device.state <> "device" Then Throw "Android device " + configured + " is " + device.state + ". Check its screen and USB debugging connection."
			Return device
		Next
		Throw "Configured Android device " + configured + " is not connected. Available devices: " + AndroidAvailableDeviceSummary(devices)
	End If

	Local selected:TAndroidDeviceInfo
	Local authorized:Int
	For Local device:TAndroidDeviceInfo = EachIn devices
		If device.state <> "device" Then Continue
		selected = device
		authorized :+ 1
	Next
	If authorized = 1 Then Return selected
	If authorized > 1 Then
		Throw "Multiple authorized Android devices are connected: " + AndroidAvailableDeviceSummary(devices) + ". Set android.device in bin/custom.bmk or ANDROID_SERIAL."
	End If
	If devices.length Then Throw "No authorized Android device is available: " + AndroidAvailableDeviceSummary(devices) + ". Unlock the device and accept its USB debugging prompt."
	Throw "No Android device is connected. Connect one with USB debugging enabled, then confirm it appears in 'adb devices'."
End Function

Function SelectedAndroidDevice:TAndroidDeviceInfo()
	Return SelectAndroidDevice(AndroidDevices())
End Function

Function AndroidAdbCommand:String(device:TAndroidDeviceInfo)
	Return CQuote(AndroidAdbPath()) + " -s " + CQuote(device.serial)
End Function

Function AndroidDeviceProperties:String(device:TAndroidDeviceInfo)
	Return PicoCaptureCommand(AndroidAdbCommand(device) + " shell getprop")
End Function

Function PrintAndroidDeviceInfoField(label:String, value:String)
	If value.length Then Print "  " + label + ": " + value
End Function

Function ReportAndroidDeviceInfo()
	Local device:TAndroidDeviceInfo = SelectedAndroidDevice()
	Local properties:String = AndroidDeviceProperties(device)
	Print "Detected Android device:"
	PrintAndroidDeviceInfoField("Serial", device.serial)
	PrintAndroidDeviceInfoField("Manufacturer", AndroidDeviceProperty(properties, "ro.product.manufacturer"))
	PrintAndroidDeviceInfoField("Model", AndroidDeviceProperty(properties, "ro.product.model"))
	PrintAndroidDeviceInfoField("Product", AndroidDeviceProperty(properties, "ro.product.name"))
	PrintAndroidDeviceInfoField("Device", AndroidDeviceProperty(properties, "ro.product.device"))
	PrintAndroidDeviceInfoField("Android", AndroidDeviceProperty(properties, "ro.build.version.release"))
	PrintAndroidDeviceInfoField("API level", AndroidDeviceProperty(properties, "ro.build.version.sdk"))
	PrintAndroidDeviceInfoField("ABIs", AndroidDeviceProperty(properties, "ro.product.cpu.abilist"))
	PrintAndroidDeviceInfoField("Hardware", AndroidDeviceProperty(properties, "ro.hardware"))
	PrintAndroidDeviceInfoField("Build", AndroidDeviceProperty(properties, "ro.build.display.id"))
	PrintAndroidDeviceInfoField("Fingerprint", AndroidDeviceProperty(properties, "ro.build.fingerprint"))
End Function

Function DeployAndroidApplication(apkPath:String, appPackage:String)
	If Not FileType(apkPath) Then Throw "Android APK was not created at " + apkPath
	If Not appPackage.length Then Throw "Android application package is not configured"
	If opt_release Then Throw "Android release APKs are unsigned and cannot be installed automatically; use a debug build or sign the APK first."
	Local device:TAndroidDeviceInfo = SelectedAndroidDevice()
	Print "Installing " + StripDir(apkPath) + " on " + AndroidDeviceDescription(device) + "..."
	If Sys(AndroidAdbCommand(device) + " install -r " + CQuote(apkPath)) Then Throw "Android APK installation failed"
	Print "Starting " + appPackage + "/.BlitzMaxApp..."
	If Sys(AndroidAdbCommand(device) + " shell am start -W -n " + CQuote(appPackage + "/.BlitzMaxApp")) Then Throw "Android application launch failed"
End Function
