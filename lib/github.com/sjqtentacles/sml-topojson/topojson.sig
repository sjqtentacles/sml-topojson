signature TOPOJSON =
sig
  (* A point is a (longitude, latitude) pair of reals. *)
  type point = real * real

  (* A TopoJSON transform: quantized integer coordinates q are mapped back to
     real coordinates by  x = q_x * scaleX + translateX,  y = q_y * scaleY + ty.
     Stored as reals; the quantized values are integral. *)
  type transform = { scale : real * real, translate : real * real }

  (* A topology: an optional transform plus a list of arcs.  Each arc is a list
     of quantized (delta-encoded on the wire, absolute here after decode) points. *)
  type topo = { transform : transform option, arcs : (real * real) list list }

  (* ---- transforms ---- *)

  (* Apply a transform to a single quantized point -> real point. *)
  val applyTransform   : transform -> (real * real) -> point
  (* Inverse: real point -> quantized integral point (rounded). *)
  val untransform      : transform -> point -> (real * real)

  (* Compute a transform from a bounding box {min,max} and a quantum q (the
     number of grid steps along each axis, e.g. 1e4).  Mirrors TopoJSON's
     `transform` computation: scale = (maxx-minx)/(q-1), translate = min. *)
  val computeTransform : { min : point, max : point } -> int -> transform

  (* ---- arc delta-encoding ---- *)

  (* Encode an arc (absolute quantized points) as a delta-encoded arc: the first
     point is absolute, each subsequent point is the difference from the prior. *)
  val quantizeArc   : (real * real) list -> (real * real) list
  (* Inverse of quantizeArc: reconstruct absolute points from deltas. *)
  val dequantizeArc : (real * real) list -> (real * real) list

  (* ---- geometry encode/decode ---- *)

  (* Build a single-point topology from a GeoJSON [lon,lat]. *)
  val fromGeoJsonPoint : real list -> topo
  (* Recover a real [lon,lat] from a quantized point under the topo transform. *)
  val toGeoJsonPoint   : topo -> (real * real) -> real list

  (* Encode a GeoJSON LineString (a list of [lon,lat]) into a topology with one
     delta-encoded arc, using a transform computed from the line's bbox + q. *)
  val fromGeoJsonLine  : int -> real list list -> topo
  (* Decode the (single) arc of a topology back into [lon,lat] points. *)
  val toGeoJsonLine    : topo -> real list list

  (* Polygon = a list of rings, each ring a list of [lon,lat]; ring is closed. *)
  val fromGeoJsonPolygon : int -> real list list list -> topo
  val toGeoJsonPolygon   : topo -> real list list list

  (* ---- shared-arc deduplication ---- *)

  (* Given a list of line geometries (each a point list), extract the distinct
     arcs and return (arcs, indices) where indices[i] is the list of arc indices
     (into `arcs`) that reconstruct line i.  Identical arcs are shared. *)
  val extractArcs   : (real * real) list list -> (real * real) list list * int list list
  (* Reconstruct line geometries from (arcs, indices). *)
  val reconstruct   : (real * real) list list * int list list -> (real * real) list list
end
