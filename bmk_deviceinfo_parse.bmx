SuperStrict

Type TAndroidDeviceInfo
	Field serial:String
	Field state:String
	Field product:String
	Field model:String
	Field device:String
	Field transportId:String
End Type

Function AndroidDeviceInfoWords:String[](line:String)
	Local words:String[] = New String[0]
	For Local word:String = EachIn line.Replace("~t", " ").Split(" ")
		word = word.Trim()
		If word.length Then words :+ [word]
	Next
	Return words
End Function

Function ParseAndroidDevices:TAndroidDeviceInfo[](output:String)
	Local devices:TAndroidDeviceInfo[] = New TAndroidDeviceInfo[0]
	For Local rawLine:String = EachIn output.Replace("~r", "").Split("~n")
		Local line:String = rawLine.Trim()
		If Not line.length Or line.StartsWith("*") Or line.ToLower().StartsWith("list of devices") Then Continue
		Local words:String[] = AndroidDeviceInfoWords(line)
		If words.length < 2 Then Continue
		Local state:String = words[1].ToLower()
		Local detailStart:Int = 2
		If state = "no" And words.length > 2 And words[2].ToLower() = "permissions" Then
			state = "no permissions"
			detailStart = 3
		End If
		If state <> "device" And state <> "offline" And state <> "unauthorized" And state <> "authorizing" And state <> "connecting" And state <> "recovery" And state <> "sideload" And state <> "bootloader" And state <> "no permissions" Then Continue
		Local info:TAndroidDeviceInfo = New TAndroidDeviceInfo
		info.serial = words[0]
		info.state = state
		For Local index:Int = detailStart Until words.length
			Local separator:Int = words[index].Find(":")
			If separator < 1 Then Continue
			Local key:String = words[index][..separator]
			Local value:String = words[index][separator + 1..]
			Select key
				Case "product" info.product = value
				Case "model" info.model = value.Replace("_", " ")
				Case "device" info.device = value
				Case "transport_id" info.transportId = value
			End Select
		Next
		devices :+ [info]
	Next
	Return devices
End Function

Function AndroidDeviceProperty:String(output:String, key:String)
	Local prefix:String = "[" + key + "]: ["
	For Local rawLine:String = EachIn output.Replace("~r", "").Split("~n")
		Local line:String = rawLine.Trim()
		If Not line.StartsWith(prefix) Or Not line.EndsWith("]") Then Continue
		Return line[prefix.length..line.length - 1]
	Next
	Return ""
End Function

Function EmbeddedDeviceInfoField:String(output:String, label:String, section:String = "")
	Local active:Int = Not section.length
	Local wantedLabel:String = label.ToLower()
	Local wantedSection:String = section.ToLower()
	For Local rawLine:String = EachIn output.Replace("~r", "").Split("~n")
		Local line:String = rawLine.Trim()
		If Not line.length Then Continue
		Local lowerLine:String = line.ToLower()
		If section.length And lowerLine.EndsWith(" information")
			active = lowerLine = wantedSection
			Continue
		End If
		If Not active Then Continue
		Local colon:Int = line.Find(":")
		If colon < 0 Then Continue
		If line[..colon].Trim().ToLower() = wantedLabel Then Return line[colon + 1..].Trim()
	Next
	Return ""
End Function

Function Esp32DeviceInfoPort:String(output:String)
	For Local rawLine:String = EachIn output.Replace("~r", "").Split("~n")
		Local line:String = rawLine.Trim()
		If Not line.ToLower().StartsWith("serial port ") Then Continue
		Local value:String = line[12..].Trim()
		If value.EndsWith(":") Then value = value[..value.length - 1]
		Return value
	Next
	Return ""
End Function

Function Esp32DetectedTarget:String(chip:String)
	Local result:String = chip.Trim().ToLower().Replace("-", "")
	Local separator:Int = result.Find(" ")
	If separator >= 0 Then result = result[..separator]
	For Local target:String = EachIn ["esp32s2", "esp32s3", "esp32c2", "esp32c3", "esp32c5", "esp32c6", "esp32h2", "esp32p4"]
		If result.StartsWith(target) Then Return target
	Next
	If result.StartsWith("esp32") Then Return "esp32"
	Return result
End Function
