structure TopoJson :> TOPOJSON =
struct
  type point = real * real
  type transform = { scale : real * real, translate : real * real }
  type topo = { transform : transform option, arcs : (real * real) list list }

  (* Fixed grid step used by the single-point helpers (kept for the legacy
     fromGeoJsonPoint round-trip): 1e-6 degrees, ~0.1m. *)
  val step = 1.0E~6
  fun quantize x = Real.realRound (x / step)

  (* ---- transforms ---- *)

  fun applyTransform ({ scale = (sx, sy), translate = (tx, ty) } : transform) (qx, qy) =
    (qx * sx + tx, qy * sy + ty)

  fun untransform ({ scale = (sx, sy), translate = (tx, ty) } : transform) (x, y) =
    (Real.realRound ((x - tx) / sx), Real.realRound ((y - ty) / sy))

  fun computeTransform ({ min = (minx, miny), max = (maxx, maxy) } : { min : point, max : point }) q =
    let
      val denom = Real.fromInt (Int.max (q, 2) - 1)
      val sx = if Real.== (maxx, minx) then 1.0 else (maxx - minx) / denom
      val sy = if Real.== (maxy, miny) then 1.0 else (maxy - miny) / denom
    in
      { scale = (sx, sy), translate = (minx, miny) }
    end

  (* ---- arc delta-encoding ---- *)

  fun quantizeArc [] = []
    | quantizeArc (p0 :: rest) =
        let
          fun go _ [] = []
            | go (px, py) ((x, y) :: tl) = (x - px, y - py) :: go (x, y) tl
        in
          p0 :: go p0 rest
        end

  fun dequantizeArc [] = []
    | dequantizeArc (p0 :: rest) =
        let
          fun go (px, py) [] = []
            | go (px, py) ((dx, dy) :: tl) =
                let val cur = (px + dx, py + dy) in cur :: go cur tl end
        in
          p0 :: go p0 rest
        end

  (* ---- single-point helpers (legacy) ---- *)

  fun fromGeoJsonPoint [lon, lat] =
        { transform = SOME { scale = (step, step), translate = (0.0, 0.0) }
        , arcs = [[(quantize lon, quantize lat)]] }
    | fromGeoJsonPoint _ = { transform = NONE, arcs = [] }

  fun toGeoJsonPoint ({ transform, ... } : topo) (qx, qy) =
    case transform of
        SOME t => let val (x, y) = applyTransform t (qx, qy) in [x, y] end
      | NONE => [qx, qy]

  (* ---- bbox of a list of [lon,lat] points ---- *)

  fun bboxOf (pts : real list list) =
    let
      fun toXY [x, y] = (x, y)
        | toXY _ = raise Fail "point must be [lon,lat]"
      val xys = List.map toXY pts
      fun fold ((x, y), { min = (mnx, mny), max = (mxx, mxy) }) =
        { min = (Real.min (mnx, x), Real.min (mny, y))
        , max = (Real.max (mxx, x), Real.max (mxy, y)) }
    in
      case xys of
          [] => raise Fail "bboxOf: empty"
        | (x0, y0) :: _ =>
            List.foldl fold { min = (x0, y0), max = (x0, y0) } xys
    end

  (* ---- LineString ---- *)

  fun fromGeoJsonLine q (pts : real list list) =
    if List.null pts then { transform = NONE, arcs = [] }
    else
      let
        val t = computeTransform (bboxOf pts) q
        fun toXY [x, y] = (x, y) | toXY _ = raise Fail "bad point"
        val quantized = List.map (fn p => untransform t (toXY p)) pts
        val arc = quantizeArc quantized
      in
        { transform = SOME t, arcs = [arc] }
      end

  fun decodeArc (t : transform) arc =
    List.map (fn q => let val (x, y) = applyTransform t q in [x, y] end)
             (dequantizeArc arc)

  fun toGeoJsonLine ({ transform, arcs } : topo) =
    case (transform, arcs) of
        (SOME t, arc :: _) => decodeArc t arc
      | (NONE, arc :: _) => List.map (fn (x, y) => [x, y]) (dequantizeArc arc)
      | _ => []

  (* ---- Polygon (list of rings) ---- *)

  fun fromGeoJsonPolygon q (rings : real list list list) =
    if List.null rings orelse List.all List.null rings then { transform = NONE, arcs = [] }
    else
      let
        val allPts = List.concat rings
        val t = computeTransform (bboxOf allPts) q
        fun toXY [x, y] = (x, y) | toXY _ = raise Fail "bad point"
        fun ringToArc ring = quantizeArc (List.map (fn p => untransform t (toXY p)) ring)
      in
        { transform = SOME t, arcs = List.map ringToArc rings }
      end

  fun toGeoJsonPolygon ({ transform, arcs } : topo) =
    case transform of
        SOME t => List.map (decodeArc t) arcs
      | NONE => List.map (fn arc => List.map (fn (x, y) => [x, y]) (dequantizeArc arc)) arcs

  (* ---- shared-arc dedup ---- *)

  fun extractArcs (lines : (real * real) list list) =
    let
      fun eqPt ((a, b), (c, d)) = Real.== (a, c) andalso Real.== (b, d)
      fun eqArc (xs, ys) =
        List.length xs = List.length ys andalso ListPair.all eqPt (xs, ys)
      (* find index of arc in accumulated list, or NONE *)
      fun indexOf (arc, acc) =
        let
          fun go (_, []) = NONE
            | go (i, a :: tl) = if eqArc (a, arc) then SOME i else go (i + 1, tl)
        in go (0, acc) end
      fun step (arc, (arcs, rev)) =
        case indexOf (arc, arcs) of
            SOME i => (arcs, i :: rev)
          | NONE => (arcs @ [arc], List.length arcs :: rev)
      val (arcs, idxRev) =
        List.foldl (fn (arc, (arcs, idxs)) =>
                       let val (arcs', rev) = step (arc, (arcs, []))
                       in (arcs', List.rev rev :: idxs) end)
                   ([], []) lines
    in
      (arcs, List.rev idxRev)
    end

  fun reconstruct (arcs, indices) =
    List.map (fn idxs => List.concat (List.map (fn i => List.nth (arcs, i)) idxs)) indices
end
