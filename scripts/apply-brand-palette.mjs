import { execFileSync } from 'node:child_process';

const [input, output, mode, ...extra] = process.argv.slice(2);
if (!input || !output || input === output || (mode && mode !== '--solid') || extra.length) {
  throw new Error('Usage: node scripts/apply-brand-palette.mjs INPUT.png OUTPUT.png [--solid]');
}

// The app icon uses the light brand purple. Website artwork can use the download button gradient.
const bottom = [0x7c, 0x3a, 0xed];
const top = mode === '--solid' ? bottom : [0x8b, 0x5c, 0xf6];

const [width, height] = execFileSync('magick', ['identify', '-format', '%w %h', input])
  .toString().trim().split(/\s+/).map(Number);
const pixels = execFileSync('magick', [input, '-alpha', 'on', '-depth', '8', 'rgba:-'],
  { maxBuffer: width * height * 4 + 1024 });

// Find the original disc color and its vertical bounds. The white ring, feather,
// background tile and alpha are reused from each native variant.
const histogram = new Map();
let first = height;
let last = 0;
for (let i = 0; i < pixels.length; i += 4) {
  const [red, green, blue, alpha] = pixels.subarray(i, i + 4);
  if (alpha < 240 || red - green < 30 || blue - green < 90 || blue <= red) continue;
  const key = (red << 16) | (green << 8) | blue;
  histogram.set(key, (histogram.get(key) ?? 0) + 1);
  const row = Math.floor(i / (width * 4));
  first = Math.min(first, row);
  last = Math.max(last, row);
}
if (histogram.size === 0 || first === last) throw new Error(`No violet disc found in ${input}`);
const [key] = [...histogram].sort((a, b) => b[1] - a[1])[0];
const source = [key >> 16, (key >> 8) & 255, key & 255];
const sourceChroma = source[2] - source[1];
const sourceHue = (source[0] - source[1]) / sourceChroma;
for (let row = 0; row < height; row++) {
  const progress = Math.max(0, Math.min(1, (row - first) / (last - first)));
  const delta = top.map((start, index) => start + progress * (bottom[index] - start) - source[index]);
  for (let x = 0; x < width; x++) {
    const i = (row * width + x) * 4;
    const chroma = pixels[i + 2] - pixels[i + 1];
    if (pixels[i + 3] === 0 || chroma <= 0) continue;
    const hue = (pixels[i] - pixels[i + 1]) / chroma;
    if (Math.abs(hue - sourceHue) > 0.14) continue;
    const weight = Math.min(1, chroma / sourceChroma);
    for (let channel = 0; channel < 3; channel++) {
      pixels[i + channel] = Math.max(0, Math.min(255, Math.round(pixels[i + channel] + weight * delta[channel])));
    }
  }
}
execFileSync('magick', ['-size', `${width}x${height}`, '-depth', '8', 'rgba:-', '-strip', output], { input: pixels });
