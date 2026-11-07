SuperStrict

Import "bmk_pico.bmx"

Function Nrf52VirtualEnvironmentBin:String(zephyrBase:String)
	Local configured:String = PicoConfiguredPath("nrf52.venv", "NRF52_VENV")
	Local environment:String = configured
	If Not environment.length Then environment = ExtractDir(zephyrBase) + "/.venv"
	Local binDir:String = environment + "/bin"
	If PicoHostPlatform() = "win32" Then binDir = environment + "/Scripts"
	If FileType(binDir) = FILETYPE_DIR Then Return binDir
	If configured.length Then Throw "nRF52 Python virtual environment was not found: " + configured
	Return ""
End Function

Function Nrf52WestExecutable:String(venvBin:String)
	Local configured:String = PicoConfiguredPath("nrf52.west", "WEST")
	Local platform:String = PicoHostPlatform()
	If configured.length Then
		Local west:String = PicoExecutableFromValue(configured, "west", platform)
		If west.length Then Return west
		Throw "nRF52 west executable was not found at " + configured
	End If
	If venvBin.length Then
		Local west:String = PicoExecutableFromValue(venvBin, "west", platform)
		If west.length Then Return west
	End If
	Local west:String = PicoFindExecutableOnPath("west", getenv_("PATH"), platform)
	If west.length Then Return west
	Throw "Install west in the Zephyr virtual environment, or set nrf52.west in custom.bmk"
End Function

Function ReportNrf52BoardInfo(args:String[])
	If args.length Then CmdError "boardinfo does not accept a source file"
	Local board:String = "promicro_nrf52840"
	If opt_target_board_set Then board = ValidatePicoBoardName(opt_target_board)
	If board <> "promicro_nrf52840" Then Throw "Unsupported nRF52 board: " + board
	Print "Board: " + board
	Print "SoC: nRF52840 (Cortex-M4F, 1 MiB flash, 256 KiB RAM)"
	Print "Zephyr target: promicro_nrf52840/nrf52840/uf2"
	Print "Expected UF2 bootloader: nRF52840-nicenano (verified on one Tenstar Robot test unit)"
	Print "Application partition: 0x26000-0xEC000 (S140 v6 UF2 layout)"
	Print "Managed arena: 65536 bytes; main stack: 16384 bytes"
	Print "Carrier pin map, SWD access and battery circuitry: unverified"
End Function

Function MakeNrf52Application(mainSource:String, outputPath:String, compileOnly:Int)
	If compileOnly Then Throw "The nRF52 target currently produces complete Zephyr applications only"
	If processor.CPU() <> "arm" Then Throw "The nRF52 target requires the arm architecture"
	If processor.BCCVersion() <> "bcc2" Then Throw "The nRF52 target requires bcc2"
	If Not opt_release And Not PicoDebugBuild() Then Throw "Select -r or -d for an nRF52 application"
	If opt_embedded_gc_multicore Then Throw "The nRF52 target currently supports one managed thread"
	Local board:String = "promicro_nrf52840"
	If opt_target_board_set Then board = ValidatePicoBoardName(opt_target_board)
	If board <> "promicro_nrf52840" Then Throw "Unsupported nRF52 board: " + board + ". Available board: promicro_nrf52840"

	Local sdk:String = BlitzMaxPath()
	Local bcc:String = EmbeddedBccExecutablePath(sdk, PicoHostPlatform())
	Local blitzRoot:String = sdk + "/mod/brl.mod/blitz.mod"
	Local template:String = sdk + "/mod/nrf52.mod/cmake/application"
	If FileType(bcc) <> FILETYPE_FILE Then Throw "bcc2 was not found at " + bcc
	If FileType(template + "/CMakeLists.txt") <> FILETYPE_FILE Then Throw "The nRF52 Zephyr application template is missing at " + template

	Local zephyrBase:String = PicoConfiguredPath("nrf52.zephyr", "ZEPHYR_BASE")
	If Not zephyrBase.length Or FileType(zephyrBase + "/CMakeLists.txt") <> FILETYPE_FILE Then Throw "Set nrf52.zephyr in custom.bmk or ZEPHYR_BASE to a Zephyr checkout"
	Local sdkInstall:String = PicoConfiguredPath("nrf52.sdk", "ZEPHYR_SDK_INSTALL_DIR")
	If Not sdkInstall.length Or FileType(sdkInstall + "/sdk_version") <> FILETYPE_FILE Then Throw "Set nrf52.sdk in custom.bmk or ZEPHYR_SDK_INSTALL_DIR to a Zephyr SDK installation"
	Local overlay:String = PicoConfiguredPath("nrf52.overlay", "BMX_NRF52_EXTRA_OVERLAY_FILE")
	If overlay.length Then
		If FileType(overlay) <> FILETYPE_FILE Then Throw "nRF52 devicetree overlay was not found: " + overlay
		overlay = RealPath(overlay)
		putenv_ "BMX_NRF52_EXTRA_OVERLAY_FILE=" + overlay
	End If
	Local venvBin:String = Nrf52VirtualEnvironmentBin(zephyrBase)
	Local west:String = Nrf52WestExecutable(venvBin)
	If venvBin.length Then putenv_ "PATH=" + venvBin + PicoPathSeparator(PicoHostPlatform()) + getenv_("PATH")
	putenv_ "ZEPHYR_BASE=" + zephyrBase
	putenv_ "ZEPHYR_SDK_INSTALL_DIR=" + sdkInstall

	Local outputBase:String = outputPath
	Select ExtractExt(outputBase).ToLower()
		Case "elf", "uf2", "hex", "bin"
			outputBase = StripExt(outputBase)
	End Select
	CreateDir(ExtractDir(outputBase), True)
	Local buildDir:String = ExtractDir(mainSource) + "/.bmx/" + StripDir(StripExt(mainSource)) + "." + PicoBuildModeName() + ".nrf52.arm." + board
	CreateDir(buildDir, True)
	Local compilerRoot:String = buildDir + "/bcc"
	CreateDir(compilerRoot, True)

	GeneratePicoInterface(bcc, sdk, "brl.blitz", blitzRoot + "/blitz.bmx", blitzRoot + "/blitz." + EmbeddedTargetMung() + ".i")
	Local applicationUnits:TList
	Local units:TList = DiscoverPicoModules(mainSource, applicationUnits)
	Local nativeLinkOptions:TList
	Local nativeImports:TList = DiscoverPicoNativeImports(mainSource, units, nativeLinkOptions)
	Local moduleSources:String[] = New String[0]
	Local applicationSources:String[] = New String[0]
	Local specializationOwners:TMap = New TMap
	Local index:Int
	For Local unit:TPicoModuleUnit = EachIn units
		Local bundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, unit.source, compilerRoot + "/module_" + index, "module.c", unit.name, unit.sourceUnitPath, unit.interfacePath, "", False, "", PicoRuntimeHeaderPath(unit.source))
		AppendPicoBundleSources(bundle, moduleSources, specializationOwners)
		index :+ 1
	Next
	Local applicationIdentity:String = Bcc2ApplicationIdentity(mainSource)
	Local frameworkModule:String = ParseSourceFile(mainSource).framewk
	index = 0
	For Local unit:TPicoApplicationUnit = EachIn applicationUnits
		Local bundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, unit.source, compilerRoot + "/application_unit_" + index, "application_unit.c", applicationIdentity, unit.sourceUnitPath, unit.interfacePath, applicationIdentity, True, frameworkModule, PicoRuntimeHeaderPath(unit.source))
		AppendPicoBundleSources(bundle, applicationSources, specializationOwners)
		index :+ 1
	Next
	Local applicationBundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, mainSource, compilerRoot + "/application", "application.c", "", "", "", applicationIdentity, False, "", PicoRuntimeHeaderPath(mainSource))
	AppendPicoBundleSources(applicationBundle, applicationSources, specializationOwners)
	Local nativeCmake:String = GeneratePicoNativeCMake(nativeImports, nativeLinkOptions, buildDir)

	Local zephyrBuildDir:String = buildDir + "/zephyr-build"
	Local command:String = CQuote(west) + " build -p always -b promicro_nrf52840/nrf52840/uf2 -d " + CQuote(zephyrBuildDir) + " " + CQuote(template) + " --" + ..
		" -DBLITZMAX_SDK=" + CQuote(sdk) + ..
		" -DBLITZMAX_APPLICATION_ROOT=" + CQuote(ExtractDir(mainSource)) + ..
		" -DBLITZMAX_OUTPUT_NAME=" + CQuote(StripDir(outputBase)) + ..
		" -DBLITZMAX_GENERATED_C=" + CQuote(JoinPicoPaths(applicationSources)) + ..
		" -DBLITZMAX_MODULE_SOURCES=" + CQuote(JoinPicoPaths(moduleSources)) + ..
		" -DBLITZMAX_NATIVE_CMAKE=" + CQuote(nativeCmake) + ..
		" -DBLITZMAX_MODULE_INITIALIZERS=" + CQuote(JoinPicoModuleField(units, "initialize"))
	RunPicoCommand(command, "Building nRF52 Zephyr application")
	Local built:String = zephyrBuildDir + "/zephyr/zephyr"
	If FileType(built + ".uf2") <> FILETYPE_FILE Then Throw "Zephyr did not produce a UF2 image"
	For Local extension:String = EachIn ["elf", "uf2", "hex", "bin"]
		If FileType(built + "." + extension) = FILETYPE_FILE Then CopyFile(built + "." + extension, outputBase + "." + extension)
	Next
	Print "nRF52 UF2: " + outputBase + ".uf2"
	If opt_execute Then RunPicoCommand(CQuote(west) + " flash -d " + CQuote(zephyrBuildDir) + " -r uf2 --board-id nRF52840-nicenano", "Uploading nRF52 UF2")
End Function
