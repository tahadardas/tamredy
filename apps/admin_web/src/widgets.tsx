import {useEffect, useId, useRef, useState, type ReactNode} from 'react';
import {createPortal} from 'react-dom';
import {api} from './session';

export const Modal = ({
  title,
  onClose,
  children,
  maxWidth,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  maxWidth?: string | number;
}) => {
  const titleId = useId();
  const boxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const prevFocused = document.activeElement as HTMLElement | null;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    const focusables = () =>
      Array.from(
        boxRef.current?.querySelectorAll<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
        ) ?? [],
      ).filter(el => !el.hasAttribute('disabled'));

    const initial = focusables()[0] ?? boxRef.current;
    initial?.focus();

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onClose();
        return;
      }
      if (e.key === 'Tab') {
        const list = focusables();
        if (list.length === 0) return;
        const first = list[0];
        const last = list[list.length - 1];
        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault();
          last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };

    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = prevOverflow;
      prevFocused?.focus?.();
    };
  }, [onClose]);

  return createPortal(
    <div className="modal" onClick={onClose} role="dialog" aria-modal="true" aria-labelledby={titleId}>
      <div
        ref={boxRef}
        tabIndex={-1}
        className="modal-box wide"
        style={maxWidth ? {maxWidth} : undefined}
        onClick={e => e.stopPropagation()}
      >
        <div className="modal-head">
          <h2 id={titleId}>{title}</h2>
          <button className="ghost" onClick={onClose} aria-label="إغلاق" type="button">✕</button>
        </div>
        <div className="modal-content">
          {children}
        </div>
      </div>
    </div>,
    document.body
  );
};

/** Shows a secret exactly once (temporary password). */
export const Secret = ({label, value, onClose}: {label: string; value: string; onClose: () => void}) =>
  <Modal title="كلمة المرور المؤقتة" onClose={onClose}>
    <p className="hint">{label} تُعرض مرة واحدة فقط. سلّمها لصاحب الحساب بشكل آمن؛ سيُطلب منه تغييرها عند أول دخول.</p>
    <p className="secret" dir="ltr">{value}</p>
    <div className="actions"><button className="pill on" onClick={() => void navigator.clipboard?.writeText(value)}>نسخ</button><button className="pill" onClick={onClose}>تم</button></div>
  </Modal>;

export function useBusy() {
  const [busy, setBusy] = useState(false); const [err, setErr] = useState('');
  async function run<T>(f: () => Promise<T>): Promise<T | undefined> {
    setBusy(true); setErr('');
    try { return await f(); } catch (e) { setErr((e as Error).message); } finally { setBusy(false); }
  }
  return {busy, err, run, setErr};
}

/** Opens a protected file: fetched with the admin token, shown from a temporary blob URL (never a public link). */
export async function openProtected(path: string) {
  const r = await api(path);
  if (!r.ok) throw new Error('تعذر فتح المستند');
  const url = URL.createObjectURL(await r.blob());
  window.open(url, '_blank', 'noopener');
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
export const fmtDate = (v?: string | null) => v ? new Date(v).toLocaleDateString('ar-SY', {year: 'numeric', month: 'short', day: 'numeric'}) : '—';
