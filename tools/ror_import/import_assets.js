#!/usr/bin/env node

/*
 * Minimal read-only asset importer for the original Age of Empires / RoR DRS
 * and SLP 2.x formats. The decoder follows the format documentation and SLP
 * command semantics used by openage. Generated PNG files are local build
 * artifacts and must not be redistributed with the source code.
 */

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const argv = process.argv.slice(2);

const CACHE_SCHEMA_VERSION = 1;
const ASSET_MANIFEST_SCHEMA_VERSION = 2;
const IMPORTER_VERSIONS = Object.freeze({
  slp: "slp-4",
  raw: "raw-1",
  sourceManifest: "source-3",
});

function option(name, fallback = null) {
  const index = argv.indexOf(name);
  return index >= 0 && index + 1 < argv.length ? argv[index + 1] : fallback;
}

function fail(message) {
  console.error(`ror-import: ${message}`);
  process.exit(1);
}

const gameDir = path.resolve(option("--game", ""));
const outputDir = path.resolve(option("--output", "prototype/assets/generated"));
const catalogArchive = option("--catalog");
const selectionPath = option("--selection");
const interfaceInventoryPath = option("--interface-inventory");
const limit = Number.parseInt(option("--limit", "800"), 10);
const gameVersion = option("--game-version", "1.1");

function sha256(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function sha256Buffer(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function cacheKey(components) {
  return sha256Buffer(Buffer.from(JSON.stringify(components), "utf8"));
}

function readJsonIfPresent(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (_error) {
    return fallback;
  }
}

function paletteHash(palette) {
  return sha256Buffer(Buffer.from(JSON.stringify(palette.colors), "utf8"));
}

function cacheComponents(kind, sourceHash, palette, selection) {
  return {
    sourceSha256: sourceHash,
    importerVersion: IMPORTER_VERSIONS[kind],
    schemaVersion: ASSET_MANIFEST_SCHEMA_VERSION,
    palette: palette ? {id: palette.id, sha256: paletteHash(palette)} : {id: "none", sha256: "none"},
    gameVersion,
    selection,
  };
}

function parseDrs(filePath) {
  const data = fs.readFileSync(filePath);
  if (data.length < 64) {
    throw new Error(`${filePath} is too small to be a DRS archive`);
  }

  const tableCount = data.readInt32LE(56);
  const entries = [];
  for (let tableIndex = 0; tableIndex < tableCount; tableIndex += 1) {
    const tablePos = 64 + tableIndex * 12;
    const extension = Buffer.from(data.subarray(tablePos, tablePos + 4))
      .reverse()
      .toString("latin1")
      .trim()
      .toLowerCase();
    const tableOffset = data.readInt32LE(tablePos + 4);
    const fileCount = data.readInt32LE(tablePos + 8);
    for (let index = 0; index < fileCount; index += 1) {
      const entryPos = tableOffset + index * 12;
      entries.push({
        id: data.readInt32LE(entryPos),
        extension,
        offset: data.readInt32LE(entryPos + 4),
        size: data.readInt32LE(entryPos + 8),
      });
    }
  }

  const byKey = new Map(entries.map((entry) => [`${entry.extension}:${entry.id}`, entry]));
  return {
    filePath,
    data,
    entries,
    get(extension, id) {
      const entry = byKey.get(`${extension}:${id}`);
      return entry ? data.subarray(entry.offset, entry.offset + entry.size) : null;
    },
  };
}

function findDrsFiles(name) {
  const result = [];
  for (const folder of [path.join(gameDir, "data2"), path.join(gameDir, "data")]) {
    if (!fs.existsSync(folder)) continue;
    const found = fs.readdirSync(folder).find((file) => file.toLowerCase() === `${name}.drs`);
    if (found) result.push(path.join(folder, found));
  }
  return result;
}

function layerDrs(filePaths) {
  const sources = filePaths.map(parseDrs);
  const byKey = new Map();
  for (const source of sources) {
    for (const entry of source.entries) {
      const key = `${entry.extension}:${entry.id}`;
      if (!byKey.has(key)) byKey.set(key, {...entry, sourcePath: source.filePath, sourceData: source.data});
    }
  }
  return {
    sourceFiles: filePaths,
    entries: [...byKey.values()],
    get(extension, id, sourceFolder = null) {
      if (sourceFolder) {
        const selected = selectLayerSource(sources, sourceFolder);
        return selected ? selected.get(extension, id) : null;
      }
      const entry = byKey.get(`${extension}:${id}`);
      return entry ? entry.sourceData.subarray(entry.offset, entry.offset + entry.size) : null;
    },
  };
}

function normalizedSourcePath(filePath) {
  return path.relative(gameDir, filePath).replaceAll("\\", "/").toLowerCase();
}

function selectLayerSource(sources, selector) {
  const normalized = String(selector).replaceAll("\\", "/").toLowerCase();
  const isExactArchive = normalized.includes("/") || normalized.endsWith(".drs");
  const matches = sources.filter((source) => {
    if (isExactArchive) return normalizedSourcePath(source.filePath) === normalized;
    return path.basename(path.dirname(source.filePath)).toLowerCase() === normalized
      || path.basename(source.filePath).toLowerCase() === normalized;
  });
  if (matches.length > 1) {
    throw new Error(`source selector '${selector}' is ambiguous; use an exact path such as data2/inter_up.drs`);
  }
  return matches[0] || null;
}

function readSlpMetadata(slp) {
  if (slp.length < 64) throw new Error("SLP is too small");
  const version = slp.subarray(0, 4).toString("latin1");
  const frameCount = slp.readInt32LE(4);
  if (frameCount <= 0 || frameCount > 100000 || 32 + frameCount * 32 > slp.length) {
    throw new Error(`invalid SLP frame count ${frameCount}`);
  }
  const frames = [];
  for (let frame = 0; frame < frameCount; frame += 1) {
    const header = 32 + frame * 32;
    frames.push({
      frame,
      width: slp.readInt32LE(header + 16),
      height: slp.readInt32LE(header + 20),
      hotspot: [slp.readInt32LE(header + 24), slp.readInt32LE(header + 28)],
    });
  }
  const dimensions = [...new Set(frames.map((frame) => `${frame.width}x${frame.height}`))].sort();
  return {
    version,
    frameCount,
    dimensions,
    width: frames[0].width,
    height: frames[0].height,
    minWidth: Math.min(...frames.map((frame) => frame.width)),
    maxWidth: Math.max(...frames.map((frame) => frame.width)),
    minHeight: Math.min(...frames.map((frame) => frame.height)),
    maxHeight: Math.max(...frames.map((frame) => frame.height)),
    hotspot: frames[0].hotspot,
  };
}

function classifyInterfaceSprite(id, metadata) {
  const fullScreenDimensions = new Set(["640x480", "800x600", "801x602", "1024x768"]);
  if (metadata.frameCount === 1 && fullScreenDimensions.has(`${metadata.width}x${metadata.height}`)) {
    return {role: "fixed_resolution_background", confidence: "structural", basis: "single frame matches a supported full-screen canvas"};
  }
  if ([50210, 50212, 50214, 50216].includes(id) && metadata.height === 138) {
    return {role: "repeatable_ingame_panel", confidence: "source-reviewed", basis: "known 138px in-game panel family; dimensions verified from SLP"};
  }
  if ([50729, 50730].includes(id) && metadata.frameCount > 32) {
    return {role: "command_technology_object_icon_sheet", confidence: "source-reviewed", basis: "known multi-frame in-game icon family; frame structure verified from SLP"};
  }
  if (id >= 50733 && id <= 50744 && metadata.frameCount === 2 && [640, 800, 1024].includes(metadata.width)) {
    return {role: "fixed_resolution_hud_shell", confidence: "source-reviewed", basis: "two-frame top/bottom HUD shell at a supported source resolution"};
  }
  if (id >= 50713 && id <= 50716 && metadata.frameCount === 4 && metadata.width === 54 && metadata.height === 54) {
    return {role: "square_control_backplate_candidate", confidence: "structural", basis: "four equal 54x54 frames; semantic role and executable composition require observation"};
  }
  if (id >= 50725 && id <= 50728 && metadata.frameCount === 4 && metadata.width === 54 && metadata.height === 31) {
    return {role: "compact_control_family_candidate", confidence: "structural", basis: "four equal 54x31 frames; control role and executable composition require observation"};
  }
  if (id >= 50717 && id <= 50719 && metadata.frameCount === 2 && metadata.width === 72 && metadata.height === 20) {
    return {role: "text_button_backplate_candidate", confidence: "structural", basis: "two equal 72x20 frames; state and context require executable observation"};
  }
  if (id >= 50747 && id <= 50750 && metadata.frameCount === 2 && metadata.width === 108 && metadata.height === 20) {
    return {role: "wide_text_button_backplate_candidate", confidence: "structural", basis: "two equal 108x20 frames; state and context require executable observation"};
  }
  if (id === 50721 && metadata.frameCount === 15 && metadata.maxWidth <= 50 && metadata.maxHeight <= 51) {
    return {role: "command_glyph_sheet_candidate", confidence: "structural", basis: "15 small variable-size frames; glyph meaning and composition require executable observation"};
  }
  if (id === 50745 && metadata.frameCount === 26 && metadata.width === 50 && metadata.height === 7) {
    return {role: "status_strip_family_candidate", confidence: "structural", basis: "26 equal 50x7 frames; health/progress role requires original executable observation"};
  }
  if (metadata.frameCount > 1 && metadata.maxWidth <= 128 && metadata.maxHeight <= 128) {
    return {role: "cursor_button_state_or_decoration", confidence: "structural", basis: "small multi-frame interface sprite"};
  }
  if (metadata.maxWidth <= 160 && metadata.maxHeight <= 160) {
    return {role: "fixed_decoration_or_control", confidence: "structural", basis: "small interface sprite"};
  }
  return {role: "unknown_pending_evidence", confidence: "pending", basis: "requires original executable observation or source mapping"};
}

function interfacePalettePolicy(classification) {
  const ingameRoles = new Set([
    "repeatable_ingame_panel",
    "command_technology_object_icon_sheet",
    "progress_status_strip",
    "fixed_resolution_hud_shell",
    "square_control_backplate_candidate",
    "compact_control_family_candidate",
    "text_button_backplate_candidate",
    "wide_text_button_backplate_candidate",
    "command_glyph_sheet_candidate",
    "status_strip_family_candidate",
    "cursor_button_state_or_decoration",
    "fixed_decoration_or_control",
  ]);
  if (ingameRoles.has(classification.role)) {
    return {mode: "explicit", paletteId: 50500, evidence: "AoE1 in-game art palette; selection must record it explicitly"};
  }
  return {mode: "explicit_pending_evidence", paletteId: null, evidence: "menu/loading palette must be established before runtime use"};
}

function writeInterfaceInventory(filePath, sourceFiles) {
  const records = [];
  for (const sourceFile of sourceFiles) {
    const source = parseDrs(sourceFile);
    const provenance = path.relative(gameDir, sourceFile).replaceAll("\\", "/");
    for (const entry of source.entries.filter((candidate) => candidate.extension === "slp")) {
      const slp = source.get("slp", entry.id);
      try {
        const metadata = readSlpMetadata(slp);
        const classification = classifyInterfaceSprite(entry.id, metadata);
        records.push({
          key: `${provenance.toLowerCase()}:slp:${entry.id}`,
          source: provenance,
          sourceSha256: sha256Buffer(slp),
          id: entry.id,
          extension: "slp",
          byteLength: slp.length,
          ...metadata,
          ...classification,
          palettePolicy: interfacePalettePolicy(classification),
        });
      } catch (error) {
        records.push({
          key: `${provenance.toLowerCase()}:slp:${entry.id}`,
          source: provenance,
          sourceSha256: sha256Buffer(slp),
          id: entry.id,
          extension: "slp",
          byteLength: slp.length,
          role: "invalid_or_unsupported",
          confidence: "machine-error",
          basis: error.message,
          palettePolicy: {mode: "blocked", paletteId: null, evidence: "sprite metadata could not be parsed"},
        });
      }
    }
  }
  records.sort((left, right) => left.source.localeCompare(right.source) || left.id - right.id);
  const duplicateIds = {};
  for (const record of records) {
    const key = String(record.id);
    if (!duplicateIds[key]) duplicateIds[key] = [];
    duplicateIds[key].push(record.source);
  }
  for (const id of Object.keys(duplicateIds)) {
    if (duplicateIds[id].length < 2) delete duplicateIds[id];
  }
  const roleCounts = {};
  for (const record of records) roleCounts[record.role] = (roleCounts[record.role] || 0) + 1;
  const inventory = {
    formatVersion: 1,
    gameVersion,
    sourceRoot: gameDir,
    sourceArchives: sourceFiles.map((sourceFile) => ({
      file: path.relative(gameDir, sourceFile).replaceAll("\\", "/"),
      sha256: sha256(sourceFile),
    })),
    selectionContract: "Use the exact source path and an explicit palette ID; directory-only selectors are rejected when ambiguous.",
    roleCounts,
    duplicateIds,
    records,
  };
  writeFileIfChanged(filePath, Buffer.from(`${JSON.stringify(inventory, null, 2)}\n`, "utf8"));
  return inventory;
}

function parsePalettes(interfac) {
  const candidates = interfac.entries.filter((entry) => entry.extension === "bina");
  const palettes = new Map();

  for (const entry of candidates) {
    const text = entry.sourceData.subarray(entry.offset, entry.offset + entry.size).toString("ascii");
    if (!text.startsWith("JASC-PAL")) continue;
    const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
    const count = Number.parseInt(lines[2], 10);
    const colors = [];
    for (const line of lines.slice(3)) {
      if (line.startsWith("#") || line.startsWith("$")) continue;
      const values = line.split(/\s+/).map(Number);
      if (values.length >= 3 && values.every(Number.isFinite)) {
        colors.push(values.slice(0, 3));
      }
    }
    if (colors.length >= count) {
      palettes.set(entry.id, {id: entry.id, colors: colors.slice(0, count)});
    }
  }
  if (!palettes.has(50500)) throw new Error("base JASC palette 50500 was not found in Interfac.drs");
  return palettes;
}

function paintPixel(rgba, width, x, y, color) {
  if (x < 0 || y < 0 || x >= width || y * width * 4 >= rgba.length) return;
  const offset = (y * width + x) * 4;
  rgba[offset] = color[0];
  rgba[offset + 1] = color[1];
  rgba[offset + 2] = color[2];
  rgba[offset + 3] = color[3];
}

function decodeSlp(slp, palettes, frameIndex = 0, player = 1, paletteOverride = null) {
  if (slp.length < 64) throw new Error("SLP is too small");
  const version = slp.subarray(0, 4).toString("latin1");
  if (version.startsWith("4.")) throw new Error(`SLP ${version} is not an AoE1 2.x sprite`);
  const frameCount = slp.readInt32LE(4);
  if (frameCount <= 0 || frameIndex < 0 || frameIndex >= frameCount) {
    throw new Error(`invalid frame ${frameIndex}/${frameCount}`);
  }

  const header = 32 + frameIndex * 32;
  const commandTable = slp.readUInt32LE(header);
  const outlineTable = slp.readUInt32LE(header + 4);
  const width = slp.readInt32LE(header + 16);
  const height = slp.readInt32LE(header + 20);
  const hotspotX = slp.readInt32LE(header + 24);
  const hotspotY = slp.readInt32LE(header + 28);
  if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
    throw new Error(`invalid SLP dimensions ${width}x${height}`);
  }

  const rgba = Buffer.alloc(width * height * 4);
  const semanticPixels = {
    transparency: 0,
    player_color: 0,
    shadow: 0,
    outline: 0,
    anti_outline: 0,
    palette: 0,
  };
  // palette_offset is an abandoned AoE1 frame-header field. The original
  // executable does not use it; non-default palettes must be selected by the
  // owning asset context.
  const paletteId = paletteOverride || 50500;
  const palette = palettes.get(paletteId) || palettes.get(50500);
  const standard = (value) => {
    const rgb = palette.colors[value] || [255, 0, 255];
    return [rgb[0], rgb[1], rgb[2], 255];
  };
  const playerColor = (value) => {
    // AoE1/RoR SLP player-colour commands carry ten shade indices (0..9).
    // Masking to three bits is an AoK-era assumption: it aliases the two
    // darkest AoE1 shades (8/9) to the two brightest shades (0/1), producing
    // the conspicuous bright speckles on units and buildings.
    const index = 16 * player + value;
    const rgb = palette.colors[index] || [50, 120, 255];
    return [rgb[0], rgb[1], rgb[2], 255];
  };

  for (let row = 0; row < height; row += 1) {
    const edgePos = outlineTable + row * 4;
    const left = slp.readUInt16LE(edgePos);
    const right = slp.readUInt16LE(edgePos + 2);
    if (left === 0x8000 || right === 0x8000) {
      semanticPixels.transparency += width;
      continue;
    }

    semanticPixels.transparency += left + right;

    let x = left;
    let pos = slp.readUInt32LE(commandTable + row * 4);
    let complete = false;
    let guard = 0;
    while (!complete && guard < width * 8 + 4096) {
      guard += 1;
      const command = slp[pos];
      const lowNibble = command & 0x0f;
      const highNibble = command & 0xf0;
      const lowCrumb = command & 0x03;

      const packedCount = (shift) => {
        const packed = command >> shift;
        if (packed !== 0) return packed;
        pos += 1;
        return slp[pos];
      };

      if (lowNibble === 0x0f) {
        complete = true;
      } else if (lowCrumb === 0x00) {
        const count = command >> 2;
        semanticPixels.palette += count;
        for (let index = 0; index < count; index += 1) {
          pos += 1;
          paintPixel(rgba, width, x++, row, standard(slp[pos]));
        }
      } else if (lowCrumb === 0x01) {
        const count = packedCount(2);
        semanticPixels.transparency += count;
        x += count;
      } else if (lowNibble === 0x02) {
        pos += 1;
        const count = (highNibble << 4) + slp[pos];
        semanticPixels.palette += count;
        for (let index = 0; index < count; index += 1) {
          pos += 1;
          paintPixel(rgba, width, x++, row, standard(slp[pos]));
        }
      } else if (lowNibble === 0x03) {
        pos += 1;
        const count = (highNibble << 4) + slp[pos];
        semanticPixels.transparency += count;
        x += count;
      } else if (lowNibble === 0x06) {
        const count = packedCount(4);
        semanticPixels.player_color += count;
        for (let index = 0; index < count; index += 1) {
          pos += 1;
          paintPixel(rgba, width, x++, row, playerColor(slp[pos]));
        }
      } else if (lowNibble === 0x07) {
        const count = packedCount(4);
        semanticPixels.palette += count;
        pos += 1;
        const color = standard(slp[pos]);
        for (let index = 0; index < count; index += 1) paintPixel(rgba, width, x++, row, color);
      } else if (lowNibble === 0x0a) {
        const count = packedCount(4);
        semanticPixels.player_color += count;
        pos += 1;
        const color = playerColor(slp[pos]);
        for (let index = 0; index < count; index += 1) paintPixel(rgba, width, x++, row, color);
      } else if (lowNibble === 0x0b) {
        const count = packedCount(4);
        semanticPixels.shadow += count;
        for (let index = 0; index < count; index += 1) paintPixel(rgba, width, x++, row, [0, 0, 0, 100]);
      } else if (lowNibble === 0x0e) {
        if (highNibble === 0x40 || highNibble === 0x60) {
          const isOutline = highNibble === 0x40;
          semanticPixels[isOutline ? "outline" : "anti_outline"] += 1;
          paintPixel(rgba, width, x++, row, isOutline ? playerColor(0) : [0, 0, 0, 255]);
        } else if (highNibble === 0x50 || highNibble === 0x70) {
          pos += 1;
          const count = slp[pos];
          const isOutline = highNibble === 0x50;
          semanticPixels[isOutline ? "outline" : "anti_outline"] += count;
          const color = isOutline ? playerColor(0) : [0, 0, 0, 255];
          for (let index = 0; index < count; index += 1) paintPixel(rgba, width, x++, row, color);
        }
      } else {
        throw new Error(`unknown SLP command 0x${command.toString(16)} at row ${row}`);
      }
      pos += 1;
    }
  }

  return {version, frameCount, frameIndex, width, height, hotspotX, hotspotY, paletteId: palette.id, semanticPixels, rgba};
}

function runSlpSemanticSelfTest() {
  const slp = Buffer.alloc(96);
  slp.write("2.0N", 0, "latin1");
  slp.writeInt32LE(1, 4);
  slp.writeUInt32LE(68, 32);
  slp.writeUInt32LE(64, 36);
  slp.writeUInt32LE(7, 40);
  slp.writeInt32LE(8, 48);
  slp.writeInt32LE(1, 52);
  slp.writeInt32LE(4, 56);
  slp.writeInt32LE(1, 60);
  slp.writeUInt16LE(0, 64);
  slp.writeUInt16LE(0, 66);
  slp.writeUInt32LE(72, 68);
  Buffer.from([0x04, 3, 0x05, 0x16, 9, 0x1b, 0x4e, 0x6e, 0x17, 4, 0x1a, 8, 0x0f]).copy(slp, 72);

  const colors = Array.from({length: 256}, (_, index) => [index, (index + 1) & 255, (index + 2) & 255]);
  const alternateColors = Array.from({length: 256}, () => [200, 201, 202]);
  const palettes = new Map([
    [50500, {id: 50500, colors}],
    [50507, {id: 50507, colors: alternateColors}],
  ]);
  const decoded = decodeSlp(slp, palettes, 0, 1);
  if (decoded.paletteId !== 50500) {
    throw new Error("unused AoE1 frame palette_offset changed the selected palette");
  }
  const expectedCounts = {transparency: 1, player_color: 2, shadow: 1, outline: 1, anti_outline: 1, palette: 2};
  for (const [name, expected] of Object.entries(expectedCounts)) {
    if (decoded.semanticPixels[name] !== expected) {
      throw new Error(`${name}: expected ${expected}, got ${decoded.semanticPixels[name]}`);
    }
  }
  const alpha = (pixel) => decoded.rgba[pixel * 4 + 3];
  if (alpha(0) !== 255 || alpha(1) !== 0 || alpha(2) !== 255 || alpha(3) !== 100 || alpha(4) !== 255 || alpha(5) !== 255) {
    throw new Error("SLP semantic RGBA output does not match the AoE1 contract");
  }
  const red = (pixel) => decoded.rgba[pixel * 4];
  if (red(2) !== 25 || red(7) !== 24) {
    throw new Error("AoE1 player-colour shades 8/9 were aliased instead of preserving their palette indices");
  }
  console.log("G-004 SLP semantic self-test passed");
}

function runCacheKeySelfTest() {
  const palette = {id: 50500, colors: [[0, 1, 2], [3, 4, 5]]};
  const base = cacheComponents("slp", "source-a", palette, {frame: 2, player: 1});
  const same = cacheComponents("slp", "source-a", palette, {frame: 2, player: 1});
  const changedSource = cacheComponents("slp", "source-b", palette, {frame: 2, player: 1});
  const changedPalette = cacheComponents("slp", "source-a", {id: 50501, colors: palette.colors}, {frame: 2, player: 1});
  if (cacheKey(base) !== cacheKey(same)) throw new Error("identical cache components are not deterministic");
  if (cacheKey(base) === cacheKey(changedSource)) throw new Error("source hash does not invalidate cache key");
  if (cacheKey(base) === cacheKey(changedPalette)) throw new Error("palette does not invalidate cache key");
  const fakeSources = [
    {filePath: path.join(gameDir, "data2", "inter_up.drs")},
    {filePath: path.join(gameDir, "data2", "Interfac.drs")},
    {filePath: path.join(gameDir, "data", "Interfac.drs")},
  ];
  if (normalizedSourcePath(selectLayerSource(fakeSources, "data2/inter_up.drs").filePath) !== "data2/inter_up.drs") {
    throw new Error("exact source archive selector did not preserve provenance");
  }
  let rejectedAmbiguousSelector = false;
  try {
    selectLayerSource(fakeSources, "data2");
  } catch (_error) {
    rejectedAmbiguousSelector = true;
  }
  if (!rejectedAmbiguousSelector) throw new Error("ambiguous source directory selector was accepted");
  console.log("D-001 asset cache key self-test passed");
}

const crcTable = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let value = n;
    for (let bit = 0; bit < 8; bit += 1) value = (value & 1) ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    table[n] = value >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeData = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([typeData, data])));
  return Buffer.concat([length, typeData, data, checksum]);
}

function writePng(filePath, width, height, rgba) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const rows = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y += 1) {
    const destination = y * (width * 4 + 1);
    rows[destination] = 0;
    rgba.copy(rows, destination + 1, y * width * 4, (y + 1) * width * 4);
  }
  const png = Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", zlib.deflateSync(rows, {level: 9})),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
  fs.mkdirSync(path.dirname(filePath), {recursive: true});
  writeFileIfChanged(filePath, png);
}

function writeFileIfChanged(filePath, data) {
  if (fs.existsSync(filePath)) {
    const existing = fs.readFileSync(filePath);
    if (existing.equals(data)) return false;
  }
  fs.writeFileSync(filePath, data);
  return true;
}

const glyphs = {
  "0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
  "2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
  "4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
  "6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
  "8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
  "-": ["000", "000", "111", "000", "000"],
};

function drawLabel(canvas, width, text, x, y, scale = 2) {
  let cursor = x;
  for (const character of String(text)) {
    const glyph = glyphs[character] || glyphs["-"];
    glyph.forEach((row, gy) => [...row].forEach((pixel, gx) => {
      if (pixel === "1") {
        for (let sy = 0; sy < scale; sy += 1) for (let sx = 0; sx < scale; sx += 1) {
          paintPixel(canvas, width, cursor + gx * scale + sx, y + gy * scale + sy, [240, 210, 120, 255]);
        }
      }
    }));
    cursor += 4 * scale;
  }
}

function blitScaled(source, destination, destinationWidth, dx, dy, maxWidth, maxHeight) {
  const scale = Math.min(1, maxWidth / source.width, maxHeight / source.height);
  const width = Math.max(1, Math.round(source.width * scale));
  const height = Math.max(1, Math.round(source.height * scale));
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const sx = Math.min(source.width - 1, Math.floor(x / scale));
      const sy = Math.min(source.height - 1, Math.floor(y / scale));
      const sourceOffset = (sy * source.width + sx) * 4;
      const alpha = source.rgba[sourceOffset + 3] / 255;
      if (alpha === 0) continue;
      const targetOffset = ((dy + y) * destinationWidth + dx + x) * 4;
      for (let channel = 0; channel < 3; channel += 1) {
        destination[targetOffset + channel] = Math.round(source.rgba[sourceOffset + channel] * alpha + destination[targetOffset + channel] * (1 - alpha));
      }
      destination[targetOffset + 3] = 255;
    }
  }
  return {width, height};
}

if (argv.includes("--self-test-slp")) {
	runSlpSemanticSelfTest();
	process.exit(0);
}

if (argv.includes("--self-test-cache")) {
  runCacheKeySelfTest();
  process.exit(0);
}

if (!gameDir || !fs.existsSync(gameDir)) {
  fail("pass a valid original game folder with --game");
}

const archiveFiles = {
  graphics: findDrsFiles("graphics"),
  terrain: findDrsFiles("terrain"),
  interfac: [...findDrsFiles("inter_up"), ...findDrsFiles("interfac")],
  sounds: findDrsFiles("sounds"),
  border: findDrsFiles("border"),
};
if (archiveFiles.interfac.length === 0) fail("Interfac.drs was not found");

const archives = {};
for (const [name, filePaths] of Object.entries(archiveFiles)) {
  if (filePaths.length > 0) archives[name] = layerDrs(filePaths);
}
const palettes = parsePalettes(archives.interfac);

if (interfaceInventoryPath) {
  const absoluteInventoryPath = path.resolve(interfaceInventoryPath);
  const inventory = writeInterfaceInventory(absoluteInventoryPath, archiveFiles.interfac);
  console.log(`inventoried ${inventory.records.length} interface sprites from ${inventory.sourceArchives.length} source archives to ${absoluteInventoryPath}`);
}

fs.mkdirSync(outputDir, {recursive: true});
const sourceManifest = {
  format: 2,
  generatedAt: new Date().toISOString(),
  source: gameDir,
  gameVersion,
  cacheSchemaVersion: CACHE_SCHEMA_VERSION,
  importers: IMPORTER_VERSIONS,
  paletteIds: [...palettes.keys()].sort((left, right) => left - right),
  palettes: Object.fromEntries([...palettes.entries()].map(([id, palette]) => [id, {sha256: paletteHash(palette), colors: palette.colors.length}])),
  archives: Object.fromEntries(Object.entries(archives).map(([name, archive]) => [name, {
    sources: archive.sourceFiles.map((filePath) => ({
      file: path.relative(gameDir, filePath).replaceAll("\\", "/"),
      sha256: sha256(filePath),
    })),
    entries: archive.entries.length,
    types: [...new Set(archive.entries.map((entry) => entry.extension))].sort(),
  }])),
};
fs.writeFileSync(path.join(outputDir, "source-manifest.json"), `${JSON.stringify(sourceManifest, null, 2)}\n`);

if (catalogArchive) {
  const archive = archives[catalogArchive.toLowerCase()];
  if (!archive) fail(`archive '${catalogArchive}' is not available`);
  const entries = archive.entries.filter((entry) => entry.extension === "slp").slice(0, limit);
  const catalogDir = path.join(outputDir, "catalog", catalogArchive.toLowerCase());
  fs.mkdirSync(catalogDir, {recursive: true});
  const cellsPerPage = 80;
  const columns = 8;
  const cellWidth = 128;
  const cellHeight = 120;
  const decodedEntries = [];

  for (let pageStart = 0; pageStart < entries.length; pageStart += cellsPerPage) {
    const pageEntries = entries.slice(pageStart, pageStart + cellsPerPage);
    const rows = Math.ceil(pageEntries.length / columns);
    const canvasWidth = columns * cellWidth;
    const canvasHeight = rows * cellHeight;
    const canvas = Buffer.alloc(canvasWidth * canvasHeight * 4);
    for (let offset = 0; offset < canvas.length; offset += 4) {
      canvas[offset] = 24; canvas[offset + 1] = 31; canvas[offset + 2] = 38; canvas[offset + 3] = 255;
    }

    pageEntries.forEach((entry, index) => {
      const cellX = (index % columns) * cellWidth;
      const cellY = Math.floor(index / columns) * cellHeight;
      drawLabel(canvas, canvasWidth, entry.id, cellX + 5, cellY + 5, 2);
      try {
        const decoded = decodeSlp(archive.get("slp", entry.id), palettes, 0, 1);
        const size = blitScaled(decoded, canvas, canvasWidth, cellX + 8, cellY + 20, cellWidth - 16, cellHeight - 24);
        decodedEntries.push({id: entry.id, frames: decoded.frameCount, width: decoded.width, height: decoded.height, page: Math.floor(pageStart / cellsPerPage) + 1, cell: index, preview: size});
      } catch (error) {
        decodedEntries.push({id: entry.id, error: error.message, page: Math.floor(pageStart / cellsPerPage) + 1, cell: index});
      }
    });
    writePng(path.join(catalogDir, `page-${String(Math.floor(pageStart / cellsPerPage) + 1).padStart(2, "0")}.png`), canvasWidth, canvasHeight, canvas);
  }
  fs.writeFileSync(path.join(catalogDir, "index.json"), `${JSON.stringify(decodedEntries, null, 2)}\n`);
  console.log(`catalogued ${entries.length} ${catalogArchive} sprites in ${catalogDir}`);
}

if (selectionPath) {
  const absoluteSelectionPath = path.resolve(selectionPath);
  const selection = JSON.parse(fs.readFileSync(absoluteSelectionPath, "utf8"));
  const assetCachePath = path.join(outputDir, "asset-cache.json");
  const previousCache = readJsonIfPresent(assetCachePath, {entries: {}});
  const previousEntries = previousCache.entries || {};
  const cacheEntries = {};
  const currentKeys = new Map();
  const selectedNames = new Set(selection.map((item) => item.name));
  const exported = [];
  let cacheHits = 0;
  let cacheMisses = 0;
  for (const item of selection) {
    const archive = archives[item.archive];
    if (!archive) throw new Error(`archive '${item.archive}' is not available`);
    const extension = item.extension || "slp";
	const requestedSource = item.source || null;
    const source = archive.get(extension, item.id, requestedSource);
    if (!source) throw new Error(`${item.archive}:${item.id}.${extension}${requestedSource ? ` in ${requestedSource}` : ""} was not found`);
    const sourceHash = sha256Buffer(source);
    if (extension !== "slp") {
      const filename = `${item.name}.${extension}`;
	  const asset = {name: item.name, file: filename, archive: item.archive, source: requestedSource, id: item.id, extension};
	  const components = cacheComponents("raw", sourceHash, null, {archive: item.archive, id: item.id, extension, source: requestedSource, name: item.name});
      const key = cacheKey(components);
      if (currentKeys.has(filename)) {
        if (currentKeys.get(filename) !== key) throw new Error(`conflicting selection entries write ${filename}`);
        continue;
      }
      currentKeys.set(filename, key);
      const previous = previousEntries[filename];
      if (previous && previous.key === key && fs.existsSync(path.join(outputDir, filename))) {
        cacheHits += 1;
      } else {
        writeFileIfChanged(path.join(outputDir, filename), source);
        cacheMisses += 1;
      }
      asset.fileSha256 = sha256(path.join(outputDir, filename));
      exported.push(asset);
      cacheEntries[filename] = {key, components, asset};
      continue;
    }
    let frames = item.frames;
    if (!frames && item.frameRange) {
      const [first, last] = item.frameRange;
      frames = Array.from({length: last - first + 1}, (_, index) => first + index);
    }
    frames = frames || [item.frame || 0];
    for (const frame of frames) {
      const suffix = frames.length > 1 ? `_${String(frame).padStart(2, "0")}` : "";
      const filename = `${item.name}${suffix}.png`;
      const requestedPaletteId = item.palette || 50500;
      const palette = palettes.get(requestedPaletteId) || palettes.get(50500);
	  const components = cacheComponents("slp", sourceHash, palette, {archive: item.archive, id: item.id, frame, player: item.player || 1, paletteOverride: item.palette || null, source: requestedSource, name: item.name});
      const key = cacheKey(components);
      if (currentKeys.has(filename)) {
        if (currentKeys.get(filename) !== key) throw new Error(`conflicting selection entries write ${filename}`);
        continue;
      }
      currentKeys.set(filename, key);
      const previous = previousEntries[filename];
      let asset;
      if (previous && previous.key === key && previous.asset && fs.existsSync(path.join(outputDir, filename))) {
        asset = previous.asset;
        cacheHits += 1;
      } else {
        let decoded;
        try {
          decoded = decodeSlp(source, palettes, frame, item.player || 1, item.palette || null);
        } catch (error) {
          throw new Error(`failed to decode ${item.name} from ${item.archive}:${item.id}${requestedSource ? ` (${requestedSource})` : ""} frame ${frame}: ${error.message}`);
        }
        writePng(path.join(outputDir, filename), decoded.width, decoded.height, decoded.rgba);
        asset = {name: item.name, file: filename, archive: item.archive, source: requestedSource, id: item.id, frame, frameCount: decoded.frameCount, width: decoded.width, height: decoded.height, hotspot: [decoded.hotspotX, decoded.hotspotY], paletteId: decoded.paletteId, semanticPixels: decoded.semanticPixels};
        cacheMisses += 1;
      }
      asset.fileSha256 = sha256(path.join(outputDir, filename));
      exported.push(asset);
      cacheEntries[filename] = {key, components, asset};
    }
  }
  let staleFilesRemoved = 0;
  for (const entry of fs.readdirSync(outputDir, {withFileTypes: true})) {
    if (!entry.isFile()) continue;
    const sourceFilename = entry.name.endsWith(".import") ? entry.name.slice(0, -7) : entry.name;
    if (currentKeys.has(sourceFilename) || path.extname(sourceFilename).toLowerCase() !== ".png") continue;
    const stem = path.basename(sourceFilename, ".png");
    const numberedFrame = stem.match(/^(.*)_\d+$/);
    const belongsToSelectedAsset = selectedNames.has(stem) || (numberedFrame && selectedNames.has(numberedFrame[1]));
    if (!belongsToSelectedAsset) continue;
    fs.rmSync(path.join(outputDir, entry.name));
    staleFilesRemoved += 1;
  }
  fs.writeFileSync(path.join(outputDir, "assets.json"), `${JSON.stringify(exported, null, 2)}\n`);
  const assetCache = {
    formatVersion: CACHE_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    gameVersion,
    selection: {file: path.basename(absoluteSelectionPath), sha256: sha256(absoluteSelectionPath)},
    stats: {entries: Object.keys(cacheEntries).length, hits: cacheHits, misses: cacheMisses},
    entries: cacheEntries,
  };
  fs.writeFileSync(assetCachePath, `${JSON.stringify(assetCache, null, 2)}\n`);
  console.log(`exported ${exported.length} selected assets to ${outputDir} (${cacheHits} cache hits, ${cacheMisses} misses, ${staleFilesRemoved} stale files removed)`);
}

if (!catalogArchive && !selectionPath) {
  console.log(`wrote source manifest to ${path.join(outputDir, "source-manifest.json")}`);
}
