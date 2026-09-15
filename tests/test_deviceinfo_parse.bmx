SuperStrict

Framework BRL.StandardIO

Import "../bmk_deviceinfo_parse.bmx"

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

Print "bmk embedded device-info parser tests passed"
