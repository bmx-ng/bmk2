SuperStrict

Function MacOSPreferredSigningValue:String(environmentValue:String, localValue:String, applicationValue:String, customValue:String)
	environmentValue = environmentValue.Trim()
	If environmentValue.length Then Return environmentValue

	localValue = localValue.Trim()
	If localValue.length Then Return localValue

	applicationValue = applicationValue.Trim()
	If applicationValue.length Then Return applicationValue

	Return customValue.Trim()
End Function
