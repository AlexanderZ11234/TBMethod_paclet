(* ::Package:: *)

BeginPackage["TBMethod`MDConstruct`"]

(* Declare your package's public symbols here. *)

(* Exported symbols added here with SymbolName::usage *) 
HMatrixFromHoppings::usage = "Constructs the real-space tight-binding Hamiltonian matrix from two sets of points from a given hopping function, depending on the coordinates of one pair of points, within the space distance upper limit.";

ParallelHMatrixFromHoppings::usage = "Parallel version of ParallelHMatrixFromHoppings."

HBloch::usage = "Constructs the reciprocal space Bloch Hamiltonian matrix, with automatic consideration of opposite hoppings.";

HBlochFull::usage = "Constructs the reciprocal space Bloch Hamiltonian matrix, without consideration of opposite hoppings.";

DisjointedShellDivisionRegions::usage = "xxx.";

CoordinatesGroupByRegions::usage = "xxx.";

AttachFreeQ::usage = "Checks if two devices are out of contact.";

HCSRDiagOffDiagBlocks::usage = "Generates the n diagonal and the (n-1) first off-diagonal matrix blocks of the tight-binding Hamiltonian, where n is the layer number of the CSR partitioned.";
ParallelHCSRDiagOffDiagBlocks::usage = "Parallel version of HCSRDiagOffDiagBlocks.";
HCSRDiagOffDiagBlocksVerbose::usage = "Verbose version of HCSRDiagOffDiagBlocks.";

HLeadBlocks::usage = "Generates the three Hamiltonian blocks (\!\(\*SubscriptBox[\(h\), \(00\)]\), \!\(\*SubscriptBox[\(h\), \(10\)]\), and \!\(\*SubscriptBox[\(H\), \(10\)]\)) for each lead.";
ParallelHLeadBlocks::usage = "Parallel version of HLeadBlocks.";
HLeadBlocksVerbose::usage = "Verbose version of HLeadBlocks.";

AdaptivePartition::usage = "Partitions the CSR in an adaptive way to achieve an optimal slicing status, according to the given leads' configuration."

\[CapitalGamma]Matrix::usage = "Matrix from Kronecker product of Pauli matrixes, used in construction of Dirac model.";

FillWithDistance::usage = "Constructs the piecewise filling function according to distances."
FillWithCondition::usage = "Constructs the piecewise filling function according to conditions."

PhaseFactor2DAB::usage = "Calculates the AB phase for a magnetic flux along z-direction.";

HBlochsForSpecFunc::usage = "Constructs Bloch Hamiltonian blocks for calculation of spectral function (LDOS in reciprocal space).";

GellMannMatrix::usage = "Gives Gell-Mann matrices.";
PauliGellMannDecomposition::usage = "Decomposes a matrix into a sum of linear conbination of a series of matrix basis, which are Kronecker products of Pauli and/or Gell-Mann matrices.";
PauliGellMannAbstract::usage = "Formats tidily the information generated by PauliGellMannDecomposition.";
PauliGellMannRepresent::usage = "Transforms the result of PauliGellMannAbstract into its matrix representation.";

PhotonBlocks::usage = "Generates the Floquet dressing coefficient for a certain hopping amplitude due to light driven field via Peierls's substitution.";
PhotonDress::usage = "Generates the photon-dressed hopping amplitude.";


Begin["`Private`"]
(* Implementation of the package *)
(*SetOptions[{ParallelSum}, Method -> "ItemsPerEvaluation" -> 100 $KernelCount];*)

$DistributedContexts = {"Global`", "TBMethod`"}; (*Otherwise, dim in HMatrixFromHoppings is not working in parallel subkernels. This is very IMPORTANT!!!*)


FillWithDistance[fs_, ds_, d_, zero_:1.*^-5] :=
Module[{innerdof = Dimensions[fs[[1, 1]]]},
	Piecewise[
	MapThread[{#, Abs[d - #2] < zero} &, {fs, ds}],
	ConstantArray[0, innerdof]
	] // ReleaseHold
];
FillWithCondition[fs_, conds_] :=
Module[{innerdof = Dimensions[fs[[1, 1]]]},
	Piecewise[
		{fs, conds}\[Transpose],
		ConstantArray[0, innerdof]
	] // ReleaseHold
];

\[CapitalGamma]Matrix[is__] := KroneckerProduct @@ PauliMatrix[{is}];

(*Phys. Rev. B 40, 8169 (1989)*)
PhaseFactor2DAB[B_, \[Phi]A_][ptf_, pti_] :=
Module[{xi, yi, xj, yj, \[CurlyPhi]},
	{{xi, yi}, {xj, yj}} = {ptf, pti};
	(*B \[Pi] ( xj yi - xi yj - (xi yi - xj yj) Cos[2\[Phi]A] + (xi^2 - xj^2 - yi^2 + yj^2) Sin[2\[Phi]A]/2)*)
	\[CurlyPhi] = B \[Pi] (- xj yi + xi yj + (xi yi - xj yj) Cos[2\[Phi]A] + (-xi^2 + xj^2 + yi^2 - yj^2) Sin[2\[Phi]A]/2);
	Exp[I \[CurlyPhi]]
];

SetAttributes[GellMannMatrix, Listable]
GellMannMatrix[i : Alternatives @@ Range[0, 8]] :=
Module[{n = 3, dim},
	dim = {1, 1} n;
	Which[
		i == 0, IdentityMatrix[n, SparseArray],
		i == 1 || i == 2 || i == 3, SparseArray[PadRight[PauliMatrix[i], dim]],
		i == 4, SparseArray[{{1, 3}, {3, 1}} -> 1, dim],
		i == 5, SparseArray[{{1, 3} -> -I, {3, 1} -> I}, dim],
		i == 6 || i == 7, SparseArray[PadLeft[PauliMatrix[i - 5], dim]],
		i == 8, SparseArray[Band[{1, 1}] -> ({1, 1, -2}/Sqrt[3]), dim]
	]
];


pauliMatrixDecomposition[{{a_, b_}, {c_, d_}}] := FullSimplify[{a + d, b + c, I(b - c), a - d}/2];
gellMannMatrixDecomposition[{{a_, b_, c_}, {d_, e_, f_}, {g_, h_, i_}}] := FullSimplify[{2(a + e + i)/3, b + d, I (b - d), a - e, c + g, I(c - g), f + h, I(f - h), (a + e - 2i)/Sqrt[3]}/2];
dimfatorpattern = ({{2, _Integer}} | {{3, _Integer}} | {{2, _Integer}, {3, _Integer}});
PauliGellMannDecomposition[M_?MatrixQ, dimlist:{(2|3)..}] /; (# == #2 >= 2 && MatchQ[FactorInteger[#], dimfatorpattern] & @@ Dimensions[M]):=
Module[{decompose, rules},
	decompose[n:(2|3)] := If[n == 2, pauliMatrixDecomposition, gellMannMatrixDecomposition];
	rules = ArrayRules[Fold[BlockMap[decompose[#2], #, {1, 1} #2] &][M, Reverse @ dimlist][[1, 1]]];
	Association[MapAt[# - 1 &, {;;, 1}] @ Most[rules]]
];

PauliGellMannAbstract[PGMDecomp_Association, dimlist:{(2|3)..}] :=
Module[{s, keyfunc},
	s[n:(2|3)] := If[n == 2, "\[Sigma]", "\[Lambda]"];
	keyfunc = CircleTimes @@ MapThread[Construct, {s /@ dimlist, #}] &;
	Total[KeyValueMap[keyfunc[#] #2 &][PGMDecomp]]
];

PauliGellMannRepresent[epr_] := FullSimplify[epr /. {"\[Sigma]" -> PauliMatrix, "\[Lambda]" -> GellMannMatrix, CircleTimes -> KroneckerProduct}];


(*Auxiliary functions*)
(*coordspattern = {{__?NumericQ}..|{{__?NumericQ}, True|False}..|(_ -> {__?NumericQ})..};*)
(*coordspattern = {{__?NumericQ}..|(_ -> {__?NumericQ})..};*)
(*coordspattern={{__?NumericQ}..}|{Rule[_, {__?NumericQ}]..};*)
coordspattern={__List}|{Rule[_ , _List]..};
(*Extra information is typically of the "onsite energy like", and can be: (1) atom on bdr or not; (2) atom mass*)
(*the one containing booleans should be removed*)

(*neighbourInfos[pts:coordspattern, dist_Real] := neighbourInfos[{pts, pts}, dist];*)(*This kind of pattern splitting leads to ambiguity.*)
neighbourInfos[fipts:{fpts:coordspattern, ipts:coordspattern}, dist_Real] := neighbourInfos[fipts, dist] =
Module[{fptsnobool, iptsnobool, nfunc, a0 = 1},
	{fptsnobool, iptsnobool} = If[FreeQ[#, (*True|False*)Rule[_, _]], #, Values[#]]& /@ fipts;
	(*{fptsnobool, iptsnobool} = If[Head[#] === List, #, Values[#]]& /@ fipts;*)
	nfunc = Nearest[iptsnobool -> Automatic, WorkingPrecision -> MachinePrecision, Method -> "KDTree"];
	Flatten[MapIndexed[Thread[{#2[[1]], #}]&, nfunc[fptsnobool, {All, dist a0}]], 1]
];

AttachFreeQ[fipts:{fpts:coordspattern, ipts:coordspattern}, dist_Real] := Length[neighbourInfos[fipts, dist]] == 0;

(*HMatrixFromHoppings[pts:coordspattern, tFunc_, dist_Real, sumfunc_:Sum] := HMatrixFromHoppings[{pts, pts}, tFunc, dist, sumfunc];*)
(*General::maxrec: "Recursion limit exceeded; positive match might be missed."*)

HMatrixFromHoppings[fipts:{fpts:coordspattern, ipts:coordspattern}, tFunc_, dist_Real] :=
Block[{dim = Length /@ fipts, neighbourinfos = neighbourInfos[fipts, dist], len, (*lenup = 1000,*) summand},
	len = Length[neighbourinfos];
	summand[ij_] := KroneckerProduct[SparseArray[ij -> 1, dim], tFunc[fpts[[#]], ipts[[#2]]] & @@ ij];
	Which[
		len == 0, KroneckerProduct[SparseArray[{}, dim], tFunc[fpts[[1]], ipts[[1]]]],
		len > 0 , Sum[summand[ij], {ij, neighbourinfos}]
	]
];

ParallelHMatrixFromHoppings[fipts:{fpts:coordspattern, ipts:coordspattern}, tFunc_, dist_Real, ops:OptionsPattern[ParallelSum]] :=
Block[{dim = Length /@ fipts, neighbourinfos = neighbourInfos[fipts, dist], len, (*lenup = 1000,*) summand},
	len = Length[neighbourinfos];
	summand[ij_] := KroneckerProduct[SparseArray[ij -> 1, dim], tFunc[fpts[[#]], ipts[[#2]]] & @@ ij];
	Which[
		len == 0, KroneckerProduct[SparseArray[{}, dim], tFunc[fpts[[1]], ipts[[1]]]],
		len > 0 , ParallelSum[summand[ij], {ij, neighbourinfos}, ops]
	]
];


(*HMatrixFromHoppings[fipts:{fpts:coordspattern, ipts:coordspattern}, tFunc_, dist_Real, sumfunc_:Sum] :=
Block[{dim = Length /@ fipts, neighbourinfos = neighbourInfos[fipts, dist], len, (*lenup = 1000,*) summand},
	len = Length[neighbourinfos];
	summand[ij_] := KroneckerProduct[SparseArray[ij -> 1, dim], tFunc[fpts[[#]], ipts[[#2]]] & @@ ij];
	(*Which[
		len == 0, KroneckerProduct[SparseArray[{}, dim], tFunc[fpts[[1]], ipts[[1]]]],
		lenup > len > 0, Sum[summand[ij], {ij, neighbourinfos}],
		lenup <= len, ParallelSum[summand[ij], {ij, neighbourinfos}]
	]*)
	Which[
		len == 0, KroneckerProduct[SparseArray[{}, dim], tFunc[fpts[[1]], ipts[[1]]]],
		len > 0 , sumfunc[summand[ij], {ij, neighbourinfos}]
	]
];*)

(*HMatrixFromHoppings[pts:coordspattern, tFunc_, dist_Real] := HMatrixFromHoppings[{pts, pts}, tFunc, dist];
HMatrixFromHoppings[fipts:{fpts:coordspattern, ipts:coordspattern}, tFunc_, dist_Real] :=
Module[{dim = Length /@ fipts, fptsnobool, iptsnobool, nfunc, neighbourinfos, fillingrules, a0 = 1},
	{fptsnobool, iptsnobool} = If[FreeQ[#, True|False], #, #[[;;, 1]]]& /@ fipts;
	(*nfunc is a NearestFunction with respect to the group of initial points, which should constitute the column index*)
	nfunc = Nearest[iptsnobool -> Automatic, WorkingPrecision -> MachinePrecision(*Method -> Automatic(*{"KDtree","LeafSize"->50}*)*)];
	(*Within the disk/ball with a certain radius (= dist a0) centered at each final point, find the encompassed initial points; each point is given as its index in its corresponding ordered set (final point in fpts & initial point in ipts).*)
	neighbourinfos = Flatten[MapIndexed[Thread[{#2[[1]], #}]&, nfunc[fptsnobool, {All, dist a0}]], 1];(*{{j..}..} -> {{i, {j..}}..} -> {{i, j}..}*)
	
	(*Summation saves RAM considerably. Fine tunability lies in the methods of Parallelize[]*)
	If[Length[neighbourinfos] < 1000, Sum, ParallelSum][
		KroneckerProduct[SparseArray[ij -> 1, dim], tFunc[fpts[[#]], ipts[[#2]]]& @@ ij],
		{ij, neighbourinfos}
	]
];*)

HBloch[vk_, h0010s:<|({__?NumericQ} -> _SparseArray)..|>] :=
Module[{hermitize = # + #\[HermitianConjugate] &},
	First[h0010s] + hermitize[KeyValueMap[Exp[I # . vk] #2 &, Rest[h0010s]] // Total]
];

HBlochFull[vk_, vecaHa_Association] := Total[KeyValueMap[Exp[I # . vk] #2 &, vecaHa]];

(*Division of a large central scattering region in a disjointed covering manner, suitable for 2D & 3D*)
DisjointedShellDivisionRegions[region_?BoundaryMeshRegionQ, nregions_?(# \[Element] PositiveIntegers &)] :=
Module[{scalingfunc, scaledregions, scalingfactors = Most @ Subdivide[1, 0, nregions], regdim = RegionDimension[region]},
	scalingfunc[factor_] := ScalingTransform[ConstantArray[factor, regdim], RegionCentroid[region]];
	scaledregions = TransformedRegion[region, scalingfunc[#]] & /@ scalingfactors;
	Reverse @ BlockMap[RegionDifference, Append[scaledregions, EmptyRegion[regdim]], 2, 1]
];

CoordinatesGroupByRegions[pts:coordspattern, regions_List] :=
Module[{indexesraw, indexes, intersectionindexes, ptsdata},
	ptsdata = If[\[Not]FreeQ[pts, Rule], Values[pts], pts];
	(*label by regions*)
	indexesraw = GroupBy[SparseArray[Boole @ RegionMember[#][ptsdata] & /@ regions]["NonzeroPositions"], First -> Last];
	(*delete duplecates*)
	intersectionindexes = MapIndexed[#2[[1]] -> # &, Prepend[BlockMap[Intersection @@ # &, indexesraw, 2, 1], {}]];
	indexes = Merge[{indexesraw, intersectionindexes}, DeleteCases[#, Alternatives @@ #2] & @@ # &];
	Extract[pts, {#}\[Transpose]] & /@ indexes
];

HCSRDiagOffDiagBlocks[CSRptsgrouped_Association, tFunc_, dup_] :=
Module[{hdfill, hofill, hdblocks, hoblocks, (*attachcheck, checkresults,*) csrpts = Values[CSRptsgrouped], len = Length[CSRptsgrouped]},
	If[len == 1, HMatrixFromHoppings[Join[csrpts, csrpts], tFunc, dup],
		((*attachcheck = ({p1, p2, p3} |-> AttachFreeQ[{p1, p3}, dup]) @@ # &;
		checkresults = And @@ BlockMap[attachcheck, csrpts, 3, 1];*)
		(*Echo[StringTemplate["Attach check passed: ``."][checkresults]];
		If[checkresults,
			hdfill = p |-> HMatrixFromHoppings[{p, p}, tFunc, dup];
			hofill = p |-> HMatrixFromHoppings[Reverse @ p, tFunc, dup];
			hdblocks = hdfill /@ csrpts;
			hoblocks = BlockMap[hofill, csrpts, 2, 1];
			{hdblocks, hoblocks},
			Echo["Reduce the division number of CSR."]
		])*)
		hdfill = p |-> HMatrixFromHoppings[{p, p}, tFunc, dup];
		hofill = p |-> HMatrixFromHoppings[Reverse @ p, tFunc, dup];
		hdblocks = hdfill /@ csrpts;
		hoblocks = BlockMap[hofill, csrpts, 2, 1];
		{hdblocks, hoblocks})
	]
];

ParallelHCSRDiagOffDiagBlocks[CSRptsgrouped_Association, tFunc_, dup_] :=
Module[{hdfill, hofill, hdblocks, hoblocks, csrpts = Values[CSRptsgrouped], len = Length[CSRptsgrouped]},
	If[len == 1, HMatrixFromHoppings[Join[csrpts, csrpts], tFunc, dup],
		(hdfill = p |-> HMatrixFromHoppings[{p, p}, tFunc, dup];
		hofill = p |-> HMatrixFromHoppings[p, tFunc, dup];
		hdblocks = hdfill ~ParallelMap~ csrpts;
		(*hoblocks = hofill ~ParallelMap~ Transpose[{Rest[csrpts], Most[csrpts]}];*)
		hoblocks = Parallelize[MapThread[hofill, {Rest[csrpts], Most[csrpts]}]];
		{hdblocks, hoblocks})
	]
];

HCSRDiagOffDiagBlocksVerbose[CSRptsgrouped_Association, tFunc_, dup_] :=
Module[{hdfill, hofill, hdblocks, hoblocks, attachcheck, checkresults, csrpts = Values[CSRptsgrouped], len = Length[CSRptsgrouped]},
	If[len == 1, HMatrixFromHoppings[Join[csrpts, csrpts], tFunc, dup],
		(attachcheck = ({p1, p2, p3} |-> AttachFreeQ[{p1, p3}, dup]) @@ # &;
		checkresults = And @@ BlockMap[attachcheck, csrpts, 3, 1];
		Echo[StringTemplate["Attach check passed: ``."][checkresults]];
		If[checkresults,
			hdfill = p |-> HMatrixFromHoppings[{p, p}, tFunc, dup];
			hofill = p |-> HMatrixFromHoppings[Reverse @ p, tFunc, dup];
			hdblocks = hdfill /@ csrpts;
			hoblocks = BlockMap[hofill, csrpts, 2, 1];
			{hdblocks, hoblocks},
			Echo["Reduce the division number of CSR."]
		])
	]
];

(*HLeadBlocks[CSRptsgrouped_Association, tFunc_, dup_, leadpts_] := Table[HMatrixFromHoppings[fipts, tFunc, dup], {fipts, {{#[[1]], #[[1]]}, #, {Values[CSRptsgrouped][[-1]], #[[1]]}} & [leadpts]}];*)
HLeadBlocks[CSRptsgrouped_Association, tFunc_, dup_, leadpts_] := Table[HMatrixFromHoppings[fipts, tFunc, dup], {fipts, {{#[[1]], #[[1]]}, #, {CSRptsgrouped[[-1]], #[[1]]}} & [leadpts]}];
ParallelHLeadBlocks[CSRptsgrouped_Association, tFunc_, dup_, leadpts_] := Table[ParallelHMatrixFromHoppings[fipts, tFunc, dup], {fipts, {{#[[1]], #[[1]]}, #, {CSRptsgrouped[[-1]], #[[1]]}} & [leadpts]}];

HLeadBlocksVerbose[CSRptsgrouped_Association, tFunc_, dup_, leadpts_, leadname_String] :=
Module[{attachcheck, checkresults, csrtwoouters = Values[CSRptsgrouped][[{-2, -1}]]},
	attachcheck = p |-> AttachFreeQ[p, dup];
	checkresults = attachcheck /@ ({csrtwoouters, leadpts}\[Transpose]);
	Echo[StringTemplate["Cell 0 of Lead `` attach check passed: ``."][leadname, checkresults[[1]]]];
	Echo[StringTemplate["Cell 1 of Lead `` attach check passed: ``."][leadname, checkresults[[2]]]];
	If[And @@ checkresults,
		Table[HMatrixFromHoppings[fipts, tFunc, dup], {fipts, {{#[[1]], #[[1]]}, #, {csrtwoouters[[-1]], #[[1]]}} & [leadpts]}],
		Echo[StringTemplate["Enlarge the cell of Lead `` and/or reduce the division number of CSR."][leadname]]
	]
];

(*adaptive partition of CSR*)
(*Points in CSR without labels*)
(*AdaptivePartition[{ptslead1stcell_, ptscsr:coordspattern[[{1}, 1]]}, dup_] :=
Module[{groupfunc, iterate, ptscsrgrouped},
	groupfunc[{x_, y_}] := Module[{ptsneighbors, layerneighbors},
		ptsneighbors = Join @@ NearestTo[x, {All, dup}, WorkingPrecision -> MachinePrecision, Method -> "KDTree"][y];
		layerneighbors = DeleteDuplicates[ptsneighbors];
		{x, {#, Complement[y, #]}} & [layerneighbors]
	];
	iterate = FlattenAt[-1] @* SubsetMap[groupfunc, -2;;];
	(*ptscsrgrouped = NestWhile[iterate, {ptslead1stcell, ptscsr}, Last[#] != {} &][[2;;-2]];*)
	ptscsrgrouped = Rest @ NestWhile[iterate, {ptslead1stcell, ptscsr}, Last[#] != {} &, 1, \[Infinity], -1];
	<|MapIndexed[#2[[1]] -> # &, Reverse[ptscsrgrouped]]|>
];
(*Points in CSR with labels: this second version actually works for both patterns, but slower than the first version for the first pattern.*)
AdaptivePartition[ptsleadcsr:{ptslead1stcell_, ptscsr:coordspattern[[{1}, 2]]}, dup_] :=
Module[{neighborindex, indexneighbortolead, indexgrouped, iterate, ptsleadnobool, ptscsrnobool, indexlayered, len = Length[ptscsr], nf},
	{ptsleadnobool, ptscsrnobool} = If[FreeQ[#, Rule[_, _]], #, Values[#]] & /@ ptsleadcsr;
	nf = Nearest[ptscsrnobool -> Automatic, WorkingPrecision -> MachinePrecision, Method -> "KDTree"];
	neighborindex[x_] := DeleteDuplicates @* Join @@ nf[x, {All, dup}];
	indexneighbortolead = neighborindex[ptsleadnobool];
	iterate = neighborindex[ptscsrnobool[[#]]] &;
	indexgrouped = Reverse @ NestWhileList[iterate, indexneighbortolead, Length[#] < len &];
	indexlayered = BlockMap[Complement @@ # &, Append[indexgrouped, {}], 2, 1];
	<|MapIndexed[#2[[1]] -> ptscsr[[#]] &, indexlayered]|>
]*)
(*optimal implementation so far*)
AdaptivePartition[ptsleadcsr:{ptslead1stcell:coordspattern, ptscsr:coordspattern}, dup_] :=
Module[{neighborindex, nf, indexgrouped, iterate, ptsleadnobool, ptscsrnobool, indexlayered, initial},
	{ptsleadnobool, ptscsrnobool} = If[FreeQ[#, Rule[_, _]], #, Values[#]] & /@ ptsleadcsr;
	nf = Nearest[ptscsrnobool -> Automatic, WorkingPrecision -> MachinePrecision, Method -> "KDTree"];
	neighborindex[x_] := DeleteDuplicates @* Join @@ nf[x, {All, dup}];
	iterate = Append[#, Complement[neighborindex[ptscsrnobool[[Last[#]]]], #[[-1]], #[[-2]]]] &;
	initial = {{}, neighborindex[ptsleadnobool]};
	indexlayered = Reverse @ Rest @ NestWhile[iterate, initial, Last[#] != {} &, 1, \[Infinity], -1];
	<|MapIndexed[#2[[1]] -> ptscsr[[#]] &, indexlayered]|>
];
(*AdaptivePartition[ptsleadcsr:{ptslead1stcell:coordspattern, ptscsr:coordspattern}, dup_, opts: OptionsPattern[Nearest]] :=
Module[{neighborindex, nf, indexgrouped, iterate, ptsleadnobool, ptscsrnobool, indexlayered, initial},
	{ptsleadnobool, ptscsrnobool} = If[FreeQ[#, Rule[_, _]], #, Values[#]] & /@ ptsleadcsr;
	nf = Nearest[ptscsrnobool -> Automatic, opts, WorkingPrecision -> MachinePrecision, Method -> "KDTree"];
	neighborindex[x_] := DeleteDuplicates @* Join @@ nf[x, {All, dup}];
	iterate = Append[#, Complement[neighborindex[ptscsrnobool[[Last[#]]]], #[[-1]], #[[-2]]]] &;
	initial = {{}, neighborindex[ptsleadnobool]};
	indexlayered = Reverse @ Rest @ NestWhile[iterate, initial, Last[#] != {} &, 1, \[Infinity], -1];
	<|MapIndexed[#2[[1]] -> ptscsr[[#]] &, indexlayered]|>
];*)

(*HBlochsForSpecFunc[vk_, ptscellsvas_, tfunc_, dup_] :=
Module[{HLeadIntraInterReal, HCSRIntraLeadInterReal, fillfunc, keys = Keys[ptscellsvas], len = Length[ptscellsvas]},
	fillfunc[indfs_, indi_] := HMatrixFromHoppings[{#, ptscellsvas[[indi]]}, tfunc, dup] & /@ KeyMap[# - keys[[indi]] &][ptscellsvas[[indfs]]];
	(*fillfunc[indfs_, indi_] := HMatrixFromHoppings[{#, ptscellsvas[[indi]]}, tfunc, dup] & /@ ptscellsvas[[indfs]];*)
	HLeadIntraInterReal = fillfunc @@@ {{2;;4, 3}, {2;;4, 1}};
	Which[
		len == 4, HBlochFull[vk, #]& /@ HLeadIntraInterReal,
		len == 7,
		(HCSRIntraLeadInterReal = fillfunc @@@ {{5;;, 6}, {5;;, 3}};
		Map[HBlochFull[vk, #]&, {HLeadIntraInterReal, HCSRIntraLeadInterReal}, {2}]),
		True, 0
	]
];*)

HBlochsForSpecFunc[vk:({_, _}|{_, _, _}), bdrdirec:({_, _}|{_, _, _}), ptscellsvasraw_, tfunc_, dup_] :=
Module[{HLeadIntraInterReal, HCSRIntraLeadInterReal, fillfunc, keys, len = Length[ptscellsvasraw], ptscellsvas},
	ptscellsvas = Association /@ SortBy[N @* Norm @* Keys] /@ GatherBy[Normal[ptscellsvasraw], Norm[Keys[#] . bdrdirec] &];
	(*KeyMap only works on Association, rather than List.*)
	keys = Keys[ptscellsvas];
	fillfunc[indfs_, indi_] := HMatrixFromHoppings[{#, Extract[indi] @ ptscellsvas}, tfunc, dup] & /@ (KeyMap[# - Extract[indi][keys] &] @ ptscellsvas[[indfs]]);
	HLeadIntraInterReal = fillfunc @@@ {{2, {2, 1}}, {2, {1, 1}}};
	Which[
		MemberQ[{4, 8, 10}, len],
		HBlochFull[vk, #] & /@ HLeadIntraInterReal,
		MemberQ[{7, 15, 19}, len],
		(HCSRIntraLeadInterReal = fillfunc @@@ {{3, {3, 1}}, {3, {2, 1}}};
		Map[HBlochFull[vk, #] &, {HLeadIntraInterReal, HCSRIntraLeadInterReal}, {2}]),
		True, 0
	]
] /; MemberQ[{4, 7, 8, 10, 15, 19}, Length[ptscellsvasraw]];
(*
necessary number of celle to consider: 2D: 1->3(->3); 3D: 1->9(->9) or 1->7(->7).
The basic idea is to add self-energy to the CSR in a single terminal setup.
The point here is that each part has lattice momenta as parameter, to conceptually accommondate the infiniteness of the device in one or two dimensions.
*)


(*HBlochsForSpecFunc[vk_, ptscellsvas_, tfunc_, dup_] :=
Module[{HLeadIntraInterReal, HCSRIntraLeadInterReal, fillfunc, keys = Keys[ptscellsvas], len = Length[ptscellsvas]},
	(*fillfunc[indfs_, indi_] := HMatrixFromHoppings[{#, ptscellsvas[[indi]]}, tfunc, dup] & /@ KeyMap[# - keys[[indi]] &][ptscellsvas[[indfs]]];*)
	fillfunc[indfs_, indi_] := HMatrixFromHoppings[{#, ptscellsvas[[indi]]}, tfunc, dup] & /@ ptscellsvas[[indfs]];
	HLeadIntraInterReal = fillfunc @@@ {{2;;4, 3}, {2;;4, 1}};
	HCSRIntraLeadInterReal = fillfunc @@@ {{5;;, 6}, {5;;, 3}};
	Map[HBlochFull[vk, #]&, {HLeadIntraInterReal, HCSRIntraLeadInterReal}, {2}]
]*)

PhotonBlocks[{A0_, Avecn:(_Function|_Symbol), \[Omega]_}, mnup_Integer][ptf_, pti_] :=
Module[{vd = ptf - pti, zero = 1.*^-5, d, ele, dim = (2 mnup + 1){1, 1}, photondress, sparseconst, sparsediag},
	(*A0 -> q A0/\[HBar], \[Omega] -> \[HBar] \[Omega]*)
	d = Norm[vd];
	ele[m_, n_] := 1/(2\[Pi]) NIntegrate[Exp[I (A0 vd . Avecn[\[CurlyPhi]] + (m - n) \[CurlyPhi])], {\[CurlyPhi], -\[Pi], \[Pi]}, Method -> "LocalAdaptive"] // Chop;
	(*ele[m_,n_]:=Module[{\[CurlyPhi]},
	\[CurlyPhi]=ArcTan@@Reverse[vd]+\[Pi];
	Exp[-\[ImaginaryI](m-n) \[CurlyPhi]]BesselJ[m-n,A0 d]//N
	];*)
	photondress := Array[ele, dim, -mnup] // Chop;
	sparseconst[i_] := ConstantArray[i, dim, SparseArray];
	sparsediag := SparseArray[Band[{1, 1}]-> -\[Omega] Range[-mnup, mnup]];
	If[d > zero,
		{photondress, sparseconst[0]},
		{sparseconst[1], sparsediag}
	]
];

PhotonDress[t_, photonblocks_] :=
Module[{n = Length[t], s},
	s = IdentityMatrix[n, SparseArray];
	(*t~KroneckerProduct~a+IdentityMatrix[n,SparseArray]~KroneckerProduct~b*)
	MapThread[KroneckerProduct, {{t, s}, photonblocks}] // Total
];


End[] (* End `Private` *)

EndPackage[]
