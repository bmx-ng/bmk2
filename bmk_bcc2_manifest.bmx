' Copyright (c) 2026 Bruce A Henderson and contributors
' SPDX-License-Identifier: Zlib

SuperStrict

Import BRL.Base64
Import BRL.FileSystem
Import BRL.Map
Import BRL.TextStream
Import Crypto.SHA256Digest

Const BMK_BCC2_BUILD_MANIFEST_VERSION:Int = 1

Type TBcc2BuildFile
	Field role:String
	Field contentDigest:String
	Field cacheKey:String
	Field semanticIdentity:String
	Field relativePath:String
End Type

Type TBcc2BuildLink
	Field cacheKey:String
	Field specializationIdentity:String
	Field sourcePath:String
	Field objectPath:String
End Type

Type TBcc2ValidatedBuildFile
	Field modifiedTime:Long
	Field size:Long
	Field digest:String
End Type

Type TBcc2BuildValidationStats
	Field declarations:Int
	Field hashedFiles:Int
	Field reusedFiles:Int
	Field hashedBytes:Long
End Type

Type TBcc2BuildManifest
	Field files:TBcc2BuildFile[] = New TBcc2BuildFile[0]
	Field links:TBcc2BuildLink[] = New TBcc2BuildLink[0]
	Field filesByPath:TMap = New TMap

	Method FileForPath:TBcc2BuildFile(relativePath:String)
		Return TBcc2BuildFile(filesByPath.ValueForKey(NormalizePath(relativePath)))
	End Method

	Function NormalizePath:String(path:String)
		Return path.Replace("\", "/").ToLower()
	End Function

	Method ValidateGeneratedFiles(rootPath:String, validatedFiles:TMap = Null, stats:TBcc2BuildValidationStats = Null)
		For Local file:TBcc2BuildFile = EachIn files
			Local path:String = TBcc2BuildManifestCodec.Resolve(rootPath, file.relativePath)
			Local info:SFileStat
			If Not FileStat(path, info) Or info.fileType <> FILETYPE_FILE Then
				Throw "BMKGEN020 declared compiler output is missing: " + path
			End If
			If stats Then stats.declarations :+ 1
			Local digest:String
			Local modifiedTime:Long = info.modifiedTime
			Local size:Long = info.size
			Local normalizedPath:String = path.Replace("\", "/").ToLower()
			Local cached:TBcc2ValidatedBuildFile
			If validatedFiles Then cached = TBcc2ValidatedBuildFile(validatedFiles.ValueForKey(normalizedPath))
			If cached And cached.modifiedTime = modifiedTime And cached.size = size Then
				digest = cached.digest
				If stats Then stats.reusedFiles :+ 1
			Else
				digest = TBcc2BuildManifestCodec.FileDigest(path)
				If validatedFiles Then
					cached = New TBcc2ValidatedBuildFile
					cached.modifiedTime = modifiedTime
					cached.size = size
					cached.digest = digest
					validatedFiles.Insert(normalizedPath, cached)
				End If
				If stats Then
					stats.hashedFiles :+ 1
					stats.hashedBytes :+ size
				End If
			End If
			If digest <> file.contentDigest Then
				Throw "BMKGEN021 compiler output digest mismatch: " + path
			End If
		Next
	End Method

	Method ValidateLinkClosure()
		Local linksBySourcePath:TMap = New TMap
		For Local link:TBcc2BuildLink = EachIn links
			Local file:TBcc2BuildFile = FileForPath(link.sourcePath)
			If Not file Or file.role <> "generic-specialization-c" Then
				Throw "BMKGEN022 specialization link source is not a declared generated C unit: " + link.sourcePath
			End If
			If file.cacheKey <> link.cacheKey Or file.semanticIdentity <> link.specializationIdentity Then
				Throw "BMKGEN023 specialization file/link identity mismatch: " + link.sourcePath
			End If
			Local normalizedSourcePath:String = NormalizePath(link.sourcePath)
			If linksBySourcePath.Contains(normalizedSourcePath) Then
				Throw "BMKGEN024 specialization C unit must have exactly one link record: " + link.sourcePath
			End If
			linksBySourcePath.Insert(normalizedSourcePath, link)
		Next
		For Local file:TBcc2BuildFile = EachIn files
			If file.role <> "generic-specialization-c" Then Continue
			If Not linksBySourcePath.Contains(NormalizePath(file.relativePath)) Then Throw "BMKGEN024 specialization C unit must have exactly one link record: " + file.relativePath
		Next
	End Method
End Type

Type TBcc2BuildManifestCacheEntry
	Field manifest:TBcc2BuildManifest
	Field modifiedTime:Long
	Field size:Long
End Type

Type TBcc2BuildManifestCodec
	Global loadedManifests:TMap = New TMap

	Function Decode:TBcc2BuildManifest(content:String)
		Local result:TBcc2BuildManifest = New TBcc2BuildManifest
		Local linkIdentities:TMap = New TMap
		Local linkObjectPaths:TMap = New TMap
		Local lines:String[] = content.Replace("~r~n", "~n").Replace("~r", "~n").Split("~n")
		If Not lines.length Or lines[0] <> "BMXBUILD " + BMK_BCC2_BUILD_MANIFEST_VERSION Then
			Throw "BMKGEN001 unsupported or missing compiler build manifest version"
		End If
		For Local index:Int = 1 Until lines.length
			Local line:String = lines[index]
			If Not line.length And index = lines.length - 1 Then Continue
			Local parts:String[] = line.Split(" ")
			If parts.length = 6 And parts[0] = "file" Then
				Local file:TBcc2BuildFile = New TBcc2BuildFile
				file.role = parts[1]
				file.contentDigest = parts[2]
				If parts[3] <> "-" Then file.cacheKey = parts[3]
				file.semanticIdentity = DecodeField(parts[4])
				file.relativePath = DecodeField(parts[5])
				If Not ValidRole(file.role) Or Not IsDigest(file.contentDigest) Or (file.cacheKey.length And Not IsDigest(file.cacheKey)) Then
					Throw "BMKGEN002 malformed compiler build file record"
				End If
				If Not IsSafeRelativePath(file.relativePath) Then Throw "BMKGEN003 unsafe compiler build file path"
				Local normalizedFilePath:String = TBcc2BuildManifest.NormalizePath(file.relativePath)
				If result.filesByPath.Contains(normalizedFilePath) Then Throw "BMKGEN004 duplicate compiler build file path"
				result.files :+ [file]
				result.filesByPath.Insert(normalizedFilePath, file)
			Else If parts.length = 5 And parts[0] = "link" Then
				Local link:TBcc2BuildLink = New TBcc2BuildLink
				link.cacheKey = parts[1]
				link.specializationIdentity = parts[2]
				link.sourcePath = DecodeField(parts[3])
				link.objectPath = DecodeField(parts[4])
				If Not IsDigest(link.cacheKey) Or Not IsDigest(link.specializationIdentity) Then
					Throw "BMKGEN005 malformed compiler build link identity"
				End If
				If Not IsSafeRelativePath(link.sourcePath) Or Not IsSafeRelativePath(link.objectPath) Then
					Throw "BMKGEN006 unsafe compiler build link path"
				End If
				Local normalizedObjectPath:String = TBcc2BuildManifest.NormalizePath(link.objectPath)
				If linkIdentities.Contains(link.specializationIdentity) Or linkObjectPaths.Contains(normalizedObjectPath) Then Throw "BMKGEN007 duplicate compiler build link input"
				result.links :+ [link]
				linkIdentities.Insert(link.specializationIdentity, link)
				linkObjectPaths.Insert(normalizedObjectPath, link)
			Else
				Throw "BMKGEN008 unknown or malformed compiler build manifest record"
			End If
		Next
		result.ValidateLinkClosure()
		Return result
	End Function

	Function Load:TBcc2BuildManifest(path:String)
		Local info:SFileStat
		If Not FileStat(path, info) Or info.fileType <> FILETYPE_FILE Then Throw "BMKGEN009 compiler build manifest is missing: " + path
		Local normalizedPath:String = path.Replace("\", "/").ToLower()
		Local modifiedTime:Long = info.modifiedTime
		Local size:Long = info.size
		Local cached:TBcc2BuildManifestCacheEntry = TBcc2BuildManifestCacheEntry(loadedManifests.ValueForKey(normalizedPath))
		If cached And cached.modifiedTime = modifiedTime And cached.size = size Then Return cached.manifest
		Local result:TBcc2BuildManifest = Decode(LoadText(path))
		cached = New TBcc2BuildManifestCacheEntry
		cached.manifest = result
		cached.modifiedTime = modifiedTime
		cached.size = size
		loadedManifests.Insert(normalizedPath, cached)
		Return result
	End Function

	Function Invalidate(path:String)
		loadedManifests.Remove(path.Replace("\", "/").ToLower())
	End Function

	Function DecodeField:String(value:String)
		If value = "-" Then Return ""
		Try
			Local bytes:Byte[] = TBase64.Decode(value)
			Return String.FromUTF8Bytes(bytes, bytes.length)
		Catch exception:Object
			Throw "BMKGEN010 malformed encoded compiler build manifest field"
		End Try
	End Function

	Function ValidRole:Int(role:String)
		Select role
			Case "application-c", "runtime-header", "interface", "generic-template", "generic-specialization-c"
				Return True
		End Select
		Return False
	End Function

	Function IsDigest:Int(value:String)
		If value.length <> 64 Then Return False
		For Local character:Int = EachIn value.ToLower()
			If Not (character >= 48 And character <= 57) And Not (character >= 97 And character <= 102) Then Return False
		Next
		Return True
	End Function

	Function IsSafeRelativePath:Int(path:String)
		Local normalized:String = path.Replace("\", "/")
		If Not normalized.length Or normalized.StartsWith("/") Or normalized.Contains(":") Then Return False
		For Local component:String = EachIn normalized.Split("/")
			If Not component.length Or component = "." Or component = ".." Then Return False
		Next
		Return True
	End Function

	Function Resolve:String(rootPath:String, relativePath:String)
		If Not IsSafeRelativePath(relativePath) Then Throw "BMKGEN011 refusing to resolve unsafe compiler build path"
		Return rootPath.Replace("\", "/") + "/" + relativePath
	End Function

	Function Digest:String(content:String)
		Local bytes:Byte[] = New Byte[content.length]
		For Local index:Int = 0 Until content.length
			bytes[index] = Byte(content[index])
		Next
		Return DigestBytes(bytes)
	End Function

	Function FileDigest:String(path:String)
		Local stream:TStream = ReadFile(path)
		If Not stream Then Throw "BMKGEN020 declared compiler output is missing: " + path
		Local size:Long = stream.Size()
		If size < 0 Or size > $7fffffff Then
			stream.Close()
			Throw "BMKGEN025 declared compiler output cannot be hashed: " + path
		End If
		Local bytes:Byte[] = New Byte[Int(size)]
		Local offset:Int
		While offset < bytes.length
			Local count:Int = stream.Read(Byte Ptr(bytes) + offset, bytes.length - offset)
			If count <= 0 Then
				stream.Close()
				Throw "BMKGEN025 declared compiler output cannot be hashed: " + path
			End If
			offset :+ count
		Wend
		stream.Close()
		Return DigestBytes(bytes)
	End Function

	Function DigestBytes:String(bytes:Byte[])
		Local digest:TSHA256 = New TSHA256
		If bytes.length Then digest.Update(bytes, bytes.length)
		Local result:Byte[] = New Byte[digest.OutBytes()]
		digest.Finish(result)
		Local hex:String = "0123456789abcdef"
		Local output:String
		For Local value:Byte = EachIn result
			output :+ Chr(hex[(Int(value) Shr 4) & 15]) + Chr(hex[Int(value) & 15])
		Next
		Return output
	End Function
End Type
