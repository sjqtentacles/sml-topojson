structure Tests = struct open Harness structure T = TopoJson

fun run () = let
  (* ---- legacy single point still works ---- *)
  val () = section "single-point legacy round-trip"
  val topo = T.fromGeoJsonPoint [1.0, 2.0]
  val () = checkBool "transform present" (true, Option.isSome (#transform topo))
  val (qx, qy) = List.hd (List.hd (#arcs topo))
  val () = checkRealTol 1E~3 "qx quantized" (1000000.0, qx)
  val () = check "qx integral" (Real.== (qx, Real.realRound qx))
  val pt = T.toGeoJsonPoint topo (qx, qy)
  val () = checkRealTol 1E~6 "lon" (1.0, List.nth (pt, 0))
  val () = checkRealTol 1E~6 "lat" (2.0, List.nth (pt, 1))

  (* ---- computeTransform + apply/untransform round-trip ---- *)
  val () = section "transform round-trip"
  val t = T.computeTransform { min = (0.0, 0.0), max = (100.0, 50.0) } 1001
  (* scale = (100/1000, 50/1000) = (0.1, 0.05), translate = (0,0) *)
  val { scale = (sx, sy), translate = (tx, ty) } = t
  val () = checkRealTol 1E~9 "scaleX" (0.1, sx)
  val () = checkRealTol 1E~9 "scaleY" (0.05, sy)
  val () = checkRealTol 1E~9 "transX" (0.0, tx)
  (* quantize then dequantize a real point -> close to original *)
  val (qx2, qy2) = T.untransform t (37.5, 12.25)
  val () = check "quantized x integral" (Real.== (qx2, Real.realRound qx2))
  val (rx, ry) = T.applyTransform t (qx2, qy2)
  val () = checkRealTol 1E~1 "x recovered" (37.5, rx)
  val () = checkRealTol 1E~1 "y recovered" (12.25, ry)

  val () = section "transform with translate"
  val t2 = T.computeTransform { min = (~10.0, 5.0), max = (10.0, 25.0) } 21
  val { scale = (sx2, sy2), translate = (tx2, ty2) } = t2
  val () = checkRealTol 1E~9 "translateX = minx" (~10.0, tx2)
  val () = checkRealTol 1E~9 "translateY = miny" (5.0, ty2)
  (* min maps to quantized (0,0) *)
  val (qmin_x, qmin_y) = T.untransform t2 (~10.0, 5.0)
  val () = checkRealTol 1E~9 "min -> 0 x" (0.0, qmin_x)
  val () = checkRealTol 1E~9 "min -> 0 y" (0.0, qmin_y)

  (* ---- quantizeArc / dequantizeArc delta-encoding ---- *)
  val () = section "arc delta round-trip"
  val abs = [(10.0, 10.0), (12.0, 13.0), (12.0, 20.0), (5.0, 20.0)]
  val deltas = T.quantizeArc abs
  (* first point absolute, rest are diffs *)
  val () = checkRealTol 1E~9 "first abs x" (10.0, #1 (List.hd deltas))
  val () = checkRealTol 1E~9 "second delta x" (2.0, #1 (List.nth (deltas, 1)))
  val () = checkRealTol 1E~9 "second delta y" (3.0, #2 (List.nth (deltas, 1)))
  val back = T.dequantizeArc deltas
  val () = checkInt "same length" (List.length abs, List.length back)
  val () = checkRealTol 1E~9 "last x recovered" (5.0, #1 (List.last back))
  val () = checkRealTol 1E~9 "last y recovered" (20.0, #2 (List.last back))
  val () = checkInt "empty arc deltas" (0, List.length (T.quantizeArc []))

  (* ---- LineString encode/decode ---- *)
  val () = section "LineString encode/decode"
  val line = [[0.0,0.0],[1.0,1.0],[2.0,0.0],[3.0,3.0]]
  val ltopo = T.fromGeoJsonLine 1001 line
  val () = checkInt "one arc" (1, List.length (#arcs ltopo))
  (* stored deltas are integral *)
  val arc0 = List.hd (#arcs ltopo)
  val () = check "all stored coords integral"
             (List.all (fn (x,y) => Real.== (x, Real.realRound x)
                                    andalso Real.== (y, Real.realRound y)) arc0)
  val dline = T.toGeoJsonLine ltopo
  val () = checkInt "same vertex count" (4, List.length dline)
  val () = checkRealTol 1E~2 "p0 x" (0.0, List.nth (List.nth (dline,0),0))
  val () = checkRealTol 1E~2 "p3 x" (3.0, List.nth (List.nth (dline,3),0))
  val () = checkRealTol 1E~2 "p3 y" (3.0, List.nth (List.nth (dline,3),1))

  (* ---- Polygon encode/decode ---- *)
  val () = section "Polygon encode/decode"
  val poly = [ [[0.0,0.0],[4.0,0.0],[4.0,4.0],[0.0,4.0],[0.0,0.0]]
             , [[1.0,1.0],[2.0,1.0],[2.0,2.0],[1.0,2.0],[1.0,1.0]] ]
  val ptopo = T.fromGeoJsonPolygon 1001 poly
  val () = checkInt "two rings" (2, List.length (#arcs ptopo))
  val dpoly = T.toGeoJsonPolygon ptopo
  val () = checkInt "two rings back" (2, List.length dpoly)
  val () = checkInt "outer ring 5 pts" (5, List.length (List.hd dpoly))
  val ring0p1 = List.nth (List.hd dpoly, 1)
  val () = checkRealTol 1E~2 "outer p1 x" (4.0, List.nth (ring0p1, 0))

  (* ---- shared-arc dedup ---- *)
  val () = section "extractArcs dedup + reconstruct"
  val shared = [(0.0,0.0),(1.0,1.0),(2.0,2.0)]
  val other  = [(9.0,9.0),(8.0,8.0)]
  val lines = [shared, other, shared]
  val (arcs, idx) = T.extractArcs lines
  val () = checkInt "deduped to 2 arcs" (2, List.length arcs)
  val () = checkIntList "line0 idx" ([0], List.nth (idx, 0))
  val () = checkIntList "line1 idx" ([1], List.nth (idx, 1))
  val () = checkIntList "line2 reuses arc0" ([0], List.nth (idx, 2))
  val rebuilt = T.reconstruct (arcs, idx)
  val () = checkInt "3 lines rebuilt" (3, List.length rebuilt)
  val () = check "line2 matches shared"
             (ListPair.all (fn ((a,b),(c,d)) => Real.==(a,c) andalso Real.==(b,d))
                           (List.nth (rebuilt, 2), shared))

in Harness.run () end end
