SuperStrict

Function AndroidPreferredSigningValue:String(environmentValue:String, applicationValue:String, customValue:String)
	environmentValue = environmentValue.Trim()
	If environmentValue.length Then Return environmentValue

	applicationValue = applicationValue.Trim()
	If applicationValue.length Then Return applicationValue

	Return customValue.Trim()
End Function
