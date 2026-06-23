structure Tests = struct open Harness structure T = TopoJson
fun run () = let
  (* Build a topology from a GeoJSON point.  The point must be recovered by
     reading the QUANTIZED integer coordinate that was stored in `#arcs` and
     pushing it back through `toGeoJsonPoint`, which applies the stored
     transform.  This exercises the full encode -> store -> decode path
     (not a pass-through of the answer). *)
  val topo = T.fromGeoJsonPoint [1.0, 2.0]

  val () = section "transform is captured"
  val () = checkBool "transform present" (true, Option.isSome (#transform topo))
  val () = checkInt  "one arc" (1, List.length (#arcs topo))
  val () = checkInt  "one vertex in arc" (1, List.length (List.hd (#arcs topo)))

  val () = section "quantized storage is integral and scaled"
  val (qx, qy) = List.hd (List.hd (#arcs topo))
  (* 1.0 / 1e-6 = 1e6 ; 2.0 / 1e-6 = 2e6 *)
  val () = checkRealTol 1E~3 "qx is quantized 1e6" (1000000.0, qx)
  val () = checkRealTol 1E~3 "qy is quantized 2e6" (2000000.0, qy)
  val () = check "qx is integral" (Real.== (qx, Real.realRound qx))

  val () = section "decode round-trip through transform"
  val pt = T.toGeoJsonPoint topo (qx, qy)
  val () = checkRealTol 1E~6 "lon" (1.0, List.nth (pt, 0))
  val () = checkRealTol 1E~6 "lat" (2.0, List.nth (pt, 1))

  val () = section "negative + fractional coordinates"
  val topo2 = T.fromGeoJsonPoint [~122.4194, 37.7749]
  val (q2x, q2y) = List.hd (List.hd (#arcs topo2))
  val pt2 = T.toGeoJsonPoint topo2 (q2x, q2y)
  val () = checkRealTol 1E~5 "sf lon" (~122.4194, List.nth (pt2, 0))
  val () = checkRealTol 1E~5 "sf lat" (37.7749, List.nth (pt2, 1))
in Harness.run () end end
