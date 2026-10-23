SuperStrict

Framework BRL.StandardIO

Import "../bmk_deviceinfo_parse.bmx"
Import "../bmk_ios_device_parse.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local esp32Output:String = "Serial port /dev/cu.usbmodem101:~n" + ..
	"Connected to ESP32-S3 on /dev/cu.usbmodem101:~n" + ..
	"Chip type:          ESP32-S3 (QFN56) (revision v0.2)~n" + ..
	"Features:           Wi-Fi, BT 5 (LE), Dual Core + LP Core, 240MHz, Embedded Flash 8MB (GD)~n" + ..
	"Crystal frequency:  40MHz~n" + ..
	"USB mode:           USB-Serial/JTAG~n" + ..
	"MAC:                38:44:be:c7:e4:b0~n~n" + ..
	"Flash Memory Information:~n" + ..
	"Manufacturer: c8~n" + ..
	"Device: 4017~n" + ..
	"Detected flash size: 8MB~n" + ..
	"Flash type set in eFuse: quad (4 data lines)~n" + ..
	"Flash voltage set by eFuse: 3.3V~n"

Check(Esp32DeviceInfoPort(esp32Output) = "/dev/cu.usbmodem101", "ESP32 serial port is parsed")
Check(EmbeddedDeviceInfoField(esp32Output, "Chip type") = "ESP32-S3 (QFN56) (revision v0.2)", "ESP32 chip is parsed")
Check(EmbeddedDeviceInfoField(esp32Output, "Detected flash size") = "8MB", "ESP32 flash size is parsed")
Check(EmbeddedDeviceInfoField(esp32Output, "Flash type set in eFuse") = "quad (4 data lines)", "ESP32 flash bus is parsed")
Check(Esp32DetectedTarget(EmbeddedDeviceInfoField(esp32Output, "Chip type")) = "esp32s3", "ESP32 target is normalized from the detailed chip label")
Check(Esp32DetectedTarget("ESP32-C6FH4 (QFN32) (revision v0.2)") = "esp32c6", "ESP32 target is normalized from a package-qualified C6 chip label")
Check(Esp32DetectedTarget("ESP32-S31 (revision v0.0)") = "esp32s31", "ESP32-S31 is normalized without falling back to the original ESP32 target")
Check(Esp32DetectedTarget("ESP32-D0WD-V3 (revision v3.1)") = "esp32", "Original ESP32 package names map to the base target")

Local picoOutput:String = "Program Information~n" + ..
	" name:          sample~n" + ..
	" features:      USB stdin / stdout~n~n" + ..
	"Device Information~n" + ..
	" type:        RP2350~n" + ..
	" revision:    A4~n" + ..
	" flash size: 4096K~n" + ..
	" flash id:   0x0123456789abcdef~n"

Check(EmbeddedDeviceInfoField(picoOutput, "type", "device information") = "RP2350", "Pico chip is parsed")
Check(EmbeddedDeviceInfoField(picoOutput, "flash size", "device information") = "4096K", "Pico flash size is parsed")
Check(Not EmbeddedDeviceInfoField(picoOutput, "features", "device information").length, "Pico program fields do not leak into device information")

Local androidOutput:String = "List of devices attached~n" + ..
	"R58M1234567 device usb:1-2 product:a54x model:SM_A546B device:a54x transport_id:7~n" + ..
	"emulator-5554 offline transport_id:8~n" + ..
	"ZY22ABC unauthorized usb:1-3~n" + ..
	"LINUX123 no permissions (user in plugdev group)~n"
Local androidDevices:TAndroidDeviceInfo[] = ParseAndroidDevices(androidOutput)
Check(androidDevices.length = 4, "Android devices in every state are parsed")
Check(androidDevices[0].serial = "R58M1234567", "Android serial is parsed")
Check(androidDevices[0].state = "device", "Android authorization state is parsed")
Check(androidDevices[0].model = "SM A546B", "Android model is made readable")
Check(androidDevices[0].product = "a54x", "Android product is parsed")
Check(androidDevices[0].transportId = "7", "Android transport ID is parsed")
Check(androidDevices[1].state = "offline", "Offline Android devices remain visible")
Check(androidDevices[2].state = "unauthorized", "Unauthorized Android devices remain visible")
Check(androidDevices[3].state = "no permissions", "Android devices blocked by host permissions remain visible")

Local androidProperties:String = "[ro.product.manufacturer]: [Google]~n" + ..
	"[ro.product.model]: [Pixel 8]~n" + ..
	"[ro.build.version.release]: [16]~n" + ..
	"[ro.product.cpu.abilist]: [arm64-v8a,armeabi-v7a]~n"
Check(AndroidDeviceProperty(androidProperties, "ro.product.model") = "Pixel 8", "Android properties are parsed")
Check(AndroidDeviceProperty(androidProperties, "ro.build.version.release") = "16", "Android version is parsed")
Check(Not AndroidDeviceProperty(androidProperties, "ro.hardware").length, "Missing Android properties are empty")

Local iosJSON:String = "{" + ..
	"~qresult~q:{~qdevices~q:[" + ..
	"{~qidentifier~q:~qCORE-WIRED~q,~qproperties~q:{~qhardware~q:{~qmarketingName~q:~qiPad Air~q,~qplatform~q:~qiOS~q,~qproductType~q:~qiPad16,6~q,~qreality~q:~qphysical~q,~qserialNumber~q:~qSERIAL1~q,~qudid~q:~qUDID-WIRED~q},~qsoftware~q:{~qosVersionNumber~q:{~qstringValue~q:~q26.1~q},~qosBuildVersions~q:{~qbuildVersion~q:{~qname~q:~q23B85~q}}},~qstate~q:{~qbootState~q:~qbooted~q,~qdeveloperModeStatus~q:{~qenabled~q:{~qmode~q:1}},~qname~q:~qiPad Air m4~q},~qconnection~q:{~qpairingState~q:~qpaired~q,~qstate~q:~qdisconnected~q,~qtransportType~q:~qwired~q}}}," + ..
	"{~qidentifier~q:~qCORE-WIFI~q,~qproperties~q:{~qhardware~q:{~qmarketingName~q:~qiPad~q,~qplatform~q:~qiOS~q,~qproductType~q:~qiPad13,18~q,~qreality~q:~qphysical~q,~qudid~q:~qUDID-WIFI~q},~qsoftware~q:{~qosVersionNumber~q:{~qstringValue~q:~q26.0~q}},~qstate~q:{~qbootState~q:~qbooted~q,~qdeveloperModeStatus~q:{~qdisabled~q:{}},~qname~q:~qWi-Fi iPad~q},~qconnection~q:{~qpairingState~q:~qpaired~q,~qstate~q:~qdisconnected~q,~qtransportType~q:~qlocalNetwork~q}}}," + ..
	"{~qidentifier~q:~qSIMULATOR~q,~qproperties~q:{~qhardware~q:{~qplatform~q:~qiOS~q,~qreality~q:~qsimulated~q,~qudid~q:~qSIM-UDID~q},~qstate~q:{~qbootState~q:~qbooted~q,~qname~q:~qiPhone Simulator~q},~qconnection~q:{~qpairingState~q:~qpaired~q,~qtransportType~q:~qsameMachine~q}}}" + ..
	"]}}"
Local iosError:String
Local iosDevices:TIOSDeviceInfo[] = ParseIOSDevices(iosJSON, iosError)
Check(Not iosError.length, "CoreDevice JSON parses without an error")
Check(iosDevices.length = 3, "CoreDevice devices are parsed")
Check(iosDevices[0].name = "iPad Air m4", "iOS device name is parsed")
Check(iosDevices[0].udid = "UDID-WIRED", "iOS UDID is parsed")
Check(iosDevices[0].osVersion = "26.1", "iOS version is parsed")
Check(iosDevices[0].osBuild = "23B85", "iOS build is parsed")
Check(iosDevices[0].developerModeStatus = "enabled", "iOS Developer Mode is parsed")
Check(iosDevices[0].IsAvailable(), "A paired, booted physical iOS device is available even when its tunnel is disconnected")
Check(iosDevices[1].transportType = "localNetwork", "A Wi-Fi device transport is parsed")
Check(iosDevices[1].developerModeStatus = "disabled", "Disabled iOS Developer Mode is parsed")
Check(Not iosDevices[2].IsPhysicalIOS(), "Simulators are excluded from physical iOS devices")
Check(IOSDeviceMatches(iosDevices[0], "ipad air M4"), "iOS devices can be selected by name without case sensitivity")
Check(IOSDeviceMatches(iosDevices[0], "UDID-WIRED"), "iOS devices can be selected by UDID")

Local invalidIOSError:String
ParseIOSDevices("{", invalidIOSError)
Check(invalidIOSError.length > 0, "Malformed CoreDevice JSON reports an error")

Print "bmk device-info parser tests passed"
