# sml-topojson

[![CI](https://github.com/sjqtentacles/sml-topojson/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-topojson/actions/workflows/ci.yml)

A [TopoJSON](https://github.com/topojson/topojson-specification)-style
**coordinate quantization and topology toolkit** for Standard ML. It implements
the core encoding TopoJSON uses to shrink geometry: a quantizing `transform`
(scale + translate), delta-encoded arcs, line/polygon encode/decode, and
shared-arc deduplication.

It operates on the in-memory `topo` record (no JSON text parsing — pair it with
`sml-json`/`sml-geo` for that).

## API

```sml
type point     = real * real
type transform = { scale : real * real, translate : real * real }
type topo      = { transform : transform option, arcs : (real * real) list list }

(* transforms: q -> real and real -> q *)
val applyTransform   : transform -> (real * real) -> point
val untransform      : transform -> point -> (real * real)
val computeTransform : { min : point, max : point } -> int -> transform

(* arc delta-encoding *)
val quantizeArc   : (real * real) list -> (real * real) list  (* abs -> deltas *)
val dequantizeArc : (real * real) list -> (real * real) list  (* deltas -> abs *)

(* geometry *)
val fromGeoJsonPoint   : real list -> topo
val toGeoJsonPoint     : topo -> (real * real) -> real list
val fromGeoJsonLine    : int -> real list list -> topo
val toGeoJsonLine      : topo -> real list list
val fromGeoJsonPolygon : int -> real list list list -> topo
val toGeoJsonPolygon   : topo -> real list list list

(* shared-arc dedup *)
val extractArcs : (real*real) list list -> (real*real) list list * int list list
val reconstruct : (real*real) list list * int list list -> (real*real) list list
```

## How it works

TopoJSON stores coordinates as small integers on a grid. A real point `(x,y)`
is recovered from a quantized integer point `q` by

```
x = q_x * scaleX + translateX
y = q_y * scaleY + translateY
```

`computeTransform {min,max} q` derives that transform from a bounding box and a
quantum `q` (number of grid steps per axis): `scale = (max-min)/(q-1)`,
`translate = min`. Arcs are then **delta-encoded** — the first point is
absolute and the rest are deltas — which keeps the integers tiny for dense
lines.

```sml
val line  = [[0.0,0.0],[1.0,1.0],[2.0,0.0],[3.0,3.0]]
val topo  = TopoJson.fromGeoJsonLine 1001 line   (* one delta-encoded arc *)
val back  = TopoJson.toGeoJsonLine topo          (* ~= line, to grid precision *)
```

Shared-arc deduplication collapses identical geometry so it is stored once:

```sml
val (arcs, idx) = TopoJson.extractArcs [shared, other, shared]
(* arcs has 2 entries; idx = [[0],[1],[0]] — line 0 and 2 share arc 0 *)
val lines = TopoJson.reconstruct (arcs, idx)
```

## Scope and limitations

- Quantization is **lossy**: coordinates snap to the grid implied by the
  transform. Round-trips are exact only to grid precision.
- `extractArcs` dedups whole arcs by exact equality; it does not split arcs at
  shared sub-paths (the full spec's junction-cutting) — only identical arcs are
  shared.
- `fromGeoJsonPoint` keeps the legacy fixed 1e-6 grid for single points; line
  and polygon helpers compute a transform from the data's bounding box.
- No JSON serialization — this is the in-memory topology layer.

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-topojson
smlpkg sync
```

Reference from your `.mlb`:

```
lib/github.com/sjqtentacles/sml-topojson/topojson.mlb
```

## Building and testing

```sh
make test        # MLton
make test-poly   # Poly/ML
make all-tests   # both
make clean
```

## Project layout

```
sml.pkg
Makefile
lib/github.com/sjqtentacles/sml-topojson/
  topojson.sig
  topojson.sml   transform, delta arcs, line/polygon, shared-arc dedup
  topojson.mlb
test/
  test.sml       transform round-trip, arc deltas, line+polygon, dedup
```

## License

MIT. See [LICENSE](LICENSE).
