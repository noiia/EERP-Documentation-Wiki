# ADR-030: Geographic fields: PostGIS, GeoJSON on the wire

**Status**: Accepted — design in [the geo fields spec](https://github.com/noiia/EERP/blob/dev/docs/superpowers/specs/2026-10-09-geo-fields-design.md).
**Date**: 2026-10-10

---

Builds on [ADR-014](014-field-level-group-gating.md) (group gating),
[ADR-025](025-public-access-and-website-identities.md) (public scope) and
[ADR-015](015-search-filter-bar.md) (search filters).

## Context
Records need places, and the database should answer the geographic questions:
1. sort / filter a list by distance ("contacts within 10 km, nearest first");
2. the distance between two records (attendee to event);
3. the website's "events nearest to me";
4. zones: "contacts inside our service zone", "which companies serve this point".

Zones rule out plain lat/lon columns or `earthdistance`; a framework feature must also stay
declarative (a struct tag), tenant-safe and usable by any module.

## Decision
1. **PostGIS, `geography(…, 4326)`.** Distances are in meters on the globe with no projection
   choice for callers. The DB image is `postgis/postgis:18-3.6` (dev, prod, CI); boot runs
   `CREATE EXTENSION IF NOT EXISTS postgis` under the schema advisory lock, before any table DDL
   (boot, `EnsureSchema`, `MigrateModules`, and so dbmanage create/switch).
2. **Two ORM types**, `orm.GeoPoint` (`geography(Point,4326)`) and `orm.GeoShape`
   (`geography(Geometry,4326)`: Polygon, MultiPolygon, LineString). Declared as nullable pointers:
   `` Location *orm.GeoPoint `db:"geo_location,index=gist"` ``.
3. **Text I/O, not a pgx codec.** Values are read as EWKB hex and written as EWKT
   (`SRID=4326;POINT(lon lat)`) through `Scanner`/`Valuer`. A codec would have to be registered
   on the pool's type map, which needs the extension to exist *before* the pool connects and
   re-registration after a dbmanage hot-swap. Text needs neither and no SQL rewriting.
4. **GeoJSON geometry on the wire** (what Leaflet and Nominatim speak). Generic CRUD recognises a
   geo column by its Go type, converts on read, validates and converts on write. Invalid input
   is a **422 `VALIDATION_ERROR`** with the field in `fields`.
5. **List params** on `GET /api/v1/{table}`: `near[col]=lon,lat` (nearest first, rows carry a
   read-only `_distance_m`), `within[col]=lon,lat,meters` (radius), `covers[col]=lon,lat` (zones
   containing a point), `inside[col]=<table>:<id>:<shape col>` (points inside another record's
   zone). Malformed values are **400**; an unusable reference is **404**.
6. **References are authorized in the ORM.** `inside` and the distance endpoint resolve
   `table:id:col` only if the table is registered and not `Excluded`, its module is **active**
   (`orm.SetTableActiveCheck`), the caller can read it (`access.CanRead`, stamped by the
   permission middleware as `<table>:<table>:read`; `core/orm` never imports `auth`), the column
   has the right geo kind and is not group-gated for the caller. Tenant and soft-delete scoping
   sit *inside* the subquery, so a missing or foreign record matches nothing and leaks nothing.
   References are refused (400) on public routes; `near`/`within`/`covers` work there on
   published columns.
7. **`GET /api/v1/geo/distance?from=&to=`** (`internal/geo`, permission `geo:distance:read`)
   returns `{"meters": n|null}` for point/zone pairs, via the same reference resolution.
8. **Frontend:** Leaflet with OSM tiles and a minimal own polygon editor (no API key);
   `geo` field type (`point`, `shape` widgets), computed `distance` widget, search-bar
   Near / Inside / Covers filters. The user's unit system (`units.system`, in
   `/me/preferences` as `unit_system`) picks km or miles.

```mermaid
sequenceDiagram
    participant C as Client
    participant H as CRUD handler
    participant P as Permission middleware
    participant R as crud (resolveGeoRef)
    participant DB as PostgreSQL
    C->>H: GET /api/v1/contact?inside[geo_location]=company:ID:service_zone
    H->>P: route contact:contact:read
    P->>P: stamp access.CanRead (lazy, memoized)
    P->>R: list with the inside param
    R->>R: company registered, module active, readable, shape column, not gated
    R->>DB: WHERE ST_Covers((SELECT service_zone FROM company z WHERE id=$1 AND tenant=$2 AND deleted_at IS NULL), geo_location)
    DB-->>C: rows (an unknown id matches nothing)
```

## Consequences
- **Image switch:** the only deployment step; the data directory format is unchanged. On managed
  Postgres, `CREATE EXTENSION` needs a privileged role (or the extension pre-created).
- **OSM tile policy:** the default tile server is for light use; a heavy deployment must point
  at its own tile provider.
- Group gating, the public scope and tenant pinning apply to geo columns and params unchanged.
  The Redis read cache ([ADR-023](023-optional-redis-query-cache.md)) serves `near`/`within`/
  `covers` reads like any other (keys include the SQL and args), but **never caches a read with
  `inside`**: its result depends on the referenced record's table, whose writes only bump that
  table's generation, so a cached entry would outlive an edited zone. `near` orders by distance
  then primary key, so equal distances (unlocated rows) page stably.
- Not in v1: routing/travel time, drawing lines (stored and shown only), marker clustering,
  reverse geocoding.

## Pitfalls
- GeoJSON and EWKT coordinates are `[lon, lat]`, the reverse of the habitual "lat, lon".
- A point exactly on a zone's boundary is covered (`ST_Covers`, not `ST_Contains`).
- `_distance_m` is computed: never writable, absent without `near`; at most one `near` per request;
  `?distinct=` and `?aggregate=` ignore it.
- A point column without `index=gist` makes `near`/`within` scan the table.
- `inside` is refused on `/api/v1/public`, as it would reference arbitrary records.
- A shape with fewer than 3 vertices in the editor means "no zone" (`null`).
- Tree grids never render geo columns; keep geo fields in list descriptors for the search bar.
- Production: the extension is created at boot, but a role without the right cannot do it.
