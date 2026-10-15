SuperStrict

Import BRL.Map

Function AndroidApplicationId:String(projectSettings:TMap)
	Local applicationId:String = String(projectSettings.ValueForKey("android.application.id")).Trim()
	If Not applicationId Then applicationId = String(projectSettings.ValueForKey("app.package")).Trim()
	If Not applicationId Then Throw "Android application identifier is empty"
	Return applicationId
End Function

Function AndroidPreferredSigningValue:String(environmentValue:String, applicationValue:String, customValue:String)
	environmentValue = environmentValue.Trim()
	If environmentValue.length Then Return environmentValue

	applicationValue = applicationValue.Trim()
	If applicationValue.length Then Return applicationValue

	Return customValue.Trim()
End Function
