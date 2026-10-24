// Flags comment blocks over one line, or lines over MAX_WIDTH, in non-test sources.
// Keeps comments to a short why; part of `pnpm verify`.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const dir = join(import.meta.dirname, "..", "src");
const files = readdirSync(dir, { recursive: true }).filter(
  (f) => f.endsWith(".ts") && !f.endsWith(".test.ts") && !f.endsWith(".d.ts"),
);
const isComment = (l) => /^\s*(\/\/|\/\*|\*)/.test(l);
// One line is only short if it is also narrow.
const MAX_WIDTH = 100;

let problems = 0;
for (const file of files) {
  const lines = readFileSync(join(dir, file), "utf8").split("\n");
  for (let i = 0; i < lines.length; i += 1) {
    if (!isComment(lines[i])) continue;
    let end = i;
    while (end + 1 < lines.length && isComment(lines[end + 1])) end += 1;
    for (let j = i; j <= end; j += 1) {
      if (lines[j].length > MAX_WIDTH) {
        problems += 1;
        console.log(`src/${file}:${j + 1}  comment line is ${lines[j].length} chars, max is ${MAX_WIDTH}:`);
        console.log(`    ${lines[j].trim()}`);
      }
    }
    if (end > i) {
      problems += 1;
      console.log(`src/${file}:${i + 1}  ${end - i + 1}-line comment, max is 1:`);
      for (let j = i; j <= end; j += 1) console.log(`    ${lines[j].trim()}`);
    }
    i = end;
  }
}
console.log(problems ? `\n${problems} comment problem(s).` : `Comments OK: one line each, at most ${MAX_WIDTH} chars.`);
process.exit(problems ? 1 : 0);
