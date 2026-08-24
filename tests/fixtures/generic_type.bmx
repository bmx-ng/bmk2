Import BRL.StringBuilder

Type TBuildReferenceBox<T> Where T Extends TStringBuilder
	Field value:T

	Method Read:T()
		Return value
	End Method
End Type

Function BuildKeepReference<T>:T(value:T) Where T Extends TStringBuilder
	Return value
End Function

Function BuildIdentity<T>:T(value:T)
	Return value
End Function

Function BuildOverload<T>:T(value:T)
	Return value
End Function

Function BuildOverload<T>:T(value:T, fallback:T)
	Return fallback
End Function

Type TBuildMethodBox<T>
	Field value:T

	Method Select<U>:T(input:U)
		Return value
	End Method
End Type

Function BuildForward<T>:T(value:T)
	Return BuildIdentity(value)
End Function

Function BuildTransform<T>:T(left:T, right:T)
	Return -(left + right * right)
End Function

Function BuildOffset:Int(value:Int) { nomangle }
	Return value + 1
End Function

Function BuildViaPlain<T>:Int(value:Int)
	Return BuildOffset(value)
End Function

Function BuildAccumulate<T>:T(first:T, second:T)
	Local result:T = first
	result = result + second
	Return result
End Function

Function BuildCompound<T>:Int(value:Int)
	value :+ 5
	value :* 2
	value :- 4
	value :/ 2
	Return value
End Function

Function BuildArrayRoundTrip<T>:T(value:T)
	Local data:T[] = New T[2]
	data[0] = value
	Local count:Int = data.length
	Return data[count - 2]
End Function

Function BuildArraySlice<T>:T(value:T)
	Local data:T[] = New T[3]
	data[1] = value
	Local selected:T[] = data[1..]
	Return selected[0]
End Function

Function BuildObserve<T>(value:T)
End Function

Function BuildStatement<T>:T(value:T)
	BuildObserve<T>(value)
	Return value
End Function

Function BuildThrow<T>:T(value:T, failure:Object, enabled:Int)
	If enabled Then
		Throw failure
	End If
	Return value
End Function

Type TBuildInitialized<T>
	Field marker:T
	Field index:Int = -1

	Method Index:Int()
		Return index
	End Method
End Type

Type TBuildIndexBox<T>
	Field value:T

	Method Operator[]:T(index:Int)
		Return value
	End Method

	Method Operator[]=(index:Int, newValue:T)
		value = newValue
	End Method
End Type

Function BuildIndexRead<T>:T(box:TBuildIndexBox<T>)
	Return box[0]
End Function

Function BuildIndexWrite<T>:T(box:TBuildIndexBox<T>, value:T)
	box[0] = value
	Return value
End Function

Function BuildChoose<T>:T(value:T, fallback:T, enabled:Int)
	If enabled > 0 Then
		Return value
	Else If enabled < 0 Then
		Return fallback
	Else
		Return value
	End If
End Function

Function BuildLoop<T>:T(seed:T, count:Int)
	Local result:T = seed
	Local index:Int
	While index < count
		result = result + seed
		index = index + 1
	Wend
	Return result
End Function

Function BuildRepeat<T>:T(seed:T, count:Int)
	Local result:T = seed
	Local index:Int
	Repeat
		result = result + seed
		index = index + 1
	Until index = count
	Return result
End Function

Function BuildFor<T>:T(seed:T, count:Int)
	Local result:T = seed
	For Local index:Int = 0 Until count
		result = result + seed
	Next
	Return result
End Function

Function BuildControl<T>:T(seed:T, count:Int)
	Local result:T = seed
	Local index:Int
	While index < count
		index = index + 1
		If index = 2 Then Continue
		result = result + seed
		If index = 4 Then Exit
	Wend
	Return result
End Function

Function BuildForExisting<T>:T(seed:T, count:Int)
	Local result:T = seed
	Local index:Int
	For index = 0 Until count
		result = result + seed
	Next
	Return result
End Function

Function BuildEachInString<T>:T(value:T, text:String)
	For Local code:Int = EachIn text
		If code = 32 Then Continue
		If code = 33 Then Exit
	Next
	Return value
End Function

Function BuildEachInArray<T>:T(fallback:T, values:T[])
	For Local item:T = EachIn values
		Return item
	Next
	Return fallback
End Function

Function BuildEachInStatic<T>:T(value:T, StaticArray values:Int[2])
	For Local item:Short = EachIn values
		If item = 0 Then Continue
		Exit
	Next
	Return value
End Function

Interface IIterator<T>
	Method Current:T()
	Method MoveNext:Int()
End Interface

Interface IIterable<T>
	Method GetIterator:IIterator<T>()
End Interface

Type TBuildIterator<T> Implements IIterator<T>
	Field value:T
	Field remaining:Int

	Method Current:T()
		Return value
	End Method

	Method MoveNext:Int()
		If remaining Then
			remaining = 0
			Return True
		End If
		Return False
	End Method
End Type

Type TBuildValues<T> Implements IIterable<T>
	Field iterator:IIterator<T>

	Method GetIterator:IIterator<T>()
		Return iterator
	End Method
End Type

Function BuildEachInIterator<T>:T(fallback:T, iterator:IIterator<T>)
	For Local item:T = EachIn iterator
		Return item
	Next
	Return fallback
End Function

Function BuildEachInIterable<T>:T(fallback:T, values:IIterable<T>)
	For Local item:T = EachIn values
		Return item
	Next
	Return fallback
End Function

Interface IBuildLegacyItem<T>
End Interface

Type TBuildLegacyIterator<T> Implements IBuildLegacyItem<T>
	Field value:Object
	Field remaining:Int

	Method HasNext:Int()
		If remaining Then
			remaining = 0
			Return True
		End If
		Return False
	End Method

	Method NextObject:Object()
		Return value
	End Method
End Type

Type TBuildLegacyValues<T>
	Field iterator:TBuildLegacyIterator<T>

	Method ObjectEnumerator:TBuildLegacyIterator<T>()
		Return iterator
	End Method
End Type

Function BuildEachInLegacy<T>:T(value:T, values:TBuildLegacyValues<T>)
	For Local item:Object = EachIn values
	Next
	Return value
End Function

Type TBuildInheritedLegacyIteratorBase<T>
	Field value:Object

	Method HasNext:Int()
		Return True
	End Method

	Method NextObject:Object()
		Return value
	End Method
End Type

Type TBuildInheritedLegacyIterator<T> Extends TBuildInheritedLegacyIteratorBase<T>
	Method HasNext:Int() Override
		Return False
	End Method
End Type

Type TBuildInheritedLegacyValuesBase<T>
	Field iterator:TBuildInheritedLegacyIterator<T>

	Method ObjectEnumerator:TBuildInheritedLegacyIterator<T>()
		Return iterator
	End Method
End Type

Type TBuildInheritedLegacyValues<T> Extends TBuildInheritedLegacyValuesBase<T>
End Type

Function BuildEachInInheritedLegacy<T>:T(value:T, values:TBuildInheritedLegacyValues<T>)
	For Local item:Object = EachIn values
	Next
	Return value
End Function

Function BuildEachInLegacyType<T>:T(value:T, values:TBuildLegacyValues<T>)
	Local result:T = value
	For Local item:TBuildLegacyIterator<T> = EachIn values
		result = result + 1
	Next
	Return result
End Function

Function BuildEachInLegacyInterface<T>:T(value:T, values:TBuildLegacyValues<T>)
	Local result:T = value
	For Local item:IBuildLegacyItem<T> = EachIn values
		result = result + 1
	Next
	Return result
End Function

Function BuildEachInLegacyOrdinaryType<T>:T(value:T, values:TBuildLegacyValues<T>)
	Local result:T = value
	For Local item:TList = EachIn values
		result = result + 1
	Next
	Return result
End Function

Function BuildEachInLegacyOrdinaryInterface<T>:T(value:T, values:TBuildLegacyValues<T>)
	Local result:T = value
	For Local item:ICloseable = EachIn values
		result = result + 1
	Next
	Return result
End Function

Function BuildEachInLegacyOrdinaryReceivers<T>:T(value:T, values:TList)
	Local result:T = value
	For Local item:Object = EachIn values
		result = result + 1
	Next
	Return result
End Function

Type TBuildList<T>
	Field value:T

	Method First:T()
		Return value
	End Method
End Type

Type TBuildOrdinaryHolder
	Field list:TBuildList<String>

	Method GetList:TBuildList<String>()
		Return list
	End Method

	Method SetList(value:TBuildList<String>)
		list = value
	End Method
End Type

Type TBuildStringList Extends TBuildList<String>
	Field suffix:String

	Method First:String() Override
		Return value + suffix
	End Method
End Type

Type TBuildFactory<T>
	Method Create:TBuildList<T>()
		Return New TBuildList<T>
	End Method

	Method Read:T(list:TBuildList<T>)
		Return list.First()
	End Method
End Type

Type TBuildHolder<T>
	Field list:TBuildList<T>

	Method Get:TBuildList<T>()
		Return list
	End Method
End Type

Struct TBuildBox<T>
	Field value:T

	Method StructValue:T()
		Return value
	End Method
End Struct

Struct TBuildOuter<T>
	Field box:TBuildBox<T>
End Struct

Struct TBuildConstructed<T>
	Field box:TBuildBox<T>
	Field value:T
	Field count:Int

	Method New()
	End Method

	Method New(input:T)
		value = input
	End Method

	Method New(amount:Int)
		count = amount
	End Method

	Method New(input:T, amount:Int)
		New(input)
		count = amount
	End Method

	Method ConstructedValue:T()
		Return value
	End Method
End Struct

Type TBuildConstructedFactory<T>
	Method Create:TBuildConstructed<T>(input:T, amount:Int)
		Return New TBuildConstructed<T>(input, amount)
	End Method
End Type

Type TBuildBase<T>
	Field baseValue:T

	Method GetBase:T()
		Return baseValue
	End Method

	Method VirtualValue:T(value:T)
		Return value
	End Method

	Method InvokeVirtual:T(value:T)
		Return Self.VirtualValue(value)
	End Method
End Type

Type TBuildDerived<T> Extends TBuildBase<T>
	Field derivedValue:T

	Method GetBase:T() Override
		Return Super.GetBase()
	End Method

	Method VirtualValue:T(value:T) Override
		Return derivedValue
	End Method

	Method GetDerived:T()
		Return derivedValue
	End Method
End Type

Type TBuildConstructedType<T>
	Field value:T
	Field count:Int

	Method New()
		count = 1
	End Method

	Method New(input:T)
		value = input
	End Method

	Method New(amount:Int)
		count = amount
	End Method

	Method New(input:T, amount:Int)
		New(input)
		count = amount
	End Method

	Method Read:T()
		Return value
	End Method
End Type

Type TBuildConstructedTypeFactory<T>
	Method Create:TBuildConstructedType<T>(input:T, amount:Int)
		Return New TBuildConstructedType<T>(input, amount)
	End Method
End Type

Type TBuildOrdinaryConstructionFactory<T>
	Method Create:TStringBuilder(input:String)
		Return New TStringBuilder(input)
	End Method
End Type

Interface IBuildValue<T>
	Method Read:T()
End Interface

Type TBuildValue<T> Implements IBuildValue<T>
	Field interfaceValue:T

	Method Read:T()
		Return interfaceValue
	End Method
End Type

Interface IBuildLeft<T> Extends IBuildValue<T>
	Method Left:T()
End Interface

Interface IBuildRight<T> Extends IBuildValue<T>
	Method Right:T()
End Interface

Interface IBuildDiamond<T> Extends IBuildLeft<T>, IBuildRight<T>
	Method Diamond:T()
End Interface

Interface IBuildExtra<T>
	Method Extra:T()
End Interface

Type TBuildMultiValue<T> Implements IBuildDiamond<T>, IBuildExtra<T>
	Field value:T

	Method Read:T()
		Return value
	End Method

	Method Left:T()
		Return value
	End Method

	Method Right:T()
		Return value
	End Method

	Method Diamond:T()
		Return value
	End Method

	Method Extra:T()
		Return value
	End Method
End Type

Type TBuildOrdinaryStringValue Implements IBuildLeft<String>
	Field value:String

	Method Read:String()
		Return value
	End Method

	Method Left:String()
		Return value
	End Method
End Type

Interface IBuildTransform<T>
	Method Apply:T(value:T)
End Interface

Type TBuildTransform<T> Implements IBuildTransform<T>
	Method Apply:T(value:T)
		Return value
	End Method
End Type

Function BuildInterfaceCall<T>:T(transform:IBuildTransform<T>, value:T)
	Return transform.Apply(value)
End Function

Interface IBuildRootTransform<T>
	Method Apply:T(value:T)
End Interface

Interface IBuildChildTransform<T> Extends IBuildRootTransform<T>
	Method Extra:T(value:T)
End Interface

Type TBuildChildTransform<T> Implements IBuildChildTransform<T>
	Method Apply:T(value:T)
		Return value
	End Method

	Method Extra:T(value:T)
		Return value
	End Method
End Type

Function BuildInheritedInterfaceCall<T>:T(transform:IBuildChildTransform<T>, value:T)
	Return transform.Apply(value)
End Function

Interface IBuildFlowTransform<T>
	Method Apply:T(value:T)
End Interface

Type TBuildFlowTransform<T> Implements IBuildFlowTransform<T>
	Method Apply:T(value:T)
		Return value
	End Method
End Type

Type TBuildFlowForwarder<T>
	Field transform:IBuildFlowTransform<T>

	Method Invoke:T(value:T)
		Local current:IBuildFlowTransform<T> = transform
		Return current.Apply(value)
	End Method
End Type

Interface IBuildFlowProvider<T>
	Method Current:IBuildFlowTransform<T>()
End Interface

Type TBuildFlowProvider<T> Implements IBuildFlowProvider<T>
	Field transform:IBuildFlowTransform<T>

	Method Current:IBuildFlowTransform<T>()
		Return transform
	End Method
End Type

Function BuildReturnedInterfaceCall<T>:T(provider:IBuildFlowProvider<T>, value:T)
	Return provider.Current().Apply(value)
End Function

Type TBuildDirectBase
	Field baseValue:Int

	Method Pick<U>:Int(value:U)
		Return baseValue
	End Method
End Type

Type TBuildDirectDerived Extends TBuildDirectBase
	Field derivedValue:Int

	Method Pick<U>:Int(value:U) Override
		Return Super.Pick(value) + derivedValue
	End Method

	Method Forward<U>:Int(value:U)
		Return Self.Pick(value)
	End Method
End Type

Struct SBuildDirect
	Field value:Int

	Method Read<U>:Int(fallback:U)
		Return value
	End Method
End Struct
