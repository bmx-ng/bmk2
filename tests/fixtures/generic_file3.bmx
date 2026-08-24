Local buildList:TBuildList<String> = buildList1
buildList.value = "one"
buildList2.value = "two"
Local ordinaryMemberList:TBuildList<String> = buildOrdinaryHolder1.GetList()
buildOrdinaryHolder2.SetList(ordinaryMemberList)
Local closedBaseView:TBuildList<String> = buildStringList1
Local ordinaryRootView:IBuildValue<String> = buildOrdinaryStringValue1
Local ordinaryLeftView:IBuildLeft<String> = buildOrdinaryStringValue2
Local holder:TBuildHolder<String> = New TBuildHolder<String>
holder.list = buildList
Local factory:TBuildFactory<String> = New TBuildFactory<String>
Local created:TBuildList<String> = factory.Create()
created.value = "created"

If buildIdentity1 <> "identity one" Or buildIdentity2 <> "identity two" Then RuntimeError "canonical generic routine used an incompatible ABI"
If buildOverload1 <> "overload one" Or buildOverload2 <> "overload two" Then RuntimeError "signature-qualified generic overload used an incompatible ABI"
If buildMethodValue1 <> "method one" Or buildMethodValue2 <> "method two" Then RuntimeError "canonical generic method used incompatible containing-Type or method substitutions"
If buildReferenceBox1.Read() <> buildOrdinaryConstructed1 Or buildReferenceBox2.Read() <> buildOrdinaryConstructed2 Then RuntimeError "constrained canonical generic Type used an incompatible named-reference ABI"
If buildKeptReference1 <> buildOrdinaryConstructed1 Or buildKeptReference2 <> buildOrdinaryConstructed2 Then RuntimeError "constrained canonical generic routine used an incompatible named-reference ABI"
If buildForward1 <> "forward one" Or buildForward2 <> "forward two" Then RuntimeError "transitive canonical generic routine used an incompatible ABI"
If buildTransform1 <> -18 Or buildTransform2 <> -28 Then RuntimeError "canonical generic scalar expression used an incompatible ABI"
If buildViaPlain1 <> 42 Or buildViaPlain2 <> 43 Then RuntimeError "canonical generic ordinary routine dependency used an incompatible ABI"
If buildAccumulate1 <> 42 Or buildAccumulate2 <> 42 Then RuntimeError "canonical generic sequential body used an incompatible ABI"
If buildCompound1 <> 6 Or buildCompound2 <> 7 Then RuntimeError "canonical generic compound assignment used an incompatible ABI"
If buildArrayRoundTrip1 <> "array one" Or buildArrayRoundTrip2 <> 42 Then RuntimeError "canonical generic managed Array used an incompatible ABI"
If buildArraySlice1 <> "slice one" Or buildArraySlice2 <> 42 Then RuntimeError "canonical generic managed Array slice used an incompatible ABI"
If buildStatement1 <> "statement one" Or buildStatement2 <> 42 Then RuntimeError "canonical generic expression statement used an incompatible ABI"
If buildThrow1 <> "throw one" Or buildThrow2 <> 42 Then RuntimeError "canonical generic Throw used an incompatible ABI"
If buildInitialized1.Index() <> -1 Or buildInitialized2.Index() <> -1 Then RuntimeError "canonical generic field initializer used an incompatible ABI"
If buildIndexRead1 <> "index one" Or buildIndexRead2 <> "index two" Then RuntimeError "canonical generic index operator used an incompatible ABI"
If buildChoose1 <> 42 Or buildChoose2 <> 1 Then RuntimeError "canonical generic branch body used an incompatible ABI"
If buildLoop1 <> 42 Or buildLoop2 <> 42 Then RuntimeError "canonical generic While body used an incompatible ABI"
If buildRepeat1 <> 42 Or buildRepeat2 <> 42 Then RuntimeError "canonical generic Repeat body used an incompatible ABI"
If buildFor1 <> 42 Or buildFor2 <> 42 Then RuntimeError "canonical generic range For body used an incompatible ABI"
If buildControl1 <> 40 Or buildControl2 <> 40 Then RuntimeError "canonical generic loop control used an incompatible ABI"
If buildForExisting1 <> 42 Or buildForExisting2 <> 42 Then RuntimeError "canonical generic existing-target range For used an incompatible ABI"
If buildEachInString1 <> 42 Or buildEachInString2 <> 42 Then RuntimeError "canonical generic String EachIn used an incompatible ABI"
If buildEachInArray1 <> 42 Or buildEachInArray2 <> 42 Then RuntimeError "canonical generic managed Array EachIn used an incompatible ABI"
If buildEachInStatic1 <> 42 Or buildEachInStatic2 <> 42 Then RuntimeError "canonical generic StaticArray EachIn used an incompatible ABI"
If buildEachInIterator1 <> 42 Or buildEachInIterator2 <> 42 Then RuntimeError "canonical direct generic IIterator EachIn used an incompatible ABI"
If buildEachInIterable1 <> 42 Or buildEachInIterable2 <> 42 Then RuntimeError "canonical generic IIterable EachIn used an incompatible ABI"
If buildEachInLegacy1 <> 42 Or buildEachInLegacy2 <> 42 Then RuntimeError "canonical generic ObjectEnumerator EachIn used an incompatible ABI"
If buildEachInInheritedLegacy1 <> 42 Or buildEachInInheritedLegacy2 <> 42 Then RuntimeError "inherited canonical generic ObjectEnumerator EachIn used an incompatible ABI"
If buildEachInLegacyType1 <> 42 Or buildEachInLegacyType2 <> 42 Then RuntimeError "canonical generic ObjectEnumerator Type cast used an incompatible ABI"
If buildEachInLegacyInterface1 <> 42 Or buildEachInLegacyInterface2 <> 42 Then RuntimeError "canonical generic ObjectEnumerator Interface cast used an incompatible ABI"
If buildEachInLegacyOrdinaryType1 <> 42 Or buildEachInLegacyOrdinaryType2 <> 42 Then RuntimeError "canonical generic ObjectEnumerator imported ordinary Type cast used an incompatible ABI"
If buildEachInLegacyOrdinaryInterface1 <> 41 Or buildEachInLegacyOrdinaryInterface2 <> 41 Then RuntimeError "canonical generic ObjectEnumerator imported ordinary Interface rejection used an incompatible ABI"
If buildEachInLegacyOrdinaryReceivers1 <> 42 Or buildEachInLegacyOrdinaryReceivers2 <> 42 Then RuntimeError "canonical generic imported ordinary ObjectEnumerator receivers used incompatible virtual slots"
If buildInterfaceCall1 <> "interface call one" Or buildInterfaceCall2 <> "interface call two" Then RuntimeError "generic Interface calls used an incompatible canonical slot"
If buildInheritedInterfaceCall1 <> "inherited interface call one" Or buildInheritedInterfaceCall2 <> "inherited interface call two" Then RuntimeError "inherited generic Interface calls used an incompatible root slot"
If buildFlowForwarded1 <> "field local one" Or buildFlowForwarded2 <> "field local two" Then RuntimeError "generic Interface fields or locals used an incompatible canonical slot"
If buildReturnedInterfaceCall1 <> "returned interface one" Or buildReturnedInterfaceCall2 <> "returned interface two" Then RuntimeError "generic Interface-valued call results used an incompatible canonical slot"
If buildList.First() <> "one" Then RuntimeError "canonical generic value did not cross file boundaries"
If buildList2.First() <> "two" Then RuntimeError "second canonical generic instance used an incompatible ABI"
If buildOrdinaryHolder1.GetList().First() <> "one" Or buildOrdinaryHolder2.GetList().First() <> "one" Then RuntimeError "ordinary Type members used an incompatible closed generic ABI"
If closedBaseView.First() <> "derived one!" Or buildStringList2.First() <> "derived two?" Then RuntimeError "ordinary Type inheritance used an incompatible closed generic base ABI"
If ordinaryRootView.Read() <> "ordinary interface one" Or ordinaryLeftView.Left() <> "ordinary interface two" Then RuntimeError "ordinary Type used an incompatible closed generic Interface table"
If holder.Get().First() <> "one" Then RuntimeError "transitive canonical specialization used an incompatible ABI"
If factory.Read(created) <> "created" Then RuntimeError "executable transitive generic body used an incompatible ABI"

buildBox1.value = "value"
buildBox2 = buildBox1
Local buildBox:TBuildBox<String> = buildBox2
If buildBox.StructValue() <> "value" Then RuntimeError "canonical generic Struct value used an incompatible ABI"

buildOuter1.box.value = "nested value"
buildOuter2 = buildOuter1
Local buildOuter:TBuildOuter<String> = buildOuter2
If buildOuter.box.StructValue() <> "nested value" Then RuntimeError "nested canonical generic Struct value used an incompatible ABI"

Local buildConstructed:TBuildConstructed<String> = buildConstructed1
If buildConstructed.ConstructedValue() <> "constructed one" Then RuntimeError "generic Struct constructor used an incompatible ABI"
If buildConstructed2.ConstructedValue() <> "constructed two" Then RuntimeError "second generic Struct constructor request was not canonical"
Local buildConstructedDefault:TBuildConstructed<String> = New TBuildConstructed<String>
If buildConstructedDefault.ConstructedValue() <> "" Then RuntimeError "zero-argument generic Struct constructor overload used an incompatible ABI"
Local buildConstructedCount:TBuildConstructed<String> = New TBuildConstructed<String>(7)
If buildConstructedCount.count <> 7 Then RuntimeError "same-arity generic Struct constructor selected an incompatible ABI"
Local buildConstructedDelegated:TBuildConstructed<String> = New TBuildConstructed<String>("delegated", 11)
If buildConstructedDelegated.ConstructedValue() <> "delegated" Or buildConstructedDelegated.count <> 11 Then RuntimeError "generic Struct constructor delegation used an incompatible ABI"
If buildConstructedFromFactory1.ConstructedValue() <> "factory Struct one" Or buildConstructedFromFactory1.count <> 31 Then RuntimeError "parameterized generic Struct construction inside a generic body used an incompatible ABI"
If buildConstructedFromFactory2.ConstructedValue() <> "factory Struct two" Or buildConstructedFromFactory2.count <> 32 Then RuntimeError "second generic-body Struct construction request was not canonical"
If buildConstructedType1.Read() <> "constructed Type one" Or buildConstructedType2.Read() <> "constructed Type two" Then RuntimeError "parameterized generic Type constructor used an incompatible canonical ABI"
Local buildConstructedTypeDefault:TBuildConstructedType<String> = New TBuildConstructedType<String>
If buildConstructedTypeDefault.count <> 1 Then RuntimeError "zero-argument generic Type constructor body used an incompatible ABI"
Local buildConstructedTypeCount:TBuildConstructedType<String> = New TBuildConstructedType<String>(17)
If buildConstructedTypeCount.count <> 17 Then RuntimeError "same-arity generic Type constructor overload selected an incompatible ABI"
Local buildConstructedTypeDelegated:TBuildConstructedType<String> = New TBuildConstructedType<String>("delegated Type", 13)
If buildConstructedTypeDelegated.Read() <> "delegated Type" Or buildConstructedTypeDelegated.count <> 13 Then RuntimeError "generic Type constructor delegation or overload selection used an incompatible ABI"
If buildConstructedTypeFromFactory1.Read() <> "factory Type one" Or buildConstructedTypeFromFactory1.count <> 21 Then RuntimeError "parameterized generic Type construction inside a generic body used an incompatible ABI"
If buildConstructedTypeFromFactory2.Read() <> "factory Type two" Or buildConstructedTypeFromFactory2.count <> 22 Then RuntimeError "second parameterized generic-body construction request was not canonical"

Local inherited:TBuildDerived<String> = New TBuildDerived<String>
inherited.baseValue = "base"
inherited.derivedValue = "derived"
If inherited.GetBase() <> "base" Then RuntimeError "generic base layout or inherited slot used an incompatible ABI"
If inherited.GetDerived() <> "derived" Then RuntimeError "generic derived layout or declared slot used an incompatible ABI"
If inherited.InvokeVirtual("base fallback") <> "derived" Then RuntimeError "generic Self call did not dispatch through the derived canonical slot"

Local concreteValue:TBuildValue<String> = New TBuildValue<String>
concreteValue.interfaceValue = "interface"
Local abstractValue:IBuildValue<String> = concreteValue
If abstractValue.Read() <> "interface" Then RuntimeError "canonical generic Interface table used an incompatible ABI"

Local multiValue:TBuildMultiValue<String> = New TBuildMultiValue<String>
multiValue.value = "multiple"
Local rootValue:IBuildValue<String> = multiValue
Local leftValue:IBuildLeft<String> = multiValue
Local rightValue:IBuildRight<String> = multiValue
Local diamondValue:IBuildDiamond<String> = multiValue
Local extraValue:IBuildExtra<String> = multiValue
If rootValue.Read() <> "multiple" Then RuntimeError "shared generic Interface ancestor used an incompatible ABI"
If leftValue.Left() <> "multiple" Then RuntimeError "left generic Interface parent used an incompatible ABI"
If rightValue.Right() <> "multiple" Then RuntimeError "right generic Interface parent used an incompatible ABI"
If diamondValue.Diamond() <> "multiple" Then RuntimeError "diamond generic Interface used an incompatible ABI"
If extraValue.Extra() <> "multiple" Then RuntimeError "second implemented generic Interface used an incompatible ABI"

Local directValue:TBuildDirectDerived = New TBuildDirectDerived
directValue.baseValue = 20
directValue.derivedValue = 22
If directValue.Forward(1) <> 42 Then RuntimeError "source-local direct generic Self/Super edges used an incompatible ABI"
Local directBase:TBuildDirectBase = directValue
If directBase.Pick(2) <> 20 Then RuntimeError "source-local base-typed direct generic method selected an incompatible specialization"
Local directStruct:SBuildDirect
directStruct.value = 42
If directStruct.Read("fallback") <> 42 Then RuntimeError "source-local direct generic Struct method used an incompatible ABI"
