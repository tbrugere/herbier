// MapLibre facade (architecture §8), exposed as globalThis.herbier.map and
// bound by app/bindings/maplibre.ml. Styles and GeoJSON arrive as JSON text;
// Herbier's sources and layers are already in the style (app/geo/style.ml),
// so this file only keeps the last data of each source across setStyle.
import { Map as MaplibreMap, setWorkerUrl } from 'maplibre-gl';

// vendor.js is an IIFE bundle: MapLibre cannot find its worker from
// import.meta.url, so build-web.sh ships it next to index.html.
setWorkerUrl(new URL('maplibre-gl-worker.js', document.baseURI).href);

function applyData(h) {
  for (const [id, data] of Object.entries(h.data)) {
    const source = h.map.getSource(id);
    if (source) source.setData(data);
  }
}

function presentLayers(h, layerIds) {
  return layerIds.filter((id) => h.map.getLayer(id));
}

function distinctIds(features) {
  const ids = [];
  for (const f of features) {
    const id = f.properties && f.properties.id;
    if (typeof id === 'string' && !ids.includes(id)) ids.push(id);
  }
  return ids;
}

export function create(container, { style, lng, lat, zoom, interactive }) {
  const map = new MaplibreMap({
    container,
    style: JSON.parse(style),
    center: [lng, lat],
    zoom,
    interactive,
    attributionControl: { compact: true },
  });
  const h = { map, data: {} };
  map.on('style.load', () => applyData(h));
  return h;
}

export function setStyle(h, styleText) {
  h.map.setStyle(JSON.parse(styleText));
}

export function setData(h, sourceId, geojsonText) {
  const data = JSON.parse(geojsonText);
  h.data[sourceId] = data;
  const source = h.map.getSource(sourceId);
  if (source) source.setData(data);
}

// A finger is wider than a point: a click with nothing under it takes the
// point features whose centre is within TAP_SLOP_PX, nearest first (MapLibre
// orders a box query by paint order, not by distance).
const TAP_SLOP_PX = 22;

function distance(h, point, f) {
  if (!f.geometry || f.geometry.type !== 'Point') return Infinity;
  const p = h.map.project(f.geometry.coordinates);
  return Math.hypot(p.x - point.x, p.y - point.y);
}

function hitsAt(h, point, layers) {
  const exact = h.map.queryRenderedFeatures(point, { layers });
  if (exact.length > 0) return exact;
  const r = TAP_SLOP_PX;
  const box = [
    [point.x - r, point.y - r],
    [point.x + r, point.y + r],
  ];
  return h.map
    .queryRenderedFeatures(box, { layers })
    .map((f) => ({ f, d: distance(h, point, f) }))
    .filter(({ d }) => d <= r)
    .sort((a, b) => a.d - b.d)
    .map(({ f }) => f);
}

export function onClick(h, layerIds, cb) {
  h.map.on('click', (e) => {
    const layers = presentLayers(h, layerIds);
    const features = layers.length === 0 ? [] : hitsAt(h, e.point, layers);
    cb({
      lng: e.lngLat.lng,
      lat: e.lngLat.lat,
      ids: distinctIds(features),
      properties: features.map((f) => JSON.stringify(f.properties || {})),
    });
  });
}

export function onMoveend(h, cb) {
  h.map.on('moveend', () => {
    const c = h.map.getCenter();
    cb({ lng: c.lng, lat: c.lat, zoom: h.map.getZoom() });
  });
}

export function onIdle(h, cb) {
  h.map.on('idle', () => cb());
}

export function onError(h, cb) {
  h.map.on('error', (e) => cb(String((e.error && e.error.message) || e)));
}

export function getCenter(h) {
  const c = h.map.getCenter();
  return { lng: c.lng, lat: c.lat };
}

export function getZoom(h) {
  return h.map.getZoom();
}

export function flyTo(h, lng, lat, zoom) {
  h.map.flyTo({ center: [lng, lat], zoom });
}

export function fitBounds(h, west, south, east, north, padding, maxZoom) {
  h.map.fitBounds([[west, south], [east, north]], { padding, maxZoom });
}

export function renderedIds(h, layerIds) {
  const layers = presentLayers(h, layerIds);
  return layers.length === 0 ? [] : distinctIds(h.map.queryRenderedFeatures({ layers }));
}

export function resize(h) {
  h.map.resize();
}

export function remove(h) {
  h.map.remove();
  h.data = {};
}
