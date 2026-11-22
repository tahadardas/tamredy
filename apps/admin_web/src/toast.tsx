import {useSyncExternalStore} from 'react';

type Toast = {id: number; kind: 'error' | 'ok'; text: string};
let items: Toast[] = [];
let seq = 0;
const subs = new Set<() => void>();
const emit = () => subs.forEach(f => f());

function push(kind: Toast['kind'], text: string) {
  if (items.some(t => t.text === text)) return; // the same message is never stacked twice
  const id = ++seq;
  items = [...items, {id, kind, text}].slice(-4);
  emit();
  window.setTimeout(() => dismiss(id), kind === 'error' ? 9000 : 4000);
}
function dismiss(id: number) { items = items.filter(t => t.id !== id); emit(); }

/** Clear, visible messages for every failure or success (replaces silent failures and browser alerts). */
export const toast = {error: (text: string) => push('error', text), ok: (text: string) => push('ok', text)};

export function ToastHost() {
  const list = useSyncExternalStore(f => { subs.add(f); return () => { subs.delete(f); }; }, () => items);
  return <div className="toasts" role="status" aria-live="polite">
    {list.map(t => <div key={t.id} className={'toast ' + t.kind} onClick={() => dismiss(t.id)}>
      <b>{t.kind === 'error' ? '⚠ ' : '✓ '}</b>{t.text}
    </div>)}
  </div>;
}
