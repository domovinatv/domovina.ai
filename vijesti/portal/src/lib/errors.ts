// Greške za urednika na hrvatskom (odluka 607): urednička pravila po prefiksu
// koda (`kod: tekst`, odluka 511), ostalo po HTTP statusu.
import { parseEditorialError, type EditorialErrorCode } from '../../../db/editorial.js';
import { RestError } from './rest.js';

const MESSAGES: Record<EditorialErrorCode, string> = {
  forbidden: 'Nemaš ovlasti za ovu radnju.',
  not_found: 'Članak ili verzija ne postoji (možda je obrisan).',
  invalid_transition: 'Članak iz ovog stanja ne može u traženo stanje.',
  invalid_state: 'Članak nije u stanju za ovu radnju.',
  invalid_input: 'Neki unos nije ispravan.',
  invalid_quote: 'Citat se smije pozvati samo na trenutak iz iste epizode koji je prošao provjeru citata.',
  stale_version:
    'U međuvremenu je nastala novija verzija članka. Osvježi članak, pogledaj promjene i ponovi radnju.',
  not_verified: 'Ova verzija još nije prošla automatsku provjeru; odobriti se može tek provjerena verzija.',
  unresolved: 'Prije odobravanja razriješi sve označene rečenice.',
  already_resolved: 'Ta je rečenica već razriješena.',
  channel_not_allowed: 'Kanal ove epizode nije na popisu kanala s pristankom za objavu.',
  last_admin: 'Zadnji administrator se ne može ukloniti.',
  append_only: 'Zapis u dnevniku se ne mijenja.',
  immutable: 'Spremljena verzija se ne mijenja.',
};

export interface HumanError {
  /** Kod uredničke greške ili `null`. */
  code: EditorialErrorCode | null;
  /** Rečenica za urednika. */
  text: string;
  /** Pojedinosti iz baze (npr. popis rečenica), ako postoje. */
  detail: string | null;
}

export function describeError(e: unknown): HumanError {
  const ed = parseEditorialError(e);
  if (ed) return { code: ed.code, text: MESSAGES[ed.code], detail: ed.message || null };
  if (e instanceof RestError) {
    if (e.status === 401 || e.code === 'PGRST303' || e.code === 'PGRST301') {
      return { code: null, text: 'Prijava je istekla ili nije valjana. Prijavi se ponovno.', detail: e.message };
    }
    if (e.status === 403 || e.code === '42501') {
      return { code: null, text: 'Nemaš ovlasti za ovu radnju.', detail: e.message };
    }
    return { code: null, text: 'Poslužitelj je odbio zahtjev.', detail: e.message };
  }
  if (e instanceof Error && (e.name === 'TimeoutError' || e.name === 'AbortError')) {
    return { code: null, text: 'Poslužitelj se ne javlja. Pokušaj ponovno.', detail: null };
  }
  if (e instanceof TypeError) {
    return { code: null, text: 'Poslužitelj nije dostupan. Provjeri vezu i pokušaj ponovno.', detail: e.message };
  }
  return { code: null, text: 'Nešto nije u redu.', detail: e instanceof Error ? e.message : String(e) };
}
