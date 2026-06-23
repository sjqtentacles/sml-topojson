signature TOPOJSON =
sig
  type topo = { transform : (real * real) option, arcs : (real * real) list list }
  val toGeoJsonPoint : topo -> real * real -> real list
  val fromGeoJsonPoint : real list -> topo
end
