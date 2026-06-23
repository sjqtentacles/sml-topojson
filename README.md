# sml-topojson

[![CI](https://github.com/sjqtentacles/sml-topojson/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-topojson/actions/workflows/ci.yml)

A minimal [TopoJSON](https://github.com/topojson/topojson-specification)-style
**coordinate quantization** for Standard ML. It converts a GeoJSON point into a
quantized TopoJSON object (integer grid coordinates plus a `transform`) and
back, demonstrating the lossy fixed-precision encoding TopoJSON uses to shrink
coordinates.

## API

```sml
type topo = { transform : (real * real) option
            , arcs : (real * real) list list }

Topojson.fromGeoJsonPoint [lon, lon]   (* quantize -> topo with transform *)
Topojson.toGeoJsonPoint topo (qx, qy)  (* dequantize using the transform *)
```

`fromGeoJsonPoint` divides each coordinate by a fixed `step` (1e-6) and rounds
to the nearest integer; the resulting `transform = SOME (step, step)` records
the scale so `toGeoJsonPoint` can recover the original coordinate by multiplying
back. The round-trip is exact to the quantization grid.

## Scope and limitations

- **Points only.** This handles single points (one-element arcs). It does not
  implement arc delta-encoding, line/polygon topology, shared-arc extraction, or
  the full TopoJSON object model.
- Quantization is **lossy**: coordinates are snapped to a 1e-6 grid (~0.1 m at
  the equator). Values below the grid resolution are not recoverable.
- No JSON serialization — this operates on the in-memory `topo` record.

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
  topojson.sml   quantize / dequantize through a transform
  topojson.mlb
test/
  test.sml       transform capture, integral storage, round-trip
```

## License

MIT. See [LICENSE](LICENSE).
