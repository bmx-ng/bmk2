Global buildList1:TBuildList<String> = New TBuildList<String>
Global buildOrdinaryHolder1:TBuildOrdinaryHolder = New TBuildOrdinaryHolder
buildOrdinaryHolder1.SetList(buildList1)
Global buildStringList1:TBuildStringList = New TBuildStringList
buildStringList1.value = "derived one"
buildStringList1.suffix = "!"
Global buildOrdinaryStringValue1:TBuildOrdinaryStringValue = New TBuildOrdinaryStringValue
buildOrdinaryStringValue1.value = "ordinary interface one"
Global buildBox1:TBuildBox<String>
Global buildOuter1:TBuildOuter<String>
Global buildConstructed1:TBuildConstructed<String> = New TBuildConstructed<String>("constructed one")
Global buildConstructedFactory1:TBuildConstructedFactory<String> = New TBuildConstructedFactory<String>
Global buildConstructedFromFactory1:TBuildConstructed<String> = buildConstructedFactory1.Create("factory Struct one", 31)
Global buildConstructedType1:TBuildConstructedType<String> = New TBuildConstructedType<String>("constructed Type one")
Global buildConstructedTypeFactory1:TBuildConstructedTypeFactory<String> = New TBuildConstructedTypeFactory<String>
Global buildConstructedTypeFromFactory1:TBuildConstructedType<String> = buildConstructedTypeFactory1.Create("factory Type one", 21)
Global buildOrdinaryConstructionFactory1:TBuildOrdinaryConstructionFactory<String> = New TBuildOrdinaryConstructionFactory<String>
Global buildOrdinaryConstructed1:TStringBuilder = buildOrdinaryConstructionFactory1.Create("ordinary construction one")
Global buildReferenceBox1:TBuildReferenceBox<TStringBuilder> = New TBuildReferenceBox<TStringBuilder>
buildReferenceBox1.value = buildOrdinaryConstructed1
Global buildKeptReference1:TStringBuilder = BuildKeepReference<TStringBuilder>(buildOrdinaryConstructed1)
Global buildIdentity1:String = BuildIdentity("identity one")
Global buildOverload1:String = BuildOverload("overload one")
Global buildMethodBox1:TBuildMethodBox<String> = New TBuildMethodBox<String>
buildMethodBox1.value = "method one"
Global buildMethodValue1:String
buildMethodValue1 = buildMethodBox1.Select(1)
Global buildForward1:String = BuildForward("forward one")
Global buildTransform1:Int = BuildTransform(2, 4)
Global buildViaPlain1:Int = BuildViaPlain<String>(41)
Global buildAccumulate1:Int = BuildAccumulate(20, 22)
Global buildCompound1:Int = BuildCompound<String>(3)
Global buildArrayRoundTrip1:String = BuildArrayRoundTrip<String>("array one")
Global buildArraySlice1:String = BuildArraySlice<String>("slice one")
Global buildStatement1:String = BuildStatement<String>("statement one")
Global buildThrow1:String = BuildThrow<String>("throw one", New TList, False)
Global buildInitialized1:TBuildInitialized<String> = New TBuildInitialized<String>
Global buildIndexBox1:TBuildIndexBox<String> = New TBuildIndexBox<String>
Global buildIndexWrite1:String = BuildIndexWrite<String>(buildIndexBox1, "index one")
Global buildIndexRead1:String = BuildIndexRead<String>(buildIndexBox1)
Global buildChoose1:Int = BuildChoose(42, 1, True)
Global buildLoop1:Int = BuildLoop(7, 5)
Global buildRepeat1:Int = BuildRepeat(7, 5)
Global buildFor1:Int = BuildFor(7, 5)
Global buildControl1:Int = BuildControl(10, 10)
Global buildForExisting1:Int = BuildForExisting(7, 5)
Global buildEachInString1:Int = BuildEachInString(42, "A B!")
Global buildEachInArray1:Int = BuildEachInArray(0, [42])
Global StaticArray buildFixedValues1:Int[2]
buildFixedValues1[0] = 42
Global buildEachInStatic1:Int = BuildEachInStatic(42, buildFixedValues1)
Global buildIterator1:TBuildIterator<Int> = New TBuildIterator<Int>
buildIterator1.value = 42
buildIterator1.remaining = 1
Global buildIteratorView1:IIterator<Int> = buildIterator1
Global buildEachInIterator1:Int
buildEachInIterator1 = BuildEachInIterator(42, buildIteratorView1)
buildIterator1.remaining = 1
Global buildValues1:TBuildValues<Int> = New TBuildValues<Int>
buildValues1.iterator = buildIterator1
Global buildIterableView1:IIterable<Int> = buildValues1
Global buildEachInIterable1:Int
buildEachInIterable1 = BuildEachInIterable(42, buildIterableView1)
Global buildLegacyIterator1:TBuildLegacyIterator<Int> = New TBuildLegacyIterator<Int>
buildLegacyIterator1.remaining = 1
Global buildLegacyValues1:TBuildLegacyValues<Int> = New TBuildLegacyValues<Int>
buildLegacyValues1.iterator = buildLegacyIterator1
Global buildEachInLegacy1:Int
buildEachInLegacy1 = BuildEachInLegacy(42, buildLegacyValues1)
Global buildInheritedLegacyIterator1:TBuildInheritedLegacyIterator<Int> = New TBuildInheritedLegacyIterator<Int>
Global buildInheritedLegacyValues1:TBuildInheritedLegacyValues<Int> = New TBuildInheritedLegacyValues<Int>
buildInheritedLegacyValues1.iterator = buildInheritedLegacyIterator1
Global buildEachInInheritedLegacy1:Int
buildEachInInheritedLegacy1 = BuildEachInInheritedLegacy(42, buildInheritedLegacyValues1)
buildLegacyIterator1.value = buildLegacyIterator1
buildLegacyIterator1.remaining = 1
Global buildEachInLegacyType1:Int
buildEachInLegacyType1 = BuildEachInLegacyType(41, buildLegacyValues1)
buildLegacyIterator1.remaining = 1
Global buildEachInLegacyInterface1:Int
buildEachInLegacyInterface1 = BuildEachInLegacyInterface(41, buildLegacyValues1)
buildLegacyIterator1.value = New TList
buildLegacyIterator1.remaining = 1
Global buildEachInLegacyOrdinaryType1:Int
buildEachInLegacyOrdinaryType1 = BuildEachInLegacyOrdinaryType(41, buildLegacyValues1)
buildLegacyIterator1.value = New TList
buildLegacyIterator1.remaining = 1
Global buildEachInLegacyOrdinaryInterface1:Int
buildEachInLegacyOrdinaryInterface1 = BuildEachInLegacyOrdinaryInterface(41, buildLegacyValues1)
Global buildOrdinaryReceiverValues1:TList = New TList
buildOrdinaryReceiverValues1.AddLast("ordinary receiver one")
Global buildEachInLegacyOrdinaryReceivers1:Int
buildEachInLegacyOrdinaryReceivers1 = BuildEachInLegacyOrdinaryReceivers(41, buildOrdinaryReceiverValues1)
Global buildTransformObject1:TBuildTransform<String> = New TBuildTransform<String>
Global buildTransformView1:IBuildTransform<String> = buildTransformObject1
Global buildInterfaceCall1:String = BuildInterfaceCall<String>(buildTransformView1, "interface call one")
Global buildChildTransformObject1:TBuildChildTransform<String> = New TBuildChildTransform<String>
Global buildChildTransformView1:IBuildChildTransform<String> = buildChildTransformObject1
Global buildInheritedInterfaceCall1:String = BuildInheritedInterfaceCall<String>(buildChildTransformView1, "inherited interface call one")
Global buildFlowTransform1:TBuildFlowTransform<String> = New TBuildFlowTransform<String>
Global buildFlowTransformView1:IBuildFlowTransform<String> = buildFlowTransform1
Global buildFlowForwarder1:TBuildFlowForwarder<String> = New TBuildFlowForwarder<String>
buildFlowForwarder1.transform = buildFlowTransformView1
Global buildFlowForwarded1:String
Global buildFlowProvider1:TBuildFlowProvider<String> = New TBuildFlowProvider<String>
buildFlowProvider1.transform = buildFlowTransformView1
Global buildFlowProviderView1:IBuildFlowProvider<String> = buildFlowProvider1
Global buildReturnedInterfaceCall1:String
buildFlowForwarded1 = buildFlowForwarder1.Invoke("field local one")
buildReturnedInterfaceCall1 = BuildReturnedInterfaceCall<String>(buildFlowProviderView1, "returned interface one")
