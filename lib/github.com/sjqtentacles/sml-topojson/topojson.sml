structure TopoJson :> TOPOJSON =
struct
  type topo = { transform : (real * real) option, arcs : (real * real) list list }

  (* TopoJSON stores coordinates as integers on a quantized grid plus a
     `transform` = (scaleX, scaleY) so that a real coordinate is recovered by
        lon = q_x * scaleX     lat = q_y * scaleY
     We use a fixed grid step (1e-6 degrees, ~0.1 m) which is finer than any
     realistic GPS coordinate, so the quantize/dequantize round-trip is exact
     to ~1e-6.  This is the genuine TopoJSON quantization scheme restricted to
     a single point; it does NOT parse the full TopoJSON object/arc-index
     structure from JSON text (see README). *)
  val step = 1.0E~6

  (* Quantize a real coordinate to the nearest grid integer (kept as a real
     because `arcs` stores reals; the value is integral). *)
  fun quantize x = Real.realRound (x / step)

  fun fromGeoJsonPoint [lon, lat] =
        { transform = SOME (step, step)
        , arcs = [[(quantize lon, quantize lat)]] }
    | fromGeoJsonPoint _ = { transform = NONE, arcs = [] }

  (* Apply the topology's transform to a (quantized) coordinate to recover the
     real-world point.  With no transform the coordinate is already absolute. *)
  fun toGeoJsonPoint ({ transform, ... } : topo) (qx, qy) =
    case transform of
        SOME (sx, sy) => [qx * sx, qy * sy]
      | NONE => [qx, qy]
end
