SuperStrict

Import BRL.FileSystem
Import BRL.Map
Import BRL.TextStream

Type TEsp32BoardPin
	Field name:String
	Field gpio:Int
	Field connector:String
	Field position:String
End Type

Type TEsp32BoardProfile
	Field name:String
	Field directory:String
	Field displayName:String
	Field vendor:String
	Field kind:String
	Field aliases:String[] = New String[0]
	Field idfTarget:String
	Field moduleName:String
	Field homepage:String
	Field documentation:String

	Field flashSize:String
	Field flashMode:String
	Field flashFrequency:String
	Field psramSize:String
	Field sdkconfigDefaults:String
	Field partitions:String
	Field consoleTransport:String

	Field pins:TMap = New TMap
	Field buses:TMap = New TMap
	Field resources:TMap = New TMap
	Field constraints:TMap = New TMap

	Method Pin:TEsp32BoardPin(name:String)
		Return TEsp32BoardPin(pins.ValueForKey(name.Trim().ToLower()))
	End Method

	Method PinNumber:Int(name:String, fallback:Int = -1)
		Local pin:TEsp32BoardPin = Pin(name)
		If pin Then Return pin.gpio
		Return fallback
	End Method

	Method Bus:TMap(name:String)
		Return TMap(buses.ValueForKey(name.Trim().ToLower()))
	End Method

	Method EsptoolResetMode:String()
		If consoleTransport = "usb_serial_jtag" Then Return "usb-reset"
		Return ""
	End Method
End Type

Type TEsp32BoardProfileRegistry
	Field profiles:TMap = New TMap
	Field aliases:TMap = New TMap

	Method Add(profile:TEsp32BoardProfile, source:String)
		Local name:String = profile.name.ToLower()
		If profiles.Contains(name) Then Throw "Duplicate ESP32 board profile '" + name + "' in " + source
		profiles.Insert(name, profile)
		RegisterAlias(name, profile, source)
		For Local aliasName:String = EachIn profile.aliases
			RegisterAlias(aliasName.ToLower(), profile, source)
		Next
	End Method

	Method RegisterAlias(aliasName:String, profile:TEsp32BoardProfile, source:String)
		If Not aliasName.length Then Return
		If aliases.Contains(aliasName) Then Throw "Duplicate ESP32 board profile name or alias '" + aliasName + "' in " + source
		aliases.Insert(aliasName, profile)
	End Method

	Method Find:TEsp32BoardProfile(name:String)
		Return TEsp32BoardProfile(aliases.ValueForKey(name.Trim().ToLower()))
	End Method

	Method Names:String()
		Local result:String
		For Local name:String = EachIn profiles.Keys()
			If result.length Then result :+ ", "
			result :+ name
		Next
		Return result
	End Method
End Type

Function Esp32ProfileNameValid:Int(name:String)
	If Not name.length Then Return False
	For Local index:Int = 0 Until name.length
		Local character:Int = name[index]
		If character >= Asc("a") And character <= Asc("z") Then Continue
		If character >= Asc("A") And character <= Asc("Z") Then Continue
		If character >= Asc("0") And character <= Asc("9") Then Continue
		If character = Asc("_") Or character = Asc("-") Then Continue
		Return False
	Next
	Return True
End Function

Function Esp32ProfileAliases:String[](value:String)
	Local result:String[] = New String[0]
	For Local rawAlias:String = EachIn value.Split(",")
		Local aliasName:String = rawAlias.Trim().ToLower()
		If Not aliasName.length Then Continue
		If Not Esp32ProfileNameValid(aliasName) Then Throw "Invalid ESP32 board profile alias '" + aliasName + "'"
		result :+ [aliasName]
	Next
	Return result
End Function

Function Esp32ProfileRelativePathValid:Int(path:String)
	Local normalized:String = path.Replace("\", "/")
	Return normalized.length And Not normalized.StartsWith("/") And normalized <> ".." And ..
		Not normalized.StartsWith("../") And Not normalized.Contains("/../")
End Function

Function Esp32ProfileValueNameValid:Int(name:String)
	If Not name.length Then Return False
	For Local index:Int = 0 Until name.length
		Local character:Int = name[index]
		If character >= Asc("a") And character <= Asc("z") Then Continue
		If character >= Asc("0") And character <= Asc("9") Then Continue
		If character = Asc("_") Or character = Asc("-") Or character = Asc(".") Then Continue
		Return False
	Next
	Return True
End Function

Function Esp32ProfileMapValue(map:TMap, key:String, value:String, source:String, lineNumber:Int)
	If map.Contains(key) Then Throw "Duplicate ESP32 board field '" + key + "' at " + source + ":" + lineNumber
	map.Insert(key, value)
End Function

Function Esp32ProfileDynamicFieldValid:Int(section:String, key:String)
	If section.StartsWith("bus.")
		Return key = "controller" Or key = "sda" Or key = "scl" Or key = "frequency" Or ..
			key = "miso" Or key = "mosi" Or key = "clock" Or key = "chip_select" Or ..
			key = "tx" Or key = "rx" Or key = "baud"
	Else If section.StartsWith("resource.")
		Return key = "type" Or key = "pin" Or key = "count" Or key = "order" Or ..
			key = "interface" Or key = "controller" Or key = "clock" Or key = "command" Or ..
			key = "data0" Or key = "data1" Or key = "data2" Or key = "data3" Or ..
			key = "bus" Or key = "voltage" Or key = "active" Or key = "address"
	Else If section.StartsWith("constraint.")
		Return key = "pins" Or key = "status" Or key = "reason"
	End If
	Return False
End Function

Function Esp32ProfileSectionMap:TMap(profile:TEsp32BoardProfile, section:String, source:String, lineNumber:Int)
	Local destination:TMap
	If section.StartsWith("bus.")
		destination = profile.buses
	Else If section.StartsWith("resource.")
		destination = profile.resources
	Else If section.StartsWith("constraint.")
		destination = profile.constraints
	Else
		Throw "Unknown ESP32 board section '[" + section + "]' at " + source + ":" + lineNumber
	End If
	If Not Esp32ProfileValueNameValid(section) Then Throw "Invalid ESP32 board section '[" + section + "]' at " + source + ":" + lineNumber
	Local values:TMap = TMap(destination.ValueForKey(section))
	If Not values
		values = New TMap
		destination.Insert(section, values)
	End If
	Return values
End Function

Function ParseEsp32BoardProfile:TEsp32BoardProfile(text:String, name:String, source:String = "ESP32 board profile")
	name = name.Trim().ToLower()
	If Not Esp32ProfileNameValid(name) Then Throw "Invalid ESP32 board profile name '" + name + "'"
	Local profile:TEsp32BoardProfile = New TEsp32BoardProfile
	profile.name = name
	Local section:String
	Local formatSeen:Int
	Local sectionValues:TMap
	Local scalarFields:TMap = New TMap
	Local lineNumber:Int
	For Local rawLine:String = EachIn text.Replace("~r", "").Split("~n")
		lineNumber :+ 1
		Local line:String = rawLine.Trim()
		If Not line.length Or line.StartsWith("#") Or line.StartsWith(";") Then Continue
		If line.StartsWith("[") And line.EndsWith("]")
			section = line[1..line.length - 1].Trim().ToLower()
			If section = "board" Or section = "build" Or section = "console"
				sectionValues = Null
			Else
				sectionValues = Esp32ProfileSectionMap(profile, section, source, lineNumber)
			End If
			Continue
		End If

		Local equals:Int = line.Find("=")
		If equals <= 0 Then Throw "Invalid ESP32 board entry at " + source + ":" + lineNumber
		Local key:String = line[..equals].Trim().ToLower()
		Local value:String = line[equals + 1..].Trim()
		If Not section.length
			If key <> "format" Or value <> "1" Or formatSeen Then Throw "Expected one 'format=1' before ESP32 board sections at " + source + ":" + lineNumber
			formatSeen = True
			Continue
		End If

		Select section
			Case "board"
				If scalarFields.Contains(section + "." + key) Then Throw "Duplicate ESP32 board field '" + key + "' at " + source + ":" + lineNumber
				scalarFields.Insert(section + "." + key, value)
				Select key
					Case "name" profile.displayName = value
					Case "vendor" profile.vendor = value
					Case "kind" profile.kind = value.ToLower()
					Case "aliases" profile.aliases = Esp32ProfileAliases(value)
					Case "target" profile.idfTarget = value.ToLower()
					Case "module" profile.moduleName = value
					Case "homepage" profile.homepage = value
					Case "documentation" profile.documentation = value
					Default Throw "Unknown ESP32 [board] field '" + key + "' at " + source + ":" + lineNumber
				End Select
			Case "build"
				If scalarFields.Contains(section + "." + key) Then Throw "Duplicate ESP32 board field '" + key + "' at " + source + ":" + lineNumber
				scalarFields.Insert(section + "." + key, value)
				Select key
					Case "flash_size" profile.flashSize = value
					Case "flash_mode" profile.flashMode = value
					Case "flash_frequency" profile.flashFrequency = value
					Case "psram_size" profile.psramSize = value
					Case "sdkconfig_defaults" profile.sdkconfigDefaults = value.Replace("\", "/")
					Case "partitions" profile.partitions = value.Replace("\", "/")
					Default Throw "Unknown ESP32 [build] field '" + key + "' at " + source + ":" + lineNumber
				End Select
			Case "console"
				If scalarFields.Contains(section + "." + key) Then Throw "Duplicate ESP32 board field '" + key + "' at " + source + ":" + lineNumber
				scalarFields.Insert(section + "." + key, value)
				If key <> "transport" Then Throw "Unknown ESP32 [console] field '" + key + "' at " + source + ":" + lineNumber
				profile.consoleTransport = value.ToLower()
			Default
				If Not Esp32ProfileDynamicFieldValid(section, key) Then Throw "Unknown ESP32 [" + section + "] field '" + key + "' at " + source + ":" + lineNumber
				Esp32ProfileMapValue(sectionValues, key, value, source, lineNumber)
		End Select
	Next
	If Not formatSeen Then Throw "ESP32 board profile does not declare format=1: " + source
	If Not profile.displayName.length Then Throw "ESP32 board profile '" + name + "' has no board name in " + source
	If profile.kind <> "generic" And profile.kind <> "board" Then Throw "ESP32 board profile '" + name + "' must use kind=generic or kind=board in " + source
	If Not profile.idfTarget.length Then Throw "ESP32 board profile '" + name + "' has no target in " + source
	If profile.sdkconfigDefaults.length And Not Esp32ProfileRelativePathValid(profile.sdkconfigDefaults) Then Throw "ESP32 board profile '" + name + "' has an unsafe sdkconfig_defaults path in " + source
	If profile.partitions.length And Not Esp32ProfileRelativePathValid(profile.partitions) Then Throw "ESP32 board profile '" + name + "' has an unsafe partitions path in " + source
	Return profile
End Function

Function Esp32ProfileUnsigned:Int(value:String)
	If Not value.length Then Return -1
	For Local character:Int = EachIn value
		If character < Asc("0") Or character > Asc("9") Then Return -1
	Next
	Return Int(value)
End Function

Function ParseEsp32BoardPins(text:String, profile:TEsp32BoardProfile, source:String = "ESP32 board pins")
	Local headerSeen:Int
	Local lineNumber:Int
	For Local rawLine:String = EachIn text.Replace("~r", "").Split("~n")
		lineNumber :+ 1
		Local line:String = rawLine.Trim()
		If Not line.length Or line.StartsWith("#") Then Continue
		Local fields:String[] = line.Split(",")
		If Not headerSeen
			If fields.length <> 4 Or fields[0].Trim().ToLower() <> "name" Or fields[1].Trim().ToLower() <> "gpio" Or fields[2].Trim().ToLower() <> "connector" Or fields[3].Trim().ToLower() <> "position" Then Throw "Expected ESP32 pin header 'name,gpio,connector,position' at " + source + ":" + lineNumber
			headerSeen = True
			Continue
		End If
		If fields.length <> 4 Then Throw "Expected four ESP32 pin fields at " + source + ":" + lineNumber
		Local pin:TEsp32BoardPin = New TEsp32BoardPin
		pin.name = fields[0].Trim()
		If Not Esp32ProfileNameValid(pin.name) Then Throw "Invalid ESP32 board pin name '" + pin.name + "' at " + source + ":" + lineNumber
		pin.gpio = Esp32ProfileUnsigned(fields[1].Trim())
		If pin.gpio < 0 Or pin.gpio > 63 Then Throw "Invalid ESP32 GPIO at " + source + ":" + lineNumber
		pin.connector = fields[2].Trim()
		pin.position = fields[3].Trim()
		Local normalized:String = pin.name.ToLower()
		If profile.pins.Contains(normalized) Then Throw "Duplicate ESP32 board pin name '" + pin.name + "' at " + source + ":" + lineNumber
		profile.pins.Insert(normalized, pin)
	Next
	If Not headerSeen Then Throw "ESP32 board pin file is empty: " + source
End Function

Function ValidateEsp32BoardPinReferences(profile:TEsp32BoardProfile, source:String)
	For Local section:String = EachIn profile.buses.Keys()
		Local values:TMap = TMap(profile.buses.ValueForKey(section))
		For Local key:String = EachIn values.Keys()
			If key <> "sda" And key <> "scl" And key <> "miso" And key <> "mosi" And key <> "clock" And key <> "chip_select" And key <> "tx" And key <> "rx" Then Continue
			Local name:String = String(values.ValueForKey(key))
			If profile.PinNumber(name) < 0 Then Throw "ESP32 board profile '" + profile.name + "' " + section + " references unknown pin '" + name + "' in " + source
		Next
	Next
	For Local section:String = EachIn profile.resources.Keys()
		Local values:TMap = TMap(profile.resources.ValueForKey(section))
		Local bus:String = String(values.ValueForKey("bus"))
		If bus.length And Not profile.buses.Contains(bus.ToLower()) Then Throw "ESP32 board profile '" + profile.name + "' " + section + " references unknown bus '" + bus + "' in " + source
		For Local key:String = EachIn values.Keys()
			If key <> "pin" And key <> "clock" And key <> "command" And Not key.StartsWith("data") Then Continue
			Local name:String = String(values.ValueForKey(key))
			If profile.PinNumber(name) < 0 Then Throw "ESP32 board profile '" + profile.name + "' " + section + " references unknown pin '" + name + "' in " + source
		Next
	Next
	For Local section:String = EachIn profile.constraints.Keys()
		Local values:TMap = TMap(profile.constraints.ValueForKey(section))
		Local pins:String = String(values.ValueForKey("pins"))
		For Local rawName:String = EachIn pins.Split(",")
			Local name:String = rawName.Trim()
			If name.length And profile.PinNumber(name) < 0 Then Throw "ESP32 board profile '" + profile.name + "' " + section + " references unknown pin '" + name + "' in " + source
		Next
	Next
End Function

Function LoadEsp32BoardProfile:TEsp32BoardProfile(directory:String, name:String)
	Local boardPath:String = directory + "/board.ini"
	If FileType(boardPath) <> FILETYPE_FILE Then Throw "ESP32 board profile has no board.ini: " + directory
	Local profile:TEsp32BoardProfile = ParseEsp32BoardProfile(LoadText(boardPath), name, boardPath)
	profile.directory = directory
	Local pinsPath:String = directory + "/pins.csv"
	If FileType(pinsPath) = FILETYPE_FILE Then ParseEsp32BoardPins(LoadText(pinsPath), profile, pinsPath)
	ValidateEsp32BoardPinReferences(profile, boardPath)
	If profile.sdkconfigDefaults.length And FileType(directory + "/" + profile.sdkconfigDefaults) <> FILETYPE_FILE Then Throw "ESP32 board profile '" + name + "' defaults file was not found: " + directory + "/" + profile.sdkconfigDefaults
	If profile.partitions.length And FileType(directory + "/" + profile.partitions) <> FILETYPE_FILE Then Throw "ESP32 board profile '" + name + "' partition file was not found: " + directory + "/" + profile.partitions
	Return profile
End Function
