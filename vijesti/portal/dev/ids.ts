// Stalni identiteti lokalnih podataka (seed, shim, lažna prijava). Nisu tajne:
// lokalni shim ne provjerava potpis, a pravi PostgREST nepotpisan token odbija.

/** Urednik iz seeda (`vijesti.staff`, uloga `editor`). */
export const LOCAL_EDITOR_ID = '11111111-1111-4111-8111-111111111111';
/** Admin iz seeda (vodi `allowed_channels`). */
export const LOCAL_ADMIN_ID = '22222222-2222-4222-8222-222222222222';
/** Prijavljen korisnik bez uloge (vidi isto što i čitatelj). */
export const LOCAL_STRANGER_ID = '33333333-3333-4333-8333-333333333333';
/** Lažni `apikey` koji shim traži (PostgREST/Kong ga traži uvijek). */
export const LOCAL_ANON_KEY = 'lokalni-anon-kljuc';
