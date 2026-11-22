'use strict';

// DE x1 assets use 4.2P containers. Ground diamonds carry direct colour,
// while the standing tree and its ground shadow have separate indexed layers.
function unpack(data) {
  if (data.toString('ascii', 0, 4) !== '4.2P') return data;
  const size = data.readUInt32LE(4);
  if (!size || size > 64 * 1024 * 1024) throw Error('Invalid DE ground sheet size');
  const result = Buffer.alloc(size);
  let input = 8, output = 0;
  function length(n) {
    if (n === 15) {
      let extra;
      do {
        if (input >= data.length) throw Error('Truncated LZ4 length');
        extra = data[input++];
        n += extra;
      } while (extra === 255);
    }
    return n;
  }
  while (input < data.length) {
    const token = data[input++];
    const literals = length(token >> 4);
    if (input + literals > data.length || output + literals > size) throw Error('Invalid LZ4 literal run');
    data.copy(result, output, input, input + literals);
    input += literals;
    output += literals;
    if (input === data.length) break;
    const offset = data.readUInt16LE(input);
    input += 2;
    const count = length(token & 15) + 4;
    if (offset === 0 || offset > output || output + count > size) throw Error('Invalid LZ4 back reference');
    for (let i = 0; i < count; i++, output++) result[output] = result[output - offset];
  }
  if (output !== size) throw Error('Incomplete DE ground sheet');
  return result;
}

function decodeFrame(sheet, header, palette = null) {
  const commands = sheet.readUInt32LE(header), edges = sheet.readUInt32LE(header + 4);
  const width = sheet.readInt32LE(header + 16), height = sheet.readInt32LE(header + 20);
  if (width <= 0 || width > 1024 || height <= 0 || height > 1024) throw Error('Invalid DE frame size');
  const stride = palette ? 1 : 4;
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    let x = sheet.readUInt16LE(edges + y * 4);
    if (x === 0x8000) continue;
    const end = width - sheet.readUInt16LE(edges + y * 4 + 2);
    let p = sheet.readUInt32LE(commands + y * 4);
    while (p < sheet.length) {
      const op = sheet[p++], low = op & 15;
      if (low === 15) break;
      let count;
      if ((op & 3) === 0) count = op >> 2;
      else if ((op & 3) === 1) count = (op >> 2) || sheet[p++];
      else if (low === 2 || low === 3) count = ((op & 0xf0) << 4) + sheet[p++];
      else if (low === 7) count = (op >> 4) || sheet[p++];
      else throw Error('Unexpected DE ground opcode ' + op);
      if (x + count > end) throw Error('DE ground row overrun');
      if ((op & 3) === 1 || low === 3) { x += count; continue; }
      for (let i = 0; i < count; i++, x++) {
        const dst = (y * width + x) * 4;
        if (palette) rgba.set(palette[sheet[p]], dst);
        else {
          rgba[dst] = sheet[p + 2];
          rgba[dst + 1] = sheet[p + 1];
          rgba[dst + 2] = sheet[p];
          rgba[dst + 3] = 255;
        }
        if (low !== 7) p += stride;
      }
      if (low === 7) p += stride;
    }
    if (x !== end) throw Error('Incomplete DE ground row');
  }
  return {width, height, rgba, hotspotX:sheet.readInt32LE(header + 24), hotspotY:sheet.readInt32LE(header + 28)};
}

function terrainFrames(data) {
  const sheet = unpack(data);
  const frames = sheet.readUInt32LE(4);
  if (frames !== 256) throw Error('Expected a 16 × 16 DE ground pattern');
  return Array.from({length: frames}, (_, i) => {
    const header = 32 + i * 32;
    if ((sheet.readUInt32LE(header + 12) & 7) !== 7 || sheet.readInt32LE(header + 16) !== 81 || sheet.readInt32LE(header + 20) !== 41) {
      throw Error('Expected a direct-colour DE x1 ground diamond');
    }
    return decodeFrame(sheet, header);
  });
}

function standingTree(data, paletteData) {
  const sheet = unpack(data);
  const colors = paletteData.toString('utf8').trim().split(/\r?\n/).slice(3).map(line => [...line.trim().split(/\s+/).map(Number), 255]);
  const main = sheet.readUInt32LE(16), shadow = sheet.readUInt32LE(20);
  if (sheet.toString('ascii', 0, 4) !== '4.0X' || sheet.readUInt32LE(main + 12) !== (2 << 16) || colors.length !== 256 || !shadow) {
    throw Error('Expected a nature-palette DE tree with a shadow layer');
  }
  const opacity = Array.from({length:256}, (_, value) => [0, 0, 0, Math.max(0, 255 - value * 4)]);
  return {canopy:decodeFrame(sheet, main, colors), shadow:decodeFrame(sheet, shadow, opacity)};
}

module.exports = {terrainFrames, standingTree};
