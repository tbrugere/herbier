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

export function onClick(h, layerIds, cb) {
  h.map.on('click', (e) => {
    const layers = presentLayers(h, layerIds);
    const features =
      layers.length === 0 ? [] : h.map.queryRenderedFeatures(e.point, { layers });
    cb({ lng: e.lngLat.lng, lat: e.lngLat.lat, ids: distinctIds(features) });
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
