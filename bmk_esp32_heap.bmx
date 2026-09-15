' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Const ESP32_AUTOMATIC_PSRAM_MINIMUM_RESERVE:Long = 256 * 1024

Function Esp32AutomaticPSRAMHeapBytes:Long(psramBytes:Long)
	Local reserveBytes:Long = psramBytes / 8
	If reserveBytes < ESP32_AUTOMATIC_PSRAM_MINIMUM_RESERVE Then
		reserveBytes = ESP32_AUTOMATIC_PSRAM_MINIMUM_RESERVE
	End If
	Local automaticBytes:Long = psramBytes - reserveBytes
	If automaticBytes < 1024 Then Return 0
	Return automaticBytes & ~15:Long
End Function
