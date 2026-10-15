# Geographic Widgets

The frontend side of [Geographic Fields](../../core/geo.md): map widgets for PostGIS columns, a
distance field, and location filters in the search bar.

## `type: 'geo'`

| Widget | Edits | Value |
|---|---|---|
| `point` (default) | a marker on a Leaflet map (OSM tiles) | GeoJSON `Point` |
| `shape` | a polygon drawn with the built-in editor (fewer than 3 vertices = `null`) | GeoJSON `Polygon` / `MultiPolygon` |

```ts
{ name: 'geo_location', label: 'Location', type: 'geo', widget: 'point',
  widgetOptions: {
    address: 'address',                                         // "Locate from address" uses this address field
    zones: [{ entity: 'delivery_zone', field: 'zone', label: 'Delivery zone' }], // offered to the search bar
  } }
```

- Maps are client-only components.
- `point` has an address search and, with `widgetOptions.address`, a **Locate from address**
  button — both appear only while the OpenStreetMap connector is enabled (Settings → Integrations),
  and go through the BFF (`/api/integrations/osm/*`), never from the browser to Nominatim.
- A form save logs a changed geo field to the chatter as "<label> : changed", never the GeoJSON.

## `type: 'distance'`

```ts
// core/modules/event: how far is the booker from the event?
{ name: 'distance', label: 'Distance', type: 'distance',
  widgetOptions: {
    from: { entity: 'contact', id: 'contact_id', field: 'geo_location' }, // id = a field of this record
    to:   { entity: 'event',   id: 'event_id',   field: 'geo_location' },
  } }
```

Display-only (no column of its own). Read through the BFF `/api/geo/distance` (Go `GET /api/v1/geo/distance`), shown in km or miles
from the workspace unit system (`useUnitStore`, seeded from `/me/preferences`).

## Records in a zone

A one2many relation can list the records whose point lies inside this record's zone, instead of
following a foreign key:

```ts
{ name: 'properties', label: 'Properties in zone', type: 'relation',
  relation: { entity: 'property', kind: 'one2many', inside: { field: 'geo_location', zone: 'zone' } } }
```

It is read-only (there is no link to create).

## Search bar filters

Entities with geo fields get extra filters: **Near** (an address or the browser's position,
optional radius — adds a Distance column from `_distance_m`), **Inside zone of** (from
`widgetOptions.zones`) and **Covers**. Invalid values are dropped client-side, never sent.

## Where geo fields don't render

List grids never show geo columns (they stay in descriptors for the filters), and Kanban cards,
Calendar labels and list tiles skip geo and distance fields.

## Related

- [Geographic Fields (core)](../../core/geo.md) · [Search & Filter Bar](search-filter-bar.md) · [ADR-030](../../adrs/030-geographic-fields.md)
