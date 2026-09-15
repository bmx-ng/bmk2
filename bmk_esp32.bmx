' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "bmk_pico.bmx"
Import "bmk_esp32_profiles.bmx"
Include "bmk_esp32_paths.bmx"

Global esp32BoardProfiles:TEsp32BoardProfileRegistry

Function LoadEsp32BoardProfileRoot(registry:TEsp32BoardProfileRegistry, root:String, required:Int)
	If FileType(root) <> FILETYPE_DIR
		If required Then Throw "ESP32 board profile directory was not found: " + root
		Return
	End If
	For Local name:String = EachIn LoadDir(root)
		Local directory:String = root + "/" + name
		If FileType(directory) <> FILETYPE_DIR Or FileType(directory + "/board.ini") <> FILETYPE_FILE Then Continue
		registry.Add(LoadEsp32BoardProfile(directory, name), directory + "/board.ini")
	Next
End Function

Function Esp32BoardProfiles:TEsp32BoardProfileRegistry()
	If esp32BoardProfiles Then Return esp32BoardProfiles
	esp32BoardProfiles = New TEsp32BoardProfileRegistry
	LoadEsp32BoardProfileRoot(esp32BoardProfiles, BlitzMaxPath() + "/mod/esp32.mod/boards", True)
	Local configured:String = processor.Option("esp32.board.dirs", "").Trim()
	If Not configured.length Then configured = getenv_("ESP32_BOARD_DIRS").Trim()
	If configured.length
		Local separator:String = ":"
		If PicoHostPlatform() = "win32" Then separator = ";"
		For Local root:String = EachIn configured.Split(separator)
			root = root.Trim()
			If root.length Then LoadEsp32BoardProfileRoot(esp32BoardProfiles, root, True)
		Next
	End If
	If esp32BoardProfiles.profiles.IsEmpty() Then Throw "No ESP32 board profiles were found"
	Return esp32BoardProfiles
End Function

Function Esp32IdfPath:String()
	Local configured:String = processor.Option("esp32.idf", "").Trim()
	If Not configured.length Then configured = getenv_("IDF_PATH").Trim()
	If configured.length Then
		If FileType(configured + "/tools/idf.py") = FILETYPE_FILE Then Return RealPath(configured)
		Throw "The configured ESP-IDF path does not contain tools/idf.py: " + configured
	End If

	Local installationsRoot:String = PicoUserHome(PicoHostPlatform()) + "/.espressif"
	Local selected:String
	For Local name:String = EachIn LoadDir(installationsRoot)
		If Not name.StartsWith("v") Then Continue
		Local candidate:String = installationsRoot + "/" + name + "/esp-idf"
		If FileType(candidate + "/tools/idf.py") <> FILETYPE_FILE Then Continue
		If Not selected.length Or name > StripDir(ExtractDir(selected)) Then selected = candidate
	Next
	If selected.length Then Return RealPath(selected)
	Throw "Unable to locate ESP-IDF. Set IDF_PATH or esp32.idf in custom.bmk."
End Function

Function Esp32ToolsRoot:String(idfPath:String)
	Local optionValue:String = processor.Option("esp32.tools", "").Trim()
	Local configured:String = PicoPreferredConfiguredValue(optionValue, getenv_("IDF_TOOLS_PATH"))
	If configured.length
		Local explicitRoot:String = Esp32ToolsRootCandidate(configured)
		If explicitRoot.length Then Return explicitRoot
		If optionValue.length Then Throw "The esp32.tools path does not contain an ESP-IDF tools directory: " + configured
		Throw "IDF_TOOLS_PATH does not contain an ESP-IDF tools directory: " + configured
	End If
	Local root:String = Esp32ResolveToolsRoot("", PicoUserHome(PicoHostPlatform()), idfPath)
	If root.length Then Return root
	Throw "Unable to locate the ESP-IDF tools root. Set IDF_TOOLS_PATH; its default is the .espressif directory in the user's home."
End Function

Function Esp32Python:String(idfPath:String, toolsRoot:String)
	Local optionValue:String = processor.Option("esp32.python", "").Trim()
	Local configured:String = PicoPreferredConfiguredValue(optionValue, getenv_("IDF_PYTHON_ENV_PATH"))
	If configured.length
		Local explicitPython:String = Esp32PythonExecutable(configured, PicoHostPlatform())
		If explicitPython.length Then Return explicitPython
		If optionValue.length Then Throw "The esp32.python path does not contain a Python executable: " + configured
		Throw "IDF_PYTHON_ENV_PATH does not contain a Python executable: " + configured
	End If
	Local version:String = Esp32IdfVersion(idfPath)
	If Not version.length Then Throw "Unable to determine the ESP-IDF version from " + idfPath + "/tools/cmake/version.cmake"
	Local python:String = Esp32ResolvePython("", toolsRoot, idfPath, PicoHostPlatform())
	If python.length Then Return python
	Throw "Unable to locate the ESP-IDF " + Esp32IdfMajorMinor(version) + " Python environment under " + toolsRoot + "/python_env or " + toolsRoot + "/python"
End Function

Function Esp32BoardProfile:String()
	Local board:String
	If opt_target_board_set Then
		board = opt_target_board.Trim().ToLower()
	Else
		board = processor.Option("esp32.target", "esp32").Trim().ToLower()
	End If
	Local profile:TEsp32BoardProfile = Esp32BoardProfiles().Find(board)
	If profile Then Return profile.name
	Throw "Unsupported ESP32 board profile: " + board + ". Available profiles: " + Esp32BoardProfiles().Names() + "."
End Function

Function Esp32IdfTarget:String(boardProfile:String)
	Local profile:TEsp32BoardProfile = Esp32BoardProfiles().Find(boardProfile)
	If Not profile Then Throw "Unknown ESP32 board profile: " + boardProfile
	Return profile.idfTarget
End Function

Function Esp32TargetArchitecture:String(idfTarget:String)
	Select idfTarget.ToLower()
		Case "esp32", "esp32s2", "esp32s3"
			Return "xtensa"
		Case "esp32c2", "esp32c3", "esp32c5", "esp32c6", "esp32h2", "esp32p4"
			Return "riscv32"
	End Select
	Throw "Unknown ESP-IDF target architecture: " + idfTarget
End Function

Function Esp32BoardMapValue:String(values:TMap, key:String)
	If Not values Then Return ""
	Return String(values.ValueForKey(key))
End Function

Function Esp32BoardUnsigned:Int(profile:TEsp32BoardProfile, section:String, values:TMap, key:String, required:Int = True)
	Local value:String = Esp32BoardMapValue(values, key)
	If Not value.length
		If required Then Throw "ESP32 board profile '" + profile.name + "' " + section + " has no " + key
		Return -1
	End If
	Local result:Int = Esp32ProfileUnsigned(value)
	If result < 0 Then Throw "ESP32 board profile '" + profile.name + "' " + section + " has invalid " + key + "='" + value + "'"
	Return result
End Function

Function Esp32ProfileByteSize:Long(value:String)
	Local normalized:String = value.Trim().ToLower()
	If Not normalized.length Or normalized = "none" Or normalized = "0" Then Return 0
	Local parsed:String = ParsePicoHeapSize(normalized)
	If parsed = "auto" Then Return 0
	Return Long(parsed)
End Function

Function GenerateEsp32BoardHeader:String(profile:TEsp32BoardProfile, buildDir:String)
	Local includeDirectory:String = buildDir + "/board"
	CreateDir(includeDirectory, True)
	Local text:String = "#ifndef BLITZMAX_ESP32_BOARD_H~n#define BLITZMAX_ESP32_BOARD_H~n~n"
	text :+ "#define BMX_ESP32_BOARD_PROFILE ~q" + profile.name + "~q~n"
	Local i2c:TMap = profile.Bus("bus.i2c.default")
	If i2c
		text :+ "#define BMX_ESP32_BOARD_I2C_CONTROLLER " + Esp32BoardUnsigned(profile, "bus.i2c.default", i2c, "controller") + "~n"
		text :+ "#define BMX_ESP32_BOARD_I2C_SDA " + profile.PinNumber(Esp32BoardMapValue(i2c, "sda")) + "u~n"
		text :+ "#define BMX_ESP32_BOARD_I2C_SCL " + profile.PinNumber(Esp32BoardMapValue(i2c, "scl")) + "u~n"
	End If
	Local spi:TMap = profile.Bus("bus.spi.default")
	If spi
		text :+ "#define BMX_ESP32_BOARD_SPI_CONTROLLER " + Esp32BoardUnsigned(profile, "bus.spi.default", spi, "controller") + "~n"
		text :+ "#define BMX_ESP32_BOARD_SPI_MISO " + profile.PinNumber(Esp32BoardMapValue(spi, "miso")) + "u~n"
		text :+ "#define BMX_ESP32_BOARD_SPI_MOSI " + profile.PinNumber(Esp32BoardMapValue(spi, "mosi")) + "u~n"
		text :+ "#define BMX_ESP32_BOARD_SPI_CLOCK " + profile.PinNumber(Esp32BoardMapValue(spi, "clock")) + "u~n"
		Local chipSelect:String = Esp32BoardMapValue(spi, "chip_select")
		If chipSelect.length Then text :+ "#define BMX_ESP32_BOARD_SPI_CHIP_SELECT " + profile.PinNumber(chipSelect) + "u~n"
	End If
	Local microsd:TMap = TMap(profile.resources.ValueForKey("resource.microsd"))
	If microsd
		text :+ "#define BMX_ESP32_BOARD_SDMMC_CONTROLLER " + Esp32BoardUnsigned(profile, "resource.microsd", microsd, "controller") + "~n"
		text :+ "#define BMX_ESP32_BOARD_SDMMC_CLOCK " + profile.PinNumber(Esp32BoardMapValue(microsd, "clock")) + "u~n"
		text :+ "#define BMX_ESP32_BOARD_SDMMC_COMMAND " + profile.PinNumber(Esp32BoardMapValue(microsd, "command")) + "u~n"
		text :+ "#define BMX_ESP32_BOARD_SDMMC_DATA0 " + profile.PinNumber(Esp32BoardMapValue(microsd, "data0")) + "u~n"
		Local data3:String = Esp32BoardMapValue(microsd, "data3")
		If data3.length Then text :+ "#define BMX_ESP32_BOARD_SDMMC_DATA3 " + profile.PinNumber(data3) + "u~n"
	End If
	text :+ "~n#endif~n"
	Local path:String = includeDirectory + "/blitzmax_esp32_board.h"
	SaveText(text, path)
	Return includeDirectory
End Function

Function GenerateEsp32SdkconfigDefaults:String(profile:TEsp32BoardProfile, buildDir:String, bleEnabled:Int = False)
	Local source:String
	If profile.sdkconfigDefaults.length Then source = LoadText(profile.directory + "/" + profile.sdkconfigDefaults)
	If bleEnabled
		If source.length And Not source.EndsWith("~n") Then source :+ "~n"
		source :+ "CONFIG_BT_ENABLED=y~n"
		If profile.idfTarget = "esp32"
			source :+ "CONFIG_BTDM_CTRL_MODE_BLE_ONLY=y~n"
			source :+ "CONFIG_BTDM_CTRL_MODE_BR_EDR_ONLY=n~n"
			source :+ "CONFIG_BTDM_CTRL_MODE_BTDM=n~n"
		End If
		source :+ "CONFIG_BT_BLUEDROID_ENABLED=n~n"
		source :+ "CONFIG_BT_NIMBLE_ENABLED=y~n"
		source :+ "CONFIG_BT_NIMBLE_NVS_PERSIST=y~n"
	End If
	If Not profile.partitions.length And Not bleEnabled Then
		If profile.sdkconfigDefaults.length Then Return profile.directory + "/" + profile.sdkconfigDefaults
		Return ""
	End If
	If profile.partitions.length
		Local partitionPath:String = RealPath(profile.directory + "/" + profile.partitions).Replace("\", "/")
		If source.length And Not source.EndsWith("~n") Then source :+ "~n"
		source :+ "CONFIG_PARTITION_TABLE_CUSTOM=y~n"
		source :+ "CONFIG_PARTITION_TABLE_CUSTOM_FILENAME=~q" + partitionPath + "~q~n"
	End If
	Local path:String = buildDir + "/sdkconfig.board.defaults"
	If Not SaveText(source, path) Then Throw "Unable to write ESP32 board sdkconfig defaults: " + path
	Return path
End Function

Function Esp32ToolchainBin:String(idfToolsPath:String, targetArchitecture:String, idfTarget:String)
	Local toolName:String
	Local compilerName:String
	Select targetArchitecture
		Case "xtensa"
			toolName = "xtensa-esp-elf"
			compilerName = "xtensa-" + idfTarget + "-elf-gcc"
		Case "riscv32"
			toolName = "riscv32-esp-elf"
			compilerName = "riscv32-esp-elf-gcc"
		Default
			Throw "Unsupported ESP32 toolchain architecture: " + targetArchitecture
	End Select
	Local toolRoot:String = Esp32ToolDirectory(idfToolsPath, toolName)
	If Not toolRoot.length Then Throw "Unable to locate the ESP-IDF " + targetArchitecture + " toolchain under " + idfToolsPath
	Local selected:String
	For Local version:String = EachIn LoadDir(toolRoot)
		Local candidate:String = toolRoot + "/" + version + "/" + toolName + "/bin"
		If FileType(candidate + "/" + compilerName) <> FILETYPE_FILE Then Continue
		If Not selected.length Or version > StripDir(ExtractDir(ExtractDir(selected))) Then selected = candidate
	Next
	If selected.length Then Return selected
	Throw "Unable to locate the ESP-IDF " + targetArchitecture + " compiler under " + toolRoot
End Function

Function Esp32SerialPort:String()
	Local configured:String = processor.Option("esp32.port", "").Trim()
	If Not configured.length Then configured = getenv_("ESPPORT").Trim()
	Return configured
End Function

Function MakeEsp32Application(mainSource:String, outputPath:String, compileOnly:Int)
	If compileOnly Then Throw "The ESP32 target currently produces complete ESP-IDF applications only"
	If processor.BCCVersion() <> "bcc2" Then Throw "The ESP32 target requires bcc2"
	Local boardProfile:String = Esp32BoardProfile()
	Local profile:TEsp32BoardProfile = Esp32BoardProfiles().Find(boardProfile)
	Local idfTarget:String = profile.idfTarget
	Local targetArchitecture:String = Esp32TargetArchitecture(idfTarget)
	If processor.CPU() <> targetArchitecture Then Throw "ESP-IDF target '" + idfTarget + "' requires the " + targetArchitecture + " architecture"

	Local arenaRegionOption:String = opt_pico_heap_region
	If Not opt_pico_heap_region_set Then arenaRegionOption = processor.Option("esp32.heap.region", "sram")
	Local arenaRegion:String = ParsePicoHeapRegion(arenaRegionOption)
	Local psramBytes:Long = Esp32ProfileByteSize(profile.psramSize)
	If arenaRegion = "psram" And psramBytes <= 0 Then
		Throw "ESP32 board profile '" + boardProfile + "' does not declare a fixed PSRAM capacity"
	End If
	Local arenaSize:String = ParsePicoHeapSize(opt_pico_heap)
	If arenaSize = "auto" Then
		If arenaRegion = "psram" Then
			Local automaticBytes:Long = psramBytes - 65536
			If automaticBytes < 1024 Then Throw "ESP32 PSRAM is too small for an automatic managed heap"
			arenaSize = String(automaticBytes)
		Else
			arenaSize = "65536"
		End If
	End If
	Local arenaBytes:Long = Long(arenaSize)
	If (arenaBytes & 15) Then arenaBytes = (arenaBytes + 15) & ~15:Long
	If arenaRegion = "psram" And arenaBytes > psramBytes Then
		Throw "ESP32 managed heap of " + arenaBytes + " bytes exceeds the profile PSRAM capacity of " + psramBytes + " bytes"
	End If
	arenaSize = String(arenaBytes)
	Local arenaInPSRAM:Int = arenaRegion = "psram"
	Local sdk:String = BlitzMaxPath()
	Local esp32ModuleRoot:String = sdk + "/mod/esp32.mod"
	Local blitzModuleRoot:String = sdk + "/mod/brl.mod/blitz.mod"
	Local bcc:String = sdk + "/bin/bcc"
	Local cmakeTemplate:String = esp32ModuleRoot + "/cmake/application"
	If FileType(esp32ModuleRoot) <> FILETYPE_DIR Then Throw "ESP32 modules were not found at " + esp32ModuleRoot
	If FileType(bcc) <> FILETYPE_FILE Then Throw "bcc2 was not found at " + bcc
	If FileType(cmakeTemplate + "/CMakeLists.txt") <> FILETYPE_FILE Then Throw "The ESP32 CMake application template is missing"

	Local idfPath:String = Esp32IdfPath()
	Local idfToolsRoot:String = Esp32ToolsRoot(idfPath)
	Local python:String = Esp32Python(idfPath, idfToolsRoot)
	Local pythonEnvironment:String = ExtractDir(ExtractDir(python))
	Local idfVersion:String = Esp32IdfVersion(idfPath)
	Local toolchainBin:String = Esp32ToolchainBin(idfToolsRoot, targetArchitecture, idfTarget)
	Local idfPy:String = idfPath + "/tools/idf.py"

	Local outputBase:String = outputPath
	Select ExtractExt(outputBase).ToLower()
		Case "elf", "bin"
			outputBase = StripExt(outputBase)
	End Select
	Local outputDirectory:String = ExtractDir(outputBase)
	If outputDirectory.length And FileType(outputDirectory) = FILETYPE_NONE Then CreateDir(outputDirectory, True)
	Local outputName:String = StripDir(outputBase)
	Local buildVariant:String = PicoBuildModeName()
	Local buildDir:String = ExtractDir(mainSource) + "/.bmx/" + StripDir(StripExt(mainSource)) + "." + buildVariant + ".esp32." + targetArchitecture + "." + boardProfile
	CreateDir(buildDir, True)
	Local compilerBuildRoot:String = buildDir + "/bcc"
	CreateDir(compilerBuildRoot, True)
	Local boardInclude:String = GenerateEsp32BoardHeader(profile, buildDir)

	GeneratePicoInterface(bcc, sdk, "brl.blitz", blitzModuleRoot + "/blitz.bmx", blitzModuleRoot + "/blitz." + EmbeddedTargetMung() + ".i")

	Local applicationUnits:TList
	Local units:TList = DiscoverPicoModules(mainSource, applicationUnits)
	Local moduleInitializers:String = JoinPicoModuleField(units, "initialize")
	Local bleEnabled:Int = moduleInitializers.Find("__bb_embedded_network_ble_ble") >= 0
	Local nativeLinkOptions:TList
	Local nativeImports:TList = DiscoverPicoNativeImports(mainSource, units, nativeLinkOptions)
	Local generatedModuleSources:String[] = New String[0]
	Local specializationOwners:TMap = New TMap
	Local unitIndex:Int
	For Local unit:TPicoModuleUnit = EachIn units
		Local bundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, unit.source, compilerBuildRoot + "/module_" + unitIndex, "module.c", unit.name, unit.sourceUnitPath, unit.interfacePath, "", False, "", PicoRuntimeHeaderPath(unit.source))
		AppendPicoBundleSources(bundle, generatedModuleSources, specializationOwners)
		unitIndex :+ 1
	Next

	Local generatedApplicationSources:String[] = New String[0]
	Local applicationIdentity:String = Bcc2ApplicationIdentity(mainSource)
	Local frameworkModule:String = ParseSourceFile(mainSource).framewk
	Local applicationUnitIndex:Int
	For Local applicationUnit:TPicoApplicationUnit = EachIn applicationUnits
		Local bundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, applicationUnit.source, compilerBuildRoot + "/application_unit_" + applicationUnitIndex, "application_unit.c", applicationIdentity, applicationUnit.sourceUnitPath, applicationUnit.interfacePath, applicationIdentity, True, frameworkModule, PicoRuntimeHeaderPath(applicationUnit.source))
		AppendPicoBundleSources(bundle, generatedApplicationSources, specializationOwners)
		applicationUnitIndex :+ 1
	Next
	Local applicationBundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, mainSource, compilerBuildRoot + "/application", "application.c", "", "", "", applicationIdentity, False, "", PicoRuntimeHeaderPath(mainSource))
	AppendPicoBundleSources(applicationBundle, generatedApplicationSources, specializationOwners)
	Local nativeCMake:String = GeneratePicoNativeCMake(nativeImports, nativeLinkOptions, buildDir)
	Local sdkconfigDefaults:String = GenerateEsp32SdkconfigDefaults(profile, buildDir, bleEnabled)

	Local idfEnvironment:String = "PATH=" + CQuote(toolchainBin + PicoPathSeparator(PicoHostPlatform()) + getenv_("PATH")) + " IDF_PATH=" + CQuote(idfPath) + " IDF_TOOLS_PATH=" + CQuote(idfToolsRoot) + " IDF_PYTHON_ENV_PATH=" + CQuote(pythonEnvironment) + " ESP_IDF_VERSION=" + idfVersion + " IDF_VERSION=" + idfVersion + " "
	Local idfCommand:String = idfEnvironment + CQuote(python) + " " + CQuote(idfPy) + ..
		" -C " + CQuote(cmakeTemplate) + " -B " + CQuote(buildDir)
	Local command:String = idfCommand + ..
		" -DIDF_TARGET=" + idfTarget + ..
		" -DSDKCONFIG=" + CQuote(buildDir + "/sdkconfig") + ..
		" -DBLITZMAX_ESP32_SDK=" + CQuote(sdk) + ..
		" -DBLITZMAX_APPLICATION_ROOT=" + CQuote(ExtractDir(mainSource)) + ..
		" -DBLITZMAX_OUTPUT_NAME=" + outputName + ..
		" -DBLITZMAX_ESP32_ARENA_SIZE=" + arenaSize + ..
		" -DBLITZMAX_ESP32_ARENA_IN_PSRAM=" + arenaInPSRAM + ..
		" -DBLITZMAX_GENERATED_C=" + CQuote(JoinPicoPaths(generatedApplicationSources)) + ..
		" -DBLITZMAX_ESP32_GENERATED_SOURCES=" + CQuote(JoinPicoPaths(generatedModuleSources)) + ..
		" -DBLITZMAX_ESP32_NATIVE_CMAKE=" + CQuote(nativeCMake) + ..
		" -DBLITZMAX_ESP32_MODULE_INITIALIZERS=" + CQuote(moduleInitializers)
	command :+ " -DBLITZMAX_ESP32_BOARD_INCLUDE=" + CQuote(boardInclude)
	If sdkconfigDefaults.length Then command :+ " -DSDKCONFIG_DEFAULTS=" + CQuote(sdkconfigDefaults)
	command :+ " build"
	RunPicoCommand(command, "Building ESP-IDF application")

	Local builtBase:String = buildDir + "/" + outputName
	For Local extension:String = EachIn ["elf", "bin", "map"]
		If FileType(builtBase + "." + extension) = FILETYPE_FILE Then
			If Not CopyFile(builtBase + "." + extension, outputBase + "." + extension) Then Throw "Unable to publish ESP32 ." + extension + " output"
		End If
	Next
	If FileType(outputBase + ".elf") <> FILETYPE_FILE Then Throw "ESP-IDF did not produce " + outputName + ".elf"
	Print "ESP32 IDF target: " + idfTarget
	Print "ESP32 board profile: " + boardProfile
	Print "ESP32 managed heap: " + arenaSize + " bytes (" + arenaRegion.ToUpper() + ")"
	Print "ESP32 ELF: " + outputBase + ".elf"
	If FileType(outputBase + ".bin") = FILETYPE_FILE Then Print "ESP32 application image: " + outputBase + ".bin"
	If opt_execute Then
		Local serialPort:String = Esp32SerialPort()
		Local resetMode:String = profile.EsptoolResetMode()
		Local flashCommand:String
		If resetMode.length Then
			flashCommand = idfEnvironment + CQuote(python) + " -m esptool --chip " + idfTarget
			If serialPort.length Then flashCommand :+ " -p " + CQuote(serialPort)
			flashCommand :+ " --before " + resetMode + " --after hard-reset write-flash " + CQuote("@flash_args")
		Else
			flashCommand = idfCommand
			If serialPort.length Then flashCommand :+ " -p " + CQuote(serialPort)
			flashCommand :+ " flash"
		End If
		If serialPort.length Then
			Print "Uploading ESP32 firmware through " + serialPort
		Else
			Print "Uploading ESP32 firmware through the automatically detected serial port"
		End If
		If resetMode.length Then
			Local originalDirectory:String = CurrentDir()
			ChangeDir(buildDir)
			Try
				RunPicoCommand(flashCommand, "Uploading ESP32 firmware")
			Finally
				ChangeDir(originalDirectory)
			End Try
		Else
			RunPicoCommand(flashCommand, "Uploading ESP32 firmware")
		End If
		If profile.RequiresManualPostFlashReset()
			Print "ESP32 upload complete; press the board's RESET button to start the firmware."
		Else
			Print "ESP32 upload complete; firmware was started."
		End If
	End If
End Function
