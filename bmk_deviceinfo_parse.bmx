SuperStrict

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
	Return result
End Function
