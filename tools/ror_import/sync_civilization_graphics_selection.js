#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

function option(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

const repositoryRoot = path.resolve(__dirname, "..", "..");
const objectsPath = path.resolve(option("--objects", path.join(repositoryRoot, "prototype", "assets", "generated", "objects-catalog.json")));
const graphicsPath = path.resolve(option("--graphics", path.join(repositoryRoot, "prototype", "assets", "generated", "graphics-catalog.json")));
const rosterPath = path.resolve(option("--roster", path.join(repositoryRoot, "prototype", "data", "content_waves", "all_civilizations.json")));
const wavePath = path.resolve(option("--wave", path.join(repositoryRoot, "prototype", "data", "content_waves", "civilizations_1_4.json")));
const selectionPath = path.resolve(option("--selection", path.join(__dirname, "prototype-selection.json")));
const dryRun = process.argv.includes("--dry-run");

const objects = readJson(objectsPath);
const graphics = readJson(graphicsPath).graphics || {};
const roster = readJson(rosterPath);
const wave = readJson(wavePath);
const selectionText = fs.readFileSync(selectionPath, "utf8");
const selection = JSON.parse(selectionText);
const selectedNames = new Set(selection.map((entry) => String(entry.name || "")));

const civilizationIds = (wave.civilizations || []).map((entry) => Number(entry.civilization_id));
const buildingLines = (roster.common_roster_lines || []).filter((entry) => entry.category === "building");
const pending = [];
const reachable = new Set();

function rememberGraphic(value) {
  const graphicId = Number(value);
  if (Number.isInteger(graphicId) && graphicId >= 0) pending.push(graphicId);
}

for (const civilizationId of civilizationIds) {
  for (const line of buildingLines) {
    for (const sourceUnitId of line.source_unit_ids || []) {
      const source = (objects.objects || {})[`${civilizationId}:${sourceUnitId}`];
      if (!source) continue;
      const presentation = source.graphics || {};
      for (const field of ["idle", "move", "attack", "death", "construction"]) rememberGraphic(presentation[field]);
      for (const damage of presentation.damage || []) rememberGraphic(damage.graphic_id);
    }
  }
}

while (pending.length > 0) {
  const graphicId = pending.pop();
  if (reachable.has(graphicId)) continue;
  reachable.add(graphicId);
  const graphic = graphics[String(graphicId)] || {};
  for (const delta of graphic.deltas || []) rememberGraphic(delta.graphic_id);
}

const additions = [];
for (const graphicId of [...reachable].sort((left, right) => left - right)) {
  const graphic = graphics[String(graphicId)] || {};
  const slp = graphic.slp || {};
  const frameCount = Number(slp.frame_count || 0);
  if (!slp.valid || frameCount <= 0 || Number(graphic.slp_id) < 0) continue;
  for (const player of [1, 2]) {
    const name = `graphic_${graphicId}_p${player}`;
    if (selectedNames.has(name)) continue;
    additions.push({
      archive: "graphics",
      id: Number(graphic.slp_id),
      name,
      player,
      frameRange: [0, frameCount - 1],
    });
    selectedNames.add(name);
  }
}

if (!dryRun && additions.length > 0) {
  const closingBracket = selectionText.lastIndexOf("]");
  if (closingBracket < 0) throw new Error(`Selection is not a JSON array: ${selectionPath}`);
  const prefix = selectionText.slice(0, closingBracket).trimEnd();
  const serialized = additions.map((entry) => `  ${JSON.stringify(entry)}`).join(",\n");
  const separator = prefix.endsWith("[") ? "\n" : ",\n";
  fs.writeFileSync(selectionPath, `${prefix}${separator}${serialized}\n]\n`, "utf8");
}

process.stdout.write(`${JSON.stringify({
  wave: path.basename(wavePath),
  civilizations: civilizationIds,
  buildingLines: buildingLines.length,
  reachableGraphics: reachable.size,
  addedSelections: additions.length,
  addedFrames: additions.reduce((total, entry) => total + entry.frameRange[1] + 1, 0),
  dryRun,
})}\n`);
