# Snimljeni LLM odgovori

Format: `<ime>.json` = `{"text": "<sirovi izlaz modela>", "usage": {"tokensIn", "tokensOut"}}`,
učitava ih `loadRecordedResponses` (`engine/llm/fake.ts`), a ime je `req.name`.

S1 ne zove Gemini (odluka 6), pa su ove dvije snimke **ručno napisane** u obliku
izlaza modela, nad stvarnim cueom iz `pIx_7N-6HJ4`: `moments-ok` prolazi shemu iz
testa, `moments-invalid` namjerno ne prolazi (`start_ms` je string, `end_ms` fali).
Prave snimke nastaju u S2/S3 kroz `npm run eval -- --max-calls N`.
