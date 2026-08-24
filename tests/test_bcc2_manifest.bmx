SuperStrict

Framework BRL.StandardIO

Include "../bmk_bcc2_manifest.bmx"

Function Check(condition:Int, message:String)
	If Not condition Then Throw message
End Function

Function Enc:String(value:String)
	Return TBase64.Encode(value, EBase64Options.DontBreakLines)
End Function

Local sourcePath:String = ".generics/identity.c"
Local objectPath:String = ".generics/objects/cache.o"
Local content:String = "generated specialization"
Local digest:String = TBcc2BuildManifestCodec.Digest(content)
Check(TBcc2BuildManifestCodec.Digest("BOM=" + Chr(239) + Chr(187) + Chr(191)) = "a8b67a10948cef33f0332f258104ae7c271ab921cf8230404484295018b05760", "manifest digests hash the LATIN1 bytes materialized by SaveText")
Local utf8FixturePath:String = "fixtures/manifest_utf8.txt"
If AppArgs.length > 1 Then utf8FixturePath = AppArgs[1]
Check(TBcc2BuildManifestCodec.FileDigest(utf8FixturePath) = "d4e63bc7f243d3cb9aeab0ccd7a83ea9d13cbdfadb4896d60fb8b15d5e142a62", "generated-file validation hashes exact non-ASCII bytes")
Local cacheKey:String = "1111111111111111111111111111111111111111111111111111111111111111"
Local identity:String = "2222222222222222222222222222222222222222222222222222222222222222"
Local manifestText:String = "BMXBUILD 1~n"
manifestText :+ "file application-c " + digest + " - - " + Enc("application.c") + "~n"
manifestText :+ "file runtime-header " + digest + " - - " + Enc("application.h") + "~n"
manifestText :+ "file generic-specialization-c " + digest + " " + cacheKey + " " + Enc(identity) + " " + Enc(sourcePath) + "~n"
manifestText :+ "link " + cacheKey + " " + identity + " " + Enc(sourcePath) + " " + Enc(objectPath) + "~n"

Local manifest:TBcc2BuildManifest = TBcc2BuildManifestCodec.Decode(manifestText)
Check(manifest.files.length = 3 And manifest.FileForPath("application.h").role = "runtime-header" And manifest.links.length = 1, "manifest records and runtime headers decode")
Check(manifest.links[0].sourcePath = sourcePath And manifest.links[0].objectPath = objectPath, "manifest paths round-trip")
Local rejected:Int
Try
	TBcc2BuildManifestCodec.Decode(manifestText.Replace("BMXBUILD 1", "BMXBUILD 99"))
Catch exception:Object
	rejected = String(exception).StartsWith("BMKGEN001")
End Try
Check(rejected, "unknown versions are rejected")

rejected = False
Try
	TBcc2BuildManifestCodec.Decode(manifestText.Replace(Enc("application.c"), Enc("../escape.c")))
Catch exception:Object
	rejected = String(exception).StartsWith("BMKGEN003")
End Try
Check(rejected, "path traversal is rejected")

rejected = False
Try
	TBcc2BuildManifestCodec.Decode(manifestText.Replace(cacheKey + " " + identity + " " + Enc(sourcePath), cacheKey + " " + identity + " " + Enc(".generics/other.c")))
Catch exception:Object
	rejected = String(exception).StartsWith("BMKGEN022")
End Try
Check(rejected, "link records must name declared specialization sources")

Local cacheManifestPath:String = AppDir + "/bmk-bcc2-manifest-cache-" + MilliSecs() + ".bmxbuild"
Check(SaveText(manifestText, cacheManifestPath), "cache fixture can be written")
Local cachedManifest:TBcc2BuildManifest = TBcc2BuildManifestCodec.Load(cacheManifestPath)
Check(TBcc2BuildManifestCodec.Load(cacheManifestPath) = cachedManifest, "unchanged manifests reuse their validated decode")
TBcc2BuildManifestCodec.Invalidate(cacheManifestPath)
Check(TBcc2BuildManifestCodec.Load(cacheManifestPath) <> cachedManifest, "explicit invalidation reloads a republished manifest")
DeleteFile(cacheManifestPath)

Local generatedName:String = "bmk-bcc2-validation-cache-" + MilliSecs() + ".c"
Local generatedPath:String = AppDir + "/" + generatedName
Local generatedContent:String = "cached generated output"
Check(SaveText(generatedContent, generatedPath), "generated validation-cache fixture can be written")
Local generatedManifestText:String = "BMXBUILD 1~nfile application-c " + TBcc2BuildManifestCodec.Digest(generatedContent) + " - - " + Enc(generatedName) + "~n"
Local generatedManifest:TBcc2BuildManifest = TBcc2BuildManifestCodec.Decode(generatedManifestText)
Local validatedFiles:TMap = New TMap
Local validationStats:TBcc2BuildValidationStats = New TBcc2BuildValidationStats
generatedManifest.ValidateGeneratedFiles(AppDir, validatedFiles, validationStats)
generatedManifest.ValidateGeneratedFiles(AppDir, validatedFiles, validationStats)
Check(validationStats.declarations = 2 And validationStats.hashedFiles = 1 And validationStats.reusedFiles = 1, "generated-file validation reuses an unchanged digest within one build")
Check(SaveText(generatedContent + " changed", generatedPath), "generated validation-cache fixture can be changed")
rejected = False
Try
	generatedManifest.ValidateGeneratedFiles(AppDir, validatedFiles, validationStats)
Catch exception:Object
	rejected = String(exception).StartsWith("BMKGEN021")
End Try
Check(rejected And validationStats.hashedFiles = 2, "generated-file validation rehashes changed metadata and still rejects digest mismatches")
DeleteFile(generatedPath)

Print "bmk bcc2 build-manifest tests passed"
