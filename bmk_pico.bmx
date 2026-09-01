SuperStrict

Import "bmk_make.bmx"
Include "bmk_pico_paths.bmx"

Type TPicoModuleUnit
	Field name:String
	Field source:String
	Field sourceUnitPath:String
	Field interfacePath:String
	Field initializeFunction:String
	Field primary:Int
End Type

Type TPicoApplicationUnit
	Field source:String
	Field sourceUnitPath:String
	Field interfacePath:String
End Type

Type TPicoBuildBundle
	Field root:String
	Field manifest:TBcc2BuildManifest
	Field generatedC:String
	Field incbinC:String
End Type

Type TPicoGenericSpecializationOwner
	Field link:TBcc2BuildLink
	Field contentDigest:String
End Type

Type TPicoPIOImport
	Field source:String
	Field programs:String[]
End Type

Type TPicoNativeImport
	Field source:String
	Field compileOptions:String
End Type

Function AppendPicoOption:String(current:String, extra:String)
	current = current.Trim()
	extra = extra.Trim()
	If Not current.length Then Return extra
	If Not extra.length Then Return current
	Return current + " " + extra
End Function

Function PicoSourceOption:String(source:TSourceFile, kind:String)
	If Not source Or Not source.mod_opts Then Return ""
	Select kind
		Case "cc"
			Return source.mod_opts.cc_opts
		Case "c"
			Return source.mod_opts.c_opts
		Case "cpp"
			Return source.mod_opts.cpp_opts
	End Select
	Return ""
End Function

Function IsPicoHeaderExtension:Int(extension:String)
	extension = extension.ToLower()
	Return extension = "h" Or extension = "hh" Or extension = "hpp" Or extension = "hxx"
End Function

Function CollectPicoNativeImports(sourcePath:String, inheritedCC:String, inheritedC:String, inheritedCPP:String, imports:TList, linkOptions:TList, visitedSources:TMap, nativeOwners:TMap)
	Local source:String = RealPath(sourcePath)
	Local parsed:TSourceFile = ParseSourceFile(source)
	If Not parsed Then Throw "Unable to read Pico source while discovering native imports at " + source

	Local ccOptions:String = AppendPicoOption(inheritedCC, PicoSourceOption(parsed, "cc"))
	Local cOptions:String = AppendPicoOption(inheritedC, PicoSourceOption(parsed, "c"))
	Local cppOptions:String = AppendPicoOption(inheritedCPP, PicoSourceOption(parsed, "cpp"))
	' A quoted header import publishes its directory to native compilation. In
	' particular, src/*.h means -I src; it does not enumerate or compile headers.
	' Discover these paths before walking native imports so source order does not
	' change the include environment inherited by a translation unit.
	Local includePaths:TMap = New TMap
	For Local importedPath:String = EachIn parsed.imports
		If importedPath.StartsWith("-") Or Not IsPicoHeaderExtension(ExtractExt(importedPath)) Then Continue
		Local includePath:String
		If importedPath.Find("*") >= 0 Then
			includePath = RealPath(ExtractDir(source) + "/" + ExtractDir(importedPath))
			If FileType(includePath) <> FILETYPE_DIR Then Throw "Unable to read quoted Pico header directory '" + importedPath + "' from " + source
		Else
			Local headerPath:String = RealPath(ExtractDir(source) + "/" + importedPath)
			If FileType(headerPath) <> FILETYPE_FILE Then Throw "Unable to read quoted Pico header '" + importedPath + "' from " + source
			includePath = ExtractDir(headerPath)
		End If
		If Not includePaths.Contains(includePath) Then
			includePaths.Insert(includePath, includePath)
			ccOptions = AppendPicoOption(ccOptions, "-I" + CQuote(includePath))
		End If
	Next
	Local visitIdentity:String = "options|" + ccOptions + "|" + cOptions + "|" + cppOptions
	Local previousVisit:String = String(visitedSources.ValueForKey(source))
	If previousVisit.length Then
		If previousVisit <> visitIdentity Then Throw "Quoted Pico source has conflicting native compiler options: " + source
		Return
	End If
	visitedSources.Insert(source, visitIdentity)
	If parsed.mod_opts Then
		For Local option:String = EachIn parsed.mod_opts.ld_opts
			linkOptions.AddLast(option)
		Next
	End If

	Local importIndex:Int
	For Local importedPath:String = EachIn parsed.imports
		Local lexicalOptions:TSourceImportOptions
		If importIndex < parsed.importOptions.Count() Then lexicalOptions = TSourceImportOptions(parsed.importOptions.ValueAtIndex(importIndex))
		importIndex :+ 1
		If importedPath.StartsWith("-") Then Continue

		Local extension:String = ExtractExt(importedPath).ToLower()
		If extension <> "bmx" And extension <> "c" And extension <> "cc" And extension <> "cpp" And extension <> "cxx" And extension <> "h" And extension <> "hh" And extension <> "hpp" And extension <> "hxx" Then Continue
		If IsPicoHeaderExtension(extension) And importedPath.Find("*") >= 0 Then Continue
		Local resolved:String = RealPath(ExtractDir(source) + "/" + importedPath)
		If FileType(resolved) <> FILETYPE_FILE Then Throw "Unable to read quoted Pico source '" + importedPath + "' from " + source

		Local importedCC:String = ccOptions
		If lexicalOptions Then importedCC = AppendPicoOption(importedCC, lexicalOptions.ccOpts)
		If extension = "bmx" Then
			CollectPicoNativeImports(resolved, importedCC, cOptions, cppOptions, imports, linkOptions, visitedSources, nativeOwners)
			Continue
		End If
		' Header imports are validated here. The native compiler's dependency files
		' make Ninja track the headers actually included by a C/C++ translation unit.
		If IsPicoHeaderExtension(extension) Then Continue

		Local compileOptions:String = importedCC
		If extension = "c" Then
			compileOptions = AppendPicoOption(compileOptions, cOptions)
		Else
			compileOptions = AppendPicoOption(compileOptions, cppOptions)
		End If
		Local owner:TPicoNativeImport = TPicoNativeImport(nativeOwners.ValueForKey(resolved))
		If owner Then
			If owner.compileOptions <> compileOptions Then Throw "Quoted Pico native source has conflicting compiler options: " + resolved
			Continue
		End If
		Local nativeImport:TPicoNativeImport = New TPicoNativeImport
		nativeImport.source = resolved
		nativeImport.compileOptions = compileOptions
		nativeOwners.Insert(resolved, nativeImport)
		imports.AddLast(nativeImport)
	Next
End Function

Function DiscoverPicoNativeImports:TList(mainSource:String, units:TList, linkOptions:TList Var)
	Local imports:TList = New TList
	linkOptions = New TList
	Local visitedSources:TMap = New TMap
	Local nativeOwners:TMap = New TMap
	CollectPicoNativeImports(mainSource, "", "", "", imports, linkOptions, visitedSources, nativeOwners)
	For Local unit:TPicoModuleUnit = EachIn units
		If unit.primary Then CollectPicoNativeImports(unit.source, "", "", "", imports, linkOptions, visitedSources, nativeOwners)
	Next
	Return imports
End Function

Function IsPicoPIOIdentifier:Int(name:String)
	If Not name.length Then Return False
	For Local index:Int = 0 Until name.length
		Local character:Int = name[index]
		Local valid:Int = character = Asc("_") Or ..
			(character >= Asc("a") And character <= Asc("z")) Or ..
			(character >= Asc("A") And character <= Asc("Z")) Or ..
			(index > 0 And character >= Asc("0") And character <= Asc("9"))
		If Not valid Then Return False
	Next
	Return True
End Function

Function PicoPIOProgramNames:String[](source:String)
	Local text:String = LoadText(source)
	If Not text.length Then Throw "Unable to read imported PIO source " + source
	Local names:String[] = New String[0]
	Local seen:TMap = New TMap
	For Local line:String = EachIn text.Replace("~r", "").Split("~n")
		Local comment:Int = line.Find(";")
		If comment >= 0 Then line = line[..comment]
		line = line.Trim()
		If line.length < 9 Or line[..8].ToLower() <> ".program" Or line[8] > 32 Then Continue
		Local remainder:String = line[8..].Trim()
		Local endIndex:Int
		While endIndex < remainder.length And remainder[endIndex] > 32
			endIndex :+ 1
		Wend
		Local name:String = remainder[..endIndex]
		If Not IsPicoPIOIdentifier(name) Then Throw "Invalid PIO program name '" + name + "' in " + source
		Local normalized:String = name.ToLower()
		If seen.Contains(normalized) Then Throw "Duplicate PIO program name '" + name + "' in " + source
		seen.Insert(normalized, name)
		names :+ [name]
	Next
	If Not names.length Then Throw "Imported PIO source declares no .program: " + source
	Return names
End Function

Function CollectPicoPIOImports(sourcePath:String, imports:TList, visitedSources:TMap, visitedPIO:TMap)
	Local source:String = RealPath(sourcePath)
	If visitedSources.Contains(source) Then Return
	visitedSources.Insert(source, source)
	Local parsed:TSourceFile = ParseSourceFile(source)
	If Not parsed Then Throw "Unable to read Pico source while discovering PIO imports at " + source
	For Local importedPath:String = EachIn parsed.imports
		If importedPath.StartsWith("-") Then Continue
		Local extension:String = ExtractExt(importedPath).ToLower()
		If extension <> "bmx" And extension <> "pio" Then Continue
		Local resolved:String = RealPath(ExtractDir(source) + "/" + importedPath)
		If FileType(resolved) <> FILETYPE_FILE Then Throw "Unable to read quoted Pico source '" + importedPath + "' from " + source
		If extension = "bmx" Then
			CollectPicoPIOImports(resolved, imports, visitedSources, visitedPIO)
		Else If Not visitedPIO.Contains(resolved) Then
			visitedPIO.Insert(resolved, resolved)
			Local imported:TPicoPIOImport = New TPicoPIOImport
			imported.source = resolved
			imported.programs = PicoPIOProgramNames(resolved)
			imports.AddLast(imported)
		End If
	Next
End Function

Function DiscoverPicoPIOImports:TList(mainSource:String, units:TList)
	Local imports:TList = New TList
	Local visitedSources:TMap = New TMap
	Local visitedPIO:TMap = New TMap
	CollectPicoPIOImports(mainSource, imports, visitedSources, visitedPIO)
	For Local unit:TPicoModuleUnit = EachIn units
		CollectPicoPIOImports(unit.source, imports, visitedSources, visitedPIO)
	Next
	Local programOwners:TMap = New TMap
	For Local imported:TPicoPIOImport = EachIn imports
		For Local name:String = EachIn imported.programs
			Local normalized:String = name.ToLower()
			Local owner:String = String(programOwners.ValueForKey(normalized))
			If owner.length Then Throw "PIO program name '" + name + "' is declared by both " + owner + " and " + imported.source
			programOwners.Insert(normalized, imported.source)
		Next
	Next
	Return imports
End Function

Function PicoModuleInitializeFunction:String(moduleName:String, sourceUnitPath:String)
	Local normalized:String = moduleName.ToLower()
	Return "__bb_" + normalized.Replace(".", "_") + "_" + Bcc2SourceUnitAbiIdentity(sourceUnitPath)
End Function

Function DiscoverPicoSourceUnit(moduleName:String, source:String, sourceUnitPath:String, interfacePath:String, units:TList, visitedModules:TMap, visitedSources:TMap, primary:Int = False)
	Local normalizedUnitPath:String = sourceUnitPath.Replace("\", "/").ToLower()
	Local sourceKey:String = moduleName.ToLower() + "|" + normalizedUnitPath
	If visitedSources.Contains(sourceKey) Then Return
	visitedSources.Insert(sourceKey, sourceKey)

	Local parsed:TSourceFile = ParseSourceFile(source)
	If Not parsed Then Throw "Unable to read Pico source unit at " + source
	If primary And parsed.modid <> moduleName.ToLower() Then Throw "Pico module source '" + source + "' declares '" + parsed.modid + "', expected '" + moduleName.ToLower() + "'"

	For Local dependency:String = EachIn parsed.modimports
		DiscoverPicoModule(dependency, units, visitedModules, visitedSources)
	Next
	For Local importedPath:String = EachIn parsed.imports
		If importedPath.StartsWith("-") Or ExtractExt(importedPath).ToLower() <> "bmx" Then Continue
		Local importedUnitPath:String = Bcc2SourceUnitPath(normalizedUnitPath, importedPath)
		If Not importedUnitPath.length Then Throw "Quoted Pico source escapes module root: " + importedPath
		Local importedSource:String = RealPath(ExtractDir(source) + "/" + importedPath)
		If FileType(importedSource) <> FILETYPE_FILE Then Throw "Unable to read quoted Pico source '" + importedPath + "' from " + source
		Local importedInterface:String = ExtractDir(importedSource) + "/.bmx/" + StripDir(importedSource) + "." + PicoBuildModeName() + ".pico.arm.i"
		DiscoverPicoSourceUnit(moduleName, importedSource, importedUnitPath, importedInterface, units, visitedModules, visitedSources)
	Next

	Local unit:TPicoModuleUnit = New TPicoModuleUnit
	unit.name = moduleName.ToLower()
	unit.source = source
	unit.sourceUnitPath = normalizedUnitPath
	unit.interfacePath = interfacePath
	unit.initializeFunction = PicoModuleInitializeFunction(unit.name, normalizedUnitPath)
	unit.primary = primary
	units.AddLast(unit)
End Function

Function DiscoverPicoModule(moduleName:String, units:TList, visitedModules:TMap, visitedSources:TMap)
	Local normalized:String = moduleName.ToLower()
	If visitedModules.Contains(normalized) Then Return
	visitedModules.Insert(normalized, normalized)

	Local moduleDirectory:String = InstalledModulePath(normalized)
	Local ident:String = ModuleIdent(normalized)
	Local source:String = moduleDirectory + "/" + ident + ".bmx"
	Local interfacePath:String = moduleDirectory + "/" + ident + "." + PicoBuildModeName() + ".pico.arm.i"
	DiscoverPicoSourceUnit(normalized, source, ident + ".bmx", interfacePath, units, visitedModules, visitedSources, True)
End Function

Function DiscoverPicoApplicationModules(sourcePath:String, sourceUnitPath:String, frameworkModule:String, units:TList, applicationUnits:TList, visitedModules:TMap, visitedModuleSources:TMap, visitedApplicationSources:TMap, primary:Int = False)
	Local source:String = RealPath(sourcePath)
	If visitedApplicationSources.Contains(source) Then Return
	visitedApplicationSources.Insert(source, source)

	Local parsed:TSourceFile = ParseSourceFile(source)
	If Not parsed Then Throw "Unable to read Pico application source at " + source

	' Framework is an import for every source unit owned by the application. Mirror
	' the normal bmk dependency walk even though a single physical module build is
	' sufficient for the final Pico link.
	If frameworkModule.length Then DiscoverPicoModule(frameworkModule, units, visitedModules, visitedModuleSources)
	For Local moduleName:String = EachIn parsed.modimports
		DiscoverPicoModule(moduleName, units, visitedModules, visitedModuleSources)
	Next

	For Local importedPath:String = EachIn parsed.imports
		If importedPath.StartsWith("-") Or ExtractExt(importedPath).ToLower() <> "bmx" Then Continue
		Local importedSource:String = RealPath(ExtractDir(source) + "/" + importedPath)
		If FileType(importedSource) <> FILETYPE_FILE Then Throw "Unable to read quoted Pico application source '" + importedPath + "' from " + source
		Local importedUnitPath:String = Bcc2SourceUnitPath(sourceUnitPath, importedPath)
		If Not importedUnitPath.length Then Throw "Quoted Pico application source escapes its source root: " + importedPath
		DiscoverPicoApplicationModules(importedSource, importedUnitPath, frameworkModule, units, applicationUnits, visitedModules, visitedModuleSources, visitedApplicationSources)
	Next

	If Not primary Then
		Local applicationUnit:TPicoApplicationUnit = New TPicoApplicationUnit
		applicationUnit.source = source
		applicationUnit.sourceUnitPath = sourceUnitPath
		applicationUnit.interfacePath = ExtractDir(source) + "/.bmx/" + StripDir(source) + "." + PicoBuildModeName() + ".pico.arm.i"
		applicationUnits.AddLast(applicationUnit)
	End If
End Function

Function DiscoverPicoModules:TList(mainSource:String, applicationUnits:TList Var)
	Local parsed:TSourceFile = ParseSourceFile(mainSource)
	If Not parsed Then Throw "Unable to read Pico application source at " + mainSource
	Local units:TList = New TList
	applicationUnits = New TList
	Local visitedModules:TMap = New TMap
	Local visitedModuleSources:TMap = New TMap
	Local visitedApplicationSources:TMap = New TMap
	' BRL.Blitz is the implicit base module for every BlitzMax application. Its
	' interface is always visible to bcc2, so its implementation must likewise
	' participate in the Pico link even when the source has no explicit Framework.
	DiscoverPicoModule("brl.blitz", units, visitedModules, visitedModuleSources)
	DiscoverPicoApplicationModules(mainSource, StripDir(mainSource), parsed.framewk, units, applicationUnits, visitedModules, visitedModuleSources, visitedApplicationSources, True)
	Return units
End Function

Function JoinPicoModuleField:String(units:TList, fieldName:String)
	Local values:String[] = New String[units.Count()]
	Local index:Int
	For Local unit:TPicoModuleUnit = EachIn units
		Select fieldName
			Case "name"
				values[index] = unit.name
			Case "source"
				values[index] = unit.source
			Case "source_unit"
				values[index] = unit.sourceUnitPath
			Case "interface"
				values[index] = unit.interfacePath
			Case "initialize"
				values[index] = unit.initializeFunction
		End Select
		index :+ 1
	Next
	Return ";".Join(values)
End Function

Function PicoConfiguredPath:String(optionKey:String, environmentKey:String)
	Return PicoPreferredConfiguredValue(processor.Option(optionKey, ""), getenv_(environmentKey))
End Function

Function RequirePicoDirectory:String(label:String, optionKey:String, environmentKey:String, managedCategory:String, managedSuffixes:String[])
	Local configured:String = PicoConfiguredPath(optionKey, environmentKey)
	If configured.length Then
		If FileType(configured) = FILETYPE_DIR Then Return configured
		Throw "The configured " + label + " path does not name a directory: " + configured
	End If
	Local discovered:String = PicoLatestManagedPath(PicoUserHome(PicoHostPlatform()), managedCategory, managedSuffixes)
	If discovered.length And FileType(discovered) = FILETYPE_DIR Then Return discovered
	Throw "Unable to locate " + label + ". Set #addoption " + optionKey + " in custom.bmk or " + environmentKey + ", or install it under the user Pico SDK directory."
End Function

Function RequirePicoExecutable:String(label:String, optionKey:String, environmentKey:String, executableName:String, managedCategory:String, managedSuffixes:String[])
	Local platform:String = PicoHostPlatform()
	Local configured:String = processor.Option(optionKey, "").Trim()
	If configured.length Then
		Local executable:String = PicoExecutableFromValue(configured, executableName, platform)
		If executable.length Then Return executable
		Throw "The configured " + label + " path does not contain " + PicoExecutableName(executableName, platform) + ": " + configured
	End If
	configured = getenv_(environmentKey).Trim()
	If configured.length Then
		Local executable:String = PicoExecutableFromValue(configured, executableName, platform)
		If executable.length Then Return executable
		Throw "The " + environmentKey + " path does not contain " + PicoExecutableName(executableName, platform) + ": " + configured
	End If
	Local executable:String = PicoFindExecutableOnPath(executableName, getenv_("PATH"), platform)
	If executable.length Then Return executable
	executable = PicoLatestManagedPath(PicoUserHome(platform), managedCategory, managedSuffixes)
	If executable.length And FileType(executable) = FILETYPE_FILE Then Return executable
	Throw "Unable to locate " + label + ". Set #addoption " + optionKey + " in custom.bmk, set " + environmentKey + ", add it to PATH, or install it under the user Pico SDK directory."
End Function

Function PicoDebugBuild:Int()
	Return opt_debug Or opt_gdbdebug
End Function

Function PicoBuildModeName:String()
	If PicoDebugBuild() Then Return "debug"
	Return "release"
End Function

Function PicoBoardMainRAM:Long(board:String)
	If board = "pico" Then Return 256:Long * 1024
	If board = "pico2" Then Return 512:Long * 1024
	Throw "No Pico RAM budget is defined for board " + board
End Function

Function PicoBoardFlash:Long(board:String)
	If board = "pico" Or board = "pico2" Then Return 2:Long * 1024 * 1024
	Throw "No Pico flash budget is defined for board " + board
End Function

Function ParsePicoHeapSize:Long(value:String, board:String)
	Local normalized:String = value.Trim().ToLower()
	If Not normalized.length Or normalized = "auto" Then
		If board = "pico" Then Return 192:Long * 1024
		If board = "pico2" Then Return 384:Long * 1024
	End If

	Local multiplier:Long = 1
	If normalized.EndsWith("kib") Then
		multiplier = 1024
		normalized = normalized[..normalized.length - 3]
	Else If normalized.EndsWith("kb") Then
		multiplier = 1024
		normalized = normalized[..normalized.length - 2]
	Else If normalized.EndsWith("k") Then
		multiplier = 1024
		normalized = normalized[..normalized.length - 1]
	Else If normalized.EndsWith("mib") Then
		multiplier = 1024 * 1024
		normalized = normalized[..normalized.length - 3]
	Else If normalized.EndsWith("mb") Then
		multiplier = 1024 * 1024
		normalized = normalized[..normalized.length - 2]
	Else If normalized.EndsWith("m") Then
		multiplier = 1024 * 1024
		normalized = normalized[..normalized.length - 1]
	Else If normalized.EndsWith("b") Then
		normalized = normalized[..normalized.length - 1]
	End If

	If Not normalized.length Then Throw "Invalid Pico heap size '" + value + "'"
	For Local index:Int = 0 Until normalized.length
		If normalized[index] < Asc("0") Or normalized[index] > Asc("9") Then Throw "Invalid Pico heap size '" + value + "'"
	Next
	Local bytes:Long = Long(normalized) * multiplier
	If bytes < 1024 Then Throw "Pico heap size must be at least 1 KiB"
	bytes = (bytes + 7) & ~7:Long
	If bytes >= PicoBoardMainRAM(board) Then Throw "Pico heap size must leave room for application and SDK RAM"
	Return bytes
End Function

Function PicoCaptureCommand:String(command:String)
	Local process:TProcess = CreateProcess(command)
	If Not process Then Return ""
	Local output:TStringBuilder = New TStringBuilder
	While process.Status() Or Not process.pipe.Eof() Or Not process.err.Eof()
		Delay 1
		While True
			Local line:String = process.pipe.ReadLine()
			If Not line Then Exit
			output.Append(line).Append("~n")
		Wend
		While True
			Local line:String = process.err.ReadLine()
			If Not line Then Exit
			output.Append(line).Append("~n")
		Wend
	Wend
	process.Close()
	Return output.ToString()
End Function

Function PicoMemoryPercent:String(used:Long, capacity:Long)
	If capacity <= 0 Then Return "0.0"
	Local tenths:Long = used * 1000 / capacity
	Return (tenths / 10) + "." + (tenths Mod 10)
End Function

Function ReportPicoMemory(sizeTool:String, elfPath:String, board:String, arenaSize:Long)
	Local output:String = PicoCaptureCommand(CQuote(sizeTool) + " -B " + CQuote(elfPath))
	Local textBytes:Long = -1
	Local dataBytes:Long
	Local bssBytes:Long
	For Local line:String = EachIn output.Replace("~r", "").Replace("~t", " ").Split("~n")
		Local values:String[] = New String[0]
		For Local value:String = EachIn line.Trim().Split(" ")
			If value.length Then values :+ [value]
		Next
		If values.length < 3 Or values[0] = "text" Then Continue
		Local numeric:Int = True
		For Local index:Int = 0 Until values[0].length
			If values[0][index] < Asc("0") Or values[0][index] > Asc("9") Then numeric = False
		Next
		If Not numeric Then Continue
		textBytes = Long(values[0])
		dataBytes = Long(values[1])
		bssBytes = Long(values[2])
		Exit
	Next

	If textBytes < 0 Then
		Print "Pico managed heap: " + arenaSize + " bytes"
		Return
	End If

	Local flashCapacity:Long = PicoBoardFlash(board)
	Local ramCapacity:Long = PicoBoardMainRAM(board)
	Local flashUsed:Long = textBytes + dataBytes
	Local linkedRam:Long = dataBytes + bssBytes
	Local linkedArena:Long = arenaSize
	If bssBytes < arenaSize Then linkedArena = 0
	Local nativeRam:Long = linkedRam - linkedArena
	Local cHeapReserve:Long = 2048
	Local ramHeadroom:Long = ramCapacity - linkedRam - cHeapReserve
	If ramHeadroom < 0 Then ramHeadroom = 0

	Print "Pico memory (" + board + "):"
	Print "  Flash:        " + flashUsed + " / " + flashCapacity + " bytes (" + PicoMemoryPercent(flashUsed, flashCapacity) + "%)"
	If linkedArena Then
		Print "  Managed heap: " + linkedArena + " bytes (" + opt_pico_heap + ")"
	Else
		Print "  Managed heap: not linked; configured " + arenaSize + " bytes (" + opt_pico_heap + ")"
	End If
	Print "  App/SDK RAM:  " + nativeRam + " bytes"
	Print "  C heap reserve: " + cHeapReserve + " bytes"
	Print "  RAM headroom: " + ramHeadroom + " / " + ramCapacity + " bytes"
End Function

Function UploadPicoFirmware(picotool:String, uf2Path:String)
	Print "Uploading Pico firmware: " + StripDir(uf2Path)
	Local command:String = CQuote(picotool) + " load -f -u -v -x " + CQuote(uf2Path)
	If Not processor.Sys(command) Then
		Print "Pico upload complete; firmware was started."
		Return
	End If
	Print ""
	Print "Pico upload could not start automatically."
	Print "Connect the Pico's own USB port directly to this computer while holding BOOTSEL,"
	Print "then rerun the same bmk command with -x."
	Print "The debug probe is not required; picotool uploads through the Pico's USB connection."
	Throw "Uploading Pico firmware failed"
End Function

Function RunPicoCommand(command:String, description:String)
	If processor.Sys(command) Then Throw description + " failed"
End Function

Function GeneratePicoInterface(bcc:String, sdk:String, moduleName:String, source:String, output:String, sourceUnitPath:String = "")
	Local command:String = CQuote(bcc) + ..
		" --emit-interface" + ..
		" --sdk " + CQuote(sdk) + ..
		" --module " + moduleName
	If sourceUnitPath.length Then command :+ " --source-unit " + CQuote(sourceUnitPath)
	command :+ " --platform pico --arch arm --single-threaded"
	If PicoDebugBuild() Then
		command :+ " --debug --no-debug-instrumentation --gdb-debug"
	Else
		command :+ " --release"
	End If
	command :+ " -o " + CQuote(output) + " " + CQuote(source)
	RunPicoCommand(command, "Generating interface for " + moduleName)
End Function

Function PicoRuntimeHeaderPath:String(source:String)
	Return ExtractDir(source) + "/.bmx/" + StripDir(source) + "." + PicoBuildModeName() + ".pico.arm.h"
End Function

Function GeneratePicoBuildBundle:TPicoBuildBundle(bcc:String, sdk:String, source:String, bundleRoot:String, generatedCName:String, moduleName:String = "", sourceUnitPath:String = "", interfaceOutput:String = "", applicationIdentity:String = "", applicationSource:Int = False, frameworkModule:String = "", runtimeHeaderOutput:String = "")
	CreateDir(bundleRoot, True)
	Local manifestName:String = "bcc-build.manifest"
	Local command:String = CQuote(bcc) + ..
		" --emit-build" + ..
		" --sdk " + CQuote(sdk) + ..
		" --platform pico --arch arm --single-threaded" + ..
		" --build-c " + CQuote(generatedCName) + ..
		" --build-manifest " + CQuote(manifestName)
	If moduleName.length Then command :+ " --module " + moduleName
	If sourceUnitPath.length Then command :+ " --source-unit " + CQuote(sourceUnitPath)
	If interfaceOutput.length Then command :+ " --build-interface " + CQuote("module.i")
	If runtimeHeaderOutput.length Then command :+ " --build-header " + CQuote("module.h")
	If applicationIdentity.length Then command :+ " --application-identity " + applicationIdentity
	If applicationSource Then command :+ " --application-source"
	If frameworkModule.length Then command :+ " --framework " + frameworkModule
	If PicoDebugBuild() Then
		command :+ " --debug --no-debug-instrumentation --gdb-debug"
	Else
		command :+ " --release"
	End If
	command :+ " -o " + CQuote(bundleRoot) + " " + CQuote(source)
	RunPicoCommand(command, "Generating Pico compiler build bundle for " + source)

	Local bundle:TPicoBuildBundle = New TPicoBuildBundle
	bundle.root = bundleRoot
	Local manifestPath:String = bundleRoot + "/" + manifestName
	TBcc2BuildManifestCodec.Invalidate(manifestPath)
	bundle.manifest = TBcc2BuildManifestCodec.Load(manifestPath)
	bundle.manifest.ValidateGeneratedFiles(bundleRoot)
	For Local file:TBcc2BuildFile = EachIn bundle.manifest.files
		If file.role = "application-c" And file.relativePath = generatedCName Then bundle.generatedC = TBcc2BuildManifestCodec.Resolve(bundleRoot, file.relativePath)
	Next
	If Not bundle.generatedC.length Then Throw "Pico compiler build bundle did not declare " + generatedCName
	bundle.incbinC = GeneratePicoIncbinSource(source, bundleRoot + "/incbin.c", moduleName, sourceUnitPath)

	If interfaceOutput.length Then
		Local publishedInterface:Int
		Local interfaceDirectory:String = ExtractDir(interfaceOutput)
		For Local file:TBcc2BuildFile = EachIn bundle.manifest.files
			Local destination:String
			If file.role = "interface" Then
				destination = interfaceOutput
				publishedInterface = True
			Else If file.role = "generic-template" Then
				destination = interfaceDirectory + "/" + file.relativePath
			Else
				Continue
			End If
			CreateDir(ExtractDir(destination), True)
			If Not CopyFile(TBcc2BuildManifestCodec.Resolve(bundleRoot, file.relativePath), destination) Then Throw "Unable to publish Pico compiler interface output " + destination
		Next
		If Not publishedInterface Then Throw "Pico compiler build bundle did not declare its module interface"
	End If
	If runtimeHeaderOutput.length Then
		Local publishedHeader:Int
		For Local file:TBcc2BuildFile = EachIn bundle.manifest.files
			If file.role <> "runtime-header" Then Continue
			CreateDir(ExtractDir(runtimeHeaderOutput), True)
			If Not CopyFile(TBcc2BuildManifestCodec.Resolve(bundleRoot, file.relativePath), runtimeHeaderOutput) Then Throw "Unable to publish Pico compiler runtime header " + runtimeHeaderOutput
			publishedHeader = True
			Exit
		Next
		If Not publishedHeader Then Throw "Pico compiler build bundle did not declare its runtime header"
	End If
	Return bundle
End Function

Function GeneratePicoIncbinSource:String(sourcePath:String, outputPath:String, moduleName:String = "", sourceUnitPath:String = "")
	Local source:TSourceFile = ParseSourceFile(sourcePath)
	If Not source Then Throw "Unable to read Pico Incbin source at " + sourcePath
	If source.incbins.IsEmpty() Then Return ""

	Local unitName:String = "_bb_main"
	If moduleName.length Then
		Local identity:String = sourceUnitPath
		If Not identity.length Then identity = StripDir(sourcePath)
		unitName = "_bb_" + moduleName.ToLower().Replace(".", "_") + "_" + Bcc2SourceUnitAbiIdentity(identity)
	End If

	Local output:String = "#define INCBIN_PREFIX _ib~n"
	output :+ "#define INCBIN_STYLE INCBIN_STYLE_SNAKE~n"
	output :+ "#include ~qbrl.mod/blitz.mod/incbin/incbin.h~q~n"
	Local resources:String
	Local ordinal:Int
	For Local logicalPath:String = EachIn source.incbins
		ordinal :+ 1
		Local resolvedPath:String = RealPath(ExtractDir(sourcePath) + "/" + logicalPath)
		If FileType(resolvedPath) <> FILETYPE_FILE Then Throw "BMKGEN041 Incbin resource was not found: " + logicalPath
		Local escapedLogicalPath:String = logicalPath.Replace("\", "\\").Replace("~q", "\~q")
		Local escapedResolvedPath:String = resolvedPath.Replace("\", "\\").Replace("~q", "\~q")
		output :+ "// FILE : ~q" + escapedLogicalPath + "~q~t" + CalculateFileHash(resolvedPath) + "~n"
		resources :+ "INCBIN(" + unitName + "_" + ordinal + ", ~q" + escapedResolvedPath + "~q);~n"
	Next
	output :+ "// ----~n" + resources

	If FileType(outputPath) <> FILETYPE_FILE Or LoadText(outputPath) <> output Then
		If Not SaveText(output, outputPath) Then Throw "BMKGEN043 unable to write Pico Incbin packaging unit: " + outputPath
	End If
	Return outputPath
End Function

Function AppendPicoBundleSources(bundle:TPicoBuildBundle, sources:String[] Var, specializationOwners:TMap)
	If Not bundle Or Not bundle.manifest Then Return
	sources :+ [bundle.generatedC]
	If bundle.incbinC.length Then sources :+ [bundle.incbinC]
	For Local link:TBcc2BuildLink = EachIn bundle.manifest.links
		Local file:TBcc2BuildFile = bundle.manifest.FileForPath(link.sourcePath)
		If Not file Then Throw "Pico generic specialization source is absent from its build manifest: " + link.sourcePath
		Local owner:TPicoGenericSpecializationOwner = TPicoGenericSpecializationOwner(specializationOwners.ValueForKey(link.specializationIdentity))
		If owner Then
			' The same imported canonical specialization can be discovered while
			' compiling its owning wrapper module and again while reconstructing
			' that module's public object layout in an application. Consumer identity
			' deliberately invalidates each local compiler cache key, but identical
			' generated C still has one semantic owner and must be linked only once.
			If owner.contentDigest <> file.contentDigest Then Throw "Conflicting Pico generic specialization owners for " + link.specializationIdentity
			Continue
		End If
		owner = New TPicoGenericSpecializationOwner
		owner.link = link
		owner.contentDigest = file.contentDigest
		specializationOwners.Insert(link.specializationIdentity, owner)
		sources :+ [TBcc2BuildManifestCodec.Resolve(bundle.root, link.sourcePath)]
	Next
End Function

Function JoinPicoPaths:String(paths:String[])
	Return ";".Join(paths)
End Function

Function EscapePicoGeneratedString:String(value:String)
	Return value.Replace("\", "\\").Replace("~q", "\~q")
End Function

Function GeneratePicoNativeCMake:String(imports:TList, linkOptions:TList, buildDir:String)
	Local generatedRoot:String = buildDir + "/generated"
	CreateDir(generatedRoot, True)
	Local outputPath:String = generatedRoot + "/blitzmax_pico_native.cmake"
	Local output:String = "# Generated Pico native source graph; do not edit.~n"
	output :+ "set(BLITZMAX_PICO_NATIVE_SOURCES~n"
	For Local imported:TPicoNativeImport = EachIn imports
		output :+ "    ~q" + EscapePicoGeneratedString(imported.source.Replace("\", "/")) + "~q~n"
	Next
	output :+ ")~n"
	Local index:Int
	For Local imported:TPicoNativeImport = EachIn imports
		If imported.compileOptions.length Then
			output :+ "set(BLITZMAX_PICO_NATIVE_OPTIONS_" + index + " [==[" + imported.compileOptions + "]==])~n"
			output :+ "separate_arguments(BLITZMAX_PICO_NATIVE_OPTIONS_" + index + " NATIVE_COMMAND ~q${BLITZMAX_PICO_NATIVE_OPTIONS_" + index + "}~q)~n"
			output :+ "set_source_files_properties(~q" + EscapePicoGeneratedString(imported.source.Replace("\", "/")) + "~q PROPERTIES COMPILE_OPTIONS ~q${BLITZMAX_PICO_NATIVE_OPTIONS_" + index + "}~q)~n"
		End If
		index :+ 1
	Next
	Local combinedLinkOptions:String
	For Local option:String = EachIn linkOptions
		combinedLinkOptions = AppendPicoOption(combinedLinkOptions, option)
	Next
	If combinedLinkOptions.length Then
		output :+ "set(BLITZMAX_PICO_NATIVE_LINK_OPTIONS_RAW [==[" + combinedLinkOptions + "]==])~n"
		output :+ "separate_arguments(BLITZMAX_PICO_NATIVE_LINK_OPTIONS NATIVE_COMMAND ~q${BLITZMAX_PICO_NATIVE_LINK_OPTIONS_RAW}~q)~n"
	End If
	If FileType(outputPath) <> FILETYPE_FILE Or LoadText(outputPath) <> output Then
		If Not SaveText(output, outputPath) Then Throw "Unable to write generated Pico native source graph " + outputPath
	End If
	Return outputPath
End Function

Function GeneratePicoPIORegistry:String(imports:TList, buildDir:String, cmakeOutput:String Var)
	Local generatedRoot:String = buildDir + "/generated"
	CreateDir(generatedRoot, True)
	Local registryPath:String = generatedRoot + "/blitzmax_pio_registry.c"
	cmakeOutput = generatedRoot + "/blitzmax_pio_imports.cmake"

	Local source:String = "#include ~qblitzmax/pico_runtime.h~q~n"
	Local cmake:String = "# Generated Pico PIO imports; do not edit.~n"
	Local importIndex:Int
	For Local imported:TPicoPIOImport = EachIn imports
		Local outputDirectory:String = generatedRoot + "/pio/" + importIndex
		Local escapedSource:String = imported.source.Replace("\", "/").Replace("~q", "\~q")
		Local escapedOutput:String = outputDirectory.Replace("\", "/").Replace("~q", "\~q")
		cmake :+ "pico_generate_pio_header(${BLITZMAX_OUTPUT_NAME} ~q" + escapedSource + "~q OUTPUT_DIR ~q" + escapedOutput + "~q)~n"
		source :+ "#include ~qpio/" + importIndex + "/" + StripDir(imported.source) + ".h~q~n"
		importIndex :+ 1
	Next
	source :+ "~n#if PICO_PIO_VERSION > 0~n"
	source :+ "#define BMX_PICO_PIO_USED_RANGES(program) ((program).used_gpio_ranges)~n"
	source :+ "#else~n#define BMX_PICO_PIO_USED_RANGES(program) 0u~n#endif~n~n"

	importIndex = 0
	For Local imported:TPicoPIOImport = EachIn imports
		Local programIndex:Int
		For Local name:String = EachIn imported.programs
			source :+ "static int32_t bmx_pico_pio_initialize_" + importIndex + "_" + programIndex + "(void *instance, uint32_t state_machine, uint32_t offset) {~n"
			source :+ "    pio_sm_config config = " + name + "_program_get_default_config(offset);~n"
			source :+ "    return pio_sm_init((PIO)instance, state_machine, offset, &config);~n}~n"
			programIndex :+ 1
		Next
		importIndex :+ 1
	Next

	source :+ "~nconst BMXPicoPIOProgramDescriptor bmx_pico_imported_pio_programs[] = {~n"
	Local programCount:Int
	importIndex = 0
	For Local imported:TPicoPIOImport = EachIn imports
		Local programIndex:Int
		For Local name:String = EachIn imported.programs
			source :+ "    {~q" + EscapePicoGeneratedString(name) + "~q, " + name + "_program.instructions, "
			source :+ name + "_program.length, " + name + "_program.origin, " + name + "_program.pio_version, "
			source :+ "BMX_PICO_PIO_USED_RANGES(" + name + "_program), " + name + "_wrap_target, " + name + "_wrap, "
			source :+ "bmx_pico_pio_initialize_" + importIndex + "_" + programIndex + "},~n"
			programIndex :+ 1
			programCount :+ 1
		Next
		importIndex :+ 1
	Next
	If Not programCount Then source :+ "    {0},~n"
	source :+ "};~nconst uint32_t bmx_pico_imported_pio_program_count = " + programCount + "u;~n"

	If FileType(registryPath) <> FILETYPE_FILE Or LoadText(registryPath) <> source Then
		If Not SaveText(source, registryPath) Then Throw "Unable to write generated Pico PIO registry " + registryPath
	End If
	If FileType(cmakeOutput) <> FILETYPE_FILE Or LoadText(cmakeOutput) <> cmake Then
		If Not SaveText(cmake, cmakeOutput) Then Throw "Unable to write generated Pico PIO CMake integration " + cmakeOutput
	End If
	Return registryPath
End Function

Function MakePicoApplication(mainSource:String, outputPath:String, compileOnly:Int)
	If compileOnly Then Throw "The pico target currently supports makeapp, not compile"
	If processor.CPU() <> "arm" Then Throw "The pico target currently requires the arm architecture"
	If processor.BCCVersion() <> "bcc2" Then Throw "The pico target requires bcc2"
	If Not opt_release And Not PicoDebugBuild() Then Throw "The pico target requires an explicit -r or -d build mode"
	If opt_target_board <> "pico" And opt_target_board <> "pico2" Then
		Throw "The pico target currently supports -board pico and -board pico2"
	End If
	Local picoArenaSize:Long = ParsePicoHeapSize(opt_pico_heap, opt_target_board)

	Local sdk:String = BlitzMaxPath()
	Local picoModuleRoot:String = sdk + "/mod/pico.mod"
	Local blitzModuleRoot:String = sdk + "/mod/brl.mod/blitz.mod"
	Local bcc:String = sdk + "/bin/bcc"
	Local cmakeTemplate:String = picoModuleRoot + "/cmake/application"
	If FileType(picoModuleRoot) <> FILETYPE_DIR Then Throw "Pico modules were not found at " + picoModuleRoot
	If FileType(bcc) <> FILETYPE_FILE Then Throw "Pico-enabled bcc2 was not found at " + bcc
	If FileType(cmakeTemplate + "/CMakeLists.txt") <> FILETYPE_FILE Then Throw "Pico CMake application template was not found"

	Local platform:String = PicoHostPlatform()
	Local picoSdk:String = RequirePicoDirectory("the Pico SDK", "pico.sdk", "PICO_SDK_PATH", "sdk", [""])
	Local toolchain:String = PicoConfiguredPath("pico.toolchain", "PICO_TOOLCHAIN_PATH")
	If toolchain.length Then
		If FileType(toolchain + "/bin/" + PicoExecutableName("arm-none-eabi-gcc", platform)) <> FILETYPE_FILE Then Throw "The configured Pico ARM toolchain does not contain arm-none-eabi-gcc: " + toolchain
	Else
		Local gcc:String = PicoFindExecutableOnPath("arm-none-eabi-gcc", getenv_("PATH"), platform)
		If gcc.length Then toolchain = ExtractDir(ExtractDir(gcc))
		If Not toolchain.length Then toolchain = PicoLatestManagedPath(PicoUserHome(platform), "toolchain", [""])
		If Not toolchain.length Or FileType(toolchain + "/bin/" + PicoExecutableName("arm-none-eabi-gcc", platform)) <> FILETYPE_FILE Then Throw "Unable to locate the Pico ARM toolchain. Set #addoption pico.toolchain in custom.bmk, set PICO_TOOLCHAIN_PATH, add arm-none-eabi-gcc to PATH, or install it under the user Pico SDK directory."
	End If
	Local cmake:String = RequirePicoExecutable("CMake", "pico.cmake", "PICO_CMAKE", "cmake", "cmake", PicoCMakeManagedSuffixes(platform))
	Local ninja:String = RequirePicoExecutable("Ninja", "pico.ninja", "PICO_NINJA", "ninja", "ninja", PicoNinjaManagedSuffixes(platform))
	Local picotoolExecutable:String = RequirePicoExecutable("picotool", "pico.picotool", "PICOTOOL_DIR", "picotool", "picotool", PicoToolManagedSuffixes("picotool", platform))
	Local picotoolDir:String = PicoPackageDirectory(PicoConfiguredPath("pico.picotool", "PICOTOOL_DIR"), "picotool")
	If Not picotoolDir.length Then picotoolDir = PicoPackageDirectory(picotoolExecutable, "picotool")
	Local pioasmConfigured:String = PicoConfiguredPath("pico.pioasm", "PICO_PIOASM_DIR")
	Local pioasmExecutable:String
	If pioasmConfigured.length Then
		pioasmExecutable = PicoExecutableFromValue(pioasmConfigured, "pioasm", platform)
		If Not pioasmExecutable.length Then Throw "The configured pioasm path does not contain " + PicoExecutableName("pioasm", platform) + ": " + pioasmConfigured
	Else
		pioasmExecutable = PicoFindExecutableOnPath("pioasm", getenv_("PATH"), platform)
		If Not pioasmExecutable.length Then pioasmExecutable = PicoLatestManagedPath(PicoUserHome(platform), "tools", PicoToolManagedSuffixes("pioasm", platform))
	End If
	Local pioasmDir:String = PicoPackageDirectory(pioasmConfigured, "pioasm")
	If Not pioasmDir.length Then pioasmDir = PicoPackageDirectory(pioasmExecutable, "pioasm")

	Local outputBase:String = outputPath
	Select ExtractExt(outputBase).ToLower()
		Case "elf", "uf2", "hex", "bin"
			outputBase = StripExt(outputBase)
	End Select
	Local outputDirectory:String = ExtractDir(outputBase)
	If outputDirectory.length And FileType(outputDirectory) = FILETYPE_NONE Then
		If Not CreateDir(outputDirectory, True) Then Throw "Unable to create Pico output directory " + outputDirectory
	End If
	Local outputName:String = StripDir(outputBase)
	Local buildVariant:String = "release"
	If PicoDebugBuild() Then buildVariant = "debug"
	Local buildDir:String = ExtractDir(mainSource) + "/.bmx/" + StripDir(StripExt(mainSource)) + "." + buildVariant + ".pico.arm." + opt_target_board
	CreateDir(buildDir, True)
	Local compilerBuildRoot:String = buildDir + "/bcc"
	CreateDir(compilerBuildRoot, True)

	GeneratePicoInterface(bcc, sdk, "brl.blitz", blitzModuleRoot + "/blitz.bmx", blitzModuleRoot + "/blitz." + PicoBuildModeName() + ".pico.arm.i")

	Local picoApplicationUnits:TList
	Local picoUnits:TList = DiscoverPicoModules(mainSource, picoApplicationUnits)
	Local picoPIOImports:TList = DiscoverPicoPIOImports(mainSource, picoUnits)
	Local picoNativeLinkOptions:TList
	Local picoNativeImports:TList = DiscoverPicoNativeImports(mainSource, picoUnits, picoNativeLinkOptions)
	Local generatedModuleSources:String[] = New String[0]
	Local specializationOwners:TMap = New TMap
	Local unitIndex:Int
	For Local unit:TPicoModuleUnit = EachIn picoUnits
		Local bundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, unit.source, compilerBuildRoot + "/module_" + unitIndex, "module.c", unit.name, unit.sourceUnitPath, unit.interfacePath, "", False, "", PicoRuntimeHeaderPath(unit.source))
		AppendPicoBundleSources(bundle, generatedModuleSources, specializationOwners)
		unitIndex :+ 1
	Next
	Local generatedApplicationSources:String[] = New String[0]
	Local applicationIdentity:String = Bcc2ApplicationIdentity(mainSource)
	Local frameworkModule:String = ParseSourceFile(mainSource).framewk
	Local applicationUnitIndex:Int
	For Local applicationUnit:TPicoApplicationUnit = EachIn picoApplicationUnits
		Local bundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, applicationUnit.source, compilerBuildRoot + "/application_unit_" + applicationUnitIndex, "application_unit.c", applicationIdentity, applicationUnit.sourceUnitPath, applicationUnit.interfacePath, applicationIdentity, True, frameworkModule, PicoRuntimeHeaderPath(applicationUnit.source))
		AppendPicoBundleSources(bundle, generatedApplicationSources, specializationOwners)
		applicationUnitIndex :+ 1
	Next
	Local applicationBundle:TPicoBuildBundle = GeneratePicoBuildBundle(bcc, sdk, mainSource, compilerBuildRoot + "/application", "application.c", "", "", "", applicationIdentity, False, "", PicoRuntimeHeaderPath(mainSource))
	AppendPicoBundleSources(applicationBundle, generatedApplicationSources, specializationOwners)
	Local picoPIOCMake:String
	generatedApplicationSources :+ [GeneratePicoPIORegistry(picoPIOImports, buildDir, picoPIOCMake)]
	Local picoNativeCMake:String = GeneratePicoNativeCMake(picoNativeImports, picoNativeLinkOptions, buildDir)

	Local cmakeBuildType:String = "Release"
	If PicoDebugBuild() Then cmakeBuildType = "Debug"
	Local picoDeoptimizedDebug:Int = PicoDebugBuild()
	Local configure:String = CQuote(cmake) + " -S " + CQuote(cmakeTemplate) + " -B " + CQuote(buildDir) + " -G Ninja" + ..
		" -DPICO_SDK_PATH=" + CQuote(picoSdk) + ..
		" -DPICO_TOOLCHAIN_PATH=" + CQuote(toolchain) + ..
		" -DCMAKE_MAKE_PROGRAM=" + CQuote(ninja) + ..
		" -DCMAKE_BUILD_TYPE=" + cmakeBuildType + ..
		" -DPICO_DEOPTIMIZED_DEBUG=" + picoDeoptimizedDebug + ..
		" -DPICO_BOARD=" + opt_target_board + ..
		" -DBLITZMAX_PICO_ARENA_SIZE=" + picoArenaSize + ..
		" -DBLITZMAX_PICO_SDK=" + CQuote(sdk) + ..
		" -DBLITZMAX_APPLICATION_ROOT=" + CQuote(ExtractDir(mainSource)) + ..
		" -DBLITZMAX_OUTPUT_NAME=" + outputName + ..
		" -DBLITZMAX_GENERATED_C=" + CQuote(JoinPicoPaths(generatedApplicationSources)) + ..
		" -DBLITZMAX_PICO_GENERATED_SOURCES=" + CQuote(JoinPicoPaths(generatedModuleSources)) + ..
		" -DBLITZMAX_PICO_PIO_CMAKE=" + CQuote(picoPIOCMake) + ..
		" -DBLITZMAX_PICO_NATIVE_CMAKE=" + CQuote(picoNativeCMake) + ..
		" -DBLITZMAX_PICO_MODULE_INITIALIZERS=" + CQuote(JoinPicoModuleField(picoUnits, "initialize"))
	If picotoolDir.length Then configure :+ " -Dpicotool_DIR=" + CQuote(picotoolDir)
	If pioasmDir.length Then configure :+ " -Dpioasm_DIR=" + CQuote(pioasmDir)
	RunPicoCommand(configure, "Configuring Pico SDK application")
	RunPicoCommand(CQuote(cmake) + " --build " + CQuote(buildDir), "Building Pico SDK application")

	Local builtBase:String = buildDir + "/" + outputName
	For Local extension:String = EachIn ["elf", "uf2", "hex", "bin"]
		If FileType(builtBase + "." + extension) = FILETYPE_FILE Then
			If Not CopyFile(builtBase + "." + extension, outputBase + "." + extension) Then Throw "Unable to publish " + extension + " output"
		End If
	Next
	If FileType(builtBase + ".elf.map") = FILETYPE_FILE Then CopyFile(builtBase + ".elf.map", outputBase + ".elf.map")

	Local sizeTool:String = toolchain + "/bin/" + PicoExecutableName("arm-none-eabi-size", platform)
	If FileType(sizeTool) = FILETYPE_FILE Then ReportPicoMemory(sizeTool, outputBase + ".elf", opt_target_board, picoArenaSize)
	Print "Pico UF2: " + outputBase + ".uf2"
	If opt_execute Then UploadPicoFirmware(picotoolExecutable, outputBase + ".uf2")
End Function
