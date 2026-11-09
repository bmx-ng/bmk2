SuperStrict

Import BRL.StandardIO

Import "bmk_config.bmx"
Import "bmk_pico.bmx"
Import "bmk_esp32.bmx"
Import "bmk_esp8266.bmx"
Import "bmk_deviceinfo_parse.bmx"
Import "bmk_android_device.bmx"
Import "bmk_ios_device.bmx"

Function PrintEmbeddedDeviceInfoField(label:String, value:String)
	If value.length Then Print "  " + label + ": " + value
End Function

Function Esp32ConfiguredBoardProfile:String()
	If opt_target_board_set Then Return Esp32BoardProfile()
	Local configured:String = processor.Option("esp32.target", "").Trim()
	If configured.length Then Return Esp32BoardProfile()
	Return ""
End Function

Function Esp32BoardLabel:String(name:String)
	Select name.ToLower()
		Case "sda" Return "SDA"
		Case "scl" Return "SCL"
		Case "miso" Return "MISO"
		Case "mosi" Return "MOSI"
		Case "tx" Return "TX"
		Case "rx" Return "RX"
	End Select
	Local result:String = name.Replace("_", " ").Replace(".", " ")
	If result.length Then result = result[..1].ToUpper() + result[1..]
	result = result.Replace("I2c", "I2C").Replace("Spi", "SPI").Replace("Uart", "UART")
	result = result.Replace("Rgb", "RGB").Replace(" rgb", " RGB").Replace("Usb", "USB").Replace(" usb", " USB").Replace("Microsd", "MicroSD").Replace(" microsd", " MicroSD")
	Return result
End Function

Function Esp32BoardPinLabel:String(profile:TEsp32BoardProfile, name:String)
	Local pin:TEsp32BoardPin = profile.Pin(name)
	If pin Then Return name + " (GPIO" + pin.gpio + ")"
	Return name
End Function

Function Esp32BoardPinListLabel:String(profile:TEsp32BoardProfile, value:String)
	Local result:String
	For Local rawName:String = EachIn value.Split(",")
		Local name:String = rawName.Trim()
		If Not name.length Then Continue
		If result.length Then result :+ ", "
		result :+ Esp32BoardPinLabel(profile, name)
	Next
	Return result
End Function

Function PrintEsp32BoardSection(profile:TEsp32BoardProfile, title:String, sections:TMap, prefix:String)
	If sections.IsEmpty() Then Return
	Print title + ":"
	For Local section:String = EachIn sections.Keys()
		Local display:String = section
		If display.StartsWith(prefix) Then display = display[prefix.length..]
		Print "  " + Esp32BoardLabel(display) + ":"
		Local values:TMap = TMap(sections.ValueForKey(section))
		For Local key:String = EachIn values.Keys()
			Local value:String = String(values.ValueForKey(key))
			If key = "pins"
				value = Esp32BoardPinListLabel(profile, value)
			Else If key = "pin" Or key = "sda" Or key = "scl" Or key = "miso" Or key = "mosi" Or key = "clock" Or key = "chip_select" Or key = "tx" Or key = "rx" Or key = "command" Or key.StartsWith("data")
				value = Esp32BoardPinLabel(profile, value)
			End If
			Print "    " + Esp32BoardLabel(key) + ": " + value
		Next
	Next
End Function

Function Esp32FlashSizeComparable:String(value:String)
	Return value.Trim().ToLower().Replace("ib", "b").Replace(" ", "")
End Function

Function PrintEsp32BoardProfile(profile:TEsp32BoardProfile, includePins:Int)
	Print profile.displayName + " (" + profile.name + ")"
	PrintEmbeddedDeviceInfoField("Kind", profile.kind)
	PrintEmbeddedDeviceInfoField("Vendor", profile.vendor)
	PrintEmbeddedDeviceInfoField("ESP-IDF target", profile.idfTarget)
	PrintEmbeddedDeviceInfoField("Architecture", Esp32TargetArchitecture(profile.idfTarget))
	PrintEmbeddedDeviceInfoField("Build support", "available")
	PrintEmbeddedDeviceInfoField("Module", profile.moduleName)
	PrintEmbeddedDeviceInfoField("Flash", profile.flashSize)
	PrintEmbeddedDeviceInfoField("Flash mode", profile.flashMode)
	PrintEmbeddedDeviceInfoField("Flash frequency", profile.flashFrequency)
	PrintEmbeddedDeviceInfoField("PSRAM", profile.psramSize)
	PrintEmbeddedDeviceInfoField("Console", profile.consoleTransport.Replace("_", " "))
	PrintEmbeddedDeviceInfoField("Homepage", profile.homepage)
	PrintEmbeddedDeviceInfoField("Documentation", profile.documentation)
	If profile.sdkconfigDefaults.length Then PrintEmbeddedDeviceInfoField("SDK defaults", profile.sdkconfigDefaults)
	If profile.partitions.length Then PrintEmbeddedDeviceInfoField("Partitions", profile.partitions)
	If Not profile.buses.IsEmpty() Then
		Print ""
		PrintEsp32BoardSection(profile, "Default buses", profile.buses, "bus.")
	End If
	If Not profile.resources.IsEmpty() Then
		Print ""
		PrintEsp32BoardSection(profile, "Onboard resources", profile.resources, "resource.")
	End If
	If Not profile.constraints.IsEmpty() Then
		Print ""
		PrintEsp32BoardSection(profile, "Constraints", profile.constraints, "constraint.")
	End If
	If includePins And Not profile.pins.IsEmpty()
		Print ""
		Print "Named pins:"
		For Local name:String = EachIn profile.pins.Keys()
			Local pin:TEsp32BoardPin = TEsp32BoardPin(profile.pins.ValueForKey(name))
			Local location:String
			If pin.connector.length Then
				location = ", " + pin.connector
				If pin.position.length Then location :+ " position " + pin.position
			End If
			Print "  " + pin.name + ": GPIO" + pin.gpio + location
		Next
	End If
End Function

Function ReportEsp32BoardInfo(args:String[])
	If args.length Then CmdError "boardinfo does not accept a source file"
	If processor.Platform() <> "esp32" Then CmdError "boardinfo is currently available only for the esp32 target"
	PrintEsp32BoardProfile(Esp32BoardProfiles().Find(Esp32BoardProfile()), True)
End Function

Function PrintEsp8266BoardProfile(includePins:Int)
	Print "Generic ESP-12F D1 Mini (d1_mini_esp12f)"
	PrintEmbeddedDeviceInfoField("Kind", "development board")
	PrintEmbeddedDeviceInfoField("SoC", "ESP8266EX")
	PrintEmbeddedDeviceInfoField("Architecture", "Xtensa LX106")
	PrintEmbeddedDeviceInfoField("Build support", "available")
	PrintEmbeddedDeviceInfoField("Module", "ESP-12F")
	PrintEmbeddedDeviceInfoField("Flash", "4MB")
	PrintEmbeddedDeviceInfoField("Flash mode", "DIO")
	PrintEmbeddedDeviceInfoField("Flash frequency", "40MHz")
	PrintEmbeddedDeviceInfoField("Managed heap", "12288 bytes")
	PrintEmbeddedDeviceInfoField("Console", "UART, 74880 baud")
	If includePins
		Print ""
		Print "Named pins:"
		For Local pin:String = EachIn ["D0: GPIO16", "D1: GPIO5", "D2: GPIO4", "D3: GPIO0", "D4: GPIO2", "D5: GPIO14", "D6: GPIO12", "D7: GPIO13", "D8: GPIO15", "RX: GPIO3", "TX: GPIO1", "LED: GPIO2 (active low)"]
			Print "  " + pin
		Next
	End If
End Function

Function ReportEsp8266BoardInfo(args:String[])
	If args.length Then CmdError "boardinfo does not accept a source file"
	If processor.Platform() <> "esp8266" Then CmdError "boardinfo requires the esp8266 target"
	Esp8266BoardProfile()
	PrintEsp8266BoardProfile(True)
End Function

Function Esp8266DeviceChip:String(output:String)
	For Local line:String = EachIn output.Replace("~r", "").Split("~n")
		line = line.Trim()
		If line.StartsWith("Chip is ") Then Return line[8..].Trim()
	Next
	Return ""
End Function

Function ReportEsp8266DeviceInfo()
	Local idfPath:String = Esp8266IdfPath()
	Local toolsRoot:String = Esp8266ToolsRoot()
	Local python:String = Esp8266Python(toolsRoot)
	Local esptool:String = idfPath + "/components/esptool_py/esptool/esptool.py"
	Local command:String = CQuote(python) + " " + CQuote(esptool) + " --chip esp8266"
	Local port:String = Esp8266SerialPort()
	If port.length Then command :+ " --port " + CQuote(port)
	command :+ " --after hard_reset flash_id"
	Local output:String = PicoCaptureCommand(command)
	Local chip:String = Esp8266DeviceChip(output)
	Local flashSize:String = EmbeddedDeviceInfoField(output, "Detected flash size")
	If Not chip.length Or Not flashSize.length
		Local details:String = output.Trim()
		If Not details.length Then details = "esptool did not return device information"
		Throw "Unable to inspect an ESP8266 device: " + details
	End If
	Print "Detected ESP8266 device:"
	PrintEmbeddedDeviceInfoField("Port", port)
	PrintEmbeddedDeviceInfoField("Chip", chip)
	PrintEmbeddedDeviceInfoField("Features", EmbeddedDeviceInfoField(output, "Features"))
	PrintEmbeddedDeviceInfoField("Flash", flashSize)
	PrintEmbeddedDeviceInfoField("Flash manufacturer", EmbeddedDeviceInfoField(output, "Manufacturer"))
	PrintEmbeddedDeviceInfoField("Flash device", EmbeddedDeviceInfoField(output, "Device"))
	PrintEmbeddedDeviceInfoField("MAC", EmbeddedDeviceInfoField(output, "MAC"))
	If opt_target_board_set
		Print ""
		Print "Selected build configuration:"
		PrintEsp8266BoardProfile(False)
		If flashSize.ToLower().Replace(" ", "") <> "4mb" Then Print "  Warning: the selected profile expects 4MB flash."
	End If
End Function

Function ReportEsp32DeviceInfo()
	Local idfPath:String = Esp32IdfPath()
	Local idfToolsRoot:String = Esp32ToolsRoot(idfPath)
	Local python:String = Esp32Python(idfPath, idfToolsRoot)
	Local command:String = CQuote(python) + " -m esptool --chip auto"
	Local configuredPort:String = Esp32SerialPort()
	If configuredPort.length Then command :+ " -p " + CQuote(configuredPort)
	command :+ " --after hard-reset flash-id"

	Local output:String = PicoCaptureCommand(command)
	Local chip:String = EmbeddedDeviceInfoField(output, "Chip type")
	Local flashSize:String = EmbeddedDeviceInfoField(output, "Detected flash size")
	If Not chip.length Or Not flashSize.length
		Local details:String = output.Trim()
		If Not details.length Then details = "esptool did not return device information"
		Throw "Unable to inspect an ESP32 device: " + details
	End If

	Print "Detected ESP32 device:"
	PrintEmbeddedDeviceInfoField("Port", Esp32DeviceInfoPort(output))
	PrintEmbeddedDeviceInfoField("Chip", chip)
	PrintEmbeddedDeviceInfoField("Features", EmbeddedDeviceInfoField(output, "Features"))
	PrintEmbeddedDeviceInfoField("Crystal", EmbeddedDeviceInfoField(output, "Crystal frequency"))
	PrintEmbeddedDeviceInfoField("USB", EmbeddedDeviceInfoField(output, "USB mode"))
	PrintEmbeddedDeviceInfoField("Flash", flashSize)
	PrintEmbeddedDeviceInfoField("Flash manufacturer", EmbeddedDeviceInfoField(output, "Manufacturer"))
	PrintEmbeddedDeviceInfoField("Flash device", EmbeddedDeviceInfoField(output, "Device"))
	PrintEmbeddedDeviceInfoField("Flash bus", EmbeddedDeviceInfoField(output, "Flash type set in eFuse"))
	PrintEmbeddedDeviceInfoField("Flash voltage", EmbeddedDeviceInfoField(output, "Flash voltage set by eFuse"))
	PrintEmbeddedDeviceInfoField("MAC", EmbeddedDeviceInfoField(output, "MAC"))

	Local profile:String = Esp32ConfiguredBoardProfile()
	If profile.length
		Print ""
		Print "Selected build configuration:"
		Local board:TEsp32BoardProfile = Esp32BoardProfiles().Find(profile)
		PrintEsp32BoardProfile(board, False)
		Local configuredFlash:String = board.flashSize
		If configuredFlash.length And Esp32FlashSizeComparable(configuredFlash) <> Esp32FlashSizeComparable(flashSize)
			Print "  Warning: the selected profile's image flash size differs from the detected device."
		End If
		Local detectedTarget:String = Esp32DetectedTarget(chip)
		If detectedTarget <> board.idfTarget Then Print "  Warning: the selected profile targets " + board.idfTarget + " but the connected chip is " + chip + "."
		If Not board.pins.IsEmpty() Then Print "  Run 'bmk boardinfo -l esp32 -board " + board.name + "' for its buses, resources and pin map."
	End If
End Function

Function PicoDeviceInfoTool:String()
	Local platform:String = PicoHostPlatform()
	Local picoSdk:String = RequirePicoDirectory("the Pico SDK", "pico.sdk", "PICO_SDK_PATH", "sdk", [""])
	Local picoSdkVersion:String = StripDir(picoSdk.Replace("\", "/"))
	Return RequirePicoExecutable("picotool", "pico.picotool", "PICOTOOL_DIR", "picotool", "picotool", PicoToolManagedSuffixes("picotool", platform), picoSdkVersion)
End Function

Function ReportPicoDeviceInfo()
	Local output:String = PicoCaptureCommand(CQuote(PicoDeviceInfoTool()) + " info -a -f")
	Local chip:String = EmbeddedDeviceInfoField(output, "type", "device information")
	Local flashSize:String = EmbeddedDeviceInfoField(output, "flash size", "device information")
	If Not chip.length Or Not flashSize.length
		Local details:String = output.Trim()
		If Not details.length Then details = "picotool did not return device information"
		Throw "Unable to inspect a Pico device: " + details
	End If

	Print "Detected Pico device:"
	PrintEmbeddedDeviceInfoField("Chip", chip)
	PrintEmbeddedDeviceInfoField("Revision", EmbeddedDeviceInfoField(output, "revision", "device information"))
	PrintEmbeddedDeviceInfoField("Flash", flashSize)
	PrintEmbeddedDeviceInfoField("Flash ID", EmbeddedDeviceInfoField(output, "flash id", "device information"))
	PrintEmbeddedDeviceInfoField("Chip ID", EmbeddedDeviceInfoField(output, "chip id", "device information"))
	PrintEmbeddedDeviceInfoField("Boot architecture", EmbeddedDeviceInfoField(output, "boot architecture", "device information"))

	If opt_target_board_set
		Print ""
		Print "Selected build configuration:"
		Print "  Board profile: " + ValidatePicoBoardName(opt_target_board)
	End If
End Function

Function Nrf52UsbModeFromIoreg:Int(output:String)
	Local active:Int
	Local vendor:Int = -1
	Local product:Int = -1
	For Local line:String = EachIn output.Replace("~r", "").Split("~n")
		If line.Find("+-o ") >= 0 Then
			active = line.Find("<class IOUSBHostDevice") >= 0
			vendor = -1
			product = -1
		Else If active
			Local equals:Int = line.Find("=")
			If equals < 0 Then Continue
			If line.Find("~qidVendor~q") >= 0 Then vendor = Int(line[equals + 1..].Trim())
			If line.Find("~qidProduct~q") >= 0 Then product = Int(line[equals + 1..].Trim())
			If vendor = 12259 And product = 4 Then Return 1
			If vendor = 9114 And product = 179 Then Return 2
		End If
	Next
	Return 0
End Function

Function ReportNrf52DeviceInfo()
	Print "nRF52 device inspection:"
	Local observed:Int
	If PicoHostPlatform() = "macos" Then
		Local mode:Int = Nrf52UsbModeFromIoreg(PicoCaptureCommand("/usr/sbin/ioreg -p IOUSB -l -w 0"))
		Select mode
			Case 1
				Print "  USB: Zephyr CDC application (2FE3:0004; generic identity)"
				observed = True
			Case 2
				Print "  USB: nice!nano UF2 bootloader (239A:00B3)"
				observed = True
		End Select
	End If
	Local uf2Root:String = PicoConfiguredPath("nrf52.uf2", "NRF52_UF2_PATH")
	If Not uf2Root.length And PicoHostPlatform() = "macos" Then uf2Root = "/Volumes/NICENANO"
	If uf2Root.length And FileType(uf2Root + "/INFO_UF2.TXT") = FILETYPE_FILE Then
		Local info:String = LoadText(uf2Root + "/INFO_UF2.TXT")
		Local boardId:String = EmbeddedDeviceInfoField(info, "Board-ID")
		If boardId = "nRF52840-nicenano" Then
			Print "  UF2 drive: " + uf2Root
			Print "  Board-ID: " + boardId
			PrintEmbeddedDeviceInfoField("Model", EmbeddedDeviceInfoField(info, "Model"))
			PrintEmbeddedDeviceInfoField("SoftDevice", EmbeddedDeviceInfoField(info, "SoftDevice"))
			observed = True
		Else
			Print "  UF2 drive: " + uf2Root + " (unexpected Board-ID: " + boardId + ")"
		End If
	End If
	If Not observed Then Print "  No known nRF52 USB identity or UF2 drive was found."
	Print "  SoC device ID and reset cause require an on-device NRF52.System.Device program."
	If opt_target_board_set Then Print "  Selected board profile: " + opt_target_board
End Function

Function ReportEmbeddedDeviceInfo(args:String[])
	If args.length Then CmdError "deviceinfo does not accept a source file"
	Select processor.Platform()
		Case "android"
			ReportAndroidDeviceInfo()
		Case "ios"
			ReportIOSDeviceInfo()
		Case "esp32"
			ReportEsp32DeviceInfo()
		Case "esp8266"
			ReportEsp8266DeviceInfo()
		Case "pico"
			ReportPicoDeviceInfo()
		Case "nrf52"
			ReportNrf52DeviceInfo()
		Default
			CmdError "deviceinfo is available for android, ios, pico, esp32, esp8266 and nrf52 targets"
	End Select
End Function
