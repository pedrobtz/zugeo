// Writes tests/testthat/data/hilbert-flatbush.csv: Hilbert keys as flatbush
// v4.7.0 computes them (index.js, ISC), for test-kernel.R to compare
// geo_hilbert() with. The hilbert() function is taken from flatbush's own
// source, not rewritten; the grid mapping is finish()'s, line for line.
// Run from the package root with node and flatbush's index.js at
// $FLATBUSH (https://github.com/mourner/flatbush/blob/v4.7.0/index.js):
//
//   FLATBUSH=/path/to/index.js node tools/make-hilbert-fixture.js
const fs = require('fs');
const src = fs.readFileSync(process.env.FLATBUSH, 'utf8');
const m = src.match(/function hilbert\(x, y\) \{[\s\S]*?\n\}/);
if (!m) throw new Error('hilbert() not found in flatbush source');
const hilbert = new Function(m[0] + '\nreturn hilbert;')();

// A small linear congruential generator, so the fixture is reproducible.
let seed = 20261107;
function rand() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }

const n = 400;
const boxes = [];
for (let i = 0; i < n; i++) {
  const x = (rand() - 0.5) * 360, y = (rand() - 0.5) * 180;
  const w = rand() * 5, h = rand() * 5;
  boxes.push([x, y, x + w, y + h]);
}
boxes.push([3, 3, 3, 3]); // a point
let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
for (const b of boxes) {
  minX = Math.min(minX, b[0]); minY = Math.min(minY, b[1]);
  maxX = Math.max(maxX, b[2]); maxY = Math.max(maxY, b[3]);
}
// finish():
const width = (maxX - minX) || 1;
const height = (maxY - minY) || 1;
const hilbertMax = (1 << 16) - 1;
const sx = hilbertMax / width;
const sy = hilbertMax / height;
const lines = ['xmin,ymin,xmax,ymax,key'];
for (const [x0, y0, x1, y1] of boxes) {
  const x = (sx * ((x0 + x1) / 2 - minX)) | 0;
  const y = (sy * ((y0 + y1) / 2 - minY)) | 0;
  // flatbush shifts by -2^31 for small integers; undo it for the unsigned key.
  const key = hilbert(x, y) + 0x80000000;
  lines.push([x0, y0, x1, y1].map((v) => v.toPrecision(17)).join(',') + ',' + key);
}
fs.writeFileSync('tests/testthat/data/hilbert-flatbush.csv', lines.join('\n') + '\n');
console.log('wrote', boxes.length, 'keys');
