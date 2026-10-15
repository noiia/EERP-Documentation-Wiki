# Geographic Fields

EERP stores locations and zones natively in PostGIS, so "properties within 5 km", "which
delivery zone covers this address" or "leads nearest to me" are plain list-endpoint
parameters, not custom endpoints. Design: [ADR-030](../adrs/030-geographic-fields.md).

## Declaring a geographic column

```go
type Property struct {
    model.BaseModel
    Location *orm.GeoPoint `db:"geo_location,index=gist"` // a point
    Zone     *orm.GeoShape `db:"service_zone,index=gist"` // a polygon / multipolygon
}
```

- Columns are PostGIS `geography` (distances in metres on the globe); boot runs
  `CREATE EXTENSION IF NOT EXISTS postgis` (the dev and CI image is `postgis/postgis`).
- Always nullable pointers; `index=gist` makes spatial filters fast.
- On the wire the value is **GeoJSON**. Invalid geometry → 422.

## Querying from the list endpoint

| Param | Column kind | Meaning |
|---|---|---|
| `near[<point>]=lon,lat` | point | nearest first; each row gets a read-only `_distance_m` |
| `within[<point>]=lon,lat,meters` | point | inside a radius |
| `covers[<shape>]=lon,lat` | shape | zones containing the point |
| `inside[<point>]=<table>:<id>:<shape>` | point | points inside another record's zone |

```http
GET /api/v1/property?within[geo_location]=2.35,48.85,5000&near[geo_location]=2.35,48.85
GET /api/v1/property?inside[geo_location]=delivery_zone:6f1c…:zone
```

They combine with every other filter. A `near[]` ordering takes precedence over `order=`.
Malformed → 400. The `inside[]` reference must be a registered, active, readable, ungated geo
column of the right kind (unusable → 404; a missing or foreign record matches nothing); it is
refused on the public API, and such reads are never cached (their result depends on another
table).

## Distance between two records

`GET /api/v1/geo/distance?from=<table>:<id>:<col>&to=<table>:<id>:<col>` → `{"meters": …}`
(`null` when a side is empty), permission `geo:distance:read`. The ORM resolves and authorizes
both references with the caller's own rights.

## Units and addresses

- The workspace unit system (`GET|PUT /api/v1/settings/units`, `metric` | `imperial`) decides
  whether distances show as km or miles.
- Address search and "Locate from address" go through the OpenStreetMap/Nominatim connector
  (`/api/v1/settings/integrations/osm`), called server-side by the frontend's BFF only — enable
  it and set a real `user_agent` (Nominatim's usage policy requires one).

The map widgets, distance field and the search bar's Near / Inside zone / Covers filters are
described in [Geographic Widgets](../frontend/views-and-components/geo-widgets.md).

## Related

- [ORM](orm.md) · [Settings](settings.md)
