
SuperStrict

Import "bmk_modutil.bmx"
Import "bmk_bcc2_options.bmx"
Import "bmk_bcc2_engine.bmx"
Import "bmk_bcc2_manifest.bmx"
Import "bmk_clean.bmx"

Type TBuildDependencyNode
	Field source:TSourceFile
	Field remaining:Int
	Field dependents:TList = New TList
End Type

Type TBcc2ValidationDeclaration
	Field source:TSourceFile
	Field expectedDigest:String
End Type

Type TBcc2ValidationFile
	Field path:String
	Field normalizedPath:String
	Field exists:Int
	Field size:Long
	Field digest:String
	Field failure:Object
	Field declarations:TList = New TList
End Type

Type TBcc2ValidationLane
	Field files:TList = New TList
	Field totalBytes:Long

	Function Run:Object(data:Object)
		Local lane:TBcc2ValidationLane = TBcc2ValidationLane(data)
		For Local file:TBcc2ValidationFile = EachIn lane.files
			Try
				If Not file.exists Then Throw "BMKGEN020 declared compiler output is missing: " + file.path
				file.digest = TBcc2BuildManifestCodec.FileDigest(file.path)
			Catch exception:Object
				file.failure = exception
			End Try
		Next
		Return Null
	End Function
End Type

Type TBcc2CompileWork
	Field source:TSourceFile
	Field arguments:String[]
	Field response:TBcc2EngineResponse
	Field failure:Object
	Field finalBuildRoot:String
	Field stagingBuildRoot:String
	Field stagedManifest:TBcc2BuildManifest
	Field cleanupPath:String
	Field cleanupFailure:Object
End Type

Type TBcc2CompileLane
	Field client:TBcc2EngineClient
	Field works:TList = New TList

	Function Run:Object(data:Object)
		Local lane:TBcc2CompileLane = TBcc2CompileLane(data)
		For Local work:TBcc2CompileWork = EachIn lane.works
			Try
				work.response = lane.client.Compile(work.arguments)
			Catch exception:Object
				work.failure = exception
			End Try
		Next
		Return Null
	End Function
End Type

Type TBcc2CleanupLane
	Field works:TList = New TList

	Function Run:Object(data:Object)
		Local lane:TBcc2CleanupLane = TBcc2CleanupLane(data)
		For Local work:TBcc2CompileWork = EachIn lane.works
			Try
				If FileType(work.cleanupPath) = FILETYPE_DIR And Not DeleteDir(work.cleanupPath, True) Then
					Throw "BMKGEN054 unable to remove compiler staging directory: " + work.cleanupPath
				End If
			Catch exception:Object
				work.cleanupFailure = exception
			End Try
		Next
		Return Null
	End Function
End Type

Type TBcc2SpecializationCompileWork
	Field objectPath:String
	Field keyPath:String
	Field expectedKey:String
	Field normalizedObjectPath:String
End Type

Function CompareBcc2ValidationFiles:Int(left:Object, right:Object)
	Local leftFile:TBcc2ValidationFile = TBcc2ValidationFile(left)
	Local rightFile:TBcc2ValidationFile = TBcc2ValidationFile(right)
	If leftFile.size < rightFile.size Then Return -1
	If leftFile.size > rightFile.size Then Return 1
	Return leftFile.normalizedPath.Compare(rightFile.normalizedPath)
End Function

Global cc_opts$
Global bcc_opts$
Global cpp_opts$
Global c_opts$
Global asm_opts:String
Function BeginMake()
	InitializeInstalledModuleCatalogue()
	cc_opts=Null
	cpp_opts=Null
	c_opts=Null
	bcc_opts=Null
	asm_opts=Null
	app_main=Null
	opt_framework=""
End Function

Function ConfigureAndroidPaths()
	CheckAndroidPaths()
	
	Local toolchain:String
	Local toolchainBin:String
	Local arch:String
	Local abi:String
	
	Select processor.CPU()
		Case "x86"
			toolchain = "x86-"
			toolchainBin = "i686-linux-android-"
			arch = "arch-x86"
			abi = "x86"
		Case "x64"
			toolchain = "x86_64-"
			toolchainBin = "x86_64-linux-android-"
			arch = "arch-x86_64"
			abi = "x86_64"
		Case "arm", "armeabi", "armeabiv7a"
			toolchain = "arm-linux-androideabi-"
			toolchainBin = "arm-linux-androideabi-"
			arch = "arch-arm"
			If processor.CPU() = "armeabi" Then
				abi = "armeabi"
			Else
				abi = "armeabi-v7a"
			End If
		Case "arm64v8a"
			toolchain = "aarch64-linux-android-"
			toolchainBin = "aarch64-linux-android-"
			arch = "arch-arm64"
			abi = "arm64-v8a"
	End Select
	
	Local native:String
?macos
	native = "darwin"
?linux
	native = "linux"
?win32
	native = "windows"
?

	Local toolchainDir:String = processor.Option("android.ndk", "") + "/toolchains/" + ..
			toolchain + processor.Option("android.toolchain.version", "") + "/prebuilt/" + native
	
	' look for 64 bit build first, then x86, then fallback to no architecture (generally on 32-bit dists)
	If FileType(toolchainDir + "-x86_64") = FILETYPE_DIR Then
		toolchainDir :+ "-x86_64"
	Else If FileType(toolchainDir + "-x86") = FILETYPE_DIR Then
		toolchainDir :+ "-x86"
	Else If FileType(toolchainDir) <> FILETYPE_DIR Then
		Throw "Cannot determine toolchain dir for '" + native + "', at '" + toolchainDir + "'"
	End If

	Local exe:String	
?win32
	exe = ".exe"
?
	
	Local gccPath:String = toolchainDir + "/bin/" + toolchainBin + "gcc" + exe
	Local gppPath:String = toolchainDir + "/bin/" + toolchainBin + "g++" + exe
	Local arPath:String = toolchainDir + "/bin/" + toolchainBin + "ar" + exe
	Local libPath:String = toolchainDir + "/lib"

	' check paths
	If Not FileType(RealPath(gccPath)) Then
		Throw "gcc not found at '" + gccPath + "'"
	End If

	If Not FileType(RealPath(gppPath)) Then
		Throw "g++ not found at '" + gppPath + "'"
	End If

	If Not FileType(RealPath(gccPath)) Then
		Throw "ar not found at '" + arPath + "'"
	End If
	
	globals.SetVar("android." + processor.CPU() + ".gcc", gccPath)
	globals.SetVar("android." + processor.CPU() + ".gpp", gppPath)
	globals.SetVar("android." + processor.CPU() + ".ar", arPath)
	globals.SetVar("android." + processor.CPU() + ".lib", "-L" + libPath)

	' platform
	Local platformDir:String = processor.Option("android.ndk", "") + "/platforms/android-" + ..
			processor.Option("android.platform", "") + "/" + arch

	If Not FileType(platformDir) Then
		Throw "Cannot determine platform dir for '" + arch + "' at '" + platformDir + "'"
	End If
	
	' platform sysroot
	globals.SetVar("android.platform.sysroot", "--sysroot " + platformDir)
	globals.AddOption("cc_opts", "android.platform.sysroot", "--sysroot " + platformDir)
	
	' abi
	globals.SetVar("android.abi", abi)
	
	' sdk target
	Local target:String = GetAndroidSDKTarget()

	If Not target Or Not FileType(processor.Option("android.sdk", "") + "/platforms/android-" + target) Then
		Local sdkPath:String = processor.Option("android.sdk.target", "")
		If sdkPath Then
			Throw "Cannot determine SDK target for '" + sdkPath + "'"
		Else
			Throw "Cannot determine SDK target dir. ANDROID_SDK_TARGET or android.sdk.target option is not set, and auto-lookup failed."
		End If
	End If

	globals.SetVar("android.sdk.target", target)

End Function

Function CheckAndroidPaths()
	' check envs and paths
	Local androidHome:String = processor.Option("android.home", getenv_("ANDROID_HOME")).Trim()
	If Not androidHome Then
		Throw "ANDROID_HOME or 'android.home' config option not set"
	End If
		
	putenv_("ANDROID_HOME=" + androidHome)
	globals.SetVar("android.home", androidHome)
	
	Local androidSDK:String = processor.Option("android.sdk", getenv_("ANDROID_SDK")).Trim()
	If Not androidSDK Then
		Throw "ANDROID_SDK or 'android.sdk' config option not set"
	End If
		
	putenv_("ANDROID_SDK=" + androidSDK)
	globals.SetVar("android.sdk", androidSDK)

	Local androidNDK:String = processor.Option("android.ndk", getenv_("ANDROID_NDK")).Trim()
	If Not androidNDK Then
		Throw "ANDROID_NDK or 'android.ndk' config option not set"
	End If
		
	putenv_("ANDROID_NDK=" + androidNDK)
	globals.SetVar("android.ndk", androidNDK)

	Local androidToolchainVersion:String = processor.Option("android.toolchain.version", getenv_("ANDROID_TOOLCHAIN_VERSION")).Trim()
	If Not androidToolchainVersion Then
		Throw "ANDROID_TOOLCHAIN_VERSION or 'android.toolchain.version' config option not set"
	End If
		
	putenv_("ANDROID_TOOLCHAIN_VERSION=" + androidToolchainVersion)
	globals.SetVar("android.toolchain.version", androidToolchainVersion)

	Local androidPlatform:String = processor.Option("android.platform", getenv_("ANDROID_PLATFORM")).Trim()
	If Not androidPlatform Then
		Throw "ANDROID_PLATFORM or 'android.platform' config option not set"
	End If
		
	putenv_("ANDROID_PLATFORM=" + androidPlatform.Trim())
	globals.SetVar("android.platform", androidPlatform)

	Local androidSDKTarget:String = processor.Option("android.sdk.target", getenv_("ANDROID_SDK_TARGET")).Trim()

	' NOTE : if not set, we'll try to determine the actual target later, and fail if required then.
	If androidSDKTarget Then
		putenv_("ANDROID_SDK_TARGET=" + androidSDKTarget)
		globals.SetVar("android.sdk.target", androidSDKTarget)
	End If
		
	Local antHome:String = processor.Option("ant.home", getenv_("ANT_HOME")).Trim()
	If Not antHome Then
		' as a further fallback, we can use the one from resources folder if it exists.
		Local antDir:String = RealPath(BlitzMaxPath() + "/resources/android/apache-ant")
		
		If FileType(antDir) <> FILETYPE_DIR Then
			Throw "ANT_HOME or 'ant.home' config option not set, and resources missing apache-ant."
		Else
			antHome = antDir
			globals.SetVar("ant.home", antHome)
		End If
	End If
		
	putenv_("ANT_HOME=" + antHome)
	globals.SetVar("ant.home", antHome)

?Not win32	
	Local pathSeparator:String = ":"
	Local dirSeparator:String = "/"
?win32
	Local pathSeparator:String = ";"
	Local dirSeparator:String = "\"
?
	Local path:String = getenv_("PATH")
	path = androidSDK + dirSeparator + "platform-tools" + pathSeparator + path
	path = androidSDK + dirSeparator + "tools" + pathSeparator + path
	path = androidNDK + pathSeparator + path
	path = antHome + dirSeparator + "bin" + pathSeparator + path
	putenv_("PATH=" + path)

End Function

Function ConfigureIOSPaths()

	Select processor.CPU() 
		Case "x86", "x64"
			Local path:String = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk"
			globals.SetVar("ios." + processor.CPU() + ".sysroot", path)
			globals.SetVar("ios." + processor.CPU() + ".syslibroot", path)
		Case "armv7", "arm64"
			Local path:String = "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
			globals.SetVar("ios." + processor.CPU() + ".sysroot", path)
			globals.SetVar("ios." + processor.CPU() + ".syslibroot", path)
	End Select

End Function

Function ConfigureNXPaths()
	CheckNXPaths()
	
	Local toolchainBin:String
	
	Select processor.CPU()
		Case "arm64"
			toolchainBin = "aarch64-none-elf-"
	End Select

	Local toolchainDir:String = processor.Option("nx.devkitpro", "") + "/devkitA64/"
	
	If FileType(RealPath(toolchainDir)) <> FILETYPE_DIR Then
		Throw "Cannot determine toolchain dir for NX, at '" + toolchainDir + "'"
	End If

	Local exe:String	
?win32
	exe = ".exe"
?
	Local gccPath:String = toolchainDir + "/bin/" + toolchainBin + "gcc" + exe
	Local gppPath:String = toolchainDir + "/bin/" + toolchainBin + "g++" + exe
	Local arPath:String = toolchainDir + "/bin/" + toolchainBin + "ar" + exe
	Local libPath:String = toolchainDir + "/lib"

	' check paths
	If Not FileType(RealPath(gccPath)) Then
		Throw "gcc not found at '" + gccPath + "'"
	End If

	If Not FileType(RealPath(gppPath)) Then
		Throw "g++ not found at '" + gppPath + "'"
	End If

	If Not FileType(RealPath(gccPath)) Then
		Throw "ar not found at '" + arPath + "'"
	End If
	
	globals.SetVar("nx." + processor.CPU() + ".gcc", gccPath)
	globals.SetVar("nx." + processor.CPU() + ".gpp", gppPath)
	globals.SetVar("nx." + processor.CPU() + ".ar", arPath)
	globals.SetVar("nx." + processor.CPU() + ".lib", "-L" + libPath)

?Not win32	
	Local pathSeparator:String = ":"
	Local dirSeparator:String = "/"
?win32
	Local pathSeparator:String = ";"
	Local dirSeparator:String = "\"
?
	Local path:String = getenv_("PATH")
	path = toolchainDir + dirSeparator + "bin" + pathSeparator + path
	putenv_("PATH=" + path)

End Function

Function CheckNXPaths()
	' check envs and paths
	Local devkitpro:String = processor.Option("nx.devkitpro", getenv_("DEVKITPRO")).Trim()
	If Not devkitpro Then
		Throw "DEVKITPRO or 'nx.devkitpro' config option not set"
	End If
		
	putenv_("DEVKITPRO=" + devkitpro)
	globals.SetVar("nx.devkitpro", devkitpro)
		
End Function

Type TBcc2SpecializationOwner
	Field specializationIdentity:String
	Field cacheKey:String
	Field contentDigest:String
	Field objectPath:String
	Field manifestPath:String
	Field priority:Int
End Type

Type TBuildManager Extends TCallback

	Field sources:TMap = New TMap
	Field bcc2Engines:TBcc2EngineClient[] = New TBcc2EngineClient[0]
	Field parallelBcc2Generated:TMap = New TMap
	' Several source manifests in the same directory can resolve an identical
	' specialization to the same cache object. Their inherited include-path
	' strings need not be byte-identical even though the generated C and object
	' target are. Once that object has been validated or compiled successfully
	' in this build, do not invalidate it again from a later requesting source.
	Field ensuredBcc2SpecializationObjects:TMap = New TMap
	Field ensuredBcc2SpecializationDirectories:TMap = New TMap
	Field cachedBcc2SpecializationOwners:TMap
	Field cachedBcc2SpecializationIdentitiesByObject:TMap
	' A forced build must be able to replace a partially published application
	' graph. Old manifests scheduled for regeneration are provisional until the
	' compiler successfully republishes them; the final application link still
	' performs a strict ownership pass over every manifest.
	Field pendingForcedBcc2Manifests:TMap = New TMap
	
	Field buildAll:Int
	
	Field framework_mods:TList
	Field app_iface:String
	Field dependencySourceCount:Int
	Field dependencyModuleImportCount:Int
	Field dependencyFileImportCount:Int
	Field dependencyIncludeCount:Int
	Field dependencyIncbinCount:Int
	Field manifestValidationCount:Int
	Field manifestValidationMillis:Int
	Field manifestValidationStats:TBcc2BuildValidationStats = New TBcc2BuildValidationStats
	Field pendingBcc2ValidationFiles:TMap = New TMap
	Field invalidBcc2ValidationSources:TMap = New TMap
	Field bcc2PublishedOutputDigests:TMap = New TMap
	Field manifestValidationWorkers:Int
	Field bcc2CompilationMillis:Int
	Field bcc2CompilationRequests:Int
	Field bcc2ParallelCompilationBatches:Int
	Field bcc2SetupMillis:Int
	Field bcc2EngineMillis:Int
	Field bcc2ValidationMillis:Int
	Field bcc2PublicationMillis:Int
	Field bcc2FinalizationMillis:Int
	Field bcc2InvalidationMillis:Int
	Field bcc2CleanupMillis:Int
	Field bcc2SpecializationCompilationMillis:Int
	Field bcc2SpecializationCompilationObjects:Int
	Field bcc2SpecializationParallelBatches:Int

	Method LogVerbosePhase(name:String, startedMillis:Int, detail:String = "")
		If Not opt_verbose Then Return
		Local message:String = "bmk: " + name + ": " + (MilliSecs() - startedMillis) + " ms"
		If detail Then message :+ " (" + detail + ")"
		Print message
	End Method

	Method QueueBcc2ManifestValidation(source:TSourceFile)
		For Local file:TBcc2BuildFile = EachIn source.bcc2Manifest.files
			Local path:String = TBcc2BuildManifestCodec.Resolve(source.bcc2BuildRoot, file.relativePath)
			Local normalizedPath:String = path.Replace("\", "/").ToLower()
			Local validationFile:TBcc2ValidationFile = TBcc2ValidationFile(pendingBcc2ValidationFiles.ValueForKey(normalizedPath))
			If Not validationFile Then
				validationFile = New TBcc2ValidationFile
				validationFile.path = path
				validationFile.normalizedPath = normalizedPath
				Local info:SFileStat
				validationFile.exists = FileStat(path, info) And info.fileType = FILETYPE_FILE
				validationFile.size = Max(Long(0), info.size)
				pendingBcc2ValidationFiles.Insert(normalizedPath, validationFile)
			Else
				manifestValidationStats.reusedFiles :+ 1
			End If
			Local declaration:TBcc2ValidationDeclaration = New TBcc2ValidationDeclaration
			declaration.source = source
			declaration.expectedDigest = file.contentDigest
			validationFile.declarations.AddLast(declaration)
			manifestValidationStats.declarations :+ 1
		Next
	End Method

	Method InvalidateBcc2ValidatedSource(source:TSourceFile)
		Local sourceKey:String = source.path.Replace("\", "/").ToLower()
		If invalidBcc2ValidationSources.Contains(sourceKey) Then Return
		invalidBcc2ValidationSources.Insert(sourceKey, source)
		source.bcc2Manifest = Null
		TBcc2BuildManifestCodec.Invalidate(source.bcc2ManifestPath)
		source.SetRequiresBuild(True)
		Local objectStage:TSourceFile = TSourceFile(sources.ValueForKey(StripExt(source.obj_path) + ".c"))
		If objectStage Then source.CopyInfo(objectStage)
		InvalidateBcc2SpecializationOwners()
	End Method

	Method Bcc2ValidationWorkerCount:Int(fileCount:Int)
		Local workers:Int = Int(getenv_("BMK_MANIFEST_VALIDATION_WORKERS"))
		If workers <= 0 Then workers = Min(4, Max(1, GetCoreCount() - 1))
		workers = Min(workers, Max(1, GetCoreCount() - 1))
?Not threaded
		workers = 1
?
		If Not opt_threaded Then workers = 1
		Return Max(1, Min(workers, fileCount))
	End Method

	Method ValidatePendingBcc2Manifests()
		If pendingBcc2ValidationFiles.IsEmpty() Then Return
		Local validationStartMillis:Int = MilliSecs()
		Local files:TList = New TList
		For Local file:TBcc2ValidationFile = EachIn pendingBcc2ValidationFiles.Values()
			files.AddLast(file)
		Next
		files.Sort(False, CompareBcc2ValidationFiles)

		manifestValidationWorkers = Bcc2ValidationWorkerCount(files.Count())
		Local lanes:TBcc2ValidationLane[] = New TBcc2ValidationLane[manifestValidationWorkers]
		For Local index:Int = 0 Until lanes.length
			lanes[index] = New TBcc2ValidationLane
		Next
		For Local file:TBcc2ValidationFile = EachIn files
			Local lightest:Int
			For Local index:Int = 1 Until lanes.length
				If lanes[index].totalBytes < lanes[lightest].totalBytes Then lightest = index
			Next
			lanes[lightest].files.AddLast(file)
			lanes[lightest].totalBytes :+ file.size
		Next

		Local ranParallel:Int
?threaded
		If lanes.length > 1 Then
			ranParallel = True
			For Local lane:TBcc2ValidationLane = EachIn lanes
				processManager.AddTask(TBcc2ValidationLane.Run, lane)
			Next
			processManager.WaitForTasks()
		End If
?
		If Not ranParallel Then TBcc2ValidationLane.Run(lanes[0])

		For Local file:TBcc2ValidationFile = EachIn files
			If Not file.failure Then
				manifestValidationStats.hashedFiles :+ 1
				manifestValidationStats.hashedBytes :+ file.size
			End If
			For Local declaration:TBcc2ValidationDeclaration = EachIn file.declarations
				If file.failure Or file.digest <> declaration.expectedDigest Then InvalidateBcc2ValidatedSource(declaration.source)
			Next
		Next
		pendingBcc2ValidationFiles.Clear()
		manifestValidationMillis :+ MilliSecs() - validationStartMillis
	End Method

	Method CollectBcc2SpecializationOwners:TMap(identitiesByObject:TMap = Null, includePendingForced:Int = False)
		If Not includePendingForced And cachedBcc2SpecializationOwners Then
			If identitiesByObject Then
				For Local key:Object = EachIn cachedBcc2SpecializationIdentitiesByObject.Keys()
					identitiesByObject.Insert(key, cachedBcc2SpecializationIdentitiesByObject.ValueForKey(key))
				Next
			End If
			Return cachedBcc2SpecializationOwners
		End If
		Local ownersByIdentity:TMap = New TMap
		Local collectedIdentitiesByObject:TMap = New TMap
		Local manifestSources:TMap = New TMap
		For Local source:TSourceFile = EachIn sources.Values()
			If Not source Or Not source.bcc2Manifest Then Continue
			Local normalizedManifestPath:String = source.bcc2ManifestPath.Replace("\", "/").ToLower()
			If Not includePendingForced And pendingForcedBcc2Manifests.Contains(normalizedManifestPath) Then Continue
			Local existingSource:TSourceFile = TSourceFile(manifestSources.ValueForKey(normalizedManifestPath))
			' Generation stages own the current in-memory manifest. Object and link
			' stages are graph snapshots made before generation and can still refer
			' to the previous bundle after this build publishes a replacement.
			If Not existingSource Or (source.stage = STAGE_GENERATE And existingSource.stage <> STAGE_GENERATE) Then
				manifestSources.Insert(normalizedManifestPath, source)
			End If
		Next
		For Local source:TSourceFile = EachIn manifestSources.Values()
			Local manifest:TBcc2BuildManifest
			If includePendingForced Then
				' The strict final pass checks the published filesystem state rather
				' than the normal build snapshot.
				manifest = TBcc2BuildManifestCodec.Load(source.bcc2ManifestPath)
			Else
				' Dependency discovery already loaded and validated this manifest.
				' Reusing that snapshot avoids a second serial FileStat of every
				' manifest on high-latency filesystems.
				manifest = source.bcc2Manifest
			End If
			For Local link:TBcc2BuildLink = EachIn manifest.links
				Local generated:TBcc2BuildFile = manifest.FileForPath(link.sourcePath)
				If Not generated Then Throw "BMKGEN022 specialization link source is not declared: " + link.sourcePath
				Local objectPath:String = TBcc2BuildManifestCodec.Resolve(source.bcc2BuildRoot, link.objectPath)
				Local normalizedObjectPath:String = objectPath.Replace("\", "/").ToLower()
				Local existingObjectIdentity:String = String(collectedIdentitiesByObject.ValueForKey(normalizedObjectPath))
				If existingObjectIdentity.length And existingObjectIdentity <> link.specializationIdentity Then
					Throw "BMKGEN055 specialization cache path is claimed by distinct identities: " + objectPath + " (" + existingObjectIdentity + " and " + link.specializationIdentity + ")"
				End If
				collectedIdentitiesByObject.Insert(normalizedObjectPath, link.specializationIdentity)
				Local candidate:TBcc2SpecializationOwner = New TBcc2SpecializationOwner
				candidate.specializationIdentity = link.specializationIdentity
				candidate.cacheKey = link.cacheKey
				candidate.contentDigest = generated.contentDigest
				candidate.objectPath = objectPath
				candidate.manifestPath = source.bcc2ManifestPath
				' A published module object is reusable by every consumer of the
				' same semantic specialization. Prefer it to an application-local
				' copy, then use manifest path as a stable module tie-breaker.
				candidate.priority = 1
				If source.modid Then candidate.priority = 0
				Local existing:TBcc2SpecializationOwner = TBcc2SpecializationOwner(ownersByIdentity.ValueForKey(link.specializationIdentity))
				If existing Then
					' Equal cache keys promise identical code-generation inputs,
					' so differing C is a determinism failure. Different keys can
					' coexist transiently while a forced compiler/ABI migration
					' replaces stale dependency manifests; normal owner priority
					' converges them as the reachable graph is rebuilt.
					If existing.cacheKey = candidate.cacheKey And existing.contentDigest <> candidate.contentDigest Then
						Throw "BMKGEN038 conflicting generated implementations for specialization " + link.specializationIdentity + " (cache " + link.cacheKey + "; " + existing.manifestPath + " -> " + existing.contentDigest + "; " + candidate.manifestPath + " -> " + candidate.contentDigest + ")"
					End If
					' A forced compiler/module rebuild may publish the new
					' manifest before its specialization objects have been
					' recreated. Do not let that unavailable future owner mask
					' an equivalent usable cache entry and deadlock rebuilding.
					Local existingUsable:Int = IsBcc2SpecializationOwnerUsable(existing)
					Local candidateUsable:Int = IsBcc2SpecializationOwnerUsable(candidate)
					If existingUsable And Not candidateUsable Then Continue
					If candidateUsable And Not existingUsable Then
						ownersByIdentity.Insert(link.specializationIdentity, candidate)
						Continue
					End If
					If candidate.priority > existing.priority Then Continue
					If candidate.priority = existing.priority And candidate.manifestPath.ToLower() >= existing.manifestPath.ToLower() Then Continue
				End If
				ownersByIdentity.Insert(link.specializationIdentity, candidate)
			Next
		Next
		If Not includePendingForced Then
			cachedBcc2SpecializationOwners = ownersByIdentity
			cachedBcc2SpecializationIdentitiesByObject = collectedIdentitiesByObject
		End If
		If identitiesByObject Then
			For Local key:Object = EachIn collectedIdentitiesByObject.Keys()
				identitiesByObject.Insert(key, collectedIdentitiesByObject.ValueForKey(key))
			Next
		End If
		Return ownersByIdentity
	End Method

	Method InvalidateBcc2SpecializationOwners()
		cachedBcc2SpecializationOwners = Null
		cachedBcc2SpecializationIdentitiesByObject = Null
	End Method

	Method IsBcc2SpecializationOwnerUsable:Int(owner:TBcc2SpecializationOwner)
		If Not owner Or FileType(owner.objectPath) <> FILETYPE_FILE Then Return False
		Local keyPath:String = owner.objectPath + ".bcc2key"
		If FileType(keyPath) <> FILETYPE_FILE Then Return False
		Local expectedPrefix:String = owner.cacheKey + "~n" + owner.contentDigest + "~n"
		Return LoadText(keyPath).StartsWith(expectedPrefix)
	End Method

	Method DeduplicateBcc2Objects:TList(objects:TList, strictOwnership:Int = False)
		If Not objects Then Return objects
		Local identitiesByObject:TMap
		Local ownersByIdentity:TMap
		If strictOwnership Then
			' The final application link deliberately includes provisional forced-build
			' manifests and therefore performs an uncached ownership pass.
			identitiesByObject = New TMap
			ownersByIdentity = CollectBcc2SpecializationOwners(identitiesByObject, True)
		Else
			' Manifest publication and specialization compilation invalidate these maps.
			' Reuse both views while constructing module archives; copying the complete
			' object index for every archive is itself quadratic on a large graph.
			ownersByIdentity = CollectBcc2SpecializationOwners()
			identitiesByObject = cachedBcc2SpecializationIdentitiesByObject
		End If
		Local result:TList = New TList
		For Local objectPath:String = EachIn objects
			Local normalizedObjectPath:String = objectPath.Replace("\", "/").ToLower()
			Local specializationIdentity:String = String(identitiesByObject.ValueForKey(normalizedObjectPath))
			If specializationIdentity.length Then
				Local owner:TBcc2SpecializationOwner = TBcc2SpecializationOwner(ownersByIdentity.ValueForKey(specializationIdentity))
				If owner Then
					' A standalone bootstrap records commands before any target
					' objects exist. Ownership is still deterministic, but native
					' usability can only be established when the generated script
					' runs on the destination system.
					If Not (opt_standalone And opt_boot) And Not IsBcc2SpecializationOwnerUsable(owner) Then Throw "BMKGEN039 selected specialization owner object is unavailable: " + owner.objectPath
					If owner.objectPath.Replace("\", "/").ToLower() <> normalizedObjectPath Then Continue
				End If
			End If
			If Not result.Contains(objectPath) Then result.AddLast(objectPath)
		Next
		Return result
	End Method
	
	Method New()
		' pre build checks
		If processor.Platform() = "android" Then
			ConfigureAndroidPaths()
		Else If processor.Platform() = "ios" Then
			ConfigureIOSPaths()
		Else If processor.Platform() = "nx" Then
			ConfigureNXPaths()
		End If
		
		If processor.Platform() = "linux" Or processor.Platform() = "raspberrypi" Then
			If opt_nopie Then
				globals.SetVar("nopie", "true")
			End If
		End If
		
		processor.callback = Self
	End Method

	Method MakeMods(mods:TList, rebuild:Int = False)
		RequireBccCompilers(1)

		For Local m:String = EachIn mods
			If (opt_modfilter And (m.ToLower().Find(opt_modfilter) = 0)) Or (Not opt_modfilter) Then
				GetMod(m, rebuild Or buildAll)
			End If
		Next
	End Method

	Method MakeApp(main_path:String, makelib:Int, compileOnly:Int = False)
		Local phaseStartMillis:Int = MilliSecs()
		RequireBccCompilers(1)
		LogVerbosePhase("compiler startup", phaseStartMillis)
		app_main = main_path

		phaseStartMillis = MilliSecs()
		Local source:TSourceFile = GetSourceFile(app_main, False, opt_all)
		LogVerbosePhase("root source scan", phaseStartMillis)

		If Not source Then
			Return
		End If

		Local build_path:String = ExtractDir(main_path) + "/.bmx"

		Local appType:String
		If Not compileOnly Or source.framewk Then
			appType = "." + opt_apptype
		End If
		
		source.obj_path = build_path + "/" + StripDir( main_path ) + appType + opt_configmung + processor.CPU() + ".o"
		source.obj_time = FileTime(source.obj_path)
		source.iface_path = StripExt(source.obj_path) + ".i"
		source.iface_time = FileTime(source.iface_path)
		
		app_iface = source.iface_path
	
		Local cc_opts:String
		' bcc2 emits quoted BlitzMax imports as separate C units whose headers
		' remain beneath the application's .bmx directory.  Give every
		' application-owned unit the source root so <.bmx/...> sibling includes
		' resolve just as module-owned generated headers do.
		source.AddIncludePath(" -I" + CQuote(ExtractDir(main_path)))
		source.AddIncludePath(" -I" + CQuote(ModulePath("")))
		If opt_release And Not opt_gdbdebug Then
			cc_opts :+ " -DNDEBUG"
		End If
		If processor.BCCVersion() <> "BlitzMax" Then
			If opt_gdbdebug Then
				cc_opts :+ " -g"
			End If
			If opt_gprof Then
				cc_opts :+ " -pg"
			End If
			If opt_coverage Then
				cc_opts :+ " -DBMX_COVERAGE"
			End If
		End If
	
		Local sb:TStringBuffer = New TStringBuffer
		sb.Append(" -g ").Append(processor.CPU())
		If opt_quiet sb.Append(" -q")
		If opt_verbose sb.Append(" -v")
		If opt_release sb.Append(" -r")
		If opt_threaded sb.Append(" -h")
		If opt_framework sb.Append(" -f ").Append(opt_framework)
		If processor.BCCVersion() <> "BlitzMax" Then
			If opt_gdbdebug Then
				sb.Append(" -d")
			End If
			If Not opt_nostrictupgrade Then
				sb.Append(" -s")
			End If
			If opt_warnover Then
				sb.Append(" -w")
			End If
			If opt_musl Then
				sb.Append(" -musl")
			End If
			If makelib Then
				sb.Append(" -makelib")
				If opt_nodef Then
					sb.append(" -nodef")
				End If
				If opt_nohead Then
					sb.append(" -nohead")
				End If
			End If
			If opt_require_override Then
				sb.Append(" -override")
				If opt_override_error Then
					sb.Append(" -overerr")
				End If
			End If
			Local defs:String = opt_userdefs
			If globals.Get("user_defs") Then
				If defs Then
					defs :+ ","
				End If
				defs :+ globals.Get("user_defs")
			End If
			If defs Then
				sb.Append(" -ud ").Append(defs)
			End If
			If opt_standalone Then
				sb.Append(" -ib")
			End If
			If opt_coverage Then
				sb.Append(" -cov")
			End If
			If opt_no_auto_superstrict Then
				sb.Append(" -nas")
			End If
		End If

		source.cc_opts :+ cc_opts
		source.cpp_opts :+ cpp_opts
		source.c_opts :+ c_opts

		source.modimports.AddLast("brl.blitz")
		source.modimports.AddLast(opt_appstub)

		If source.framewk
			If opt_framework Then
				Throw "Framework already specified on commandline"
			End If
			opt_framework = source.framewk
			sb.Append(" -f ").Append(opt_framework)
			source.modimports.AddLast(opt_framework)
		Else
			framework_mods = New TList
			For Local t:String = EachIn EnumModules()
				If t.Find("brl.") = 0 Or t.Find("pub.") = 0 Then
					If t <> "brl.blitz" And t <> opt_appstub Then
						source.modimports.AddLast(t)
						framework_mods.AddLast(t)
					End If
				End If
			Next
		End If
		
		source.bcc_opts = sb.ToString()
		source.bcc_opts :+ " -t " + opt_apptype

		source.SetRequiresBuild(opt_all)
		' bcc owns a manifest freshness stamp rather than the legacy
		' compiler's generated C/header pair. Load it before walking Includes so
		' their timestamps are compared with the canonical bundle generation.
		If UseBcc2ForSource(source) Then InitializeBcc2Manifest(source, False)

		phaseStartMillis = MilliSecs()
		CalculateDependencies(source, False, opt_all)
		ValidatePendingBcc2Manifests()
		LogVerbosePhase("dependency discovery", phaseStartMillis, dependencySourceCount + " sources, " + dependencyModuleImportCount + " module imports, " + dependencyFileImportCount + " file imports, " + dependencyIncludeCount + " includes, " + dependencyIncbinCount + " incbins")
		If opt_verbose And manifestValidationCount Then
			Print "bmk: manifest validation (included in dependency discovery): " + manifestValidationMillis + " ms (" + manifestValidationCount + " manifests, " + manifestValidationWorkers + " workers, " + manifestValidationStats.hashedFiles + " files hashed, " + manifestValidationStats.reusedFiles + " shared files reused, " + (manifestValidationStats.hashedBytes / 1048576) + " MiB read)"
		End If

		' create bmx stages :
		Local gen:TSourceFile
		' for osx x86 on legacy, we need to convert asm
		If processor.BCCVersion() = "BlitzMax" And processor.CPU() = "x86" And processor.Platform() = "macos" Then
			Local fasm2as:TSourceFile = CreateFasm2AsStage(source)
			gen = CreateGenStage(fasm2as)
		Else
			gen = CreateGenStage(source)
		End If
		If Not compileOnly Then
			Local link:TSourceFile = CreateLinkStage(gen, STAGE_APP_LINK)
		End If
	End Method
	
	Method BccExecutablePath:String()
		Local executable:String = BlitzMaxPath() + "/bin/bcc"
?win32
		executable :+ ".exe"
?
		Return executable
	End Method

	Method ConfiguredBmxCompilerWorkers:Int()
		If opt_single Then Return 1
?Not threaded
		Return 1
?
		Local maximumWorkers:Int = Max(1, GetCoreCount() - 1)
		Local configured:String = getenv_("BMK_BMX_WORKERS")
		If Not configured.length Then Return Min(4, maximumWorkers)
		Local workers:Int = Int(configured)
		If workers <= 1 Then Return 1
		Return Min(workers, maximumWorkers)
	End Method

	Method FlushPendingArchives(pendingArchives:TList)
		If Not pendingArchives Or pendingArchives.IsEmpty() Then Return

		For Local archive:TArcTask = EachIn pendingArchives
			If Not opt_quiet Then
				Local message:String = ShowPct(archive.m.pct) + "Archiving:" + StripDir(archive.path)
				If opt_standalone And Not opt_nolog Then processor.PushEcho(FixPct(message))
				LogLine(message)
				UpdateProgressLine(archive.m.pct, archive.path)
			End If
			archive.Announce()
		Next

?threaded
		If Not opt_single Then
			For Local archive:TArcTask = EachIn pendingArchives
				processManager.AddTask(TArcTask._CreateArc, archive)
			Next
			processManager.WaitForTasks()
		Else
			For Local archive:TArcTask = EachIn pendingArchives
				archive.CreateArc()
			Next
		End If
?Not threaded
		For Local archive:TArcTask = EachIn pendingArchives
			archive.CreateArc()
		Next
?

		For Local archive:TArcTask = EachIn pendingArchives
			If archive.failure Then Throw archive.failure
		Next
		pendingArchives.Clear()
	End Method

	Method CleanApplicationCaches()
		Local directories:TMap = New TMap
		For Local source:TSourceFile = EachIn sources.Values()
			If Not source Or source.stage <> STAGE_GENERATE Or source.ext.ToLower() <> "bmx" Then Continue
			Local isApplicationRoot:Int = NormalizeCompilerCachePath(source.path) = NormalizeCompilerCachePath(app_main)
			If Not isApplicationRoot And Not source.bcc2ApplicationSource Then Continue
			Local sourceDirectory:String = RealPath(ExtractDir(source.path))
			Local expectedDirectory:String = sourceDirectory + "/.bmx"
			Local buildDirectory:String
			If source.bcc2BuildRoot Then
				buildDirectory = source.bcc2BuildRoot
			Else If source.obj_path Then
				buildDirectory = ExtractDir(source.obj_path)
			End If
			If Not buildDirectory Then Continue
			If NormalizeCompilerCachePath(buildDirectory) <> NormalizeCompilerCachePath(expectedDirectory) Then
				Throw "BMKCLEAN008 refusing unexpected application build directory: " + buildDirectory
			End If
			Local key:String = NormalizeCompilerCachePath(expectedDirectory)
			If Not directories.Contains(key) Then directories.Insert(key, expectedDirectory)
		Next

		Local paths:String[] = New String[0]
		For Local path:String = EachIn directories.Values()
			paths :+ [path]
		Next
		paths.Sort()
		Local plans:TList = New TList
		For Local path:String = EachIn paths
			Local normalizedPath:String = NormalizeCompilerCachePath(path)
			Local normalizedOutput:String = NormalizeCompilerCachePath(opt_outfile)
			If normalizedOutput = normalizedPath Or normalizedOutput.StartsWith(normalizedPath + "/") Then
				Throw "BMKCLEAN009 refusing to clean an application cache containing the requested output: " + path
			End If
			Local plan:TCompilerCachePlan = InspectCompilerCacheDirectory(path)
			If plan Then plans.AddLast(plan)
		Next
		For Local plan:TCompilerCachePlan = EachIn plans
			plan.Execute(opt_verbose)
		Next
	End Method

	Method RequireBccCompilers(count:Int)
		count = Max(1, count)
		Local executable:String = BccExecutablePath()
		If FileType(executable) <> FILETYPE_FILE Then Throw "BMKGEN030 bcc compiler was not found: " + executable
		While bcc2Engines.length < count
			Local client:TBcc2EngineClient = New TBcc2EngineClient
			client.Start(executable)
			bcc2Engines :+ [client]
		Wend
	End Method

	Method ShutdownBccCompilers()
		For Local client:TBcc2EngineClient = EachIn bcc2Engines
			If client Then client.Shutdown()
		Next
		bcc2Engines = New TBcc2EngineClient[0]
	End Method

	Method Bcc2GenerationRequired:Int(source:TSourceFile)
		If Not source Then Return False
		Local maxIfaceTime:Int = source.MaxIfaceTime()
		Local required:Int = source.requiresBuild Or source.time > source.gen_time Or source.gen_time < maxIfaceTime
		If required Then
			TraceBuild("bcc2 generation freshness: " + source.path + "; forced=" + source.requiresBuild + "; source=" + source.time + "; generation=" + source.gen_time + "; maximum-interface=" + maxIfaceTime)
		End If
		Return required
	End Method

	Method LoadPostBuildScripts()
		Local paths:String[] = [AppDir + "/post.bmk", ExtractDir(app_main) + "/post.bmk", ExtractDir(app_main) + "/" + StripDir(opt_outfile) + ".post.bmk"]
		Local loaded:TMap = New TMap
		For Local path:String = EachIn paths
			If FileType(path) <> FILETYPE_FILE Then Continue
			Local key:String = RealPath(path).Replace("\", "/")
?win32
			key = key.ToLower()
?
			If loaded.Contains(key) Then Continue
			loaded.Insert(key, path)
			LoadBMK(path)
		Next
	End Method

	Method CompileBcc2Batch(batch:TList, configuredWorkers:Int)
		If configuredWorkers <= 1 Then Return
		Local eligible:Int
		For Local source:TSourceFile = EachIn batch
			If Match(source.ext, "bmx") And source.stage = STAGE_GENERATE And Bcc2GenerationRequired(source) Then eligible :+ 1
		Next
		If eligible < 2 Then Return
		Local compilationStarted:Int = MilliSecs()

		Local workerCount:Int = Min(configuredWorkers, eligible)
		RequireBccCompilers(workerCount)
		Local lanes:TBcc2CompileLane[] = New TBcc2CompileLane[workerCount]
		For Local index:Int = 0 Until workerCount
			lanes[index] = New TBcc2CompileLane
			lanes[index].client = bcc2Engines[index]
		Next
		Local works:TList = New TList
		Local ordinal:Int
		For Local source:TSourceFile = EachIn batch
			If Not Match(source.ext, "bmx") Or source.stage <> STAGE_GENERATE Or Not Bcc2GenerationRequired(source) Then Continue
			Local buildPath:String
			If source.obj_path Then buildPath = ExtractDir(source.obj_path) Else buildPath = ExtractDir(source.path) + "/.bmx"
			If Not FileType(buildPath) Then CreateDir buildPath
			If FileType(buildPath) <> FILETYPE_DIR Then Throw "Unable to create temporary directory : " + buildPath
			ChangeDir ExtractDir(source.path)
			If Not opt_quiet Then
				LogLine(ShowPct(source.pct) + "Processing:" + StripDir(source.path))
				UpdateProgressLine(source.pct, source.path)
			End If
			Local pragmaInDefine:Int, pragmaText:String, pragmaName:String
			For Local pragma:String = EachIn source.pragmas
				processor.ProcessPragma(pragma, pragmaInDefine, pragmaText, pragmaName)
			Next
			Local stagingBuildRoot:String = CreateBcc2StagingRoot(source)
			Local work:TBcc2CompileWork = CreateBcc2CompileWork(source, stagingBuildRoot)
			LogBcc2EngineRequest(work)
			works.AddLast(work)
			lanes[ordinal Mod workerCount].works.AddLast(work)
			ordinal :+ 1
		Next
		bcc2SetupMillis :+ MilliSecs() - compilationStarted
		Local phaseStarted:Int = MilliSecs()

?threaded
		For Local lane:TBcc2CompileLane = EachIn lanes
			processManager.AddTask(TBcc2CompileLane.Run, lane)
		Next
		processManager.WaitForTasks()
?Not threaded
		For Local lane:TBcc2CompileLane = EachIn lanes
			TBcc2CompileLane.Run(lane)
		Next
?
		bcc2EngineMillis :+ MilliSecs() - phaseStarted

		Local invalidationPaths:String[] = New String[0]
		Local invalidationKeys:TMap = New TMap
		Try
			phaseStarted = MilliSecs()
			ValidateBcc2CompileBatch(works, workerCount)
			bcc2ValidationMillis :+ MilliSecs() - phaseStarted
			phaseStarted = MilliSecs()
			PublishBcc2CompileBatch(works)
			bcc2PublicationMillis :+ MilliSecs() - phaseStarted
			phaseStarted = MilliSecs()
			For Local work:TBcc2CompileWork = EachIn works
				FinalizeBcc2CompileWork(work, True)
				parallelBcc2Generated.Insert(work.source.GetSourcePath(), work.source)
				For Local file:TBcc2BuildFile = EachIn work.source.bcc2Manifest.files
					If file.role <> "interface" And file.role <> "generic-template" Then Continue
					Local path:String = TBcc2BuildManifestCodec.Resolve(work.source.bcc2BuildRoot, file.relativePath)
					Local key:String = path.Replace("\", "/").ToLower()
					If invalidationKeys.Contains(key) Then Continue
					invalidationKeys.Insert(key, path)
					invalidationPaths :+ [path]
				Next
			Next
			bcc2FinalizationMillis :+ MilliSecs() - phaseStarted
		Finally
			phaseStarted = MilliSecs()
			CleanupBcc2StagingBatch(works, workerCount)
			bcc2CleanupMillis :+ MilliSecs() - phaseStarted
		End Try
		phaseStarted = MilliSecs()
		For Local client:TBcc2EngineClient = EachIn bcc2Engines
			For Local offset:Int = 0 Until invalidationPaths.length Step 64
				client.Invalidate(invalidationPaths[offset..Min(offset + 64, invalidationPaths.length)])
			Next
		Next
		bcc2InvalidationMillis :+ MilliSecs() - phaseStarted
		bcc2CompilationMillis :+ MilliSecs() - compilationStarted
		bcc2CompilationRequests :+ eligible
		bcc2ParallelCompilationBatches :+ 1
	End Method

	Method DoBuild(makelib:Int, app_build:Int = False)
		processManager.ResetStatistics()
		ValidatePendingBcc2Manifests()
		parallelBcc2Generated.Clear()
		pendingForcedBcc2Manifests.Clear()
		If opt_all Then
			For Local forcedSource:TSourceFile = EachIn sources.Values()
				If Not forcedSource Or forcedSource.stage <> STAGE_GENERATE Or Not forcedSource.bcc2Manifest Then Continue
				If Not Bcc2GenerationRequired(forcedSource) Then Continue
				Local forcedManifestPath:String = forcedSource.bcc2ManifestPath.Replace("\", "/").ToLower()
				pendingForcedBcc2Manifests.Insert(forcedManifestPath, forcedSource)
			Next
		End If
		bcc2CompilationMillis = 0
		bcc2CompilationRequests = 0
		bcc2ParallelCompilationBatches = 0
		bcc2PublishedOutputDigests.Clear()
		bcc2SetupMillis = 0
		bcc2EngineMillis = 0
		bcc2ValidationMillis = 0
		bcc2PublicationMillis = 0
		bcc2FinalizationMillis = 0
		bcc2InvalidationMillis = 0
		bcc2CleanupMillis = 0
		bcc2SpecializationCompilationMillis = 0
		bcc2SpecializationCompilationObjects = 0
		bcc2SpecializationParallelBatches = 0
		Local arc_order:TList = New TList
		Local pendingArchives:TList = New TList
	
		Local files:TList = New TList
		For Local file:TSourceFile = EachIn sources.Values()
			files.AddLast(file)
		Next

		' get the list of parallelizable batches
		' each list of batches has no outstanding dependencies, and therefore
		' can be compiled in parallel.
		' the last list of batches requires all previous lists to have
		' been compiled.
		Local dependencyEdgeCount:Int
		For Local file:TSourceFile = EachIn files
			For Local dependency:Object = EachIn file.deps.Keys()
				dependencyEdgeCount :+ 1
			Next
		Next
		Local schedulingStartMillis:Int = MilliSecs()
		Local batches:TList = CalculateBatches(files)
		LogVerbosePhase("dependency scheduling", schedulingStartMillis, files.Count() + " nodes, " + dependencyEdgeCount + " edges, " + batches.Count() + " batches")
		Local bmxCompilerWorkers:Int = ConfiguredBmxCompilerWorkers()
		Local staleBmxSources:Int
		Local parallelBmxBatches:Int
		Local maximumBmxBatchWidth:Int
		For Local scheduledBatch:TList = EachIn batches
			Local width:Int
			For Local scheduledSource:TSourceFile = EachIn scheduledBatch
				If Match(scheduledSource.ext, "bmx") And scheduledSource.stage = STAGE_GENERATE And Bcc2GenerationRequired(scheduledSource) Then width :+ 1
			Next
			staleBmxSources :+ width
			If width > 1 Then parallelBmxBatches :+ 1
			maximumBmxBatchWidth = Max(maximumBmxBatchWidth, width)
		Next
		If opt_verbose Then
			Local workerLabel:String = " workers ("
			If bmxCompilerWorkers = 1 Then workerLabel = " worker ("
			Print "bmk: bmx compiler scheduling: " + bmxCompilerWorkers + workerLabel + staleBmxSources + " stale sources, " + parallelBmxBatches + " parallel batches, maximum width " + maximumBmxBatchWidth + ")"
		End If

		InitProgressLine()
		
		Local batchNumber:Int
		For Local batch:TList = EachIn batches
			batchNumber :+ 1
			TraceBuild("batch begin " + batchNumber + "/" + batches.Count() + "; sources=" + batch.Count())
			CompileBcc2Batch(batch, bmxCompilerWorkers)
			TraceBuild("batch generation complete " + batchNumber + "/" + batches.Count())
			Local s:String
			For Local m:TSourceFile = EachIn batch
				TraceBuild("source begin; batch=" + batchNumber + ", stage=" + m.stage + ", ext=" + m.ext + ", path=" + m.path)
				' sort archives for app linkage
				If m.modid Then
					Local path:String = m.arc_path
					If IOS_HAS_MERGE  And processor.Platform() = "ios" Then
						path = m.merge_path
					End If
					
					If Not arc_order.Contains(path) Then
						arc_order.AddFirst(path)
					End If
				End If

				Local build_path:String
				If m.obj_path Then
					build_path = ExtractDir(m.obj_path)
				Else
					build_path = ExtractDir(m.path) + "/.bmx"
				End If
				
				If Not FileType(build_path) Then
					CreateDir build_path
				End If
				
				If FileType(build_path) <> FILETYPE_DIR Then
					Throw "Unable to create temporary directory : " + build_path
				End If

				' change dir, so relative commands work as expected
				' (eg. file processing in BMK-scripts called via pragma)
				ChangeDir ExtractDir( m.path )

				' bmx file
				If Match(m.ext, "bmx") Then
				
					Select m.stage
						Case STAGE_GENERATE

							If Bcc2GenerationRequired(m) And Not parallelBcc2Generated.Contains(m.GetSourcePath()) Then

								If Not opt_quiet Then
									LogLine(ShowPct(m.pct) + "Processing:" + StripDir(m.path))
									UpdateProgressLine(m.pct, m.path)
								End If

								' process pragmas
								Local pragma_inDefine:Int, pragma_text:String, pragma_name:String		
								For Local pragma:String = EachIn m.pragmas
									processor.ProcessPragma(pragma, pragma_inDefine, pragma_text, pragma_name)		
								Next
								
								CompileBcc2Bundle(m)

							End If

							If UseBcc2ForSource(m) Then EnsureBcc2Specializations(m)

						Case STAGE_FASM2AS

							For Local s:TSourceFile = EachIn m.depsList
								If s.requiresBuild Then
									m.SetRequiresBuild(True)
									Exit
								End If
							Next

							If m.requiresBuild Or (m.time > m.obj_time Or m.iface_time < m.MaxIfaceTime()) Then
							
								m.SetRequiresBuild(True)

								If Not opt_quiet Then
									LogLine(ShowPct(m.pct) + "Converting:" + StripDir(StripExt(m.obj_path) + ".s"))
									UpdateProgressLine(m.pct, StripExt(m.obj_path) + ".s")
								End If
								
								Fasm2As m.path, m.obj_path
	
								m.asm_time = time_(Null)
					
							End If
							
						Case STAGE_OBJECT
							Local objectRequiresBuild:Int = m.requiresBuild Or m.time > m.obj_time Or m.gen_time > m.obj_time
							If Not objectRequiresBuild Then
								TraceBuild("generated-header freshness begin: " + m.path)
								Local maxGeneratedHeaderTime:Int = m.MaxGeneratedHeaderTime()
								TraceBuild("generated-header freshness end: " + m.path + "; maximum=" + maxGeneratedHeaderTime)
								objectRequiresBuild = maxGeneratedHeaderTime > m.obj_time
							End If
							If objectRequiresBuild Then
							
								m.SetRequiresBuild(True)
								
								If processor.BCCVersion() <> "BlitzMax" Then

									Local csrc_path:String = StripExt(m.obj_path) + ".c"
									Local cobj_path:String = StripExt(m.obj_path) + ".o"

									If Not opt_quiet Then
										Local s:String = ShowPct(m.pct) + "Compiling:" + StripDir(csrc_path)
										If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
										LogLine(s)
										UpdateProgressLine(m.pct, csrc_path)
									End If
									
									If opt_standalone And opt_boot Then
										processor.PushSource(csrc_path)
										Local generatedHeaderPath:String = StripExt(m.obj_path) + ".h"
										If FileType(generatedHeaderPath) = FILETYPE_FILE Then processor.PushSource(generatedHeaderPath)
									End If

									CompileC csrc_path,cobj_path, m.GetIncludePaths() + " " + m.cc_opts + " " + m.c_opts
								Else
									' asm compilation

									Local src_path:String = StripExt(m.obj_path) + ".s"
									Local obj_path:String = StripExt(m.obj_path) + ".o"

									If Not opt_quiet Then
										LogLine(ShowPct(m.pct) + "Compiling:" + StripDir(src_path))
										UpdateProgressLine(m.pct, src_path)
									End If

									Assemble src_path, obj_path

								End If
								
								m.obj_time = time_(Null)

							End If
						Case STAGE_LINK
							TraceBuild("object freshness begin: " + m.path)
							Local max_obj_time:Int = m.MaxObjTime()
							TraceBuild("object freshness end: " + m.path + "; maximum=" + max_obj_time)

							If (m.requiresBuild Or max_obj_time > m.arc_time) And Not m.dontbuild Then
								Local objs:TList = New TList
								TraceBuild("object collection begin: " + m.path)
								m.GetObjs(objs)
								TraceBuild("object collection end: " + m.path + "; objects=" + objs.Count())
								TraceBuild("object ownership deduplication begin: " + m.path)
								objs = DeduplicateBcc2Objects(objs)
								TraceBuild("object ownership deduplication end: " + m.path + "; objects=" + objs.Count())
	
								Local at:TArcTask = New TArcTask.Create(m, m.arc_path, objs)
								pendingArchives.AddLast(at)

							End If
						
						Case STAGE_APP_LINK
							' Generated objects do not consume module archives. Keep every ready
							' archive out of the dependency-batch barriers and create the complete
							' set concurrently only when the final link actually needs it.
							TraceBuild("application archive flush begin: " + m.path + "; archives=" + pendingArchives.Count())
							FlushPendingArchives(pendingArchives)
							TraceBuild("application archive flush end: " + m.path)

							' this probably should never happen.
							' may be a bad module?
							If Not opt_outfile Then
								Throw "Build Error: Did not expect to link against " + m.path
							End If

							' an app!
							TraceBuild("application link freshness begin: " + m.path)
							Local max_lnk_time:Int = m.MaxLinkTime()
							TraceBuild("application link freshness end: " + m.path + "; maximum=" + max_lnk_time)
							
							' include settings and icon times in calculation
							If opt_manifest And processor.Platform() = "win32" And opt_apptype="gui" Then
								Local settings:String = ExtractDir(opt_infile) + "/" + StripDir(StripExt(opt_outfile)) + ".settings"
								If Not FileType(settings) Then
									settings = ExtractDir(opt_infile) + "/" + StripDir(StripExt(opt_infile)) + ".settings"
								End If
								max_lnk_time = Max(FileTime(settings), max_lnk_time)
								
								Local icon:String = ExtractDir(opt_infile) + "/" + StripDir(StripExt(opt_outfile)) + ".ico"
								If Not FileType(icon) Then
									icon = ExtractDir(opt_infile) + "/" + StripDir(StripExt(opt_infile)) + ".ico"
								End If
								max_lnk_time = Max(FileTime(icon), max_lnk_time)
							End If
						
							If m.requiresBuild Or max_lnk_time > FileTime(opt_outfile) Or opt_all Then

								' generate manifest for app
								If opt_manifest And processor.Platform() = "win32" And opt_apptype="gui" Then
									processor.RunCommand("make_win32_resource", Null)
									Local res:String = ExtractDir(opt_infile) + "/.bmx/" + StripDir(StripExt(opt_outfile)) + "." + processor.CPU() + ".res.o"
									If Not FileType(res) Then
										res = ExtractDir(opt_infile) + "/.bmx/" + StripDir(StripExt(opt_infile)) + "." + processor.CPU() + ".res.o"
									End If
									If FileType(res) = FILETYPE_FILE Then
										Local s:TSourceFile = New TSourceFile
										s.obj_path = res
										s.stage = STAGE_LINK
										s.exti = SOURCE_RES
										m.depslist.AddLast(s)
									End If
								End If

								If Not opt_quiet Then
									Local s:String = ShowPct(m.pct) + "Linking:" + StripDir(opt_outfile)
									If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
									LogLine(s)
									UpdateProgressLine(m.pct, opt_outfile)
								End If

								Local links:TList = New TList
								Local opts:TList = New TList
								TraceBuild("application link collection begin: " + m.path)
								m.GetLinks(links, opts)
								TraceBuild("application link collection end: " + m.path + "; links=" + links.Count() + ", options=" + opts.Count())
								links = DeduplicateBcc2Objects(links, True)

								For Local arc:String = EachIn arc_order
									links.AddLast(arc)
								Next
								
								For Local o:String = EachIn opts
									links.AddLast(o)
								Next

								LinkApp opt_outfile, links, makelib, globals.Get("ld_opts")

								m.obj_time = time_(Null)
							End If

						Case STAGE_MERGE
							TraceBuild("merge archive flush begin: " + m.path + "; archives=" + pendingArchives.Count())
							FlushPendingArchives(pendingArchives)
							TraceBuild("merge archive flush end: " + m.path)
							If IOS_HAS_MERGE Then
								' a module?
								If m.modid Then
									TraceBuild("merge object freshness begin: " + m.path)
									Local max_obj_time:Int = m.MaxObjTime()
									TraceBuild("merge object freshness end: " + m.path + "; maximum=" + max_obj_time)
	
									If max_obj_time > m.merge_time And Not m.dontbuild Then
			
										If Not opt_quiet Then
											LogLine(ShowPct(m.pct) + "Merging:" + StripDir(m.merge_path))
											UpdateProgressLine(m.pct, m.merge_path)
										End If
	
										CreateMergeArc m.merge_path, m.arc_path
	
										m.merge_time = time_(Null)
										
									End If
								End If
							End If
					End Select

				Else If Match(m.ext, "s") Then

					If m.time > m.obj_time Then ' object is older or doesn't exist
						m.SetRequiresBuild(True)
					End If

					If m.requiresBuild Then

						If Not opt_quiet Then
							Local s:String = ShowPct(m.pct) + "Compiling:" + StripDir(m.path)
							If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
							LogLine(s)
							UpdateProgressLine(m.pct, m.path)
						End If
					
						If processor.BCCVersion() = "BlitzMax" Then
							Assemble m.path, m.obj_path
						Else
							CompileC m.path, m.obj_path, m.GetIncludePaths() + " " + m.cc_opts + " " + m.c_opts
						End If
						
					End If
			
				Else
				
					If Not m.dontbuild Then
						' c/c++ source
						If m.time > m.obj_time Then ' object is older or doesn't exist
							m.SetRequiresBuild(True)
						End If
						
						If m.requiresBuild Then
	
							If Not opt_quiet Then
								Local s:String = ShowPct(m.pct) + "Compiling:" + StripDir(m.path)
								If opt_standalone And Not opt_nolog processor.PushEcho(FixPct(s))
								LogLine(s)
								UpdateProgressLine(m.pct, m.path)
							End If

							If m.path.EndsWith(".cpp") Or m.path.EndsWith(".cc") Or m.path.EndsWith(".mm") Or m.path.EndsWith(".cxx") Then
								CompileC m.path, m.obj_path, m.GetIncludePaths() + " " + m.cc_opts + " " + m.cpp_opts
							ElseIf m.path.EndsWith(".S") Or m.path.EndsWith("asm") Then
								AssembleNative m.path, m.obj_path, m.asm_opts
							Else
								CompileC m.path, m.obj_path, m.GetIncludePaths() + " " + m.cc_opts + " " + m.c_opts
							End If
							
							m.obj_time = time_(Null)
						End If
					End If
				End If
				
				TraceBuild("source end; batch=" + batchNumber + ", stage=" + m.stage + ", path=" + m.path)
			Next

?threaded
			If Not opt_single Then
				TraceBuild("batch worker drain requested " + batchNumber + "/" + batches.Count())
				processManager.WaitForTasks()
			End If
?
			TraceBuild("batch end " + batchNumber + "/" + batches.Count())

		Next

		' makemods and compile-only builds have no application link stage to
		' force publication, so flush their accumulated archives here.
		FlushPendingArchives(pendingArchives)

		' The intermediate ownership view deliberately omits old manifests that a
		' forced build has promised to replace. Re-read the complete graph after
		' generation even for makemods and compile-only builds, so a conflict
		' produced by this build can never escape merely because there is no final
		' application link stage.
		If opt_all Then
			InvalidateBcc2SpecializationOwners()
			CollectBcc2SpecializationOwners(Null, True)
		End If

		ClearProgressLine()
		If opt_verbose Then Print "bmk: bmx compilation: " + bcc2CompilationMillis + " ms (" + bcc2CompilationRequests + " requests, " + bcc2ParallelCompilationBatches + " parallel batches)"
		If opt_verbose And bcc2ParallelCompilationBatches Then Print "bmk: bmx compilation phases: setup=" + bcc2SetupMillis + " ms engine=" + bcc2EngineMillis + " ms validation=" + bcc2ValidationMillis + " ms publication=" + bcc2PublicationMillis + " ms finalization=" + bcc2FinalizationMillis + " ms invalidation=" + bcc2InvalidationMillis + " ms cleanup=" + bcc2CleanupMillis + " ms"
		If opt_verbose Then Print "bmk: generic specialization compilation: " + bcc2SpecializationCompilationMillis + " ms (" + bcc2SpecializationCompilationObjects + " objects, " + bcc2SpecializationParallelBatches + " parallel batches)"
		If opt_verbose Then Print "bmk: worker task scheduling: " + processManager.Statistics()
		ShutdownBccCompilers()

		If app_build Then
			LoadPostBuildScripts()

			Select processor.Platform()
			Case "android"
				' create the apk
				
				' copy shared object
				Local androidABI:String = processor.Option("android.abi", "")
				
				Local appId:String = StripDir(StripExt(opt_outfile))
				If opt_debug And opt_outfile.EndsWith(".debug") Then
					appId :+ ".debug"
				End If
				Local buildDir:String = ExtractDir(opt_outfile)
				Local projectDir:String = buildDir + "/android-project-" + appId
		
				Local abiPath:String = projectDir + "/libs/" + androidABI
		
				Local sharedObject:String = "lib" + appId

				sharedObject :+ ".so"
				
				CopyFile(buildDir + "/" + sharedObject, abiPath + "/" + sharedObject)
		
				' build the apk :
				Local antHome:String = processor.Option("ant.home", "").Trim()
				Local cmd:String = "~q" + antHome + "/bin/ant"
?win32
				cmd :+ ".bat"
?
				cmd :+ "~q debug"
				
				Local dir:String = CurrentDir()
				
				ChangeDir(projectDir)
		
				If opt_dumpbuild Then
					Print cmd
				End If
				
				If Sys( cmd ) Then
					Throw "Error creating apk"
				End If
				
				ChangeDir(dir)
		
			'End If
		
			Case "ios"
			
				Local iosSimulator:Int = (processor.CPU() = "x86")
				
				' TODO - other stuff ?
			Case "nx"
			
				' TODO - build nro, nso, psf0 and nacp
				
			End Select
		End If
	End Method
	
	Method CalculateDependencies(source:TSourceFile, isMod:Int = False, rebuildImports:Int = False, isInclude:Int = False, parentSource:TSourceFile = Null)
		If source And Not source.processed Then
			source.processed = True
			dependencySourceCount :+ 1
			dependencyModuleImportCount :+ source.modimports.Count()
			dependencyFileImportCount :+ source.imports.Count()
			dependencyIncludeCount :+ source.includes.Count()
			dependencyIncbinCount :+ source.incbins.Count()
			If UseBcc2ForSource(source) And Not source.bcc2SourceUnitPath.length Then source.bcc2SourceUnitPath = StripDir(source.path).ToLower()

			For Local m:String = EachIn source.modimports

				Local s:TSourceFile = GetMod(m)

				If s Then
					If Not source.moddeps Then
						source.moddeps = New TMap
					End If
					
					If Not source.moddeps.ValueForKey(m) Then
						source.moddeps.Insert(m, s)
						source.deps.Insert(s.GetSourcePath(), s)
					
						source.AddIncludePath(" -I" + CQuote(ExtractDir(s.path)))
					End If
				End If
			Next

			Local ib:TSourceFile
			If processor.BCCVersion() <> "BlitzMax" And Not source.incbins.IsEmpty() Then
				If source.owner_path Then
					ib = CreateIncBin(source, source.owner_path)
				Else
					ib = CreateIncBin(source, source.path)
				End If
			End If

			Local importIndex:Int
			For Local f:String = EachIn source.imports
				Local lexicalOptions:TSourceImportOptions
				If importIndex < source.importOptions.Count() Then lexicalOptions = TSourceImportOptions(source.importOptions.ValueAtIndex(importIndex))
				importIndex :+ 1

				If f[0] <> Asc("-") Then
					Local path:String = CheckPath(ExtractDir(source.path), f)

					Local s:TSourceFile = GetSourceFile(path, isMod)
					
					' imported sourcefile not there? Maybe it's relative to the owner path instead?
					' For example, an incbin as part of an included source file.
					If Not s Then
						Local p:String = CheckPath(ExtractDir(source.owner_path), f)
						s = GetSourceFile(p, isMod)
						If s Then
							path = p
						End If
					End If
					
					If s Then
						If rebuildImports Then
							s.SetRequiresBuild(rebuildImports)
						End If
						If Match(s.ext, "bmx") Then
							' A quoted BlitzMax import is a separately ordered
							' compilation unit, but it belongs to the same bcc2
							' application/module build as its importer. Preserve
							' that ownership instead of silently returning the
							' secondary source to production bcc.
							If UseBcc2ForSource(source) Then
								Local sourceModuleName:String = source.modid
								If Not sourceModuleName.length Then sourceModuleName = source.bcc2SourceModuleName
								If Not sourceModuleName.length Then
									If isMod Then Throw "BMKGEN041 quoted BlitzMax source has no bcc2 ownership identity: " + s.path
									sourceModuleName = Bcc2ApplicationIdentity(app_main)
									source.bcc2SourceModuleName = sourceModuleName
								End If
								If s.bcc2SourceModuleName.length And s.bcc2SourceModuleName.ToLower() <> sourceModuleName.ToLower() Then
									Throw "BMKGEN040 quoted BlitzMax source has conflicting bcc2 module owners: " + s.path
								End If
								s.bcc2OwnedSource = True
								s.bcc2ApplicationSource = Not isMod
								s.bcc2SourceModuleName = sourceModuleName.ToLower()
								Local sourceUnitPath:String = Bcc2SourceUnitPath(source.bcc2SourceUnitPath, f)
								If Not sourceUnitPath.length Then Throw "BMKGEN048 quoted BlitzMax source escapes its bcc2 source root: " + f
								If s.bcc2SourceUnitPath.length And s.bcc2SourceUnitPath <> sourceUnitPath Then Throw "BMKGEN049 quoted BlitzMax source has conflicting bcc2 unit paths: " + s.path
								s.bcc2SourceUnitPath = sourceUnitPath
							End If
							s.modimports.AddLast("brl.blitz")
							
							' app source files need framework/mod dependencies applied
							If Not isMod Then
								If opt_framework Then
									' add framework as dependency
									s.modimports.AddLast(opt_framework)
								Else
									' add all pub/brl mods as dependency
									If framework_mods Then
										For Local m:String = EachIn framework_mods
											s.modimports.AddLast(m)
										Next
									End If
								End If
							End If
	
							s.bcc_opts = source.bcc_opts
							s.cc_opts :+ source.cc_opts
							If lexicalOptions Then s.cc_opts :+ lexicalOptions.ccOpts
							s.cpp_opts :+ source.cpp_opts
							s.c_opts :+ source.c_opts
							s.asm_opts :+ source.asm_opts
							If lexicalOptions Then s.asm_opts :+ lexicalOptions.asmOpts
							s.CopyIncludePaths(source.includePaths)
							
							CalculateDependencies(s, isMod, rebuildImports)
							
							' if file that we generate is missing, we need to rebuild
							If processor.BCCVersion() = "BlitzMax" Then
								If Not FileType(StripExt(s.obj_path) + ".s") Then
									s.SetRequiresBuild(True)
								End If
							Else
								If Not FileType(StripExt(s.obj_path) + ".c") Then
									s.SetRequiresBuild(True)
								End If
							End If
							
							Local gen:TSourceFile
							
							' for osx x86 on legacy, we need to convert asm
							If processor.BCCVersion() = "BlitzMax" And processor.CPU() = "x86" And processor.Platform() = "macos" Then
								Local fasm2as:TSourceFile = CreateFasm2AsStage(s)
								gen = CreateGenStage(fasm2as)
							Else
								gen = CreateGenStage(s)
							End If
							' A quoted BlitzMax unit can publish canonical generic templates
							' consumed by its importer. Until that unit has regenerated its
							' interface/template bundle, conservatively rebuild the importer
							' whenever the owned source changed; otherwise an old consumer
							' specialization can remain linked after a body-only template edit.
							Local ownerGenerationTime:Int = source.gen_time
							If UseBcc2ForSource(source) Then
								' The importer manifest is initialized after its dependency walk.
								' During that walk its C/header timestamp may be older than its
								' already-current generation stamp when publication was content-stable.
								ownerGenerationTime = Max(ownerGenerationTime, FileTime(Bcc2ManifestPathForSource(source) + ".stamp"))
								' Quoted units form one semantic application/module source. Preserve
								' that effective time even when the child is already current so later
								' manifest validation compares the same source identity.
								If s.time > source.time Then source.time = s.time
							End If
							If UseBcc2ForSource(source) And (s.requiresBuild Or s.time > ownerGenerationTime) Then
								TraceBuild("quoted-source owner freshness: owner=" + source.path + "; child=" + s.path + "; child-forced=" + s.requiresBuild + "; child-source=" + s.time + "; owner-generation=" + ownerGenerationTime)
								source.SetRequiresBuild(True)
							End If
							source.deps.Insert(gen.GetSourcePath(), gen)
	
							If Not source.depsList Then
								source.depsList = New TList
							End If
							source.depsList.AddLast(gen)
						Else
							s.cc_opts = source.cc_opts
							If lexicalOptions Then s.cc_opts :+ lexicalOptions.ccOpts
							s.cpp_opts = source.cpp_opts
							s.c_opts = source.c_opts
							s.asm_opts = source.asm_opts
							If lexicalOptions Then s.asm_opts :+ lexicalOptions.asmOpts
							s.CopyIncludePaths(source.includePaths)
							
							source.deps.Insert(s.GetSourcePath(), s)
							If Not source.depsList Then
								source.depsList = New TList
							End If
							source.depsList.AddLast(s)
						End If
						
	
					Else

						Local ext:String = ExtractExt(path)
						
						If Match(ext, "h;hpp;hxx") Then ' header?
						
							source.AddIncludePath(" -I" + CQuote(ExtractDir(path)))
							
						Else If Match(ext, "o;a;lib") Then ' object or archive?
						
							Local s:TSourceFile = New TSourceFile
							s.time = FileTime(path)
							s.obj_time = s.time
							s.path = path
							s.obj_path = path
							s.modid = source.modid

							If s.time > source.time Then
								source.time = s.time
							End If
							
							If Not source.depsList Then
								source.depsList = New TList
							End If
							source.depsList.AddLast(s)
						End If
						
					End If
				Else
					If Not source.ext_files Then
						source.ext_files = New TList
					End If
					
					source.ext_files.AddLast(f)
					
				End If
			Next
			
			If Not parentSource Then
				parentSource = source
			End If

			For Local f:String = EachIn source.includes
				Local path:String = CheckPath(ExtractDir(source.path), f)

				Local s:TSourceFile = GetSourceFile(path, isMod, rebuildImports, True)
				If s Then
					s.owner_path = parentSource.path
					
					If s.includePaths.IsEmpty() Then
						s.CopyIncludePaths(source.includePaths)
					End If
				
					' calculate included file dependencies
					CalculateDependencies(s, isMod, rebuildImports,,parentSource)

					' update our time to latest included time
					' use gen_time as threshold so changes made between the last code generation and compilation are caught
					If s.time > parentSource.gen_time Then
						If s.time > parentSource.time Then
							parentSource.time = s.time
						End If
						parentSource.SetRequiresBuild(True)
					End If
					
					If Not source.depsList Then
						source.depsList = New TList
					End If
					source.depsList.AddLast(s)
				End If
			Next

			For Local f:String = EachIn source.incbins
				Local path:String = CheckPath(ExtractDir(source.path), f)

				If FileType(path) = FILETYPE_FILE Then
					source.hashes.Insert(f, CalculateFileHash(path))
				End If

				Local time:Int = FileTime(path)

				If Not UseBcc2ForSource(parentSource) Then
					' Legacy Incbin generation is timestamp-owned by the compiler.
					If time > parentSource.gen_time Then
						If time > parentSource.time Then
							parentSource.time = time
						End If
						parentSource.SetRequiresBuild(True)
					End If

					If ib And ib.time And ib.time < time Then
						ib.time = time
					End If
				End If
			Next
			
			' incbin file
			If ib Then
				Local requiresBuild:Int = False
				' missing source.. generate and compile
				If Not ib.time Then
					requiresBuild = True
				Else If IncbinsDifference(source.incbins, ib.incbins) Then
					requiresBuild = True
				Else If IncbinsHashDifference(source, ib) Then
					requiresBuild = True
				End If
				
				If requiresBuild Then
					ib.SetRequiresBuild(True)
					parentSource.SetRequiresBuild(True)
				End If

				' Canonical resource freshness belongs to the hash-bearing Incbin C
				' unit. Do not turn a content-identical resource touch into semantic
				' source regeneration.
				If Not UseBcc2ForSource(parentSource) And ib.time > parentSource.time Then
					parentSource.time = ib.time
				End If
			End If
						
			If source.depsList Then
				For Local s:TSourceFile = EachIn source.depsList
					If Not Match(s.ext, "bmx") Then
						s.cc_opts = source.cc_opts
						s.cpp_opts = source.cpp_opts
						s.c_opts = source.c_opts
						s.asm_opts = source.asm_opts
						s.CopyIncludePaths(source.includePaths)
					End If
				Next
			End If
			
		End If

	End Method
	
	Method GetSourceFile:TSourceFile(source_path:String, isMod:Int = False, rebuild:Int = False, isInclude:Int = False, doCreate:Int = True)
		Local source:TSourceFile = TSourceFile(sources.ValueForKey(source_path))

		If Not source And doCreate Then
			source = ParseSourceFile(source_path)
			
			If source Then
				Local ext:String = ExtractExt(source_path)
				If Match(ext, ALL_SRC_EXTS) Then

					If Not isInclude Then

						sources.Insert(source_path, source)

						Local sp:String
						If app_main = source_path Then
							sp = ConcatString(ExtractDir(source_path), "/.bmx/", StripDir(source_path), "." + opt_apptype, opt_configmung, processor.CPU())
						Else
							sp = ConcatString(ExtractDir(source_path), "/.bmx/", StripDir(source_path), opt_configmung, processor.CPU())
						End If
						
						
						If Match(ext, "bmx") Then
							source.obj_path = sp + ".o"
							source.obj_time = FileTime(source.obj_path)						

							source.iface_path = sp + ".i"
							source.iface_path2 = source.iface_path + "2"
							source.iface_time = FileTime(source.iface_path2)
							
							' gen file times
							If processor.BCCVersion() <> "BlitzMax" Then
								Local p:String = sp + ".c"
								source.gen_time = FileTime(p)
								If source.gen_time Then
									p = sp + ".h"
									source.gen_time = Min(source.gen_time, FileTime(p))
								End If
							Else
								Local p:String = sp + ".s"
								source.gen_time = FileTime(p)
							End If
						Else
							source.obj_path = PPFix(sp) + ".o"
							source.obj_time = FileTime(source.obj_path)						
						End If
					Else
						source.isInclude = True
					End If
				End If
			End If
		End If
		
		Return source
	End Method
	
	Method PPFix:String(path:String)
		Local dir:String = ExtractDir(ExtractDir(path))
		Local s:String
		For Local i:Int = 0 Until 3
			Local t:String = StripDir(dir)
			If Not t Then
				t = "x"
			End If
			s = t[..1] + s
			
			dir = ExtractDir(dir)
		Next

		Return ExtractDir(path) + "/" + s + "_" + StripDir(path)
	End Method

	Method GetISourceFile:TSourceFile(arc_path:String, arc_time:Int, iface_path:String, iface_time:Int, merge_path:String, merge_time:Int)
		Local source:TSourceFile
		
		If IOS_HAS_MERGE And processor.Platform() = "ios" Then
			source = TSourceFile(sources.ValueForKey(merge_path))
		Else 
			source = TSourceFile(sources.ValueForKey(arc_path))
		End If

		If Not source Then
			Local iface_path2:String = iface_path + 2
		
			source = ParseISourceFile(iface_path2)
			
			If source Then
				source.arc_path = arc_path
				source.arc_time = arc_time
				source.iface_path = iface_path
				source.iface_path2 = iface_path2
				source.iface_time = iface_time
				source.merge_time = merge_time

				If IOS_HAS_MERGE And processor.Platform() = "ios" Then
					sources.Insert(merge_path, source)
				Else
					sources.Insert(arc_path, source)
				End If
			End If
		End If
		
		Return source
	End Method
	
	Method GetMod:TSourceFile(m:String, rebuild:Int = False)

		If (opt_all And ((opt_modfilter And (m.ToLower().Find(opt_modfilter) = 0)) Or (Not opt_modfilter)) And Not app_main) Or (app_main And opt_standalone) Then
			rebuild = True
		End If
	
		Local path:String = InstalledModulePath(m)
		Local id:String = ModuleIdent(m)
		
		Local mp:String = ConcatString(path, "/", id, opt_configmung, processor.CPU())

		' get the module interface and lib details
		Local arc_path:String = mp + ".a"
		Local arc_time:Int = FileTime(arc_path)
		Local iface_path:String = mp + ".i"
		Local iface_path2:String = iface_path + "2"
		Local iface_time:Int = FileTime(iface_path2)
		Local merge_path:String
		Local merge_time:Int
		
		If IOS_HAS_MERGE And processor.Platform() = "ios" Then
			If processor.CPU() = "x86" Or processor.CPU() = "x64" Then
				merge_path = ConcatString(path, "/", id, opt_configmung, "sim.a")
			Else
				merge_path = ConcatString(path, "/", id, opt_configmung, "dev.a")
			End If
			merge_time = FileTime(merge_path)
		End If

		Local source:TSourceFile
		Local link:TSourceFile
		Local src_path:String = ConcatString(path, "/", id, ".bmx")
		source = GetSourceFile(src_path, True, rebuild)

		If Not source Then
			Return Null
		End If

		' main module file without "Module" line?
		If Not source.modid Then
			Return Null
		End If

		If source.modid.ToLower() <> m.ToLower() Then
			Throw "Module declaration '" + source.modid + "' does not match path-derived module name '" + m + "' for '" + src_path + "'"
		End If
		
		If Not source.processed Then

			source.arc_path = arc_path
			source.arc_time = arc_time
			source.iface_path = iface_path
			source.iface_path2 = iface_path2
			source.iface_time = iface_time
			source.merge_path = merge_path
			source.merge_time = merge_time
			
			Local cc_opts:String
			source.AddIncludePath(" -I" + CQuote(path))
			source.AddIncludePath(" -I" + CQuote(ModulePath("")))
			If opt_release And Not opt_gdbdebug Then
				cc_opts :+ " -DNDEBUG"
			End If
			If opt_threaded Then
				cc_opts :+ " -DTHREADED"
			End If
			If processor.BCCVersion() <> "BlitzMax" Then
				If opt_gdbdebug Then
					cc_opts :+ " -g"
				End If
				If opt_gprof Then
					cc_opts :+ " -pg"
				End If
				If opt_coverage Then
					cc_opts :+ " -DBMX_COVERAGE"
				End If
			End If

			source.cc_opts = ""
			If source.mod_opts Then
				source.cc_opts :+ source.mod_opts.cc_opts
				source.cpp_opts :+ source.mod_opts.cpp_opts
				source.c_opts :+ source.mod_opts.c_opts
				source.asm_opts :+ source.mod_opts.asm_opts
			End If
			source.cc_opts :+ cc_opts
			source.cpp_opts :+ cpp_opts
			source.c_opts :+ c_opts
			source.asm_opts :+ asm_opts
	
			' Module BCC opts
			Local sb:TStringBuffer = New TStringBuffer
			sb.Append(" -g ").Append(processor.CPU())
			sb.Append(" -m ").Append(m)
			If opt_quiet sb.Append(" -q")
			If opt_verbose sb.Append(" -v")
			If opt_release sb.Append(" -r")
			If opt_threaded sb.Append(" -h")
			If processor.BCCVersion() <> "BlitzMax" Then
				If opt_gdbdebug Then
					sb.Append(" -d")
				End If
				If Not opt_nostrictupgrade Then
					sb.Append(" -s")
				End If
				If opt_warnover Then
					sb.Append(" -w")
				End If
				If opt_musl Then
					sb.Append(" -musl")
				End If
				If opt_require_override Then
					sb.Append(" -override")
					If opt_override_error Then
						sb.Append(" -overerr")
					End If
				End If
				Local defs:String = opt_userdefs
				If globals.Get("user_defs") Then
					If defs Then
						defs :+ ","
					End If
					defs :+ globals.Get("user_defs")
				End If
				If defs Then
					sb.Append(" -ud ").Append(defs)
				End If
				If opt_standalone Then
					sb.Append(" -ib")
				End If
				If opt_coverage Then
					sb.Append(" -cov")
				End If
				If opt_no_auto_superstrict Then
					sb.Append(" -nas")
				End If
			End If
	
			source.bcc_opts = sb.ToString()
			
			source.SetRequiresBuild(rebuild)

			' interface is REQUIRED for compilation
			If Not iface_time Then
				source.SetRequiresBuild(True)
			End If

			If m <> "brl.blitz" Then	
				source.modimports.AddLast("brl.blitz")
			End If
			
			
			CalculateDependencies(source, True, rebuild)
			
			' create bmx stages :
			Local gen:TSourceFile
			
			' for osx x86 on legacy, we need to convert asm
			If processor.BCCVersion() = "BlitzMax" And processor.CPU() = "x86" And processor.Platform() = "macos" Then
				Local fasm2as:TSourceFile = CreateFasm2AsStage(source)
				gen = CreateGenStage(fasm2as)
			Else
				gen = CreateGenStage(source)
			End If
			
			If processor.Platform() <> "ios" Then
				link = CreateLinkStage(gen)
			Else
				If IOS_HAS_MERGE Then
					Local realLink:TSourceFile = CreateLinkStage(gen)
				
					' create a fat archive
					link = CreateMergeStage(realLink)
				Else
					link = CreateLinkStage(gen)
				End If
			End If
		Else
			If IOS_HAS_MERGE And processor.Platform() = "ios" Then
				link = TSourceFile(sources.ValueForKey(source.merge_path))
			Else
				link = TSourceFile(sources.ValueForKey(source.arc_path))
			End If
			If Not link Then
				Throw "Can't find link for : " + source.path
			End If
		End If
		
		Return link
	End Method

	Method CreateFasm2AsStage:TSourceFile(source:TSourceFile)
		Local fasm:TSourceFile = New TSourceFile
		
		source.CopyInfo(fasm)
		
		fasm.deps.Insert(source.path, source)
		fasm.stage = STAGE_FASM2AS
		fasm.processed = True
		fasm.depsList = New TList
		fasm.depsList.AddLast(source)		

		sources.Insert(StripExt(fasm.obj_path) + ".s", fasm)

		Return fasm
	End Method
	
	Method CreateGenStage:TSourceFile(source:TSourceFile)
		Local generatedPath:String = StripExt(source.obj_path) + ".c"
		Local existing:TSourceFile = TSourceFile(sources.ValueForKey(generatedPath))
		If existing Then
			' Quoted imports may reach the same source through several parents.
			' Keep one graph node while refreshing options accumulated by the
			' semantic source, instead of replacing a node already referenced by
			' other dependency edges.
			source.CopyInfo(existing)
			Return existing
		End If
		Local gen:TSourceFile = New TSourceFile

		If UseBcc2ForSource(source) Then InitializeBcc2Manifest(source)

		source.CopyInfo(gen)
		
		If processor.BCCVersion() = "BlitzMax" And processor.CPU() = "x86" And processor.Platform() = "macos" Then
			gen.deps.Insert(StripExt(source.obj_path) + ".s", source)
		Else
			gen.deps.Insert(source.path, source)
		End If
		
		gen.stage = STAGE_OBJECT
		gen.processed = True
		gen.depsList = New TList
		gen.depsList.AddLast(source)		

		sources.Insert(generatedPath, gen)

		Return gen
	End Method

	Method UseBcc2ForSource:Int(source:TSourceFile)
		If Not source Then Return False
		' This matched bmk has one BlitzMax compiler. Every BlitzMax source in
		' the graph uses bcc regardless of publication history or root kind.
		Return source.ext.ToLower() = "bmx"
	End Method

	Method Bcc2ManifestPathForSource:String(source:TSourceFile)
		If Not source Then Return ""
		If source.bcc2ManifestPath.length Then Return source.bcc2ManifestPath
		If source.modid Then
			Return ExtractDir(source.iface_path) + "/" + StripDir(StripExt(source.iface_path)) + ".bmxbuild"
		End If
		Return ExtractDir(source.obj_path) + "/" + StripDir(StripExt(source.obj_path)) + ".bmxbuild"
	End Method

	Method InitializeBcc2Manifest(source:TSourceFile, validateFreshness:Int = True)
		If Not source Or Not source.obj_path Then Return
		If source.modid Then
			source.bcc2BuildRoot = ExtractDir(source.iface_path)
		Else
			source.bcc2BuildRoot = ExtractDir(source.obj_path)
		End If
		source.bcc2ManifestPath = Bcc2ManifestPathForSource(source)
		source.gen_time = FileTime(source.bcc2ManifestPath + ".stamp")
		If source.bcc2ManifestChecked Then
		Else If FileType(source.bcc2ManifestPath) = FILETYPE_FILE Then
			Local validationStartMillis:Int = MilliSecs()
			Try
				source.bcc2Manifest = TBcc2BuildManifestCodec.Load(source.bcc2ManifestPath)
				InvalidateBcc2SpecializationOwners()
				QueueBcc2ManifestValidation(source)
			Catch exception:Object
				InvalidateBcc2ValidatedSource(source)
			End Try
			manifestValidationCount :+ 1
			manifestValidationMillis :+ MilliSecs() - validationStartMillis
			Local compilerPath:String = BlitzMaxPath() + "/bin/bcc"
?win32
			compilerPath :+ ".exe"
?
			If FileTime(compilerPath) > source.gen_time Then source.SetRequiresBuild(True)
		Else
			source.SetRequiresBuild(True)
		End If
		source.bcc2ManifestChecked = True
		' The application root is initialized once before its Include/Incbin
		' walk so the existing bundle is available to the graph. Its effective
		' source time is only known after that walk; comparing the stamp early
		' would make every resource-owning application rebuild forever.
		If validateFreshness And Not source.bcc2FreshnessChecked Then
			source.bcc2FreshnessChecked = True
			If source.bcc2Manifest Then
				Local expectedStamp:String = Bcc2GenerationStamp(source)
				If FileType(source.bcc2ManifestPath + ".stamp") <> FILETYPE_FILE Or LoadText(source.bcc2ManifestPath + ".stamp") <> expectedStamp Then
					source.SetRequiresBuild(True)
				End If
			End If
		End If
	End Method

	Method CreateBcc2StagingRoot:String(source:TSourceFile)
		If Not source Or Not source.bcc2ManifestPath.length Or Not source.bcc2BuildRoot.length Then Throw "BMKGEN050 cannot stage compiler output without a build root and manifest path"
		Local result:String = Bcc2StagingPath(source)
		If FileType(result) <> FILETYPE_NONE Then Throw "BMKGEN050 compiler staging path already exists: " + result
		If Not CreateDir(result, True) Or FileType(result) <> FILETYPE_DIR Then Throw "BMKGEN050 unable to create compiler staging directory: " + result
		TraceBuild("compiler staging root: " + result)
		Return result
	End Method

	' Keep staging names independent of the manifest basename. Besides being
	' easier to inspect, this leaves enough room for nested specialization
	' identities on Windows without requiring partial long-path support.
	Method Bcc2StagingPath:String(source:TSourceFile)
		Return processor.TemporaryStagingPath(StripSlash(source.bcc2BuildRoot))
	End Method

	Method CreateBcc2CompileWork:TBcc2CompileWork(source:TSourceFile, stagingBuildRoot:String = "")
		Local generatedCPath:String = StripExt(source.obj_path) + ".c"
		Local generatedHeaderPath:String = StripExt(source.obj_path) + ".h"
		Local cPath:String = StripDir(generatedCPath)
		Local headerPath:String = StripDir(generatedHeaderPath)
		If source.modid Then
			Local normalizedRoot:String = source.bcc2BuildRoot.Replace("\", "/")
			Local normalizedCPath:String = generatedCPath.Replace("\", "/")
			If normalizedCPath.StartsWith(normalizedRoot + "/") Then cPath = normalizedCPath[normalizedRoot.length + 1..]
			Local normalizedHeaderPath:String = generatedHeaderPath.Replace("\", "/")
			If normalizedHeaderPath.StartsWith(normalizedRoot + "/") Then headerPath = normalizedHeaderPath[normalizedRoot.length + 1..]
		End If
		Local interfacePath:String = StripDir(source.iface_path)
		Local manifestPath:String = StripDir(source.bcc2ManifestPath)
		Local outputRoot:String = source.bcc2BuildRoot
		If stagingBuildRoot.length Then outputRoot = stagingBuildRoot
		Local arguments:String[] = ["--emit-build", "-o", outputRoot, "--build-c", cPath]
		If stagingBuildRoot.length Then arguments :+ ["--build-reference-root", source.bcc2BuildRoot]
		If source.modid Or source.bcc2OwnedSource Then
			arguments :+ ["--build-header", headerPath]
			arguments :+ ["--build-interface", interfacePath]
		End If
		arguments :+ ["--build-manifest", manifestPath]
		arguments :+ ["--sdk", BlitzMaxPath()]
		Local sourceModuleName:String = source.modid
		If Not sourceModuleName.length Then sourceModuleName = source.bcc2SourceModuleName
		If sourceModuleName.length And (source.modid Or source.bcc2OwnedSource) Then arguments :+ ["--module", sourceModuleName]
		If source.bcc2SourceUnitPath.length And (source.modid Or source.bcc2OwnedSource) Then arguments :+ ["--source-unit", source.bcc2SourceUnitPath]
		Local applicationCompilation:Int = Not source.modid And (Not source.bcc2OwnedSource Or source.bcc2ApplicationSource)
		If applicationCompilation And source.bcc2SourceModuleName.length Then
			arguments :+ ["--application-identity", source.bcc2SourceModuleName]
		End If
		If source.bcc2ApplicationSource Then arguments :+ ["--application-source"]
		Local definitions:String = opt_userdefs
		If globals.Get("user_defs") Then
			If definitions.length Then definitions :+ ","
			definitions :+ globals.Get("user_defs")
		End If
		Local applicationType:String
		Local frameworkArgument:String
		If applicationCompilation And opt_apptype.length Then
			applicationType = opt_apptype
			If opt_framework.length Then frameworkArgument = opt_framework
		End If
		arguments :+ Bcc2CompilerConfigurationValues(processor.Platform(), processor.CPU(), opt_release, opt_threaded, opt_coverage, opt_gdbdebug, opt_musl, opt_verbose, applicationType, frameworkArgument, definitions)
		arguments :+ [source.path]
		Local work:TBcc2CompileWork = New TBcc2CompileWork
		work.source = source
		work.arguments = arguments
		work.finalBuildRoot = source.bcc2BuildRoot
		work.stagingBuildRoot = stagingBuildRoot
		Return work
	End Method

	Method LogBcc2EngineRequest(work:TBcc2CompileWork)
		If Not opt_verbose Or Not work Then Return
		Local displayedArguments:TStringBuffer = New TStringBuffer
		displayedArguments.Append("bcc engine request:")
		For Local value:String = EachIn work.arguments
			displayedArguments.Append(" ").Append(value)
		Next
		LogLine(displayedArguments.ToString())
	End Method

	Method ValidateBcc2CompileBatch(works:TList, configuredWorkers:Int)
		For Local work:TBcc2CompileWork = EachIn works
			If Not work Or Not work.source Then Throw "BMKGEN049 missing bcc2 compiler work result"
			If work.failure Then Throw work.failure
			Local response:TBcc2EngineResponse = work.response
			If Not response Then Throw "BMKGEN049 missing bcc2 compiler response for " + work.source.path
			If response.output.length Then LogLine(response.output.Trim())
			If response.exitCode Then
				DiagnoseBcc2CompileFailure(work)
				Throw "BMKGEN031 bcc failed to produce a build bundle for " + work.source.path
			End If
			Local stagedManifestPath:String = work.stagingBuildRoot + "/" + StripDir(work.source.bcc2ManifestPath)
			TBcc2BuildManifestCodec.Invalidate(stagedManifestPath)
			work.stagedManifest = TBcc2BuildManifestCodec.Load(stagedManifestPath)
			If Not work.stagedManifest Then Throw "BMKGEN051 staged compiler manifest is missing: " + stagedManifestPath
		Next

		' Validate only the first file that can become each final path. Other
		' declarations in the batch are checked for digest conflicts below, while
		' paths already published with this digest were validated by an earlier
		' batch in this build.
		Local filesByFinalPath:TMap = New TMap
		Local files:TList = New TList
		For Local work:TBcc2CompileWork = EachIn works
			For Local file:TBcc2BuildFile = EachIn work.stagedManifest.files
				Local finalPath:String = TBcc2BuildManifestCodec.Resolve(work.finalBuildRoot, file.relativePath)
				Local key:String = finalPath.Replace("\", "/").ToLower()
				Local alreadyPublished:String = String(bcc2PublishedOutputDigests.ValueForKey(key))
				If alreadyPublished = file.contentDigest Then Continue
				Local validationFile:TBcc2ValidationFile = TBcc2ValidationFile(filesByFinalPath.ValueForKey(key))
				If validationFile Then
					Local firstDeclaration:TBcc2ValidationDeclaration = TBcc2ValidationDeclaration(validationFile.declarations.First())
					If firstDeclaration.expectedDigest <> file.contentDigest Then Throw "BMKGEN052 conflicting staged compiler outputs for " + finalPath
					Continue
				End If
				validationFile = New TBcc2ValidationFile
				validationFile.normalizedPath = key
				validationFile.path = TBcc2BuildManifestCodec.Resolve(work.stagingBuildRoot, file.relativePath)
				Local info:SFileStat
				If Not FileStat(validationFile.path, info) Or info.fileType <> FILETYPE_FILE Then
					validationFile.path = finalPath
					If Not FileStat(validationFile.path, info) Or info.fileType <> FILETYPE_FILE Then Throw "BMKGEN020 declared compiler output is missing: " + validationFile.path
				End If
				validationFile.exists = True
				validationFile.size = info.size
				Local declaration:TBcc2ValidationDeclaration = New TBcc2ValidationDeclaration
				declaration.source = work.source
				declaration.expectedDigest = file.contentDigest
				validationFile.declarations.AddLast(declaration)
				filesByFinalPath.Insert(key, validationFile)
				files.AddLast(validationFile)
			Next
		Next
		files.Sort(False, CompareBcc2ValidationFiles)
		Local laneCount:Int = Min(Max(1, configuredWorkers), Max(1, files.Count()))
		Local lanes:TBcc2ValidationLane[] = New TBcc2ValidationLane[laneCount]
		For Local index:Int = 0 Until laneCount
			lanes[index] = New TBcc2ValidationLane
		Next
		For Local file:TBcc2ValidationFile = EachIn files
			Local lightest:Int
			For Local index:Int = 1 Until lanes.length
				If lanes[index].totalBytes < lanes[lightest].totalBytes Then lightest = index
			Next
			lanes[lightest].files.AddLast(file)
			lanes[lightest].totalBytes :+ file.size
		Next
?threaded
		For Local lane:TBcc2ValidationLane = EachIn lanes
			processManager.AddTask(TBcc2ValidationLane.Run, lane)
		Next
		processManager.WaitForTasks()
?Not threaded
		For Local lane:TBcc2ValidationLane = EachIn lanes
			TBcc2ValidationLane.Run(lane)
		Next
?
		For Local file:TBcc2ValidationFile = EachIn files
			If file.failure Then Throw file.failure
			Local declaration:TBcc2ValidationDeclaration = TBcc2ValidationDeclaration(file.declarations.First())
			If file.digest <> declaration.expectedDigest Then Throw "BMKGEN021 compiler output digest mismatch: " + file.path
		Next

		' No final path may acquire two different contents from the same batch.
		' Detect this before publishing anything so failed parallel work leaves the
		' previous build snapshot intact and recoverable.
		Local digestsByPath:TMap = New TMap
		For Local work:TBcc2CompileWork = EachIn works
			For Local file:TBcc2BuildFile = EachIn work.stagedManifest.files
				Local finalPath:String = TBcc2BuildManifestCodec.Resolve(work.finalBuildRoot, file.relativePath)
				Local key:String = finalPath.Replace("\", "/").ToLower()
				If digestsByPath.Contains(key) Then
					Local existingDigest:String = String(digestsByPath.ValueForKey(key))
					If existingDigest <> file.contentDigest Then Throw "BMKGEN052 conflicting staged compiler outputs for " + finalPath
				Else
					digestsByPath.Insert(key, file.contentDigest)
				End If
			Next
		Next
	End Method

	Method DiagnoseBcc2CompileFailure(work:TBcc2CompileWork)
		Local configured:String = getenv_("BMK_BMX_DIAGNOSE_FAILURES")
		If Not configured.length Or configured = "0" Or Not work Then Return
		Local replayRoot:String = Bcc2StagingPath(work.source)
		If FileType(replayRoot) <> FILETYPE_NONE Then
			LogLine("bmk: parallel bcc failure replay skipped; diagnostic path already exists: " + replayRoot)
			Return
		End If
		If Not CreateDir(replayRoot, True) Or FileType(replayRoot) <> FILETYPE_DIR Then
			LogLine("bmk: parallel bcc failure replay skipped; unable to create diagnostic path: " + replayRoot)
			Return
		End If
		Local replayWork:TBcc2CompileWork = New TBcc2CompileWork
		replayWork.source = work.source
		replayWork.stagingBuildRoot = replayRoot
		Local replayArguments:String[] = work.arguments[..]
		For Local index:Int = 0 Until replayArguments.length - 1
			If replayArguments[index] = "-o" Or replayArguments[index] = "--output" Then
				replayArguments[index + 1] = replayRoot
				Exit
			End If
		Next
		Local client:TBcc2EngineClient = New TBcc2EngineClient
		Try
			client.Start(BccExecutablePath())
			Local replay:TBcc2EngineResponse = client.Compile(replayArguments)
			If replay.output.length Then LogLine("bmk: fresh compiler replay output:~n" + replay.output.Trim())
			If replay.exitCode Then
				LogLine("bmk: parallel bcc failure replay reproduced in a fresh compiler process")
			Else
				LogLine("bmk: parallel bcc failure replay succeeded in a fresh compiler process; persistent worker state differs")
			End If
		Catch exception:Object
			LogLine("bmk: parallel bcc failure replay could not complete: " + exception.ToString())
		Finally
			client.Shutdown()
			CleanupBcc2StagingRoot(replayWork)
		End Try
	End Method

	Method PublishBcc2CompileBatch(works:TList)
		Local publishedPaths:TMap = New TMap
		For Local work:TBcc2CompileWork = EachIn works
			For Local file:TBcc2BuildFile = EachIn work.stagedManifest.files
				Local finalPath:String = TBcc2BuildManifestCodec.Resolve(work.finalBuildRoot, file.relativePath)
				Local key:String = finalPath.Replace("\", "/").ToLower()
				If publishedPaths.Contains(key) Then Continue
				If String(bcc2PublishedOutputDigests.ValueForKey(key)) = file.contentDigest Then
					publishedPaths.Insert(key, finalPath)
					Continue
				End If
				Local stagedPath:String = TBcc2BuildManifestCodec.Resolve(work.stagingBuildRoot, file.relativePath)
				' A staged compiler may reuse an already-published file only after
				' ValidateBcc2CompileBatch has verified that the final file has the
				' exact digest declared by this manifest.
				If FileType(stagedPath) <> FILETYPE_FILE Then
					publishedPaths.Insert(key, finalPath)
					bcc2PublishedOutputDigests.Insert(key, file.contentDigest)
					Continue
				End If
				Local directory:String = ExtractDir(finalPath)
				If FileType(directory) = FILETYPE_NONE And Not CreateDir(directory, True) Then Throw "BMKGEN053 unable to create compiler output directory: " + directory
				If Not processor.PublishCompilerOutput(stagedPath, finalPath) Then Throw "BMKGEN053 unable to publish staged compiler output: " + finalPath
				publishedPaths.Insert(key, finalPath)
				bcc2PublishedOutputDigests.Insert(key, file.contentDigest)
			Next
		Next

		' Manifests become visible only after every file they declare has been
		' published. An interrupted publication therefore cannot validate as a
		' complete new bundle on the next build.
		For Local work:TBcc2CompileWork = EachIn works
			Local stagedManifestPath:String = work.stagingBuildRoot + "/" + StripDir(work.source.bcc2ManifestPath)
			If Not processor.PublishCompilerOutput(stagedManifestPath, work.source.bcc2ManifestPath) Then Throw "BMKGEN053 unable to publish staged compiler manifest: " + work.source.bcc2ManifestPath
		Next
	End Method

	Method CleanupBcc2StagingRoot(work:TBcc2CompileWork)
		If Not work Or Not work.source Or Not work.stagingBuildRoot.length Then Return
		PrepareBcc2StagingCleanup(work)
		TBcc2CleanupLane.Run(CreateBcc2CleanupLane(work))
		If work.cleanupFailure Then Throw work.cleanupFailure
	End Method

	Method PrepareBcc2StagingCleanup(work:TBcc2CompileWork)
		If Not work Or Not work.source Or Not work.stagingBuildRoot.length Then Return
		Local path:String = work.stagingBuildRoot.Replace("\", "/")
		Local prefix:String = StripSlash(work.source.bcc2BuildRoot.Replace("\", "/")) + "/.s-"
		Local suffix:String
		If path.ToLower().StartsWith(prefix.ToLower()) Then suffix = path[prefix.length..]
		If Not suffix.length Or suffix.Find("/") <> -1 Then Throw "BMKGEN054 refusing unsafe compiler staging cleanup: " + path
		work.cleanupPath = path
		work.cleanupFailure = Null
	End Method

	Method CleanupBcc2StagingBatch(works:TList, configuredWorkers:Int)
		If Not works Or Not works.Count() Then Return
		Local laneCount:Int = Min(Max(1, configuredWorkers), works.Count())
		Local lanes:TBcc2CleanupLane[] = New TBcc2CleanupLane[laneCount]
		For Local index:Int = 0 Until laneCount
			lanes[index] = New TBcc2CleanupLane
		Next
		Local ordinal:Int
		For Local work:TBcc2CompileWork = EachIn works
			PrepareBcc2StagingCleanup(work)
			lanes[ordinal Mod laneCount].works.AddLast(work)
			ordinal :+ 1
		Next
?threaded
		For Local lane:TBcc2CleanupLane = EachIn lanes
			processManager.AddTask(TBcc2CleanupLane.Run, lane)
		Next
		processManager.WaitForTasks()
?Not threaded
		For Local lane:TBcc2CleanupLane = EachIn lanes
			TBcc2CleanupLane.Run(lane)
		Next
?
		For Local work:TBcc2CompileWork = EachIn works
			If work.cleanupFailure Then Throw work.cleanupFailure
		Next
	End Method

	Function CreateBcc2CleanupLane:TBcc2CleanupLane(work:TBcc2CompileWork)
		Local lane:TBcc2CleanupLane = New TBcc2CleanupLane
		lane.works.AddLast(work)
		Return lane
	End Function

	Method CommitBcc2CompileWork(work:TBcc2CompileWork)
		If Not work Or Not work.source Then Throw "BMKGEN049 missing bcc2 compiler work result"
		If work.failure Then Throw work.failure
		Local source:TSourceFile = work.source
		Local response:TBcc2EngineResponse = work.response
		If Not response Then Throw "BMKGEN049 missing bcc2 compiler response for " + source.path
		If response.output.length Then LogLine(response.output.Trim())
		If response.exitCode Then Throw "BMKGEN031 bcc failed to produce a build bundle for " + source.path
		FinalizeBcc2CompileWork(work)
	End Method

	Method FinalizeBcc2CompileWork(work:TBcc2CompileWork, generatedFilesValidated:Int = False)
		If Not work Or Not work.source Then Throw "BMKGEN049 missing bcc2 compiler work result"
		Local source:TSourceFile = work.source
		processor.DoCallback(source.path)
		TBcc2BuildManifestCodec.Invalidate(source.bcc2ManifestPath)
		source.bcc2Manifest = TBcc2BuildManifestCodec.Load(source.bcc2ManifestPath)
		InvalidateBcc2SpecializationOwners()
		' Parallel batches validate every staged file against its manifest before
		' publishing anything. PublishCompilerOutput atomically renames those exact
		' bytes into the final tree, so hashing the published files again cannot add
		' a useful integrity guarantee. Serial compilation has no staged validation
		' and therefore retains the final-tree check.
		If Not generatedFilesValidated Then source.bcc2Manifest.ValidateGeneratedFiles(source.bcc2BuildRoot)
		If Not processor.PublishText(Bcc2GenerationStamp(source), source.bcc2ManifestPath + ".stamp") Then
			Throw "BMKGEN035 unable to write bcc2 generation freshness stamp: " + source.bcc2ManifestPath + ".stamp"
		End If
		source.gen_time = FileTime(source.bcc2ManifestPath + ".stamp")
		pendingForcedBcc2Manifests.Remove(source.bcc2ManifestPath.Replace("\", "/").ToLower())
		InvalidateBcc2SpecializationOwners()
		Local generatedCPath:String = StripExt(source.obj_path) + ".c"
		' The native object stage was created before this bundle was published and
		' therefore owns a copy of the previous generation timestamp. Mark that
		' stage directly: marking the semantic source would also make its importers
		' appear changed on the next otherwise-quiet dependency scan.
		Local objectStage:TSourceFile = TSourceFile(sources.ValueForKey(generatedCPath))
		If objectStage Then objectStage.SetRequiresBuild(True)
	End Method

	Method CompileBcc2Bundle(source:TSourceFile)
		Local compilationStarted:Int = MilliSecs()
		RequireBccCompilers(1)
		Local work:TBcc2CompileWork = CreateBcc2CompileWork(source)
		LogBcc2EngineRequest(work)
		work.response = bcc2Engines[0].Compile(work.arguments)
		CommitBcc2CompileWork(work)
		For Local file:TBcc2BuildFile = EachIn source.bcc2Manifest.files
			Local path:String = TBcc2BuildManifestCodec.Resolve(source.bcc2BuildRoot, file.relativePath)
			bcc2PublishedOutputDigests.Insert(path.Replace("\", "/").ToLower(), file.contentDigest)
		Next
		' The engine that materialized this bundle invalidates its own snapshot
		' cache, but other persistent worker engines may already have read the
		' previous interface. Broadcast publication to every live engine just as
		' the parallel batch path does, including for a batch with only one stale
		' BlitzMax source.
		Local invalidationPaths:String[] = New String[0]
		For Local file:TBcc2BuildFile = EachIn source.bcc2Manifest.files
			If file.role <> "interface" And file.role <> "generic-template" Then Continue
			invalidationPaths :+ [TBcc2BuildManifestCodec.Resolve(source.bcc2BuildRoot, file.relativePath)]
		Next
		For Local client:TBcc2EngineClient = EachIn bcc2Engines
			For Local offset:Int = 0 Until invalidationPaths.length Step 64
				client.Invalidate(invalidationPaths[offset..Min(offset + 64, invalidationPaths.length)])
			Next
		Next
		bcc2CompilationMillis :+ MilliSecs() - compilationStarted
		bcc2CompilationRequests :+ 1
	End Method

	Method EnsureBcc2Specializations(source:TSourceFile)
		If Not source Or Not source.bcc2Manifest Then Return
		If Not source.bcc2Manifest.links.length Then Return
		Local compilationStarted:Int = MilliSecs()
		Local reportedSpecializations:Int
		Local specializationOrdinal:Int
		Local specializationTotal:Int = source.bcc2Manifest.links.length
		Local pending:TList = New TList
		Local pendingByObject:TMap = New TMap
		' Existing bundles were validated as one deduplicated parallel batch during
		' dependency discovery. Bundles generated by this build are validated before
		' publication. Rehashing every declared output here once per source made an
		' otherwise clean build perform the same validation serially a second time.
		Local ownersByIdentity:TMap = CollectBcc2SpecializationOwners()
		For Local link:TBcc2BuildLink = EachIn source.bcc2Manifest.links
			specializationOrdinal :+ 1
			Local generated:TBcc2BuildFile = source.bcc2Manifest.FileForPath(link.sourcePath)
			Local sourcePath:String = TBcc2BuildManifestCodec.Resolve(source.bcc2BuildRoot, link.sourcePath)
			Local objectPath:String = TBcc2BuildManifestCodec.Resolve(source.bcc2BuildRoot, link.objectPath)
			Local owner:TBcc2SpecializationOwner = TBcc2SpecializationOwner(ownersByIdentity.ValueForKey(link.specializationIdentity))
			If owner And owner.objectPath.Replace("\", "/").ToLower() <> objectPath.Replace("\", "/").ToLower() Then
				If IsBcc2SpecializationOwnerUsable(owner) Then Continue
				' The preferred owner can be a manifest generated earlier in
				' this build whose object has not reached its compile stage yet.
				' Compile this equivalent candidate as a recoverable fallback;
				' the global ownership pass will prefer a usable candidate and
				' return to the normal priority order when the preferred object
				' becomes available.
			End If
			Local normalizedObjectPath:String = objectPath.Replace("\", "/").ToLower()
			Local compileOptions:String = source.GetIncludePaths() + " " + source.cc_opts + " " + source.c_opts
			If opt_standalone And opt_boot Then
				If ensuredBcc2SpecializationObjects.Contains(normalizedObjectPath) Then Continue
				Local objectDirectory:String = ExtractDir(objectPath)
				Local normalizedObjectDirectory:String = objectDirectory.Replace("\", "/").ToLower()
				If Not ensuredBcc2SpecializationDirectories.Contains(normalizedObjectDirectory) Then
					' Empty object-cache directories are not portable archive members,
					' so the destination build script must create them explicitly.
					If processor.Platform() = "win32" Then
						processor.PushLog("if not exist ~q" + objectDirectory + "~q mkdir ~q" + objectDirectory + "~q")
					Else
						processor.PushLog("mkdir -p " + CQuote(objectDirectory))
					End If
					ensuredBcc2SpecializationDirectories.Insert(normalizedObjectDirectory, objectDirectory)
				End If
				processor.PushSource(sourcePath)
				If Not opt_quiet Then
					If opt_verbose Then
						LogLine("Compiling generic specialization:" + sourcePath)
					Else
						If Not reportedSpecializations Then
							LogLine("Compiling generic specializations:" + StripDir(source.path))
							reportedSpecializations = True
						End If
						UpdateProgressLine(source.pct, source.path + " [generic " + specializationOrdinal + " of " + specializationTotal + "]")
					End If
				End If
				CompileC sourcePath, objectPath, compileOptions
				ensuredBcc2SpecializationObjects.Insert(normalizedObjectPath, link.cacheKey)
				Continue
			End If
			If ensuredBcc2SpecializationObjects.Contains(normalizedObjectPath) And FileType(objectPath) = FILETYPE_FILE Then Continue
			Local keyPath:String = objectPath + ".bcc2key"
			Local expectedKey:String = link.cacheKey + "~n" + generated.contentDigest + "~n" + TBcc2BuildManifestCodec.Digest(compileOptions)
			If FileType(objectPath) = FILETYPE_FILE And FileType(keyPath) = FILETYPE_FILE And LoadText(keyPath) = expectedKey Then
				ensuredBcc2SpecializationObjects.Insert(normalizedObjectPath, expectedKey)
				Continue
			End If
			Local existingWork:TBcc2SpecializationCompileWork = TBcc2SpecializationCompileWork(pendingByObject.ValueForKey(normalizedObjectPath))
			If existingWork Then
				If existingWork.expectedKey <> expectedKey Then Throw "BMKGEN039 conflicting compile requests for specialization object: " + objectPath
				Continue
			End If
			If FileType(ExtractDir(objectPath)) = FILETYPE_NONE And Not CreateDir(ExtractDir(objectPath), True) Then
				Throw "BMKGEN032 unable to create specialization object directory: " + ExtractDir(objectPath)
			End If
			If Not opt_quiet Then
				If opt_verbose Then
					LogLine("Compiling generic specialization:" + sourcePath)
				Else
					If Not reportedSpecializations Then
						LogLine("Compiling generic specializations:" + StripDir(source.path))
						reportedSpecializations = True
					End If
					UpdateProgressLine(source.pct, source.path + " [generic " + specializationOrdinal + " of " + specializationTotal + "]")
				End If
			End If
			Local work:TBcc2SpecializationCompileWork = New TBcc2SpecializationCompileWork
			work.objectPath = objectPath
			work.keyPath = keyPath
			work.expectedKey = expectedKey
			work.normalizedObjectPath = normalizedObjectPath
			pending.AddLast(work)
			pendingByObject.Insert(normalizedObjectPath, work)
			CompileC sourcePath, objectPath, compileOptions
		Next

		If pending.IsEmpty() Then Return
?threaded
		If Not opt_single Then
			processManager.WaitForTasks()
			bcc2SpecializationParallelBatches :+ 1
		End If
?
		' Validate the complete batch before publishing any cache sidecars. A failed
		' compile must never make a partial batch appear reusable on the next build.
		For Local work:TBcc2SpecializationCompileWork = EachIn pending
			If FileType(work.objectPath) <> FILETYPE_FILE Then Throw "BMKGEN033 specialization compiler did not produce: " + work.objectPath
		Next
		For Local work:TBcc2SpecializationCompileWork = EachIn pending
			If Not processor.PublishText(work.expectedKey, work.keyPath) Then Throw "BMKGEN034 unable to record specialization object cache key: " + work.keyPath
			ensuredBcc2SpecializationObjects.Insert(work.normalizedObjectPath, work.expectedKey)
		Next
		' Owner selection considers native object/key usability. Rebuild it once after
		' this batch changes that state, rather than once for every later archive.
		InvalidateBcc2SpecializationOwners()
		bcc2SpecializationCompilationObjects :+ pending.Count()
		bcc2SpecializationCompilationMillis :+ MilliSecs() - compilationStarted
	End Method

	Method CreateIncBin:TSourceFile(source:TSourceFile, sourcePath:String)
	
		Local path:String = StripDir(sourcePath) + opt_configmung +  processor.CPU()
		If opt_standalone Or (processor.CPU() = "x86" And processor.Platform() = "win32") Then
			path :+ ".incbin.c"
		Else
			path :+ ".incbin2.c"
		End If

		Local ibPath:String = ExtractDir(sourcePath) + "/.bmx/" + path

		Local ib:TSourceFile = GetSourceFile(ibPath,,,,False)
		
		If Not ib Then
			ib = New TSourceFile
			
			ib.path = ibPath
			ib.obj_path = StripExt(ib.path) + ".o"
			ib.ext = "c"
			ib.exti = String(processor.RunCommand("source_type", [ib.ext])).ToInt()

			source.imports.AddLast(".bmx/" + StripDir(path) )
		End If
		
		If ib.includePaths.IsEmpty() Then
			ib.CopyIncludePaths(source.includePaths)
		End If

		' Production bcc writes this resource-packaging unit as a side effect of
		' source generation. bcc2 deliberately emits only the semantic Incbin
		' registration and leaves packaging/freshness ownership with bmk.
		If UseBcc2ForSource(source) Then
			GenerateBcc2IncBin(source, sourcePath, ibPath)
		End If

		GetIncBinFileList(ib)
		
		ib.time = FileTime(ib.path)
		ib.obj_time = FileTime(ib.obj_path)

		sources.Insert(ib.path, ib)

		If opt_standalone And opt_boot Then
			processor.PushSource(ib.path)
		End If

		Return ib
	End Method

	Method GenerateBcc2IncBin(source:TSourceFile, sourcePath:String, incbinPath:String)
		Local sourceModuleName:String = source.modid
		If Not sourceModuleName.length Then sourceModuleName = source.bcc2SourceModuleName

		Local unitName:String
		If sourceModuleName.length And (source.modid Or source.bcc2OwnedSource) Then
			unitName = "_bb_" + sourceModuleName.ToLower().Replace(".", "_")
			Local sourceUnitIdentity:String = StripExt(StripDir(sourcePath)).ToLower()
			If source.bcc2SourceUnitPath.length Then sourceUnitIdentity = Bcc2SourceUnitAbiIdentity(source.bcc2SourceUnitPath)
			unitName :+ "_" + sourceUnitIdentity
		Else
			unitName = "_bb_main"
		End If

		Local output:String = "#define INCBIN_PREFIX _ib~n"
		output :+ "#define INCBIN_STYLE INCBIN_STYLE_SNAKE~n"
		output :+ "#include ~qbrl.mod/blitz.mod/incbin/incbin.h~q~n"

		Local resources:String
		Local ordinal:Int
		For Local logicalPath:String = EachIn source.incbins
			ordinal :+ 1
			Local resolvedPath:String = CheckPath(ExtractDir(source.path), logicalPath)
			If FileType(resolvedPath) <> FILETYPE_FILE And source.owner_path.length Then
				resolvedPath = CheckPath(ExtractDir(source.owner_path), logicalPath)
			End If
			If FileType(resolvedPath) <> FILETYPE_FILE Then
				Throw "BMKGEN041 Incbin resource was not found: " + logicalPath
			End If

			Local escapedLogicalPath:String = logicalPath.Replace("\", "\\").Replace("~q", "\~q")
			Local escapedResolvedPath:String = resolvedPath.Replace("\", "\\").Replace("~q", "\~q")
			output :+ "// FILE : ~q" + escapedLogicalPath + "~q~t" + CalculateFileHash(resolvedPath) + "~n"
			resources :+ "INCBIN(" + unitName + "_" + ordinal + ", ~q" + escapedResolvedPath + "~q);~n"
		Next
		output :+ "// ----~n"
		output :+ resources

		If FileType(ExtractDir(incbinPath)) = FILETYPE_NONE And Not CreateDir(ExtractDir(incbinPath), True) Then
			Throw "BMKGEN042 unable to create Incbin output directory: " + ExtractDir(incbinPath)
		End If
		If FileType(incbinPath) <> FILETYPE_FILE Or LoadText(incbinPath) <> output Then
			If Not SaveText(output, incbinPath) Then
				Throw "BMKGEN043 unable to write Incbin packaging unit: " + incbinPath
			End If
		End If
	End Method

	Method Bcc2GenerationStamp:String(source:TSourceFile)
		Local configuration:String = processor.Platform() + "~n" + Bcc2GenerationFingerprintOptions(source.bcc_opts)
		Return "BMXGEN 1~nsource " + source.time + "~noptions " + TBcc2BuildManifestCodec.Digest(configuration) + "~n"
	End Method

	Method GetIncBinFileList(source:TSourceFile)
		Local stream:TStream = ReadStream(source.path)
		If stream Then
			While Not stream.Eof()
				Local line:String = stream.ReadLine()
				If line.StartsWith("// FILE : ") Then
					Local parts:String[] = line[10..].Split("~t")
					Local ib:String = parts[0].Replace("~q", "")
					If ib Then
						source.incbins.AddLast(ib)
						If parts.length = 2 Then
							source.hashes.Insert(ib, parts[1])
						End If
					End If
				Else If line.StartsWith("// ----") Then
					Exit
				EndIf
			Wend
			
			stream.Close()
		End If
	End Method
	
	Method IncbinsDifference:Int(ib1:TList, ib2:TList)
		If ib1.Count() <> ib2.Count() Then
			Return True
		End If

		For Local ib:String = EachIn ib1
			If Not ib2.Contains(ib) Then
				Return True
			End If
		Next

		For Local ib:String = EachIn ib2
			If Not ib1.Contains(ib) Then
				Return True
			End If
		Next
		
		Return False
	End Method
	
	Method IncbinsHashDifference:Int(source:TSourceFile, ib:TSourceFile)
		If source.hashes.IsEmpty() Then
			Return True
		End If
		
		For Local file:String = EachIn source.hashes.Keys()
			Local sourceHash:String = String(source.hashes.ValueForKey(file))
			If sourceHash <> String(ib.hashes.ValueForKey(file)) Then
				Return True
			End If
		Next

		For Local file:String = EachIn ib.hashes.Keys()
			Local ibHash:String = String(ib.hashes.ValueForKey(file))
			If ibHash <> String(source.hashes.ValueForKey(file)) Then
				Return True
			End If
		Next
	End Method
	
	Method CreateLinkStage:TSourceFile(source:TSourceFile, stage:Int = STAGE_LINK)
		Local link:TSourceFile = New TSourceFile
		
		source.CopyInfo(link)
		
		link.deps.Insert(StripExt(link.obj_path) + ".c", source)
		link.stage = stage
		link.processed = True
		link.depsList = New TList
		link.depsList.AddLast(source)		

		If IOS_HAS_MERGE And processor.Platform() = "ios" Then
			sources.Insert(link.obj_path, link)
		Else
			sources.Insert(link.arc_path, link)
		End If

		Return link
	End Method
	
	Method CreateMergeStage:TSourceFile(source:TSourceFile)

		Local merge:TSourceFile = New TSourceFile
		
		source.CopyInfo(merge)
		
		merge.deps.Insert(merge.obj_path, source)
		merge.stage = STAGE_MERGE
		merge.processed = True
		merge.depsList = New TList
		merge.depsList.AddLast(source)		

		sources.Insert(merge.merge_path, merge)

		Return merge
	End Method
	
	Method CalculateBatches:TList(files:TList)

		Local batches:TList = New TList
		Local count:Int = files.Count()
		Local nodes:TMap = New TMap
		For Local m:TSourceFile = EachIn files
			Local node:TBuildDependencyNode = New TBuildDependencyNode
			node.source = m
			nodes.Insert(m.GetSourcePath(), node)
		Next

		For Local m:TSourceFile = EachIn files
			Local node:TBuildDependencyNode = TBuildDependencyNode(nodes.ValueForKey(m.GetSourcePath()))
			For Local dependencyName:String = EachIn m.deps.Keys()
				Local dependency:TBuildDependencyNode = TBuildDependencyNode(nodes.ValueForKey(dependencyName))
				If Not dependency Then Throw "Build graph dependency is missing: " + dependencyName
				node.remaining :+ 1
				dependency.dependents.AddLast(node)
			Next
		Next

		Local pct:Float = 100.0 / count
		Local total:Float
		Local num:Int
		Local ready:TList = New TList
		For Local node:TBuildDependencyNode = EachIn nodes.Values()
			If Not node.remaining Then ready.AddLast(node)
		Next
		Local resolved:Int

		While resolved < count
			If ready.IsEmpty() Then
				' circular dependency!
				Print "REMAINING :"
				For Local node:TBuildDependencyNode = EachIn nodes.Values()
					If node.remaining Then Print "  " + node.source.GetSourcePath()
				Next
				Throw "circular dependency!"
			End If

			Local batch:TList = New TList
			Local nextReady:TList = New TList
			For Local node:TBuildDependencyNode = EachIn ready
				batch.AddLast(node.source)
				resolved :+ 1
				For Local dependent:TBuildDependencyNode = EachIn node.dependents
					dependent.remaining :- 1
					If Not dependent.remaining Then nextReady.AddLast(dependent)
				Next
			Next
			batches.AddLast(batch)
			ready = nextReady
		Wend

		' post process batches
		Local suffix:String[]
		Local stage:Int
		For Local i:Int = 0 Until 3
			Select i
				Case 0
					suffix = ["c", "cpp", "cc", "cxx", "m", "mm"]
				Case 1
					suffix = ["o"]
					stage = STAGE_LINK
				Case 2
					suffix = ["o"]
					stage = STAGE_APP_LINK
			End Select
			
			Local newList:TList = New TList
		
			For Local list:TList = EachIn batches
	
				For Local f:TSourceFile = EachIn list
				
					Local p:String = f.GetSourcePath()
					
					If Not p.EndsWith("bmx") Then
						For Local s:String = EachIn suffix
							If p.EndsWith(s) Then
								If app_iface And stage Then
									If (stage = STAGE_LINK And app_iface = f.iface_path) Or (stage = STAGE_APP_LINK And app_iface <> f.iface_path) Then
										Continue
									End If
								End If
								newList.AddLast(f)
								list.Remove(f)
								If list.IsEmpty() Then
									batches.Remove(list)
								End If
								' found, no need to loop further
								Exit
							End If
						Next
					End If
				Next
			Next
			
			If Not newList.IsEmpty() Then
				batches.AddLast(newList)
			End If
		Next
		
		For Local list:TList = EachIn batches
			For Local m:TSourceFile = EachIn list
				total :+ pct
				num :+ 1
				If num = count Then
					m.pct = 100
				Else
					m.pct = total
				End If
			Next
		Next

		Return batches
		
	End Method
	
	Method ShowPct:String(pct:Int)
		Local s:String = "["
		Local p:String = String.FromInt(pct)
		Select p.length
			Case 1
				s :+ "  "
			Case 2
				s :+ " "
		End Select
		Return s + p + "%] "
	End Method
	
	Method FixPct:String(pct:String)
		If processor.Platform() = "win32" Then
			Return pct.Replace("%", "%%")
		Else
			Return pct
		End If
	End Method

	Method CheckPath:String(basePath:String, path:String)
		Local p:String = RealPath(basePath + "/" + path)
		If Not FileType(p) Then
			' maybe path is a full path already?
			p = RealPath(path)
			If Not FileType(p) Then
				' meh... fallback to original
				p = RealPath(basePath + "/" + path)
			End If
		End If
		Return p	
	End Method
	
	Method DoCallback(src:String)
		Local update:Int = True

		Local m:TSourceFile = TSourceFile(sources.ValueForKey(src))

		If m Then
			If UseBcc2ForSource(m) Then
				PublishBcc2CompatibilityInterface(m)
				Return
			End If

			If FileType(m.iface_path) = FILETYPE_FILE Then
				' has the interface/api changed since the last build?
				If FileType(m.iface_path2) = FILETYPE_FILE And m.time = FileTime( m.path ) Then

					If FileSize(m.iface_path) = FileSize(m.iface_path2) Then

						Local i_bytes:Byte[] = LoadByteArray(m.iface_path)
						Local i_bytes2:Byte[] = LoadByteArray(m.iface_path2)
?bmxng
						If i_bytes.length = i_bytes2.length And memcmp_( i_bytes, i_bytes2, Size_T(i_bytes.length) )=0 Then
							update = False
						End If
?Not bmxng
						If i_bytes.length = i_bytes2.length And memcmp_( i_bytes, i_bytes2, i_bytes.length )=0 Then
							update = False
						End If
?
					End If
				End If
				If update Then
					CopyFile m.iface_path, m.iface_path2
				Else If m.iface_time < m.MaxIfaceTime() Then
					SetFileTimeNow(m.iface_path2)
					m.iface_time = time_(Null)
					m.maxIfaceTimeCache = -1
				End If
			End If
	
			If update Then
				m.SetRequiresBuild(True)
				m.iface_time = time_(Null)
				m.maxIfaceTimeCache = -1
				m.gen_time = time_(Null)
			End If
		
		End If

	End Method

	Method PublishBcc2CompatibilityInterface(m:TSourceFile)
		If Not m Or Not m.modid Or FileType(m.iface_path) <> FILETYPE_FILE Then Return
		Local update:Int = FileType(m.iface_path2) <> FILETYPE_FILE
		If Not update And FileSize(m.iface_path) = FileSize(m.iface_path2) Then
			Local interfaceBytes:Byte[] = LoadByteArray(m.iface_path)
			Local compatibilityBytes:Byte[] = LoadByteArray(m.iface_path2)
			If interfaceBytes.length <> compatibilityBytes.length Then
				update = True
			Else
?bmxng
				update = memcmp_(interfaceBytes, compatibilityBytes, Size_T(interfaceBytes.length)) <> 0
?Not bmxng
				update = memcmp_(interfaceBytes, compatibilityBytes, interfaceBytes.length) <> 0
?
			End If
		Else If Not update Then
			update = True
		End If
		If Not update Then Return
		If Not CopyFile(m.iface_path, m.iface_path2) Then
			Throw "BMKGEN037 unable to publish bcc compatibility interface copy: " + m.iface_path2
		End If
		m.SetRequiresBuild(True)
		m.iface_time = FileTime(m.iface_path2)
		m.maxIfaceTimeCache = -1
		m.gen_time = time_(Null)
	End Method

End Type


Type TArcTask

	Field m:TSourceFile
	Field path:String
	Field oobjs:TList
	Field announcedMillis:Int
	Field readyMillis:Int
	Field objectCount:Int
	Field objectBytes:Long
	Field inputIdentity:String
	Field commandCount:Int
	Field commandMillis:Int
	Field failure:Object

	Method Create:TArcTask(m:TSourceFile, path$ , oobjs:TList )
		Self.m = m
		Self.path = path
		Self.oobjs = oobjs
		announcedMillis = MilliSecs()
		If opt_verbose Then
			Local identity:TStringBuffer = New TStringBuffer(4096)
			For Local objectPath:String = EachIn oobjs
				objectCount :+ 1
				objectBytes :+ Max(Long(0), FileSize(objectPath))
				identity.Append(objectPath.Replace("\", "/")).Append("~n")
			Next
			inputIdentity = TBcc2BuildManifestCodec.Digest(identity.ToString())
		End If
		readyMillis = MilliSecs()
		Return Self
	End Method

	Method Announce()
		announcedMillis = MilliSecs()
		readyMillis = MilliSecs()
	End Method

	Function _CreateArc:Object(data:Object)
		Local archive:TArcTask = TArcTask(data)
		Try
			Return archive.CreateArc()
		Catch exception:Object
			archive.failure = exception
		End Try
		Return Null
	End Function

	Method ExecuteArchiveCommand:Int(command:String)
		commandCount :+ 1
		Local startedMillis:Int = MilliSecs()
		Local result:Int = processor.Sys(command)
		commandMillis :+ MilliSecs() - startedMillis
		Return result
	End Method

	Method CreateArc:Object()
		Local startedMillis:Int = MilliSecs()
		Local prepareMillis:Int = readyMillis - announcedMillis
		Local waitMillis:Int = startedMillis - readyMillis
		Local outputPath:String = processor.TemporaryOutputPath(path)
		DeleteFile outputPath
		Local cmd$,t$
	
		If processor.Platform() = "win32" And Not opt_standalone
			' GNU ar accepts response files. Besides avoiding Windows' short command
			' line limit, one invocation lets the archiver construct its symbol table
			' once instead of repeatedly reopening and extending the same archive.
			Local responsePath:String = processor.TemporaryOutputPath(path) + ".objects.rsp"
			Local response:TStringBuffer = New TStringBuffer(4096)
			For t = EachIn oobjs
				Local objectPath:String = t.Replace("\", "/")
				response.Append(CQuote(objectPath)).Append("~n")
			Next
			DeleteFile responsePath
			If Not SaveText(response.ToString(), responsePath) Then
				Throw "Build Error: Failed to write archive response file " + responsePath
			End If
			Local prefix:String = processor.MinGWExePrefix()
			Local ext:String = ""
			If processor.OSPlatform() = "win32" Then ext = ".exe"
			cmd = CQuote(processor.Option("path_to_ar", processor.MinGWBinPath() + "/" + prefix + "ar" + ext)) + " -rc " + CQuote(outputPath) + " @" + CQuote(responsePath.Replace("\", "/"))
			Local responseResult:Int = ExecuteArchiveCommand(cmd)
			DeleteFile responsePath
			If responseResult Then
				DeleteFile outputPath
				Throw "Build Error: Failed to create archive " + path
			End If
			cmd = ""
		Else If processor.Platform() = "win32"
			For t$=EachIn oobjs
				If Len(cmd)+Len(t)>1000

					If ExecuteArchiveCommand(cmd)
						DeleteFile outputPath
						Throw "Build Error: Failed to create archive "+path
					EndIf
					cmd=""
				EndIf
				If Not cmd Then
					Local prefix:String = processor.MinGWExePrefix()
					Local ext:String = ""
					If processor.OSPlatform() = "win32" Then
						ext = ".exe"
					End If
					cmd= processor.Option("path_to_ar", processor.MinGWBinPath() + "/" + prefix + "ar" + ext) + " -rc "+CQuote(outputPath)
				End If
				cmd:+" "+CQuote(t)
			Next
		End If
		
		If processor.Platform() = "macos" Or processor.Platform() = "osx" Then
			cmd=processor.Option(processor.BuildName("libtool"), "libtool") + " -o "+CQuote(outputPath)
			For Local t$=EachIn oobjs
				cmd:+" "+CQuote(t)
			Next
		End If
	
		If processor.Platform() = "ios" Then
			Local proc:String = processor.CPU()
			Select proc
				Case "x86"
					proc = "i386"
				Case "x64"
					proc = "x86_64"
			End Select
		
			cmd= processor.Option(processor.BuildName("libtool"), "libtool") + " -static -arch_only " + proc + " -o "+CQuote(outputPath)
			For Local t$=EachIn oobjs
				cmd:+" "+CQuote(t)
			Next
		End If
		
		If processor.Platform() = "linux" Or processor.Platform() = "raspberrypi" Or processor.Platform() = "android" Or processor.Platform() = "emscripten" Or processor.Platform() = "nx" Or processor.Platform() = "haiku"
			For Local t$=EachIn oobjs
				If Len(cmd)+Len(t)>1000
				
					If ExecuteArchiveCommand(cmd)
						DeleteFile outputPath
						Throw "Build Error: Failed to create archive "+path
					EndIf
					cmd=""
				EndIf
				If processor.Platform() = "emscripten" Then
					If Not cmd cmd=processor.Option(processor.BuildName("ar"), "emar") + " r "+CQuote(outputPath)
				Else
					If Not cmd cmd=processor.Option(processor.BuildName("ar"), "ar") + " -r "+CQuote(outputPath)
				End If
				cmd:+" "+CQuote(t)
			Next
		End If
	
		If cmd
			If ExecuteArchiveCommand(cmd)
				DeleteFile outputPath
				Throw "Build Error: Failed to create archive "+path
			End If
		EndIf

		Local publishStartedMillis:Int = MilliSecs()
		If Not processor.PublishOutput(outputPath, path) Then
			DeleteFile outputPath
			Throw "Build Error: Failed to publish archive " + path
		End If
		Local publishMillis:Int = MilliSecs() - publishStartedMillis
		If opt_verbose Then
			Local completedMillis:Int = MilliSecs()
			LogLine("bmk: archive timing " + StripDir(path) + " prepare=" + prepareMillis + " ms wait=" + waitMillis + " ms command=" + commandMillis + " ms publish=" + publishMillis + " ms worker=" + (completedMillis - startedMillis) + " ms elapsed=" + (completedMillis - announcedMillis) + " ms objects=" + objectCount + " bytes=" + objectBytes + " commands=" + commandCount + " input=" + inputIdentity)
		End If

		m.arc_time = time_(Null)
		m.obj_time = time_(Null)

	End Method
	
End Type
