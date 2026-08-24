SuperStrict

Import BRL.Base64
Import Pub.FreeProcess
Import "bmk_bcc2_protocol.bmx"
Import "stringbuffer_core.bmx"

Const BMK_BCC2_ENGINE_PROTOCOL_VERSION:Int = 2

Type TBcc2EngineResponse
	Field exitCode:Int
	Field output:String
End Type

Type TBcc2EngineClient
	Field process:TProcess
	Field nextRequestId:Int = 1
	Field executable:String

	Method Start(path:String)
		If process Then Return
		executable = path
		process = CreateProcess(QuoteExecutable(path) + " --engine", HIDECONSOLE)
		If Not process Then Throw "BMKGEN043 unable to start bcc engine: " + path
		Local handshake:String = ReadProtocolLine()
		Local expected:String = "bcc2-engine " + BMK_BCC2_ENGINE_PROTOCOL_VERSION
		If handshake <> expected Then
			Local detail:String = ReadErrors()
			Stop()
			Throw "BMKGEN044 incompatible bcc engine handshake: expected '" + expected + "', received '" + handshake + "'" + detail
		End If
	End Method

	Method Compile:TBcc2EngineResponse(arguments:String[])
		If Not process Then Throw "BMKGEN045 bcc engine is not running"
		Local requestId:String = String(nextRequestId)
		nextRequestId :+ 1
		Local request:TStringBuffer = New TStringBuffer
		request.Append("compile ").Append(requestId).Append(" ").Append(String(arguments.length))
		For Local argument:String = EachIn arguments
			request.Append(" ").Append(TBase64.Encode(argument, EBase64Options.DontBreakLines))
		Next
		process.pipe.WriteLine(request.ToString())
		process.pipe.Flush()

		Local header:String[] = ReadProtocolLine().Split(" ")
		If header.length <> 4 Or header[0] <> "result" Or header[1] <> requestId Then
			Throw "BMKGEN046 malformed bcc2 engine result header"
		End If
		Local expectedLength:Int = Int(header[3])
		If expectedLength < 0 Then Throw "BMKGEN046 malformed bcc2 engine result length"
		Local encoded:TStringBuffer = New TStringBuffer
		While True
			Local line:String = ReadProtocolLine()
			Local parts:String[] = line.Split(" ")
			If parts.length = 2 And parts[0] = "end" And parts[1] = requestId Then Exit
			If parts.length <> 3 Or parts[0] <> "data" Or parts[1] <> requestId Then
				Throw "BMKGEN046 malformed bcc2 engine result body"
			End If
			encoded.Append(parts[2])
		Wend
		Local encodedValue:String = encoded.ToString()
		If encodedValue.length <> expectedLength Then Throw "BMKGEN046 incomplete bcc2 engine result body"
		Local response:TBcc2EngineResponse = New TBcc2EngineResponse
		response.exitCode = Int(header[2])
		If encodedValue.length Then
			Local bytes:Byte[] = TBase64.Decode(encodedValue)
			response.output = String.FromUTF8Bytes(bytes, bytes.length)
		End If
		Return response
	End Method

	Method Invalidate(paths:String[])
		If Not process Then Throw "BMKGEN045 bcc2 engine is not running"
		If Not paths.length Then Return
		Local requestId:String = String(nextRequestId)
		nextRequestId :+ 1
		Local request:TStringBuffer = New TStringBuffer
		request.Append("invalidate ").Append(requestId).Append(" ").Append(String(paths.length))
		For Local path:String = EachIn paths
			request.Append(" ").Append(TBase64.Encode(path, EBase64Options.DontBreakLines))
		Next
		process.pipe.WriteLine(request.ToString())
		process.pipe.Flush()
		Local response:String[] = ReadProtocolLine().Split(" ")
		If response.length <> 3 Or response[0] <> "invalidated" Or response[1] <> requestId Or response[2] <> "1" Then
			Throw "BMKGEN048 bcc2 engine rejected cache invalidation"
		End If
	End Method

	Method Shutdown()
		If Not process Then Return
		If process.Status() Then
			process.pipe.WriteLine("shutdown")
			process.pipe.Flush()
			Local line:String
			While process.Status() And line <> "shutdown"
				line = NormalizeBcc2EngineProtocolLine(process.pipe.ReadLine())
				If Not line.length Then Delay 1
			Wend
		End If
		Stop()
	End Method

	Method Stop()
		If Not process Then Return
		If process.Status() Then process.Terminate()
		process.Close()
		process = Null
	End Method

	Method ReadProtocolLine:String()
		While process And process.Status()
			Local line:String = NormalizeBcc2EngineProtocolLine(process.pipe.ReadLine())
			If line.length Then Return line
			Delay 1
		Wend
		If process Then
			Local finalLine:String = NormalizeBcc2EngineProtocolLine(process.pipe.ReadLine())
			If finalLine.length Then Return finalLine
		End If
		Local detail:String = ReadErrors()
		Throw "BMKGEN047 bcc engine exited unexpectedly" + detail
	End Method

	Method ReadErrors:String()
		If Not process Or Not process.err Then Return ""
		Local result:TStringBuffer = New TStringBuffer
		While True
			Local line:String = NormalizeBcc2EngineProtocolLine(process.err.ReadLine())
			If Not line.length Then Exit
			result.Append("~n").Append(line)
		Wend
		Return result.ToString()
	End Method

	Function QuoteExecutable:String(path:String)
		Return "~q" + path.Replace("~q", "~~q") + "~q"
	End Function
End Type
