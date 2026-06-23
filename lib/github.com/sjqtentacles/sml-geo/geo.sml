(* geo.sml

   GeoJSON (RFC 7946) typed geometry model, parser, serializer, and
   bounding-box computation. Built on the vendored sml-json. *)

structure GeoJson :> GEO =
struct
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

  datatype 'a result = Ok of 'a | Err of string

  (* ======================================================================
   * Parser
   * ====================================================================== *)

  open Json

  (* Helper: look up a key in a JObj, returning the first match. *)
  fun lookup (kvs, key) =
      case List.find (fn (k, _) => k = key) kvs of
          SOME (_, v) => SOME v
        | NONE => NONE

  (* Parse a single position: a JSON array of numbers (>= 2 elements). *)
  fun parsePos v =
      case v of
          JArr xs =>
            let
              val coords = List.map parseNum xs
            in
              if List.length coords < 2
              then raise Fail "position must have at least 2 coordinates"
              else coords
            end
        | _ => raise Fail "position must be an array"

  (* Parse a number (JInt or JReal) as a real. *)
  and parseNum v =
      case v of
          JInt n => Real.fromInt n
        | JReal r => r
        | _ => raise Fail "expected a number"

  (* Parse a position list (for MultiPoint, LineString, ring). *)
  and parsePosList v =
      case v of
          JArr xs => List.map parsePos xs
        | _ => raise Fail "expected an array of positions"

  (* Parse a list of position lists (for MultiLineString, Polygon rings). *)
  and parsePosListList v =
      case v of
          JArr xs => List.map parsePosList xs
        | _ => raise Fail "expected an array of position arrays"

  (* Parse a list of lists of position lists (for MultiPolygon). *)
  and parsePosListListList v =
      case v of
          JArr xs => List.map parsePosListList xs
        | _ => raise Fail "expected an array of polygon arrays"

  (* Parse a geometry value, given its `type` string and the containing
     object (for extracting `coordinates` or `geometries`). *)
  and parseGeometry (typeStr, obj) =
      case typeStr of
          "Point" =>
            (case lookup (obj, "coordinates") of
                 SOME v => Point (parsePos v)
               | NONE => raise Fail "Point missing coordinates")
        | "MultiPoint" =>
            (case lookup (obj, "coordinates") of
                 SOME v => MultiPoint (parsePosList v)
               | NONE => raise Fail "MultiPoint missing coordinates")
        | "LineString" =>
            (case lookup (obj, "coordinates") of
                 SOME v => LineString (parsePosList v)
               | NONE => raise Fail "LineString missing coordinates")
        | "MultiLineString" =>
            (case lookup (obj, "coordinates") of
                 SOME v => MultiLineString (parsePosListList v)
               | NONE => raise Fail "MultiLineString missing coordinates")
        | "Polygon" =>
            (case lookup (obj, "coordinates") of
                 SOME v => Polygon (parsePosListList v)
               | NONE => raise Fail "Polygon missing coordinates")
        | "MultiPolygon" =>
            (case lookup (obj, "coordinates") of
                 SOME v => MultiPolygon (parsePosListListList v)
               | NONE => raise Fail "MultiPolygon missing coordinates")
        | "GeometryCollection" =>
            (case lookup (obj, "geometries") of
                 SOME (JArr gs) =>
                   GeometryCollection (List.map parseGeometryValue gs)
               | _ => raise Fail "GeometryCollection missing geometries")
        | _ => raise Fail ("unknown geometry type: " ^ typeStr)

  (* Parse a geometry from a JSON object. *)
  and parseGeometryValue v =
      case v of
          JObj kvs =>
            (case lookup (kvs, "type") of
                 SOME (JStr s) => parseGeometry (s, kvs)
               | _ => raise Fail "geometry missing type")
        | _ => raise Fail "geometry must be an object"

  (* Parse a feature. *)
  and parseFeature v =
      case v of
          JObj kvs =>
            let
              val _ =
                  (case lookup (kvs, "type") of
                       SOME (JStr "Feature") => ()
                     | _ => raise Fail "feature type must be \"Feature\"")
              val geometry =
                  case lookup (kvs, "geometry") of
                      SOME JNull => NONE
                    | SOME g => SOME (parseGeometryValue g)
                    | NONE => raise Fail "feature missing geometry"
              val properties =
                  case lookup (kvs, "properties") of
                      SOME p => p
                    | NONE => raise Fail "feature missing properties"
              val id =
                  case lookup (kvs, "id") of
                      SOME (JStr s) => SOME s
                    | SOME (JInt n) => SOME (Int.toString n)
                    | SOME (JReal r) => SOME (Real.toString r)
                    | SOME _ => raise Fail "feature id must be string or number"
                    | NONE => NONE
            in
              Feature
                { geometry = geometry, properties = properties, id = id }
            end
        | _ => raise Fail "feature must be an object"

  (* Parse a top-level GeoJSON value. *)
  and parseTop v =
      case v of
          JObj kvs =>
            (case lookup (kvs, "type") of
                 SOME (JStr "Feature") =>
                   Ok (Feat (parseFeature v))
               | SOME (JStr "FeatureCollection") =>
                   let
                     val features =
                         case lookup (kvs, "features") of
                             SOME (JArr fs) => List.map parseFeature fs
                           | _ => raise Fail "FeatureCollection missing features"
                   in
                     Ok (FeatureCollection features)
                   end
               | SOME (JStr s) =>
                   Ok (Geometry (parseGeometryValue v))
               | _ => raise Fail "top-level value missing type")
        | _ => raise Fail "GeoJSON must be an object"

  fun fromJson v = parseTop v handle Fail msg => Err msg

  (* ======================================================================
   * Serializer
   * ====================================================================== *)

  (* Render a real as JSON. We keep reals as JReal to preserve round-trip
     fidelity (a JSON `102.0` parses to JReal and must serialize back to
     JReal). Integers embedded in GeoJSON are rare; if a caller builds a
     geometry with integer-valued reals, they still serialize as JReal. *)
  fun realToJson r = JReal r

  fun posToJson xs = JArr (List.map realToJson xs)
  fun posListToJson xss = JArr (List.map posToJson xss)
  fun posListListToJson xsss = JArr (List.map posListToJson xsss)
  fun posListListListToJson xssss =
      JArr (List.map posListListToJson xssss)

  fun geometryToJson g =
      case g of
          Point p =>
            JObj [("type", JStr "Point"), ("coordinates", posToJson p)]
        | MultiPoint ps =>
            JObj [("type", JStr "MultiPoint"), ("coordinates", posListToJson ps)]
        | LineString ps =>
            JObj [("type", JStr "LineString"), ("coordinates", posListToJson ps)]
        | MultiLineString pss =>
            JObj [("type", JStr "MultiLineString"),
                  ("coordinates", posListListToJson pss)]
        | Polygon rings =>
            JObj [("type", JStr "Polygon"),
                  ("coordinates", posListListToJson rings)]
        | MultiPolygon polygons =>
            JObj [("type", JStr "MultiPolygon"),
                  ("coordinates", posListListListToJson polygons)]
        | GeometryCollection gs =>
            JObj [("type", JStr "GeometryCollection"),
                  ("geometries", JArr (List.map geometryToJson gs))]

  fun geometryOptToJson NONE = JNull
    | geometryOptToJson (SOME g) = geometryToJson g

  fun featureToJson (Feature {geometry, properties, id}) =
      let
        val base = [("type", JStr "Feature"),
                    ("geometry", geometryOptToJson geometry),
                    ("properties", properties)]
        val withId =
            case id of
                SOME s => ("id", JStr s) :: base
              | NONE => base
      in
        JObj withId
      end

  fun toJson t =
      case t of
          Geometry g => geometryToJson g
        | Feat f => featureToJson f
        | FeatureCollection fs =>
            JObj [("type", JStr "FeatureCollection"),
                  ("features", JArr (List.map featureToJson fs))]

  (* ======================================================================
   * Bounding box
   * ====================================================================== *)

  (* Collect all positions in a geometry, then compute min/max of lon/lat. *)
  fun positions (g : geometry) : pos list =
      case g of
          Point p => [p]
        | MultiPoint ps => ps
        | LineString ps => ps
        | MultiLineString pss => List.concat pss
        | Polygon rings => List.concat rings
        | MultiPolygon polygons =>
            List.concat (List.map List.concat polygons)
        | GeometryCollection gs =>
            List.concat (List.map positions gs)

  fun bbox g =
      let
        val ps = positions g
        fun coord (p, i) = List.nth (p, i)
        val lons = List.map (fn p => coord (p, 0)) ps
        val lats = List.map (fn p => coord (p, 1)) ps
        fun mins (x :: xs) = List.foldl Real.min x xs
          | mins [] = raise Fail "bbox: empty geometry"
        fun maxs (x :: xs) = List.foldl Real.max x xs
          | maxs [] = raise Fail "bbox: empty geometry"
        val minLon = mins lons
        val maxLon = maxs lons
        val minLat = mins lats
        val maxLat = maxs lats
      in
        (minLon, minLat, maxLon, maxLat)
      end
end
