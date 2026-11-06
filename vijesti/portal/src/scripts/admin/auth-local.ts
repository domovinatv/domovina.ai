// LAŽNA PRIJAVA ZA LOKALNI RAD (odluka 606). Mintira NEPOTPISAN JWT
// (`alg: none`) sa `sub` urednika iz seeda. Prihvaća ga samo lokalni shim;
// pravi PostgREST provjerava potpis i odbija ga. U build ulazi samo uz
// VIJESTI_AUTH_MODE=local.
import { LOCAL_EDITOR_ID } from '../../../dev/ids.js';
import type { AuthApi, Session } from './auth.js';

/** Oznaka po kojoj test traži lažnu prijavu u izlazu builda. */
export const LOCAL_AUTH_MARKER = 'vijesti-lokalna-prijava-bez-potpisa';
const KEY = 'vijesti.localSession';

function b64url(s: string): string {
  let bin = '';
  for (const b of new TextEncoder().encode(s)) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** `header.payload.` bez potpisa. */
export function mintUnsignedJwt(sub: string, nowSec = Math.floor(Date.now() / 1000)): string {
  const header = b64url(JSON.stringify({ alg: 'none', typ: 'JWT' }));
  const payload = b64url(JSON.stringify({ sub, role: 'authenticated', aud: 'authenticated', iat: nowSec, exp: nowSec + 8 * 3600 }));
  return `${header}.${payload}.`;
}

function read(): Session | null {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}

export function createLocalAuth(): AuthApi {
  return {
    session: () => Promise.resolve(read()),
    signOut: () => {
      try {
        localStorage.removeItem(KEY);
      } catch {
        /* privatni prozor */
      }
      return Promise.resolve();
    },
    renderLogin(container, onSignedIn) {
      container.replaceChildren();
      const form = document.createElement('form');
      form.className = 'login';
      form.dataset.auth = LOCAL_AUTH_MARKER;
      form.dataset.testid = 'login-local-form';
      const h = document.createElement('h2');
      h.textContent = 'Lokalna prijava (samo za razvoj)';
      const p = document.createElement('p');
      p.textContent =
        'Token nije potpisan i prihvaća ga samo lokalni shim. Zadani korisnik je urednik iz seeda.';
      const label = document.createElement('label');
      label.textContent = 'Korisnik (uuid) ';
      const input = document.createElement('input');
      input.name = 'sub';
      input.value = LOCAL_EDITOR_ID;
      input.dataset.testid = 'login-local-sub';
      input.size = 38;
      label.append(input);
      const btn = document.createElement('button');
      btn.type = 'submit';
      btn.textContent = 'Prijavi se';
      btn.dataset.testid = 'login-local';
      form.append(h, p, label, btn);
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        const sub = input.value.trim();
        const s: Session = { token: mintUnsignedJwt(sub), userId: sub, email: null };
        try {
          localStorage.setItem(KEY, JSON.stringify(s));
        } catch {
          /* bez trajne sesije */
        }
        onSignedIn();
      });
      container.append(form);
    },
  };
}
