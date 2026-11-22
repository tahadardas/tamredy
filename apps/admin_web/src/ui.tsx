import type {ReactNode} from 'react';
import {
  Home, MapPin, FileText, Users, Check, Wallet, Star, BarChart3, Settings,
  AlertTriangle, Banknote, Activity, Search, Clock, Plus, Lock, User, Heart,
  Download, RefreshCw, Layers, ShieldCheck, CheckCircle2, XCircle, ArrowUpRight,
  ChevronLeft
} from 'lucide-react';

export const icons: Record<string, typeof Home> = {
  home: Home, map: MapPin, doc: FileText, users: Users, check: Check, wallet: Wallet, star: Star, chart: BarChart3,
  settings: Settings, alert: AlertTriangle, cash: Banknote, pulse: Activity, search: Search, clock: Clock, plus: Plus,
  lock: Lock, user: User, heart: Heart, pin: MapPin, download: Download, refresh: RefreshCw, layers: Layers,
  shield: ShieldCheck, checkCircle: CheckCircle2, xCircle: XCircle, arrow: ArrowUpRight, chevron: ChevronLeft,
};

export const Icon = ({name, size = 18, className = ''}: {name: string; size?: number; className?: string}) => {
  const C = icons[name] ?? Home;
  return <C size={size} strokeWidth={1.8} className={className}/>;
};

export const Chip = ({children, tone = 'default'}: {children: ReactNode; tone?: 'default' | 'success' | 'warn' | 'danger' | 'info' | 'purple'}) => (
  <span className={`chip chip-${tone}`}>{children}</span>
);

export const Stat = ({
  label, value, icon, sub, trend
}: {
  label: string;
  value: string | number;
  icon: string;
  sub?: string;
  trend?: {label: string; up?: boolean};
}) => (
  <div className="stat">
    <div className="stat-top">
      <div className="stat-ic"><Icon name={icon} size={22}/></div>
      {trend && (
        <span className={`stat-trend ${trend.up ? 'trend-up' : 'trend-down'}`}>
          {trend.label}
        </span>
      )}
    </div>
    <span className="stat-label">{label}</span>
    <strong className="stat-val">{value}</strong>
    {sub && <small className="stat-sub">{sub}</small>}
  </div>
);

export const Panel = ({
  title, subtitle, children, className = '', action
}: {
  title?: string;
  subtitle?: string;
  children: ReactNode;
  className?: string;
  action?: ReactNode;
}) => (
  <section className={'panel ' + className}>
    {(title || action) && (
      <div className="panel-head">
        <div>
          {title && <h2>{title}</h2>}
          {subtitle && <p className="panel-sub">{subtitle}</p>}
        </div>
        {action && <div className="panel-action">{action}</div>}
      </div>
    )}
    <div className="panel-body">{children}</div>
  </section>
);

export const Notice = ({children, tone = 'warn'}: {children: ReactNode; tone?: 'warn' | 'info' | 'success' | 'danger'}) => (
  <div className={`notice notice-${tone}`}>
    <div className="notice-ic"><Icon name={tone === 'warn' ? 'alert' : tone === 'info' ? 'pulse' : tone === 'success' ? 'check' : 'alert'} size={18}/></div>
    <div className="notice-body">{children}</div>
  </div>
);

export const Row = ({
  icon, title, sub, chip, chipTone = 'default', action
}: {
  icon: string;
  title: string;
  sub: string;
  chip?: string;
  chipTone?: 'default' | 'success' | 'warn' | 'danger' | 'info' | 'purple';
  action?: ReactNode;
}) => (
  <div className="row">
    <div className="row-ic"><Icon name={icon} size={20}/></div>
    <div className="row-t">
      <b>{title}</b>
      <small>{sub}</small>
    </div>
    {chip && <Chip tone={chipTone}>{chip}</Chip>}
    {action && <div className="row-act">{action}</div>}
  </div>
);

export const Table = ({
  head, rows, emptyMessage = 'لا توجد بيانات متاحة'
}: {
  head: string[];
  rows: ReactNode[][];
  emptyMessage?: string;
}) => (
  <div className="table-wrap">
    <table>
      <thead>
        <tr>{head.map(h => <th key={h}>{h}</th>)}</tr>
      </thead>
      <tbody>
        {rows.length === 0 ? (
          <tr>
            <td colSpan={head.length} className="table-empty">{emptyMessage}</td>
          </tr>
        ) : (
          rows.map((r, i) => <tr key={i}>{r.map((c, j) => <td key={j}>{c}</td>)}</tr>)
        )}
      </tbody>
    </table>
  </div>
);

export const MapArt = ({height = 250}: {height?: number}) => (
  <div className="mapart" style={{height}}>
    <svg viewBox="0 0 400 250" preserveAspectRatio="none">
      <rect width="400" height="250" fill="#e8f1ee"/>
      <g stroke="#fff" strokeWidth="14" strokeLinecap="round">
        <path d="M40 0 L100 250"/>
        <path d="M200 0 L230 250"/>
        <path d="M0 60 L400 30"/>
        <path d="M0 140 L400 190"/>
      </g>
      <rect x="60" y="50" width="56" height="36" rx="18" fill="#cfe6da"/>
      <rect x="290" y="160" width="52" height="52" rx="24" fill="#cfe6da"/>
      <path d="M250 80 C200 80 140 100 165 150 C190 190 280 140 255 95" fill="none" stroke="#0a87b8" strokeWidth="3" strokeDasharray="8 6"/>
      <circle cx="250" cy="76" r="15" fill="#074577" stroke="#fff" strokeWidth="2"/>
      <circle cx="105" cy="140" r="15" fill="#079d90" stroke="#fff" strokeWidth="2"/>
      <text x="60" y="40" fill="#7891a3" fontSize="12" fontWeight="700">المزة</text>
      <text x="300" y="235" fill="#7891a3" fontSize="12" fontWeight="700">دمشق</text>
    </svg>
    <div className="map-tag"><Chip tone="info">مسار توضيحي</Chip><small>2.4 كم</small></div>
  </div>
);
