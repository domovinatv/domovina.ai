// Prijava u admin (odluka 606). Način je konstanta zamijenjena pri buildu
// (`__VIJESTI_AUTH_MODE__`), pa produkcijski build lažnu prijavu nema ni kao
// mrtav kod: grana `local` i njezin modul ispadaju (test u portal/test/).

export interface Session {
  /** JWT za `Authorization: Bearer`. */
  token: string;
  userId: string;
  email: string | null;
}

export interface AuthApi {
  /** Trenutna sesija (osvježena ako treba) ili null. */
  session(): Promise<Session | null>;
  signOut(): Promise<void>;
  /** Iscrtaj obrazac prijave; `onSignedIn` kad sesija postoji bez preusmjeravanja. */
  renderLogin(container: HTMLElement, onSignedIn: () => void): void;
}

export interface AuthConfig {
  authUrl: string;
  anonKey: string;
}

export async function loadAuth(cfg: AuthConfig): Promise<AuthApi> {
  if (__VIJESTI_AUTH_MODE__ === 'local') {
    const m = await import('./auth-local.js');
    return m.createLocalAuth();
  }
  const m = await import('./auth-supabase.js');
  return m.createSupabaseAuth(cfg);
}
