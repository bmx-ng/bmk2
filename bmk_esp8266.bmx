' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import "bmk_pico.bmx"

Function Esp8266PythonExecutable:String(value:String)
	value = value.Trim()
	If FileType(value) = FILETYPE_FILE Then Return value
	If FileType(value) <> FILETYPE_DIR Then Return ""
	Local suffixes:String[]
	If PicoHostPlatform() = "win32" Then
		suffixes = ["/Scripts/python.exe", "/python.exe"]
	Else
		suffixes = ["/bin/python", "/bin/python3"]
	End If
	For Local suffix:String = EachIn suffixes
		If FileType(value + suffix) = FILETYPE_FILE Then Return value + suffix
	Next
	Return ""
End Function

Function Esp8266BoardProfile:String()
	Local board:String = "d1_mini_esp12f"
	If opt_target_board_set Then board = opt_target_board.Trim().ToLower()
	Select board
		Case "d1_mini_esp12f", "d1_mini", "esp12f_d1_mini"
			Return "d1_mini_esp12f"
	End Select
	Throw "Unsupported ESP8266 board profile: " + board + ". Available profile: d1_mini_esp12f"
End Function

Function Esp8266IdfPath:String()
	Local configured:String = processor.Option("esp8266.idf", "").Trim()
	If Not configured.length Then configured = getenv_("ESP8266_RTOS_SDK_PATH").Trim()
	If Not configured.length Then configured = PicoUserHome(PicoHostPlatform()) + "/.espressif/esp8266/v3.4/ESP8266_RTOS_SDK"
	If FileType(configured + "/tools/idf.py") = FILETYPE_FILE And FileType(configured + "/components/esp8266") = FILETYPE_DIR Then Return RealPath(configured)
	Throw "Unable to locate ESP8266 RTOS SDK 3.4. Set esp8266.idf in custom.bmk or ESP8266_RTOS_SDK_PATH."
End Function

Function Esp8266ToolsRoot:String()
	Local configured:String = processor.Option("esp8266.tools", "").Trim()
	If Not configured.length Then configured = getenv_("ESP8266_TOOLS_PATH").Trim()
	If Not configured.length Then configured = PicoUserHome(PicoHostPlatform()) + "/.espressif"
	If FileType(configured) = FILETYPE_DIR Then Return RealPath(configured)
	Throw "ESP8266 tools root was not found: " + configured
End Function

Function Esp8266Python:String(toolsRoot:String)
	Local configured:String = processor.Option("esp8266.python", "").Trim()
	If Not configured.length Then configured = getenv_("ESP8266_PYTHON").Trim()
	If configured.length
		Local executable:String = Esp8266PythonExecutable(configured)
		If executable.length Then Return executable
		Throw "The esp8266.python path does not contain a Python executable: " + configured
	End If
	Local root:String = toolsRoot + "/esp8266/python_env"
	If FileType(root) = FILETYPE_DIR
		Local selected:String
		Local selectedName:String
		For Local name:String = EachIn LoadDir(root)
			Local executable:String = Esp8266PythonExecutable(root + "/" + name)
			If executable.length And (Not selected.length Or name > selectedName)
				selected = executable
				selectedName = name
			End If
		Next
		If selected.length Then Return selected
	End If
	Throw "Unable to locate the ESP8266 SDK Python environment. Set esp8266.python in custom.bmk or ESP8266_PYTHON."
End Function

Function Esp8266ToolchainBin:String(toolsRoot:String)
	Local configured:String = processor.Option("esp8266.toolchain", "").Trim()
	If Not configured.length Then configured = getenv_("ESP8266_TOOLCHAIN_PATH").Trim()
	If configured.length
		For Local suffix:String = EachIn ["", "/bin", "/xtensa-lx106-elf/bin"]
			If FileType(configured + suffix + "/xtensa-lx106-elf-gcc") = FILETYPE_FILE Then Return RealPath(configured + suffix)
		Next
		Throw "The ESP8266 toolchain does not contain xtensa-lx106-elf-gcc: " + configured
	End If
	Local root:String = toolsRoot + "/tools/xtensa-lx106-elf"
	If FileType(root) <> FILETYPE_DIR Then root = toolsRoot + "/xtensa-lx106-elf"
	If FileType(root) = FILETYPE_DIR
		Local selected:String
		Local selectedVersion:String
		For Local version:String = EachIn LoadDir(root)
			For Local suffix:String = EachIn ["/xtensa-lx106-elf/bin", "/bin"]
				Local candidate:String = root + "/" + version + suffix
				If FileType(candidate + "/xtensa-lx106-elf-gcc") = FILETYPE_FILE And (Not selected.length Or version > selectedVersion)
					selected = candidate
					selectedVersion = version
				End If
			Next
		Next
		If selected.length Then Return RealPath(selected)
	End If
	Throw "Unable to locate the xtensa-lx106-elf toolchain. Set esp8266.toolchain or ESP8266_TOOLCHAIN_PATH."
End Function

Function Esp8266SerialPort:String()
	Local configured:String = processor.Option("esp8266.port", "").Trim()
	If Not configured.length Then configured = getenv_("ESP8266_PORT").Trim()
	Return configured
End Function

Function GenerateEsp8266SdkconfigDefaults:String(buildDir:String)
	Local source:String = "CONFIG_ESPTOOLPY_FLASHMODE_DIO=y~n" + ..
		"CONFIG_ESPTOOLPY_FLASHMODE=~qdio~q~n" + ..
		"CONFIG_SPI_FLASH_MODE=0x2~n" + ..
		"CONFIG_ESPTOOLPY_FLASHFREQ_40M=y~n" + ..
		"CONFIG_ESPTOOLPY_FLASHFREQ=~q40m~q~n" + ..
		"CONFIG_ESPTOOLPY_FLASHSIZE_4MB=y~n" + ..
		"CONFIG_ESPTOOLPY_FLASHSIZE=~q4MB~q~n" + ..
		"CONFIG_SPI_FLASH_SIZE=0x400000~n" + ..
		"CONFIG_ESP_CONSOLE_UART_BAUDRATE=74880~n" + ..
		"CONFIG_CONSOLE_UART_BAUDRATE=74880~n"
	Local path:String = buildDir + "/sdkconfig.defaults"
	If Not SaveText(source, path) Then Throw "Unable to write ESP8266 sdkconfig defaults: " + path
	Return path
End Function

Function MakeEsp8266Application(mainSource:String, outputPath:String, compileOnly:Int)
	If compileOnly Then Throw "The ESP8266 target currently produces complete RTOS SDK applications only"
	If processor.CPU() <> "xtensa" Then Throw "The ESP8266 target requires the xtensa architecture"
	If processor.BCCVersion() <> "bcc2" Then Throw "The ESP8266 target requires bcc2"
	If opt_embedded_gc_multicore Then Throw "The single-core ESP8266 does not support -gc-multicore"
	Local board:String = Esp8266BoardProfile()
	Local arenaSize:String = ParsePicoHeapSize(opt_pico_heap)
	If arenaSize = "auto" Then arenaSize = "12288"
	Local arenaBytes:Long = Long(arenaSize)
	If arenaBytes < 1024 Or arenaBytes > 32768 Then Throw "The ESP8266 managed heap must be between 1 KiB and 32 KiB"
	If arenaBytes & 15 Then arenaBytes = (arenaBytes + 15) & ~15:Long
	arenaSize = String(arenaBytes)

	Local sdk:String = BlitzMaxPath()
	Local moduleRoot:String = sdk + "/mod/esp8266.mod"
	Local blitzRoot:String = sdk + "/mod/brl.mod/blitz.mod"
	Local bcc:String = EmbeddedBccExecutablePath(sdk, PicoHostPlatform())
	Local template:String = moduleRoot + "/cmake/application"
	If FileType(template + "/CMakeLists.txt") <> FILETYPE_FILE Then Throw "The ESP8266 CMake application template is missing at " + template
	If FileType(bcc) <> FILETYPE_FILE Then Throw "bcc2 was not found at " + bcc

	Local idfPath:String = Esp8266IdfPath()
	Local toolsRoot:String = Esp8266ToolsRoot()
	Local python:String = Esp8266Python(toolsRoot)
	Local toolchainBin:String = Esp8266ToolchainBin(toolsRoot)
	Local outputBase:String = outputPath
	Select ExtractExt(outputBase).ToLower()
		Case "elf", "bin", "map"
			outputBase = StripExt(outputBase)
	End Select
	CreateDir(ExtractDir(outputBase), True)
	Local outputName:String = StripDir(outputBase)
	Local buildDir:String = ExtractDir(mainSource) + "/.bmx/" + StripDir(StripExt(mainSource)) + "." + PicoBuildModeName() + ".esp8266.xtensa." + board
	CreateDir(buildDir, True)
	Local compilerRoot:String = buildDir + "/bcc"
	CreateDir(compilerRoot, True)

	GeneratePicoInterface(bcc, sdk, "brl.blitz", blitzRoot + "/blitz.bmx", blitzRoot + "/blitz." + EmbeddedTargetMung() + ".i")
	Local applicationUnits:TList
	Local units:TList = DiscoverPicoModules(mainSource, applicationUnits)
	Local moduleInitializers:String = JoinPicoModuleField(units, "initialize")
	Local nativeLinkOptions:TList
	Local nativeImports:TList = DiscoverPicoNativeImports(mainSource, units, nativeLinkOptions)
	Local moduleSources:String[] = New String[0]
	Local applicationSources:String[] = New String[0]
	Local owners:TMap = New TMap
	Local index:Int
	For Local unit:TPicoModuleUnit = EachIn units
		Local bundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, unit.source, compilerRoot + "/module_" + index, "module.c", unit.name, unit.sourceUnitPath, unit.interfacePath, "", False, "", PicoRuntimeHeaderPath(unit.source))
		AppendPicoBundleSources(bundle, moduleSources, owners)
		index :+ 1
	Next
	Local applicationIdentity:String = Bcc2ApplicationIdentity(mainSource)
	Local frameworkModule:String = ParseSourceFile(mainSource).framewk
	index = 0
	For Local unit:TPicoApplicationUnit = EachIn applicationUnits
		Local bundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, unit.source, compilerRoot + "/application_unit_" + index, "application_unit.c", applicationIdentity, unit.sourceUnitPath, unit.interfacePath, applicationIdentity, True, frameworkModule, PicoRuntimeHeaderPath(unit.source))
		AppendPicoBundleSources(bundle, applicationSources, owners)
		index :+ 1
	Next
	Local applicationBundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, mainSource, compilerRoot + "/application", "application.c", "", "", "", applicationIdentity, False, "", PicoRuntimeHeaderPath(mainSource))
	AppendPicoBundleSources(applicationBundle, applicationSources, owners)
	Local nativeCmake:String = GeneratePicoNativeCMake(nativeImports, nativeLinkOptions, buildDir)
	Local sdkconfigDefaults:String = GenerateEsp8266SdkconfigDefaults(buildDir)
	Local sdkconfig:String = buildDir + "/sdkconfig"
	If FileType(sdkconfig) = FILETYPE_NONE And Not SaveText("", sdkconfig) Then Throw "Unable to create ESP8266 sdkconfig: " + sdkconfig

	Local environment:String = "PATH=" + CQuote(toolchainBin + PicoPathSeparator(PicoHostPlatform()) + ExtractDir(python) + PicoPathSeparator(PicoHostPlatform()) + getenv_("PATH")) + " IDF_PATH=" + CQuote(idfPath) + " PYTHON=" + CQuote(python) + " "
	Local command:String = environment + "cmake -G Ninja" + ..
		" -DPYTHON_DEPS_CHECKED=1 -DESP_PLATFORM=1 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DPROJECT_VER=1" + ..
		" -DPYTHON=" + CQuote(python) + ..
		" -DSDKCONFIG=" + CQuote(sdkconfig) + ..
		" -DSDKCONFIG_DEFAULTS=" + CQuote(sdkconfigDefaults) + ..
		" -DBLITZMAX_ESP8266_SDK=" + CQuote(sdk) + ..
		" -DBLITZMAX_APPLICATION_ROOT=" + CQuote(ExtractDir(mainSource)) + ..
		" -DBLITZMAX_OUTPUT_NAME=" + CQuote(outputName) + ..
		" -DBLITZMAX_ESP8266_ARENA_SIZE=" + arenaSize + ..
		" -DBLITZMAX_GENERATED_C=" + CQuote(JoinPicoPaths(applicationSources)) + ..
		" -DBLITZMAX_ESP8266_GENERATED_SOURCES=" + CQuote(JoinPicoPaths(moduleSources)) + ..
		" -DBLITZMAX_ESP8266_NATIVE_CMAKE=" + CQuote(nativeCmake) + ..
		" -DBLITZMAX_ESP8266_MODULE_INITIALIZERS=" + CQuote(moduleInitializers) + ..
		" -S " + CQuote(template) + " -B " + CQuote(buildDir)
	RunPicoCommand(command, "Configuring ESP8266 RTOS SDK application")
	RunPicoCommand(environment + "ninja -C " + CQuote(buildDir), "Building ESP8266 RTOS SDK application")

	Local builtBase:String = buildDir + "/" + outputName
	For Local extension:String = EachIn ["elf", "bin", "map"]
		If FileType(builtBase + "." + extension) = FILETYPE_FILE Then CopyFile(builtBase + "." + extension, outputBase + "." + extension)
	Next
	If FileType(outputBase + ".elf") <> FILETYPE_FILE Then Throw "ESP8266 RTOS SDK did not produce " + outputName + ".elf"
	Print "ESP8266 board profile: " + board
	Print "ESP8266 managed heap: " + arenaSize + " bytes (SRAM)"
	Print "ESP8266 console: 74880 baud"
	Print "ESP8266 ELF: " + outputBase + ".elf"
	If opt_execute
		Local idfCommand:String = environment + CQuote(python) + " " + CQuote(idfPath + "/tools/idf.py") + " -C " + CQuote(template) + " -B " + CQuote(buildDir)
		Local port:String = Esp8266SerialPort()
		If port.length Then idfCommand :+ " -p " + CQuote(port)
		RunPicoCommand(idfCommand + " flash", "Uploading ESP8266 firmware")
		Print "ESP8266 upload complete; firmware was started."
	End If
End Function
