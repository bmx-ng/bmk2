SuperStrict

Import BRL.FileSystem

' Builds the semantic/code-generation configuration suffix for a bcc2
' invocation. Arguments which may contain spaces are quoted by the caller
' using bmk's platform-aware command quoting.
Function Bcc2CompilerConfigurationArgs:String(platform:String, architecture:String, releaseBuild:Int, threadedBuild:Int, coverageBuild:Int, gdbDebugBuild:Int, muslBuild:Int, verboseBuild:Int, applicationType:String = "", frameworkArgument:String = "", definitionsArgument:String = "")
	Local result:String = " --platform " + platform.ToLower()
	result :+ " --arch " + architecture.ToLower()
	If releaseBuild Then result :+ " --release" Else result :+ " --debug"
	If threadedBuild Then result :+ " --threaded" Else result :+ " --single-threaded"
	If coverageBuild Then result :+ " --coverage"
	If gdbDebugBuild Then result :+ " --gdb-debug"
	If muslBuild Then result :+ " --musl"
	If verboseBuild Then result :+ " --verbose"
	If definitionsArgument.length Then result :+ " --user-defs " + definitionsArgument
	If applicationType.length Then
		result :+ " --app-type " + applicationType.ToLower()
		If frameworkArgument.length Then result :+ " --framework " + frameworkArgument
	End If
	Return result
End Function

' Returns the same configuration as discrete values for the persistent bcc2
' engine protocol. Unlike the command-line helper, values are deliberately
' unquoted because the protocol transports argument boundaries explicitly.
Function Bcc2CompilerConfigurationValues:String[](platform:String, architecture:String, releaseBuild:Int, threadedBuild:Int, coverageBuild:Int, gdbDebugBuild:Int, muslBuild:Int, verboseBuild:Int, applicationType:String = "", frameworkValue:String = "", definitions:String = "")
	Local result:String[]
	result :+ ["--platform", platform.ToLower()]
	result :+ ["--arch", architecture.ToLower()]
	If releaseBuild Then result :+ ["--release"] Else result :+ ["--debug"]
	If threadedBuild Then result :+ ["--threaded"] Else result :+ ["--single-threaded"]
	If coverageBuild Then result :+ ["--coverage"]
	If gdbDebugBuild Then result :+ ["--gdb-debug"]
	If muslBuild Then result :+ ["--musl"]
	If verboseBuild Then result :+ ["--verbose"]
	If definitions.length Then result :+ ["--user-defs", definitions]
	If applicationType.length Then
		result :+ ["--app-type", applicationType.ToLower()]
		If frameworkValue.length Then result :+ ["--framework", frameworkValue]
	End If
	Return result
End Function

' Verbose and quiet affect reporting only. Keep them out of the generation
' fingerprint so changing console detail cannot invalidate generated bundles.
Function Bcc2GenerationFingerprintOptions:String(compilerOptions:String)
	Return compilerOptions.Replace(" -v", "").Replace(" -q", "")
End Function

' Application-owned quoted sources share one linkage namespace, while their
' runtime units remain distinct by source basename. The identity is deliberately
' independent of the absolute workspace path so relocating a source tree does
' not change generated ABI names.
Function Bcc2ApplicationIdentity:String(mainSourcePath:String)
	Local baseName:String = StripExt(StripDir(mainSourcePath)).ToLower()
	Local sanitized:String
	For Local index:Int = 0 Until baseName.length
		Local value:Int = baseName[index]
		If (value >= Asc("a") And value <= Asc("z")) Or (value >= Asc("0") And value <= Asc("9")) Or value = Asc("_") Then
			sanitized :+ Chr(value)
		Else
			sanitized :+ "_"
		End If
	Next
	If Not sanitized.length Then sanitized = "main"
	Return "application." + sanitized
End Function

' Canonicalizes an imported quoted source against its importing unit. The
' result is relative to the stable module/application source root, never the
' absolute checkout path.
Function Bcc2SourceUnitPath:String(parentUnitPath:String, importedPath:String)
	Local baseDirectory:String = ExtractDir(parentUnitPath.Replace("\\", "/").ToLower())
	Local candidate:String = importedPath.Replace("\\", "/").ToLower()
	If baseDirectory.length Then candidate = baseDirectory + "/" + candidate
	Local parts:String[] = candidate.Split("/")
	Local normalized:String[]
	For Local part:String = EachIn parts
		If Not part.length Or part = "." Then Continue
		If part = ".." Then
			If Not normalized.length Then Return ""
			normalized = normalized[..normalized.length - 1]
		Else
			normalized :+ [part]
		End If
	Next
	Local result:String
	For Local index:Int = 0 Until normalized.length
		If index Then result :+ "/"
		result :+ normalized[index]
	Next
	Return result
End Function

Function Bcc2SourceUnitIdentity:String(sourceUnitPath:String)
	Local normalized:String = StripExt(sourceUnitPath.Replace("\\", "/").ToLower())
	If normalized.Find("/") < 0 Then Return normalized
	Local hash:ULong = $CBF29CE484222325:ULong
	For Local index:Int = 0 Until normalized.length
		hash :~ ULong(normalized[index])
		hash :* $100000001B3:ULong
	Next
	Return normalized + "_" + String(hash)
End Function

Function Bcc2SourceUnitAbiIdentity:String(sourceUnitPath:String)
	Local identity:String = Bcc2SourceUnitIdentity(sourceUnitPath)
	Local result:String
	For Local index:Int = 0 Until identity.length
		Local value:Int = identity[index]
		If (value >= Asc("a") And value <= Asc("z")) Or (value >= Asc("0") And value <= Asc("9")) Or value = Asc("_") Then
			result :+ Chr(value)
		Else
			result :+ "_"
		End If
	Next
	Return result
End Function
