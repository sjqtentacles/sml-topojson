(* geo.sig

   GeoJSON (RFC 7946) typed geometry model with parser, serializer, and
   bounding-box computation.

   The GeoJSON specification (RFC 7946) defines a JSON encoding for geographic
   data. This module provides a typed SML abstract syntax tree mirroring the
   spec's geometry and feature hierarchy, plus conversions to and from the
   `Json.json` value tree supplied by the vendored sml-json library.

   Positions
   ---------
   A `pos` is a list of reals: `[longitude, latitude]` or `[longitude,
   latitude, altitude]`. RFC 7946 section 3.1.1 requires at least two
   elements; the optional altitude is the third. This module does not enforce
   a minimum length at the type level -- a position with fewer than two
   coordinates is a data error, not a type error -- but the parser validates
   on the way in.

   Geometry
   --------
   The seven geometry types of RFC 7946 section 3.1:

     - `Point of pos` -- a single position.
     - `MultiPoint of pos list` -- several positions.
     - `LineString of pos list` -- two or more positions forming a line.
     - `MultiLineString of pos list list` -- several lines.
     - `Polygon of pos list list` -- a linear ring (the exterior boundary)
       plus zero or more interior rings (holes). RFC 7946 section 3.1.6
       requires the first ring to be the exterior; subsequent rings are holes.
     - `MultiPolygon of pos list list list` -- several polygons.
     - `GeometryCollection of geometry list` -- a heterogeneous collection.

   Features and FeatureCollections
   -------------------------------
   A `feature` is `{geometry, properties, id}`: an optional geometry, a JSON
   value for properties (an object, or `JNull` per section 3.2), and an
   optional identifier (string or number, represented here as `string option`
   after stringification). A `FeatureCollection` is a list of features.

   The top-level `t` is the union of a bare geometry, a feature, or a
   feature collection, matching the three valid GeoJSON top-level types.

   Parsing
   -------
   `GeoJsonParser.fromJson` takes a `Json.json` value and validates its
   structure, returning `Ok t` or `Err msg`. The parser checks `type`
   discriminants, coordinate array shapes, and required members. It does
   not validate ring closure (section 3.1.6 requires the first and last
   positions of a ring to be identical) -- that is a data-quality check
   left to the caller.

   Serialization
   -------------
   `GeoJsonSerializer.toJson` produces a `Json.json` value in the canonical
   member order of RFC 7946: `type` first, then `coordinates` (or
   `geometries` for a collection), then `properties`/`geometry`/`features`
   for features and collections.

   Bounding box
   ------------
   `GeoJsonBbox.bbox` computes the bounding box of a geometry as
   `(minLon, minLat, maxLon, maxLat)`, the four-number form of RFC 7946
   section 5. (The eight-number 3D form is not computed; altitude is
   ignored.) *)

signature GEO =
sig
  type pos = real list

  datatype geometry =
      Point of pos
    | MultiPoint of pos list
    | LineString of pos list
    | MultiLineString of pos list list
    | Polygon of pos list list
    | MultiPolygon of pos list list list
    | GeometryCollection of geometry list

  datatype feature = Feature of
      { geometry : geometry option
      , properties : Json.json
      , id : string option }

  datatype t =
      Geometry of geometry
    | Feat of feature
    | FeatureCollection of feature list

  (* ---- Parser ---- *)

  datatype 'a result = Ok of 'a | Err of string

  (* Parse a `Json.json` value as a GeoJSON geometry, feature, or feature
     collection. Validates `type` discriminants and coordinate array shapes.
     Returns `Err msg` on any structural violation. *)
  val fromJson : Json.json -> t result

  (* ---- Serializer ---- *)

  (* Serialize a GeoJSON value to a `Json.json` tree in canonical member
     order: `type` first, then `coordinates`/`geometries`, then the
     feature/collection members. *)
  val toJson : t -> Json.json

  (* ---- Bounding box ---- *)

  (* Compute the bounding box of a geometry as
     `(minLon, minLat, maxLon, maxLat)`. For a `GeometryCollection`, the
     box is the union of the members' boxes. *)
  val bbox : geometry -> real * real * real * real
end
