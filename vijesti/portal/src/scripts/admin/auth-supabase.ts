// Produkcijska prijava: Supabase Auth (GoTrue na api.domovina.ai), poveznica
// e-poštom ili Google. JWT sesije ide u PostgREST; uloga se provjerava u bazi
// (`vijesti.staff`), ne u klijentu. Povratni URL mora biti dopušten u GoTrue
// postavkama (S7).
import { createClient } from '@supabase/supabase-js';
import type { AuthApi, AuthConfig } from './auth.js';

export function createSupabaseAuth(cfg: AuthConfig): AuthApi {
  const sb = createClient(cfg.authUrl, cfg.anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'pkce' },
  });
  return {
    async session() {
      const { data } = await sb.auth.getSession();
      const s = data.session;
      return s ? { token: s.access_token, userId: s.user.id, email: s.user.email ?? null } : null;
    },
    async signOut() {
      await sb.auth.signOut();
    },
    renderLogin(container) {
      container.replaceChildren();
      const form = document.createElement('form');
      form.className = 'login';
      form.dataset.testid = 'login-form';
      const h = document.createElement('h2');
      h.textContent = 'Prijava urednika';
      const label = document.createElement('label');
      label.textContent = 'E-pošta ';
      const input = document.createElement('input');
      input.type = 'email';
      input.required = true;
      input.autocomplete = 'email';
      label.append(input);
      const send = document.createElement('button');
      send.type = 'submit';
      send.textContent = 'Pošalji poveznicu za prijavu';
      const google = document.createElement('button');
      google.type = 'button';
      google.textContent = 'Prijava Google računom';
      const msg = document.createElement('p');
      msg.setAttribute('role', 'status');
      const redirectTo = location.origin + location.pathname;
      form.addEventListener('submit', (e) => {
        e.preventDefault();
        void sb.auth
          .signInWithOtp({ email: input.value.trim(), options: { emailRedirectTo: redirectTo, shouldCreateUser: false } })
          .then(({ error }) => {
            msg.textContent = error
              ? `Prijava nije uspjela: ${error.message}`
              : 'Poslali smo ti poveznicu za prijavu. Otvori je u ovom pregledniku.';
          });
      });
      google.addEventListener('click', () => {
        void sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo } });
      });
      form.append(h, label, send, google, msg);
      container.append(form);
    },
  };
}
