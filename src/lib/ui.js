export const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
export const fmtDate = d => new Date(d).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
export const fmtTime = s => { s = Math.max(0, Math.round(s)); return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); };

export function toast(msg) {
  const el = document.createElement('div');
  el.textContent = msg;
  el.setAttribute('role', 'status');
  el.className = 'fixed bottom-6 left-1/2 z-[100] -translate-x-1/2 rounded-full bg-slate-900 px-5 py-2.5 text-sm font-medium text-white shadow-lg';
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 2200);
}
