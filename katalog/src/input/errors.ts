/**
 * Ulaz nije onakav kakav ugovor kaže. `path` je putanja do polja u izvornom
 * JSON-u, s izvornim imenima ključeva (`videos[3].date`, `source.title`), da se
 * kvar nađe u datoteci bez čitanja parsera. Korijen je `$`.
 */
export class InputError extends Error {
  override readonly name = "InputError";
  readonly path: string;

  constructor(path: string, message: string) {
    super(`${path}: ${message}`);
    this.path = path;
  }
}
