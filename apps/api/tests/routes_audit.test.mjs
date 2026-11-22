// Route audit: every controller is registered, and every URL used by the dashboard and the Flutter apps exists on the API.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
process.env.NODE_ENV = 'development';
const root = resolve(import.meta.dirname, '../../..');
const dist = resolve(import.meta.dirname, '../dist');
const walk = (d, ok) => readdirSync(d).flatMap(n => { const p = join(d, n); return statSync(p).isDirectory() ? (n === 'node_modules' || n === '.dart_tool' || n === 'build' ? [] : walk(p, ok)) : ok(p) ? [p] : []; });

const { AppModule } = await import('../dist/app.module.js');
const registered = new Set(Reflect.getMetadata('controllers', AppModule));

const controllerClasses = [];
for (const f of walk(dist, p => p.endsWith('.controller.js'))) {
  const mod = await import('file:///' + f.replace(/\\/g, '/'));
  for (const v of Object.values(mod)) if (typeof v === 'function' && Reflect.getMetadata('path', v) !== undefined) controllerClasses.push(v);
}

test('every controller class is registered in AppModule', () => {
  const missing = controllerClasses.filter(c => !registered.has(c)).map(c => c.name);
  assert.deepEqual(missing, [], `controllers not registered (their routes would 404): ${missing.join(', ')}`);
});

const routes = [];
for (const c of controllerClasses) {
  const base = String(Reflect.getMetadata('path', c)).replace(/^\/|\/$/g, '');
  for (const name of Object.getOwnPropertyNames(c.prototype)) {
    const h = c.prototype[name];
    if (typeof h !== 'function' || Reflect.getMetadata('method', h) === undefined) continue;
    const sub = String(Reflect.getMetadata('path', h) ?? '').replace(/^\/|\/$/g, '');
    const full = '/' + [base, sub].filter(Boolean).join('/');
    routes.push(full.split('/'));
  }
}

// 'x' marks a dynamic segment in the caller (e.g. /assignments/$id/$action); ':id' marks one in the route.
const matches = (url, route) => { const u = url.split('/'); return u.length === route.length && u.every((seg, i) => seg === 'x' || route[i].startsWith(':') || seg === route[i]); };
const norm = u => u.split('?')[0].replace(/\$\{[^}]*\}/g, 'x').replace(/\$\{?[A-Za-z_.]+\}?/g, 'x').replace(/\/+$/, '');
function used(files, re) {
  const out = new Set();
  for (const f of files) for (const m of readFileSync(f, 'utf8').matchAll(re)) out.add(norm(m[1]));
  return [...out].filter(u => u.startsWith('/v1/') && u !== '/v1/auth' && u !== '/v1/admin/x');
}

test('every URL the dashboard calls exists on the API', () => {
  const files = walk(join(root, 'apps/admin_web/src'), p => /\.tsx?$/.test(p));
  const urls = used(files, /[`'"](\/v1\/[^`'"\s]*)[`'"]/g);
  // main.tsx loads its optional panels from a {name: 'path'} map: check each value too.
  const map = readFileSync(join(root, 'apps/admin_web/src/main.tsx'), 'utf8').match(/const paths: Record<string, string> = \{([^}]*)\}/)?.[1] ?? '';
  for (const m of map.matchAll(/'([a-z/\-]+)'/g)) urls.push('/v1/admin/' + m[1]);
  assert.ok(urls.length > 30);
  const unknown = urls.filter(u => !routes.some(r => matches(u, r)));
  assert.deepEqual(unknown, [], `dashboard calls routes that do not exist: ${unknown.join(', ')}`);
});

test('every URL the Flutter apps call exists on the API', () => {
  const files = [...walk(join(root, 'apps'), p => p.endsWith('.dart') && !p.includes('admin_web')), ...walk(join(root, 'packages'), p => p.endsWith('.dart'))];
  const urls = used(files, /'(\/v1\/[^']*)'/g);
  assert.ok(urls.length > 15);
  const unknown = urls.filter(u => !routes.some(r => matches(u, r)));
  assert.deepEqual(unknown, [], `apps call routes that do not exist: ${unknown.join(', ')}`);
});
