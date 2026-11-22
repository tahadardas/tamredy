import { HttpException, Injectable } from '@nestjs/common';

export interface RouteResult { distanceMeters: number; durationSeconds: number; polyline: string; }
export type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{ ok: boolean; status: number; json(): Promise<any> }>;
type Pt = { lat: number; lng: number };

/** Driving route + ETA behind the server, so no key ever ships in an app.
 *  MAPS_PROVIDER=osm (default): OpenRouteService (free key, no card).
 *  MAPS_PROVIDER=google: Google Routes API (needs a billing account).
 *  Results are cached 30 s per rounded origin/destination to stay inside quotas. */
@Injectable()
export class RoutesService {
  private cache = new Map<string, { at: number; value: RouteResult }>();
  fetchImpl: FetchLike = (u, i) => fetch(u, i) as any;
  now = () => Date.now();

  async compute(origin: Pt, dest: Pt): Promise<RouteResult> {
    const provider = (process.env.MAPS_PROVIDER ?? 'osm') === 'google' ? 'google' : 'osm';
    const key = provider === 'google' ? process.env.GOOGLE_MAPS_SERVER_KEY : process.env.ORS_API_KEY;
    if (!key) throw new HttpException({ code: 'ROUTES_NOT_CONFIGURED', provider }, 503);
    const r4 = (n: number) => n.toFixed(4); // ~11 m: near-identical requests share a route
    const ck = `${provider}:${r4(origin.lat)},${r4(origin.lng)}>${r4(dest.lat)},${r4(dest.lng)}`;
    const hit = this.cache.get(ck);
    if (hit && this.now() - hit.at < 30_000) return hit.value;
    const value = provider === 'google' ? await this.google(key, origin, dest) : await this.ors(key, origin, dest);
    if (this.cache.size > 500) this.cache.clear();
    this.cache.set(ck, { at: this.now(), value });
    return value;
  }

  private async ors(key: string, o: Pt, d: Pt): Promise<RouteResult> {
    const base = process.env.ORS_BASE_URL ?? 'https://api.heigit.org/openrouteservice';
    const res = await this.fetchImpl(`${base}/v2/directions/driving-car`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: key },
      body: JSON.stringify({ coordinates: [[o.lng, o.lat], [d.lng, d.lat]], instructions: false }), // [lng,lat] order
    });
    if (!res.ok) throw new HttpException({ code: 'ROUTES_UPSTREAM_ERROR', status: res.status }, 502);
    const route = (await res.json()).routes?.[0];
    if (!route?.geometry || typeof route.geometry !== 'string') throw new HttpException({ code: 'ROUTE_NOT_FOUND' }, 404);
    return {
      distanceMeters: Math.round(Number(route.summary?.distance ?? 0)),
      durationSeconds: Math.round(Number(route.summary?.duration ?? 0)),
      polyline: route.geometry, // encoded polyline, precision 1e5 (same as Google)
    };
  }

  private async google(key: string, o: Pt, d: Pt): Promise<RouteResult> {
    const res = await this.fetchImpl('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline' },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: o.lat, longitude: o.lng } } },
        destination: { location: { latLng: { latitude: d.lat, longitude: d.lng } } },
        travelMode: 'DRIVE', routingPreference: 'TRAFFIC_AWARE', languageCode: 'ar', units: 'METRIC',
      }),
    });
    if (!res.ok) throw new HttpException({ code: 'ROUTES_UPSTREAM_ERROR', status: res.status }, 502);
    const route = (await res.json()).routes?.[0];
    if (!route?.polyline?.encodedPolyline) throw new HttpException({ code: 'ROUTE_NOT_FOUND' }, 404);
    return {
      distanceMeters: Number(route.distanceMeters ?? 0),
      durationSeconds: Math.round(parseFloat(String(route.duration ?? '0s'))), // "754s"
      polyline: route.polyline.encodedPolyline,
    };
  }
}
