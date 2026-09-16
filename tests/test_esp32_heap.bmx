SuperStrict

Framework BRL.StandardIO

Import "../bmk_esp32_heap.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Check(Esp32AutomaticPSRAMHeapBytes(8 * 1024 * 1024) = 7 * 1024 * 1024, "8 MiB PSRAM leaves a 1 MiB service reserve")
Check(Esp32AutomaticPSRAMHeapBytes(4 * 1024 * 1024) = 3584 * 1024, "4 MiB PSRAM leaves a 512 KiB service reserve")
Check(Esp32AutomaticPSRAMHeapBytes(2 * 1024 * 1024) = 1792 * 1024, "2 MiB PSRAM leaves the 256 KiB minimum reserve")
Check(Esp32AutomaticPSRAMHeapBytes(256 * 1024) = 0, "PSRAM no larger than the minimum reserve is rejected")

Print "bmk ESP32 managed-heap tests passed"
