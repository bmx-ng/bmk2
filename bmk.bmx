Strict

Framework brl.filesystem

Import "bmk_make.bmx"
Import "bmk_zap.bmx"

?MacOS
Import BRL.RamStream
Incbin "macos.icns"
?

If AppArgs.length<2 CmdError "Not enough parameters", True

Local cmd$=AppArgs[1],args$[]
Local startupStartMillis:Int = MilliSecs()

args=ParseConfigArgs( AppArgs[2..], processor.BCCVersion() = "BlitzMax" )

If opt_clean And cmd.ToLower() <> "makeapp" Then
	CmdError "The -clean option is available only for makeapp"
End If

' validate the platform configuration
ValidatePlatformArchitecture()

' preload the default options
processor.RunCommand("default_cc_opts", Null)

' load any global custom options (in BlitzMax/bin)
LoadOptions

' pre-init gcc version cache
processor.GCCVersion(False, False, True)

If opt_verbose Then
	Print "bmk: startup/configuration: " + (MilliSecs() - startupStartMillis) + " ms"
End If

CreateDir BlitzMaxPath()+"/tmp"

Select cmd.ToLower()
Case "makeapp"
	If opt_universal And processor.Platform() = "macos" And Float(processor.XCodeVersion()) < 12 Then
		Throw "XCode 12+ required for universal macOS build"
	End If

	SetConfigMung
	MakeApplication args,False
Case "makelib"
	CmdError "makelib is not yet supported by canonical-only bcc2"
Case "makemods"
	If opt_universal And processor.Platform() = "macos" And Float(processor.XCodeVersion()) < 12 Then
		Throw "XCode 12+ required for universal macOS build"
	End If

	opt_quickscan = False
	If opt_debug Or opt_release
		SetConfigMung
		MakeModules args
		If opt_universal
			SetConfigMung
			processor.ToggleCPU()
			LoadOptions(True) ' reload options for PPC
			MakeModules args
			processor.ToggleCPU()
			LoadOptions(True)
		End If

	Else
		opt_debug=True
		opt_release=False
		SetConfigMung
		MakeModules args
		If opt_universal
			SetConfigMung
			processor.ToggleCPU()
			LoadOptions(True) ' reload options for PPC
			MakeModules args
			processor.ToggleCPU()
			LoadOptions(True)
		End If
		opt_debug=False
		opt_release=True
		SetConfigMung
		MakeModules args
		If opt_universal
			SetConfigMung
			processor.ToggleCPU()
			LoadOptions(True) ' reload options for PPC
			MakeModules args
			processor.ToggleCPU()
			LoadOptions(True)
		End If
	EndIf
Case "makebootstrap"
	' copy sources
	'   pub ->
	'          stdc, lua, win32, zlib, freeprocess
	'
	'   brl ->
	'          blitz, appstub, stream, filesystem, bank, ramstream, map, linkedlist, system, systemdefault, threads, stringbuilder, standardio
	'
	'   bah ->
	'          libcurl, mbedtls, libarchive, libxml, xz, libiconv
	'
	'
	' create folder in src -> bootstrap
	' create sub folders as per blitzmax layout
	' copy required mod sources
	' copy bmk/bcc/etc sources
	' make standalone's for each app, for all required target platforms.
	opt_boot = True
	MakeBootstrap
Case "compile"
	SetConfigMung
	MakeApplication args,False,True
Case "cleanmods"
	CleanModules args
Case "zapmod"
	ZapModule args
Case "unzapmod"
	UnzapModule args
Case "ranlibdir"
	RanlibDir args
Case "-v"
	VersionInfo(processor.GCCVersion(), GetCoreCount(), processor.XCodeVersion())
Default
	CmdError "Unknown operation '" + cmd.ToLower() + "'"
End Select

Function SetConfigMung()
	If opt_release
		opt_debug=False
		opt_configmung="release"
		If processor.BCCVersion() = "BlitzMax" Then
			If opt_threaded opt_configmung:+".mt"
		End If
	Else
		opt_debug=True
		opt_release=False
		opt_configmung="debug"
		If processor.BCCVersion() = "BlitzMax" Then
			If opt_threaded opt_configmung:+".mt"
		End If
	EndIf
	' Coverage changes both generated BlitzMax and native C objects, so it must
	' be part of debug as well as release configuration identities.
	If opt_coverage Then
		opt_configmung :+ ".cov"
	End If
	opt_configmung="."+opt_configmung+"."+processor.Platform()+"."'+opt_arch
End Function

Function SetModfilter( t$ )

	opt_modfilter=t.ToLower()

	If opt_modfilter="*"
		opt_modfilter=""
	Else If opt_modfilter[opt_modfilter.length-1]<>"."  And opt_modfilter.Find(".") < 0 Then
		opt_modfilter:+"."
	EndIf

End Function

Function MakeModules( args$[] )

	If opt_standalone CmdError "Standalone build not available for makemods"

	If args.length>1 CmdError "Expecting only 1 argument for makemods"

	Local mods:TList

	If args.length Then
		Local m:String = args[0].ToLower()
		If m.find(".") > 0 And m[m.length-1]<>"." Then
			' full module name?
			mods = New TList
			mods.AddLast(m)
			SetModfilter m
		Else
			SetModfilter m
			mods = EnumModules()
		End If
	Else
		opt_modfilter=""
		mods = EnumModules()
	End If

	BeginMake

	Local buildManager:TBuildManager = New TBuildManager

	buildManager.MakeMods(mods, opt_all)
	buildManager.DoBuild(False)

End Function

Function CleanModules( args$[] )

	If args.length>1 CmdError "Expecting only 1 argument for cleanmods"

	If args.length SetModfilter args[0] Else opt_modfilter=""

	Local mods:TList=EnumModules()
	Local cachePaths:TList = New TList
	Local outputPaths:TList = New TList

	Local name$
	For name=EachIn mods

		If opt_modfilter Then
			Local normalizedName:String = name.ToLower()
			If opt_modfilter.EndsWith(".") Then
				' A namespace filter includes every module below that namespace.
				If (normalizedName + ".").Find(opt_modfilter) <> 0 Then Continue
			Else
				' A full module name must not match similarly prefixed modules.
				If normalizedName <> opt_modfilter Then Continue
			End If
		End If

		Print "Cleaning:"+name

		Local path$=InstalledModulePath(name)

		CollectModuleCacheDirectories(path, cachePaths)
		CollectModuleOutputFiles(path, ModuleIdent(name), outputPaths)
		Rem
		If Not opt_kill Continue
		
		For Local f$=EachIn LoadDir( path )

			Local p$=path+"/"+f
			Select FileType(p)
			Case FILETYPE_DIR
				If f<>"doc"
					DeleteDir p,True
				EndIf
			Case FILETYPE_FILE
				Select ExtractExt(f).tolower()
				Case "i","a","txt","htm","html"
					'nop
				Default
					DeleteFile p
				End Select
			End Select

		Next
		End Rem
	Next

	' Inspect every selected cache before deleting any of them. A malformed cache
	' or symbolic link therefore leaves the complete selected set untouched.
	Local plans:TList = New TList
	For Local cachePath:String = EachIn cachePaths
		Local plan:TCompilerCachePlan = InspectCompilerCacheDirectory(cachePath, StripDir(cachePath), "module")
		If plan Then plans.AddLast(plan)
	Next
	Local outputPlans:TList = New TList
	For Local outputPath:String = EachIn outputPaths
		Local outputPlan:TCompilerOutputFilePlan = InspectCompilerOutputFile(outputPath, "module")
		If outputPlan Then outputPlans.AddLast(outputPlan)
	Next
	For Local plan:TCompilerCachePlan = EachIn plans
		plan.Execute(opt_verbose)
	Next
	For Local outputPlan:TCompilerOutputFilePlan = EachIn outputPlans
		outputPlan.Execute(opt_verbose)
	Next

End Function

Function IsDecimalCleanSuffix:Int(value:String)
	If Not value.length Then Return False
	For Local index:Int = 0 Until value.length
		If value[index] < Asc("0") Or value[index] > Asc("9") Then Return False
	Next
	Return True
End Function

Function IsModuleOutputPlatformArchitecture:Int(platform:String, architecture:String)
	Select platform
		Case "win32"
			Return architecture = "x86" Or architecture = "x64" Or architecture = "armv7" Or architecture = "arm64"
		Case "macos", "osx"
			Return architecture = "x86" Or architecture = "x64" Or architecture = "ppc" Or architecture = "arm64"
		Case "ios"
			Return architecture = "x86" Or architecture = "x64" Or architecture = "armv7" Or architecture = "arm64" Or architecture = "sim" Or architecture = "dev"
		Case "linux"
			Return architecture = "x86" Or architecture = "x64" Or architecture = "arm" Or architecture = "arm64" Or architecture = "riscv32" Or architecture = "riscv64"
		Case "android"
			Return architecture = "x86" Or architecture = "x64" Or architecture = "arm" Or architecture = "armeabi" Or architecture = "armeabiv7a" Or architecture = "arm64v8a"
		Case "raspberrypi"
			Return architecture = "arm" Or architecture = "arm64"
		Case "emscripten"
			Return architecture = "js"
		Case "nx"
			Return architecture = "arm64"
		Case "haiku"
			Return architecture = "x86" Or architecture = "x64" Or architecture = "arm64"
	End Select
	Return False
End Function

Function IsGeneratedModuleOutput:Int(fileName:String, moduleIdent:String)
	Local lowerName:String = fileName.ToLower()
	Local lowerIdent:String = moduleIdent.ToLower()
	If Not lowerName.StartsWith(lowerIdent + ".debug.") And Not lowerName.StartsWith(lowerIdent + ".release.") Then
		Return False
	End If

	Local temporaryIndex:Int = lowerName.Find(".bmk-tmp-")
	If temporaryIndex >= 0 Then
		Local temporarySuffix:String = lowerName[temporaryIndex + 9..]
		Local separator:Int = temporarySuffix.Find("-")
		If separator <= 0 Or separator >= temporarySuffix.length - 1 Then Return False
		If Not IsDecimalCleanSuffix(temporarySuffix[..separator]) Or Not IsDecimalCleanSuffix(temporarySuffix[separator + 1..]) Then Return False
		lowerName = lowerName[..temporaryIndex]
	End If

	Local stem:String
	If lowerName.EndsWith(".bmxbuild.stamp") Then
		stem = lowerName[..lowerName.length - ".bmxbuild.stamp".length]
	Else If lowerName.EndsWith(".bmxbuild") Then
		stem = lowerName[..lowerName.length - ".bmxbuild".length]
	Else If lowerName.EndsWith(".i2") Then
		stem = lowerName[..lowerName.length - 3]
	Else If lowerName.EndsWith(".i") Or lowerName.EndsWith(".a") Then
		stem = lowerName[..lowerName.length - 2]
	Else
		Return False
	End If

	Local components:String[] = stem.Split(".")
	If components.length < 4 Or components[0] <> lowerIdent Then Return False
	If components[1] <> "debug" And components[1] <> "release" Then Return False
	' The final two components are platform and architecture. Configuration
	' qualifiers between them are restricted to the values emitted by bmk.
	For Local index:Int = 2 Until components.length - 2
		If components[index] <> "mt" And components[index] <> "cov" Then Return False
	Next
	Return IsModuleOutputPlatformArchitecture(components[components.length - 2], components[components.length - 1])
End Function

Function CollectModuleOutputFiles(path:String, moduleIdent:String, outputPaths:TList)
	For Local fileName:String = EachIn LoadDir(path)
		If IsGeneratedModuleOutput(fileName, moduleIdent) Then outputPaths.AddLast(path + "/" + fileName)
	Next
End Function

Function CollectModuleCacheDirectories(path:String, cachePaths:TList)
		Local bmx:String = path + "/.bmx"
		If FileType(bmx) <> FILETYPE_NONE Then cachePaths.AddLast(bmx)

		Local generatedGenerics:String = path + "/.generics"
		If FileType(generatedGenerics) <> FILETYPE_NONE Then cachePaths.AddLast(generatedGenerics)

		For Local f:String = EachIn LoadDir( path )
			Local p:String = path + "/" + f
			If p = bmx Or p = generatedGenerics Then Continue
			Select FileType(p)
				Case FILETYPE_DIR
					' Module source trees may intentionally contain directory links.
					' They are not compiler-owned and must not broaden the clean scope.
					If Not readlink_(p).length Then CollectModuleCacheDirectories(p, cachePaths)
			End Select
		Next
End Function

Function MakeApplication( args$[],makelib:Int,compileOnly:Int = False )
	Local projectSetupStartMillis:Int = MilliSecs()

	If opt_execute And Not compileOnly
		If Len(args)=0 CmdError "Execute requires at least 1 argument"
	Else
		If Len(args)<>1 Then
			If compileOnly Then
				CmdError "Expecting only 1 argument for compile"
			Else
				CmdError "Expecting only 1 argument for makeapp"
			End If
		End If
	EndIf

	Local Main$=RealPath( args[0] )

	Select ExtractExt(Main).ToLower()
	Case ""
		Main:+".bmx"
	Case "c","cpp","cxx","mm","bmx"
	Default
		Throw "Unrecognized app source file type:"+ExtractExt(Main)
	End Select

	If FileType(Main)<>FILETYPE_FILE Throw "Unable to open source file '"+Main+"'"
	
	opt_infile = Main

	If Not opt_outfile Then
		opt_outfile = StripExt( Main )
	Else
		opt_outfile = RealPath(opt_outfile)
	End If

	If opt_universal And processor.Platform() = "macos" Then
		opt_outfile :+ "." + processor.CPU()
	End If


	' set some useful global variables
	globals.SetVar("BUILDPATH", ExtractDir(opt_infile))
	globals.SetVar("EXEPATH", ExtractDir(opt_outfile))
	globals.SetVar("OUTFILE", StripDir(StripExt(opt_outfile)))
	globals.SetVar("INFILE", StripDir(StripExt(opt_infile)))

	' some more useful globals
	If processor.Platform() = "macos" And opt_apptype="gui" And Not compileOnly Then
		Local appId$=StripDir( opt_outfile )
		
		If opt_universal Then
			appId = StripExt(appId)
		End If

		globals.SetVar("APPID", appId)
		' modify for bundle
		globals.SetVar("EXEPATH", ExtractDir(opt_outfile+".app/Contents/MacOS/"+appId))


		Local baseDir:String = opt_outfile
		If opt_universal Then
			baseDir = StripExt(baseDir)
		End If

		' make bundle dirs
		Local exeDir:String = baseDir + ".app"
		Local d:String
		
		d=exeDir+"/Contents/MacOS"
		Select FileType( d )
		Case FILETYPE_NONE
			CreateDir d,True
			If FileType( d )<>FILETYPE_DIR
				Throw "Unable to create application directory"
			EndIf
		Case FILETYPE_FILE
			Throw "Unable to create application directory"
		Case FILETYPE_DIR
		End Select

		d=exeDir+"/Contents/Resources"
		Select FileType( d )
		Case FILETYPE_NONE
			CreateDir d
			If FileType( d )<>FILETYPE_DIR
				Throw "Unable to create resources directory"
			EndIf
		Case FILETYPE_FILE
			Throw "Unable to create resources directory"
		Case FILETYPE_DIR
		End Select

	Else
		Local d:String = ExtractDir(opt_outfile)
		Select FileType(d)
			Case FILETYPE_NONE
				CreateDir d, True
				If FileType(d) <> FILETYPE_DIR Then
					Throw "Unable to create output directory : " + d
				End If
			Case FILETYPE_FILE
				Throw "Invalid output directory : " + d
		End Select
	End If


	If opt_verbose Then
		Print "bmk: project setup: " + (MilliSecs() - projectSetupStartMillis) + " ms"
	End If

	Local preBuildStartMillis:Int = MilliSecs()

	' generic pre process
	LoadBMK(ExtractDir(Main) + "/pre.bmk")

	' project-specific pre process
	LoadBMK(ExtractDir(Main) + "/" + StripDir( opt_outfile ) + ".pre.bmk")

	If opt_verbose Then
		Print "bmk: pre-build scripts: " + (MilliSecs() - preBuildStartMillis) + " ms"
	End If

	If processor.Platform() = "win32" Then
		If makelib
			If ExtractExt(opt_outfile).ToLower()<>"dll" opt_outfile:+".dll"
		Else
			If ExtractExt(opt_outfile).ToLower()<>"exe" opt_outfile:+".exe"
		EndIf
	EndIf

	If processor.Platform() = "macos" Or processor.Platform() = "osx" Then
		If opt_apptype="gui" And Not compileOnly

			'Local appId$=StripDir( opt_outfile )
			Local appId$ = globals.Get("APPID")

			Local baseDir:String = opt_outfile
			If opt_universal Then
				baseDir = StripExt(baseDir)
			End If
			Local exeDir:String = baseDir+".app"
			Local t:TStream

			t=WriteStream( exeDir+"/Contents/Info.plist" )
			If Not t Throw "Unable to create Info.plist"
			t.WriteLine "<?xml version=~q1.0~q encoding=~qUTF-8~q?>"
			t.WriteLine "<!DOCTYPE plist PUBLIC ~q-//Apple Computer//DTD PLIST 1.0//EN~q ~qhttp://www.apple.com/DTDs/PropertyList-1.0.dtd~q>"
			t.WriteLine "<plist version=~q1.0~q>"
			t.WriteLine "<dict>"
			t.WriteLine "~t<key>CFBundleExecutable</key>"
			t.WriteLine "~t<string>"+appId+"</string>"
			t.WriteLine "~t<key>CFBundleIconFile</key>"
			t.WriteLine "~t<string>"+appId+"</string>"
			t.WriteLine "~t<key>CFBundlePackageType</key>"
			t.WriteLine "~t<string>APPL</string>"
			t.WriteLine "~t<key>CFBundleIdentifier</key>"
			t.WriteLine "~t<string>local.blitzmax."+appId+"</string>"
			t.WriteLine "~t<key>CFBundleName</key>"
			t.WriteLine "~t<string>"+appId+"</string>"
			t.WriteLine "~t<key>CFBundleVersion</key>"
			t.WriteLine "~t<string>1.0</string>"
			t.WriteLine "~t<key>CFBundleShortVersionString</key>"
			t.WriteLine "~t<string>1.0</string>"
			t.WriteLine "~t<key>CFBundleDevelopmentRegion</key>"
			t.WriteLine "~t<string>en</string>"
			t.WriteLine "~t<key>LSMinimumSystemVersion</key>"
			t.WriteLine "~t<string>10.13</string>"
			t.WriteLine "~t<key>NSPrincipalClass</key>"
			t.WriteLine "~t<string>NSApplication</string>"
			If opt_hi Then
				t.WriteLine "~t<key>NSHighResolutionCapable</key>"
				t.WriteLine "~t<true/>"
			End If
			If globals.Get("custom_plist") Then
				t.WriteLine "~t" + globals.Get("custom_plist")
			End If
			t.WriteLine "</dict>"
			t.WriteLine "</plist>"
			t.Close

			t=WriteStream( exeDir+"/Contents/Resources/"+appId+".icns" )
			If Not t Throw "Unable to create icons"
			Local in:TStream=ReadStream( "incbin::macos.icns" )
			CopyStream in,t
			in.Close
			t.Close

			opt_outfile=exeDir+"/Contents/MacOS/"+appId

			If opt_universal Then
				opt_outfile :+ "." + processor.CPU()
			End If

		EndIf
	End If


	If processor.Platform() = "emscripten" Then
		If ExtractExt(opt_outfile).ToLower()<>"html" opt_outfile:+".html"
	End If

	If processor.Platform() = "nx" Then
		If ExtractExt(opt_outfile).ToLower()<>"elf" opt_outfile:+".elf"
	End If

	BeginMake

	'MakeApp Main,makelib

	Local buildManager:TBuildManager = New TBuildManager

	' "android-project" check and copy
	If processor.Platform() = "android" And Not compileOnly Then
		DeployAndroidProject()
	End If

	buildManager.MakeApp(Main, makelib, compileOnly)
	If opt_clean Then
		buildManager.CleanApplicationCaches()
		buildManager.ShutdownBccCompilers()
		BeginMake
		buildManager = New TBuildManager
		buildManager.MakeApp(Main, makelib, compileOnly)
	End If
	buildManager.DoBuild(makelib, Not compileOnly)

	If opt_universal And processor.Platform() = "macos" Then

		Local original:String = opt_outfile

		processor.ToggleCPU()
		LoadOptions(True) ' reload options for other arch

		opt_outfile  = StripExt(opt_outfile) + "." + processor.CPU()

		BeginMake

		Local buildManager:TBuildManager = New TBuildManager
		buildManager.MakeApp(Main, makelib, compileOnly)
		buildManager.DoBuild(False, True)

		processor.ToggleCPU()
		LoadOptions(True)
		
		MergeApp original, opt_outfile, StripExt(opt_outfile)
	End If

	If processor.Platform() = "nx" And Not compileOnly Then
		BuildNxDependencies()
	End If

	If opt_standalone And Not compileOnly

		Local suffix:String = ".build"
		If processor.Platform() = "win32" Then
			suffix :+ ".bat"
		End If

		Local buildScript:String = String(globals.GetRawVar("EXEPATH")) + "/" + StripExt(StripDir( app_main )) + "." + opt_apptype + opt_configmung + processor.CPU() + suffix

		Local stream:TStream = WriteStream(buildScript)

		If processor.Platform() <> "win32" Then
			Local ldScript:String = "$APP_ROOT/ld." + processor.AppDet() + ".txt"

			stream.WriteString("set -e~n~n")
			stream.WriteString("echo ~qBuilding " + String(globals.GetRawVar("OUTFILE")) + "...~q~n~n")

			stream.WriteString("if [ -z ~q${APP_ROOT}~q ]; then~n")
			If opt_boot Then
				stream.WriteString("~tAPP_ROOT=`pwd`~n")
			Else
				stream.WriteString("~tAPP_ROOT=" + String(globals.GetRawVar("EXEPATH")) + "~n")
			End If
			stream.WriteString("fi~n~n")

			stream.WriteString("if [ -z ~q${BMX_ROOT}~q ]; then~n")
			If opt_boot Then
				stream.WriteString("~tBMX_ROOT=$(dirname $(dirname `pwd`))~n")
			Else
				stream.WriteString("~tBMX_ROOT=" + BlitzMaxPath() + "~n")
			End If
			stream.WriteString("fi~n")
			stream.WriteString("~n~n")

			stream.WriteString("cp " + ldScript + " " + ldScript + ".tmp~n")

			stream.WriteString("sed -i -- 's=\$BMX_ROOT='$BMX_ROOT'=g' " + ldScript + ".tmp~n")
			stream.WriteString("sed -i -- 's=\$APP_ROOT='$APP_ROOT'=g' " + ldScript + ".tmp~n")

			stream.WriteString("~n~n")
		Else
			Local ldScript:String = "%APP_ROOT%\ld." + processor.AppDet() + ".txt"
			Local minGWDirectory:String = "MinGW32"
			Select processor.CPU()
				Case "x86"
					minGWDirectory = "MinGW32x86"
				Case "x64"
					minGWDirectory = "MinGW32x64"
			End Select

			stream.WriteString("@ECHO OFF~n")
			stream.WriteString("SETLOCAL ENABLEEXTENSIONS~n")
			stream.WriteString("SET ~qPARENT=%~~dp0~q~n~n")

			stream.WriteString("echo Building " + String(globals.GetRawVar("OUTFILE")) + "...~n")

			stream.WriteString("If Not DEFINED APP_ROOT (~n")
			If opt_boot Then
				stream.WriteString("~tSET ~qAPP_ROOT=%PARENT%.~q~n")
			Else
				stream.WriteString("~tSET ~qAPP_ROOT=" + String(globals.GetRawVar("EXEPATH")) + "~q~n")
			End If
			stream.WriteString(")~n~n")
			stream.WriteString("FOR %%I IN (~q%APP_ROOT%~q) DO SET ~qAPP_ROOT=%%~~fI~q~n~n")

			stream.WriteString("If Not DEFINED BMX_ROOT (~n")
			If opt_boot Then
				stream.WriteString("~tSET ~qBMX_ROOT=%PARENT%..\..~q~n")
			Else
				stream.WriteString("~tSET ~qBMX_ROOT=" + BlitzMaxPath() + "~q~n")
			End If
			stream.WriteString(")~n~n")
			stream.WriteString("FOR %%I IN (~q%BMX_ROOT%~q) DO SET ~qBMX_ROOT=%%~~fI~q~n~n")

			stream.WriteString("If Not DEFINED MINGW_BIN (~n")
			stream.WriteString("~tSET ~qMINGW_BIN=%BMX_ROOT%\" + minGWDirectory + "\bin~q~n")
			stream.WriteString(")~n~n")
			stream.WriteString("FOR %%I IN (~q%MINGW_BIN%~q) DO SET ~qMINGW_BIN=%%~~fI~q~n~n")
			stream.WriteString("set ~qPATH=%MINGW_BIN%;%PATH%~q~n~n")

			stream.WriteString("%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe -Command ~q$bmxRoot = $env:BMX_ROOT.Replace('\','/'); ((get-content \~q" + ldScript + "\~q) -replace '%%BMX_ROOT%%',$bmxRoot) | set-content \~q" + ldScript + ".tmp\~q~q~n~n")
		End If

		If processor.buildLog Then
			For Local s:String = EachIn processor.buildLog
				stream.WriteString(s + "~n")
				If processor.Platform() = "win32" Then stream.WriteString("If ErrorLevel 1 Goto BuildFailed~n")
			Next
		End If

		If processor.Platform() <> "win32" Then
			stream.WriteString("unset APP_ROOT~n")
			stream.WriteString("~necho ~qFinished.~q~n")

		Else
			stream.WriteString("echo Finished.~n")
			stream.WriteString("ENDLOCAL~n")
			stream.WriteString("Exit /B 0~n~n")
			stream.WriteString(":BuildFailed~n")
			stream.WriteString("SET ~qBUILD_ERROR=%ERRORLEVEL%~q~n")
			stream.WriteString("ENDLOCAL & Exit /B %BUILD_ERROR%~n")
		End If

		stream.Close()

	End If
	
	If opt_upx And Not compileOnly Then
		MakeUpx()
	End If

	If opt_execute And Not compileOnly

?Not android
		Print "Executing:"+StripDir( opt_outfile )

		Local cmd$=CQuote( opt_outfile )
		For Local i=1 Until args.length
			cmd:+" "+CQuote( args[i] )
		Next

		Sys cmd
?android
		' on android we'll deploy the apk

?


	EndIf

End Function

Function ZapModule( args$[] )
	If Len(args)<>2 CmdError "Both module name and outfile required"

	Local modname$=args[0].ToLower()
	Local outfile$=RealPath( args[1] )

	Local stream:TStream=WriteStream( outfile )
	If Not stream Throw "Unable to open output file"

	ZapMod modname,stream

	stream.Close
End Function

Function UnzapModule( args$[] )
	If Len(args)<>1 CmdError "Expecting 1 argument for unzapmod"

	Local infile$=args[0]

	Local stream:TStream=ReadStream( infile )
	If Not stream Throw "Unable to open input file"

	UnzapMod stream

	stream.Close
End Function

Function RanlibDir( args$[] )
	If args.length<>1 CmdError "Expecting 1 argument for ranlibdir"

	Ranlib args[0]

End Function

Function LoadOptions(reload:Int = False)
	If reload Then
		' reset the options to default
		processor.RunCommand("default_cc_opts", Null)
	End If
	LoadBMK(AppDir + "/custom.bmk")
End Function

Function MakeBootstrap()

	Local config:TBootstrapConfig = LoadBootstrapConfig()

	Local bootstrapPath:String = BlitzMaxPath() + "/dist/bootstrap"

	' A bootstrap is a complete generated source snapshot. Keeping files from a
	' previous invocation can make removed sources appear to remain supported.
	If FileType(bootstrapPath) <> FILETYPE_NONE Then
		If Not DeleteDir(bootstrapPath, True) Throw "Error clearing bootstrap folder"
	End If
	If Not CreateDir(bootstrapPath, True) Throw "Error creating bootstrap folder"

	If Not CreateDir(bootstrapPath + "/bin") Throw "Error creating boostrap/bin folder"
	If Not CreateDir(bootstrapPath + "/mod") Throw "Error creating boostrap/mod folder"
	If Not CreateDir(bootstrapPath + "/src") Throw "Error creating boostrap/src folder"

	config.CopyAssets(bootstrapPath)

	opt_release = True
	opt_all = True

	For Local target:TBootstrapTarget = EachIn config.targets
		For Local app:TBootstrapAsset = EachIn config.assets
			If app.assetType <> "a" Then
				Continue
			End If

			Local appPath:String = BootstrapApplicationSource(app.name)

			' Keep the bootstrap executable and native build script at the
			' traditional src/<app> boundary even when canonical sources use a
			' nested implementation directory such as src/bcc/compiler.
			opt_outfile = BlitzMaxPath() + "/src/" + app.name + "/" + app.name
			opt_standalone = True
			opt_warnover = True

			opt_target_platform = target.platform
			opt_arch = target.arch

			Print "Generating " + app.name + " : " + target.platform + "/" + target.arch

			Local args:String[] = [appPath]

			processor.Reset()

			SetConfigMung
			LoadOptions(True)
			MakeApplication args,False

			config.CopySources(bootstrapPath, processor.sourceList)
			config.CopyScripts(bootstrapPath, app)
		Next
	Next

End Function

Function BootstrapApplicationSource:String(appName:String)
	Local sourceRoot:String = BlitzMaxPath() + "/src/" + appName
	Local directPath:String = sourceRoot + "/" + appName + ".bmx"
	If FileType(directPath) = FILETYPE_FILE Then Return directPath
	Local compilerPath:String = sourceRoot + "/compiler/" + appName + ".bmx"
	If FileType(compilerPath) = FILETYPE_FILE Then Return compilerPath
	Throw "App not found : " + appName
End Function
