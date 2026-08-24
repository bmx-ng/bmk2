SuperStrict

Import BRL.FileSystem
Import BRL.LinkedList
Import BRL.Map
Import BRL.StandardIO
Import Pub.StdC

Type TCompilerCacheEntry
	Field path:String
	Field fileType:Int
	Field depth:Int
End Type

Type TCompilerCachePlan
	Field path:String
	Field entries:TList
	Field maximumDepth:Int

	Method Execute(verbose:Int = False)
		If verbose Then Print "  Deleting " + path
		For Local depth:Int = maximumDepth To 0 Step -1
			For Local entry:TCompilerCacheEntry = EachIn entries
				If entry.depth <> depth Then Continue
				If entry.fileType = FILETYPE_FILE Then
					If FileType(entry.path) <> FILETYPE_FILE Or Not DeleteFile(entry.path) Then
						Throw "BMKCLEAN006 unable to remove generated file: " + entry.path
					End If
				Else
					' Never recurse here. The complete tree was inspected first, and
					' directories are removed from the leaves upward.
					If FileType(entry.path) <> FILETYPE_DIR Or Not DeleteDir(entry.path, False) Then
						Throw "BMKCLEAN007 unable to remove generated directory: " + entry.path
					End If
				End If
			Next
		Next
	End Method
End Type

Type TCompilerOutputFilePlan
	Field path:String
	Field cacheKind:String

	Method Execute(verbose:Int = False)
		If readlink_(path).length Then
			Throw "BMKCLEAN002 refusing symbolic " + cacheKind + " output file: " + path
		End If
		If FileType(path) <> FILETYPE_FILE Or Not DeleteFile(path) Then
			Throw "BMKCLEAN006 unable to remove generated file: " + path
		End If
		If verbose Then Print "  Deleted " + path
	End Method
End Type

Type TCompilerCacheWalker Implements IFileWalker
	Field root:String
	Field entries:TList = New TList
	Field paths:TMap = New TMap

	Method New(root:String)
		Self.root = NormalizeCompilerCachePath(root)
	End Method

	Method Add(path:String, fileType:Int, depth:Int)
		Local normalized:String = NormalizeCompilerCachePath(path)
		If normalized <> root And Not normalized.StartsWith(root + "/") Then
			Throw "BMKCLEAN004 refusing cache entry outside the selected directory: " + path
		End If
		If paths.Contains(normalized) Then Return
		Local entry:TCompilerCacheEntry = New TCompilerCacheEntry
		entry.path = path
		entry.fileType = fileType
		entry.depth = depth
		entries.AddLast(entry)
		paths.Insert(normalized, entry)
	End Method

	Method WalkFile:EFileWalkResult(attributes:SFileAttributes Var)
		Local path:String = attributes.GetName()
		Add(path, Int(attributes.fileType), Int(attributes.depth))
		Return EFileWalkResult.OK
	End Method
End Type

Function NormalizeCompilerCachePath:String(path:String)
	Local normalized:String = RealPath(path).Replace("\", "/")
	While normalized.length > 1 And normalized.EndsWith("/")
		normalized = normalized[..normalized.length - 1]
	Wend
?win32
	normalized = normalized.ToLower()
?
	Return normalized
End Function

Function InspectCompilerCacheDirectory:TCompilerCachePlan(path:String, expectedLeaf:String = ".bmx", cacheKind:String = "application")
	Local normalized:String = NormalizeCompilerCachePath(path)
	If StripDir(normalized) <> expectedLeaf Then
		Throw "BMKCLEAN001 refusing non-" + expectedLeaf + " " + cacheKind + " cache directory: " + path
	End If
	If readlink_(path).length Then
		Throw "BMKCLEAN002 refusing symbolic " + cacheKind + " cache directory: " + path
	End If
	Local rootType:Int = FileType(path)
	If rootType = FILETYPE_NONE Then Return Null
	If rootType <> FILETYPE_DIR Then
		Throw "BMKCLEAN003 " + cacheKind + " cache path is not a directory: " + path
	End If

	Local walker:TCompilerCacheWalker = New TCompilerCacheWalker(path)
	WalkFileTree(path, walker, EFileWalkOption.None)
	' The Windows walker reports children but not the root itself.
	walker.Add(path, FILETYPE_DIR, 0)

	Local plan:TCompilerCachePlan = New TCompilerCachePlan
	plan.path = path
	plan.entries = walker.entries
	For Local entry:TCompilerCacheEntry = EachIn walker.entries
		If readlink_(entry.path).length Or entry.fileType = FILETYPE_SYM Then
			Throw "BMKCLEAN002 refusing symbolic link inside " + cacheKind + " cache: " + entry.path
		End If
		If entry.fileType <> FILETYPE_FILE And entry.fileType <> FILETYPE_DIR Then
			Throw "BMKCLEAN005 refusing unsupported cache entry: " + entry.path
		End If
		plan.maximumDepth = Max(plan.maximumDepth, entry.depth)
	Next
	Return plan
End Function

Function InspectCompilerOutputFile:TCompilerOutputFilePlan(path:String, cacheKind:String)
	If readlink_(path).length Then
		Throw "BMKCLEAN002 refusing symbolic " + cacheKind + " output file: " + path
	End If
	Local outputType:Int = FileType(path)
	If outputType = FILETYPE_NONE Then Return Null
	If outputType <> FILETYPE_FILE Then
		Throw "BMKCLEAN005 refusing unsupported " + cacheKind + " output: " + path
	End If
	Local plan:TCompilerOutputFilePlan = New TCompilerOutputFilePlan
	plan.path = path
	plan.cacheKind = cacheKind
	Return plan
End Function
