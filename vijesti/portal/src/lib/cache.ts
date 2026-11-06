// Cache-Control (odluka 608). Javne stranice: kratko u pregledniku, dulje na
// rubu (`s-maxage`), ispravak i povlačenje S7 čisti purgeom. Admin: nikad.
export const CACHE_LIST = 'public, max-age=60, s-maxage=300, stale-while-revalidate=600';
export const CACHE_ARTICLE = 'public, max-age=60, s-maxage=600, stale-while-revalidate=3600';
export const CACHE_NOT_FOUND = 'public, max-age=0, s-maxage=60';
export const CACHE_ERROR = 'no-store';
export const CACHE_ADMIN = 'no-store';
