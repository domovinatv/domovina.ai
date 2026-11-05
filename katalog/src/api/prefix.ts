// Prefiks API-ja v1. Živi u zasebnom modulu, ne u `src/index.ts`: workerd svaki
// imenovani export glavnog modula čita kao entrypoint, pa `export const` ondje
// ruši `wrangler dev` (odluka 312).
export const API_PREFIX = "/api/katalog/v1";
