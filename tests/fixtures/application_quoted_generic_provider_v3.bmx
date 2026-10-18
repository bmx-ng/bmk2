SuperStrict

Function QuotedTransform<T>:T(value:T, transform:Closure<T(value:T)>)
	Return transform(transform(value))
End Function

Function QuotedUnused<T>:T(value:T)
	Return value
End Function
