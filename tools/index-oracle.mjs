// Builds flatbush and kdbush indexes from the same input zugeo indexed, and
// compares them with zugeo's bytes, and their query results with zugeo's
// over the same bytes (design section 9, "Indexes"). Called by
// test-ci-index.R with node, in a directory where flatbush@4.7.0 and
// kdbush@4.1.0 are installed (oracles.yaml installs them):
//
//   node tools/index-oracle.mjs <boxes.csv> <rtree.bin> <kd.bin> <node_size> <kd_node_size>
//
// Prints one JSON object.
import fs from 'fs';
import { createRequire } from 'module';
const require = createRequire(process.cwd() + '/');
const Flatbush = (await import(require.resolve('flatbush'))).default;
const KDBush = (await import(require.resolve('kdbush'))).default;

const [csv, rtreeBin, kdBin, nodeSize, kdNodeSize] = process.argv.slice(2);
const rows = fs.readFileSync(csv, 'utf8').trim().split('\n').slice(1).map((l) => l.split(',').map(Number));

const fb = new Flatbush(rows.length, +nodeSize);
for (const [x0, y0, x1, y1] of rows) fb.add(x0, y0, x1, y1);
fb.finish();
const kd = new KDBush(rows.length, +kdNodeSize);
for (const [x0, y0] of rows) kd.add(x0, y0);
kd.finish();

const ours = fs.readFileSync(rtreeBin);
const oursKd = fs.readFileSync(kdBin);
const same = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)) === 0;

// Queries over zugeo's own bytes, loaded by flatbush and kdbush.
const toAB = (buf) => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
const fb2 = Flatbush.from(toAB(ours));
const kd2 = KDBush.from(toAB(oursKd));
const queries = [[10, 10, 20, 15], [50, 50, 52, 60], [-5, -5, 0, 0], [0, 0, 100, 100]];
const out = {
  rtree_bytes_equal: same(new Uint8Array(fb.data), ours),
  kdtree_bytes_equal: same(new Uint8Array(kd.data), oursKd),
  search: queries.map((q) => fb2.search(...q).map((i) => i + 1).sort((a, b) => a - b)),
  neighbors: fb2.neighbors(50, 50, 5).map((i) => i + 1),
  range: kd2.range(10, 10, 12, 14).map((i) => i + 1).sort((a, b) => a - b),
  within: kd2.within(50, 50, 3).map((i) => i + 1).sort((a, b) => a - b),
};
process.stdout.write(JSON.stringify(out));
