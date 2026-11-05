// `npm run verify:measure`: tablice ishoda provjere citata nad 5 fixturea
// (simulirani pravi citati, odluka 212) i poravnanja titla s words.json.
// Bez mreže i bez modela.
import { formatAlignment, formatTable, loadFixtureCues, MEASURE_FIXTURES, tally, wordsAlignment } from './measure.js';

const rows = [];
const align = [];
for (const f of MEASURE_FIXTURES) {
  const cues = await loadFixtureCues(f);
  rows.push(...tally(f.id, cues));
  align.push(wordsAlignment(f.id, cues));
}
console.log(formatTable(rows));
console.log('');
console.log(formatAlignment(align));
