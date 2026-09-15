SuperStrict

Framework BRL.StandardIO

Import "../bmk_esp32_profiles.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Local profile:TEsp32BoardProfile = ParseEsp32BoardProfile("format=1~n" + ..
	"[board]~n" + ..
	"name=Example S3 Board~n" + ..
	"vendor=Example Vendor~n" + ..
	"kind=board~n" + ..
	"aliases=example-s3~n" + ..
	"target=esp32s3~n" + ..
	"module=ESP32-S3-MINI-1-N8~n" + ..
	"[build]~n" + ..
	"flash_size=8MiB~n" + ..
	"sdkconfig_defaults=sdkconfig.defaults~n" + ..
	"partitions=partitions.csv~n" + ..
	"[console]~n" + ..
	"transport=usb_serial_jtag~n" + ..
	"[bus.i2c.default]~n" + ..
	"controller=0~n" + ..
	"sda=SDA~n" + ..
	"scl=SCL~n" + ..
	"[resource.rgb_led]~n" + ..
	"type=ws2812c~n" + ..
	"pin=LED~n", "example_s3", "fixture")

ParseEsp32BoardPins("name,gpio,connector,position~nSDA,47,J1,1~nSCL,48,J1,2~nLED,8,,~n", profile, "pin fixture")
ValidateEsp32BoardPinReferences(profile, "fixture")
Check(profile.displayName = "Example S3 Board", "display name is loaded")
Check(profile.idfTarget = "esp32s3", "IDF target is loaded")
Check(profile.flashSize = "8MiB", "flash size is loaded")
Check(profile.partitions = "partitions.csv", "partition table is loaded")
Check(profile.consoleTransport = "usb_serial_jtag", "console transport is loaded")
Check(profile.EsptoolResetMode() = "usb-reset", "native USB console selects USB reset for flashing")
Check(profile.PinNumber("sda") = 47, "pin names resolve case-insensitively")
Check(profile.Pin("SCL").connector = "J1", "physical connector metadata is loaded")
Check(String(profile.Bus("bus.i2c.default").ValueForKey("scl")) = "SCL", "default bus is loaded")

Local registry:TEsp32BoardProfileRegistry = New TEsp32BoardProfileRegistry
registry.Add(profile, "fixture")
Check(registry.Find("example-s3") = profile, "aliases resolve to the canonical profile")
Check(registry.Names() = "example_s3", "canonical names are reported")

Local uartProfile:TEsp32BoardProfile = ParseEsp32BoardProfile("format=1~n[board]~nname=UART Board~nkind=board~ntarget=esp32s3~n[console]~ntransport=uart~n", "uart_board", "fixture")
Check(uartProfile.EsptoolResetMode() = "", "UART console retains ESP-IDF's default reset mode")

Local rejected:Int
Try
	ParseEsp32BoardProfile("format=1~n[board]~nname=Bad~nkind=board~ntarget=esp32s3~nunknown=value~n", "bad", "bad fixture")
Catch failure:Object
	rejected = True
End Try
Check(rejected, "unknown profile fields are rejected")

rejected = False
Try
	ParseEsp32BoardProfile("format=1~n[board]~nname=Bad~nname=Duplicate~nkind=board~ntarget=esp32s3~n", "bad", "bad fixture")
Catch failure:Object
	rejected = True
End Try
Check(rejected, "duplicate scalar fields are rejected")

rejected = False
Try
	ParseEsp32BoardProfile("format=1~n[board]~nname=Bad~nkind=board~ntarget=esp32s3~n[bus.i2c.default]~nmagic=value~n", "bad", "bad fixture")
Catch failure:Object
	rejected = True
End Try
Check(rejected, "unknown bus fields are rejected")

rejected = False
Try
	ParseEsp32BoardProfile("format=1~n[board]~nname=Bad~nkind=board~ntarget=esp32s3~n[build]~nsdkconfig_defaults=../outside~n", "bad", "bad fixture")
Catch failure:Object
	rejected = True
End Try
Check(rejected, "unsafe defaults paths are rejected")

rejected = False
Try
	ParseEsp32BoardProfile("format=1~n[board]~nname=Bad~nkind=board~ntarget=esp32s3~n[build]~npartitions=../outside.csv~n", "bad", "bad fixture")
Catch failure:Object
	rejected = True
End Try
Check(rejected, "unsafe partition paths are rejected")

rejected = False
Try
	Local badReference:TEsp32BoardProfile = ParseEsp32BoardProfile("format=1~n[board]~nname=Bad~nkind=board~ntarget=esp32s3~n[resource.led]~npin=MISSING~n", "bad", "bad fixture")
	ValidateEsp32BoardPinReferences(badReference, "bad fixture")
Catch failure:Object
	rejected = True
End Try
Check(rejected, "unknown pin references are rejected")

rejected = False
Try
	Local badConstraint:TEsp32BoardProfile = ParseEsp32BoardProfile("format=1~n[board]~nname=Bad~nkind=board~ntarget=esp32s3~n[constraint.reserved]~npins=MISSING~nstatus=occupied~n", "bad", "bad fixture")
	ValidateEsp32BoardPinReferences(badConstraint, "bad fixture")
Catch failure:Object
	rejected = True
End Try
Check(rejected, "unknown constraint pin references are rejected")

Print "bmk ESP32 board-profile tests passed"
