SuperStrict

Import Text.JSON

Type TIOSDeviceInfo
	Field identifier:String
	Field udid:String
	Field name:String
	Field marketingName:String
	Field productType:String
	Field platform:String
	Field reality:String
	Field serialNumber:String
	Field transportType:String
	Field connectionState:String
	Field pairingState:String
	Field bootState:String
	Field developerModeStatus:String
	Field osVersion:String
	Field osBuild:String

	Method IsPhysicalIOS:Int()
		Return reality.ToLower() = "physical" And (platform.ToLower() = "ios" Or platform.ToLower() = "ipados")
	End Method

	Method IsAvailable:Int()
		Return IsPhysicalIOS() And pairingState.ToLower() = "paired" And bootState.ToLower() = "booted" And developerModeStatus.ToLower() <> "disabled"
	End Method
End Type

Function IOSJSONObject:TJSONObject(obj:TJSONObject, key:String)
	If Not obj Then Return Null
	Return TJSONObject(obj.Get(key))
End Function

Function IOSJSONString:String(obj:TJSONObject, key:String)
	If Not obj Then Return ""
	Return obj.GetString(key)
End Function

Function IOSFirstString:String(primary:String, fallback:String)
	If primary.length Then Return primary
	Return fallback
End Function

Function IOSDeveloperModeStatus:String(state:TJSONObject, legacyDevice:TJSONObject)
	Local status:TJSONObject = IOSJSONObject(state, "developerModeStatus")
	If status Then
		If status.Get("enabled") Then Return "enabled"
		If status.Get("disabled") Then Return "disabled"
		If status.Get("unknown") Then Return "unknown"
	End If
	Return IOSJSONString(legacyDevice, "developerModeStatus")
End Function

Function ParseIOSDevices:TIOSDeviceInfo[](jsonText:String, errorMessage:String Var)
	errorMessage = ""
	Local jsonError:TJSONError
	' CoreDevice includes unsigned hardware values which can exceed BlitzMax's
	' signed Long range. They are not used here, so decode all numbers as reals.
	Local root:TJSONObject = TJSONObject(TJSON.Load(jsonText, JSON_DECODE_INT_AS_REAL, jsonError))
	If jsonError Then
		errorMessage = jsonError.Text
		Return New TIOSDeviceInfo[0]
	End If
	If Not root Then
		errorMessage = "the top-level value is not an object"
		Return New TIOSDeviceInfo[0]
	End If

	Local result:TJSONObject = IOSJSONObject(root, "result")
	Local values:TJSONArray
	If result Then values = TJSONArray(result.Get("devices"))
	If Not values Then
		errorMessage = "the result does not contain a devices array"
		Return New TIOSDeviceInfo[0]
	End If

	Local devices:TIOSDeviceInfo[] = New TIOSDeviceInfo[values.Size()]
	For Local index:Int = 0 Until values.Size()
		Local source:TJSONObject = TJSONObject(values.Get(index))
		If Not source Then
			errorMessage = "device " + index + " is not an object"
			Return New TIOSDeviceInfo[0]
		End If

		Local properties:TJSONObject = IOSJSONObject(source, "properties")
		Local hardware:TJSONObject = IOSJSONObject(properties, "hardware")
		Local software:TJSONObject = IOSJSONObject(properties, "software")
		Local state:TJSONObject = IOSJSONObject(properties, "state")
		Local connection:TJSONObject = IOSJSONObject(properties, "connection")
		Local legacyHardware:TJSONObject = IOSJSONObject(source, "hardwareProperties")
		Local legacyDevice:TJSONObject = IOSJSONObject(source, "deviceProperties")
		Local legacyConnection:TJSONObject = IOSJSONObject(source, "connectionProperties")

		Local device:TIOSDeviceInfo = New TIOSDeviceInfo
		device.identifier = IOSJSONString(source, "identifier")
		device.udid = IOSFirstString(IOSJSONString(hardware, "udid"), IOSJSONString(legacyHardware, "udid"))
		device.name = IOSFirstString(IOSJSONString(state, "name"), IOSJSONString(legacyDevice, "name"))
		device.marketingName = IOSFirstString(IOSJSONString(hardware, "marketingName"), IOSJSONString(legacyHardware, "marketingName"))
		device.productType = IOSFirstString(IOSJSONString(hardware, "productType"), IOSJSONString(legacyHardware, "productType"))
		device.platform = IOSFirstString(IOSJSONString(hardware, "platform"), IOSJSONString(legacyHardware, "platform"))
		device.reality = IOSFirstString(IOSJSONString(hardware, "reality"), IOSJSONString(legacyHardware, "reality"))
		device.serialNumber = IOSFirstString(IOSJSONString(hardware, "serialNumber"), IOSJSONString(legacyHardware, "serialNumber"))
		device.transportType = IOSFirstString(IOSJSONString(connection, "transportType"), IOSJSONString(legacyConnection, "transportType"))
		device.connectionState = IOSJSONString(connection, "state")
		device.pairingState = IOSFirstString(IOSJSONString(connection, "pairingState"), IOSJSONString(legacyConnection, "pairingState"))
		device.bootState = IOSFirstString(IOSJSONString(state, "bootState"), IOSJSONString(legacyDevice, "bootState"))
		device.developerModeStatus = IOSDeveloperModeStatus(state, legacyDevice)

		Local osVersion:TJSONObject = IOSJSONObject(software, "osVersionNumber")
		device.osVersion = IOSFirstString(IOSJSONString(osVersion, "stringValue"), IOSJSONString(legacyDevice, "osVersionNumber"))
		Local versions:TJSONObject = IOSJSONObject(software, "osBuildVersions")
		Local buildVersion:TJSONObject = IOSJSONObject(versions, "buildVersion")
		device.osBuild = IOSFirstString(IOSJSONString(buildVersion, "name"), IOSJSONString(legacyDevice, "osBuildUpdate"))
		devices[index] = device
	Next
	Return devices
End Function

Function IOSDeviceMatches:Int(device:TIOSDeviceInfo, selector:String)
	If Not device Or Not selector.length Then Return False
	Local normalized:String = selector.ToLower()
	Return device.udid.ToLower() = normalized Or ..
		device.identifier.ToLower() = normalized Or ..
		device.serialNumber.ToLower() = normalized Or ..
		device.name.ToLower() = normalized
End Function
