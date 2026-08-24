SuperStrict

Function NormalizeBcc2EngineProtocolLine:String(line:String)
	' TStream.ReadLine removes LF, but retains the preceding CR from a Windows
	' CRLF line ending. Protocol whitespace is otherwise significant.
	If line.EndsWith("~r") Then Return line[..line.length - 1]
	Return line
End Function
