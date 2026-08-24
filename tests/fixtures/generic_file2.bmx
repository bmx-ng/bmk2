Global buildList2:TBuildList<String> = New TBuildList<String>
Global buildOrdinaryHolder2:TBuildOrdinaryHolder = New TBuildOrdinaryHolder
buildOrdinaryHolder2.SetList(buildList2)
Global buildStringList2:TBuildStringList = New TBuildStringList
buildStringList2.value = "derived two"
buildStringList2.suffix = "?"
Global buildOrdinaryStringValue2:TBuildOrdinaryStringValue = New TBuildOrdinaryStringValue
buildOrdinaryStringValue2.value = "ordinary interface two"
Global buildBox2:TBuildBox<String>
Global buildOuter2:TBuildOuter<String>
Global buildConstructed2:TBuildConstructed<String> = New TBuildConstructed<String>("constructed two")
Global buildConstructedFactory2:TBuildConstructedFactory<String> = New TBuildConstructedFactory<String>
Global buildConstructedFromFactory2:TBuildConstructed<String> = buildConstructedFactory2.Create("factory Struct two", 32)
Global buildConstructedType2:TBuildConstructedType<String> = New TBuildConstructedType<String>("constructed Type two")
Global buildConstructedTypeFactory2:TBuildConstructedTypeFactory<String> = New TBuildConstructedTypeFactory<String>
Global buildConstructedTypeFromFactory2:TBuildConstructedType<String> = buildConstructedTypeFactory2.Create("factory Type two", 22)
Global buildOrdinaryConstructionFactory2:TBuildOrdinaryConstructionFactory<String> = New TBuildOrdinaryConstructionFactory<String>
Global buildOrdinaryConstructed2:TStringBuilder = buildOrdinaryConstructionFactory2.Create("ordinary construction two")
Global buildReferenceBox2:TBuildReferenceBox<TStringBuilder> = New TBuildReferenceBox<TStringBuilder>
buildReferenceBox2.value = buildOrdinaryConstructed2
Global buildKeptReference2:TStringBuilder = BuildKeepReference<TStringBuilder>(buildOrdinaryConstructed2)
Global buildIdentity2:String = BuildIdentity<String>("identity two")
Global buildOverload2:String = BuildOverload<String>("ignored", "overload two")
Global buildMethodBox2:TBuildMethodBox<String> = New TBuildMethodBox<String>
buildMethodBox2.value = "method two"
Global buildMethodValue2:String
buildMethodValue2 = buildMethodBox2.Select<Int>(2)
Global buildForward2:String = BuildForward<String>("forward two")
Global buildTransform2:Int = BuildTransform<Int>(3, 5)
Global buildViaPlain2:Int = BuildViaPlain<String>(42)
Global buildAccumulate2:Int = BuildAccumulate<Int>(19, 23)
Global buildCompound2:Int = BuildCompound<Int>(4)
Global buildArrayRoundTrip2:Int = BuildArrayRoundTrip<Int>(42)
Global buildArraySlice2:Int = BuildArraySlice<Int>(42)
Global buildStatement2:Int = BuildStatement<Int>(42)
Global buildThrow2:Int = BuildThrow<Int>(42, New TList, False)
Global buildInitialized2:TBuildInitialized<String> = New TBuildInitialized<String>
Global buildIndexBox2:TBuildIndexBox<String> = New TBuildIndexBox<String>
Global buildIndexWrite2:String = BuildIndexWrite<String>(buildIndexBox2, "index two")
Global buildIndexRead2:String = BuildIndexRead<String>(buildIndexBox2)
Global buildChoose2:Int = BuildChoose<Int>(42, 1, -1)
Global buildLoop2:Int = BuildLoop<Int>(6, 6)
Global buildRepeat2:Int = BuildRepeat<Int>(6, 6)
Global buildFor2:Int = BuildFor<Int>(6, 6)
Global buildControl2:Int = BuildControl<Int>(10, 10)
Global buildForExisting2:Int = BuildForExisting<Int>(6, 6)
Global buildEachInString2:Int = BuildEachInString<Int>(42, "C D!")
Global buildEachInArray2:Int = BuildEachInArray<Int>(0, [42])
Global StaticArray buildFixedValues2:Int[2]
buildFixedValues2[0] = 42
Global buildEachInStatic2:Int = BuildEachInStatic<Int>(42, buildFixedValues2)
Global buildIterator2:TBuildIterator<Int> = New TBuildIterator<Int>
buildIterator2.value = 42
buildIterator2.remaining = 1
Global buildIteratorView2:IIterator<Int> = buildIterator2
Global buildEachInIterator2:Int
buildEachInIterator2 = BuildEachInIterator<Int>(42, buildIteratorView2)
buildIterator2.remaining = 1
Global buildValues2:TBuildValues<Int> = New TBuildValues<Int>
buildValues2.iterator = buildIterator2
Global buildIterableView2:IIterable<Int> = buildValues2
Global buildEachInIterable2:Int
buildEachInIterable2 = BuildEachInIterable<Int>(42, buildIterableView2)
Global buildLegacyIterator2:TBuildLegacyIterator<Int> = New TBuildLegacyIterator<Int>
buildLegacyIterator2.remaining = 1
Global buildLegacyValues2:TBuildLegacyValues<Int> = New TBuildLegacyValues<Int>
buildLegacyValues2.iterator = buildLegacyIterator2
Global buildEachInLegacy2:Int
buildEachInLegacy2 = BuildEachInLegacy<Int>(42, buildLegacyValues2)
Global buildInheritedLegacyIterator2:TBuildInheritedLegacyIterator<Int> = New TBuildInheritedLegacyIterator<Int>
Global buildInheritedLegacyValues2:TBuildInheritedLegacyValues<Int> = New TBuildInheritedLegacyValues<Int>
buildInheritedLegacyValues2.iterator = buildInheritedLegacyIterator2
Global buildEachInInheritedLegacy2:Int
buildEachInInheritedLegacy2 = BuildEachInInheritedLegacy<Int>(42, buildInheritedLegacyValues2)
buildLegacyIterator2.value = buildLegacyIterator2
buildLegacyIterator2.remaining = 1
Global buildEachInLegacyType2:Int
buildEachInLegacyType2 = BuildEachInLegacyType<Int>(41, buildLegacyValues2)
buildLegacyIterator2.remaining = 1
Global buildEachInLegacyInterface2:Int
buildEachInLegacyInterface2 = BuildEachInLegacyInterface<Int>(41, buildLegacyValues2)
buildLegacyIterator2.value = New TList
buildLegacyIterator2.remaining = 1
Global buildEachInLegacyOrdinaryType2:Int
buildEachInLegacyOrdinaryType2 = BuildEachInLegacyOrdinaryType<Int>(41, buildLegacyValues2)
buildLegacyIterator2.value = New TList
buildLegacyIterator2.remaining = 1
Global buildEachInLegacyOrdinaryInterface2:Int
buildEachInLegacyOrdinaryInterface2 = BuildEachInLegacyOrdinaryInterface<Int>(41, buildLegacyValues2)
Global buildOrdinaryReceiverValues2:TList = New TList
buildOrdinaryReceiverValues2.AddLast("ordinary receiver two")
Global buildEachInLegacyOrdinaryReceivers2:Int
buildEachInLegacyOrdinaryReceivers2 = BuildEachInLegacyOrdinaryReceivers<Int>(41, buildOrdinaryReceiverValues2)
Global buildTransformObject2:TBuildTransform<String> = New TBuildTransform<String>
Global buildTransformView2:IBuildTransform<String> = buildTransformObject2
Global buildInterfaceCall2:String = BuildInterfaceCall<String>(buildTransformView2, "interface call two")
Global buildChildTransformObject2:TBuildChildTransform<String> = New TBuildChildTransform<String>
Global buildChildTransformView2:IBuildChildTransform<String> = buildChildTransformObject2
Global buildInheritedInterfaceCall2:String = BuildInheritedInterfaceCall<String>(buildChildTransformView2, "inherited interface call two")
Global buildFlowTransform2:TBuildFlowTransform<String> = New TBuildFlowTransform<String>
Global buildFlowTransformView2:IBuildFlowTransform<String> = buildFlowTransform2
Global buildFlowForwarder2:TBuildFlowForwarder<String> = New TBuildFlowForwarder<String>
buildFlowForwarder2.transform = buildFlowTransformView2
Global buildFlowForwarded2:String
Global buildFlowProvider2:TBuildFlowProvider<String> = New TBuildFlowProvider<String>
buildFlowProvider2.transform = buildFlowTransformView2
Global buildFlowProviderView2:IBuildFlowProvider<String> = buildFlowProvider2
Global buildReturnedInterfaceCall2:String
buildFlowForwarded2 = buildFlowForwarder2.Invoke("field local two")
buildReturnedInterfaceCall2 = BuildReturnedInterfaceCall<String>(buildFlowProviderView2, "returned interface two")
