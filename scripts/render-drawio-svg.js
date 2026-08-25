#!/usr/bin/env node
/*
 * Render an mxGraph model (draw.io) XML file to a standalone SVG body.
 *
 * Companion to scripts/build-module-diagrams.py, which owns the "which shapes
 * belong to which module" logic and calls this renderer to produce the visible
 * half of each *.drawio.svg file. See that script's header for the full
 * workflow; this file only does model XML -> rendered SVG.
 *
 * WHY THIS EXISTS
 * ---------------
 * A *.drawio.svg file stores the diagram TWICE:
 *
 *   1. the editable mxGraph model, in the root <svg content="..."> attribute
 *   2. the rendered SVG body (<g>/<path>/<image>/... elements) that viewers,
 *      browsers, and GitHub actually display
 *
 * Editing only the embedded model leaves the rendered body showing the OLD
 * topology, which is the single most common way to corrupt these files. There
 * is no pure-Python way to redraw the body, so we drive draw.io's own renderer
 * (mxGraph) in a headless browser and keep the two halves in sync.
 *
 * HOW IT WORKS
 * ------------
 * The page is loaded from the https://app.diagrams.net origin on purpose. Azure
 * shape styles reference icons by relative path (e.g. img/lib/azure2/...), and
 * those only resolve when the document's origin is diagrams.net. After the graph
 * is drawn, every still-remote <image> is fetched and re-embedded as a data URI
 * so the finished file is fully self-contained and renders offline / on GitHub.
 *
 * Two post-processing passes exist purely to match the output that the draw.io
 * desktop/web app produces, so hand-edited and script-generated files stay
 * structurally consistent and diff cleanly:
 *
 *   - the viewer de-duplicates repeated icons into <defs><symbol> + <use>;
 *     we expand those back into plain <image> elements
 *   - the crisp-edges transform="translate(0.5,0.5)" wrapper is KEPT; removing
 *     it was measured to make rendering match the app *worse*, not better
 *
 * PREREQUISITES
 * -------------
 *   - Node.js
 *   - puppeteer (NOT vendored in this repo; it downloads a Chromium build):
 *         mkdir -p /tmp/drawio-render && cd /tmp/drawio-render
 *         npm install puppeteer
 *         export DRAWIO_PUPPETEER_DIR=/tmp/drawio-render
 *     or install it anywhere Node resolves modules from.
 *   - Outbound network access to https://app.diagrams.net (for the viewer
 *     library and the Azure icon set).
 *
 * ENVIRONMENT VARIABLES
 * ---------------------
 *   DRAWIO_PUPPETEER_DIR  directory containing node_modules/puppeteer
 *   DRAWIO_VIEWER_JS      path to a local viewer JS build, pinning the renderer
 *                         instead of loading /js/viewer-static.min.js from the
 *                         diagrams.net origin
 *
 * USAGE
 * -----
 *   node scripts/render-drawio-svg.js <model.xml> <out.svg>
 *
 * Exit codes: 0 ok, 1 render error, 2 puppeteer missing.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DRAWIO_ORIGIN = 'https://app.diagrams.net/';
const VIEWER_URL = '/js/viewer-static.min.js';

function loadPuppeteer() {
  const candidates = [];
  if (process.env.DRAWIO_PUPPETEER_DIR) {
    candidates.push(path.join(process.env.DRAWIO_PUPPETEER_DIR, 'node_modules', 'puppeteer'));
  }
  candidates.push('puppeteer');
  for (const c of candidates) {
    try {
      return require(c);
    } catch (e) {
      /* try the next candidate */
    }
  }
  console.error(
    'ERROR: puppeteer is not installed.\n\n' +
    '  mkdir -p /tmp/drawio-render && cd /tmp/drawio-render\n' +
    '  npm install puppeteer\n' +
    '  export DRAWIO_PUPPETEER_DIR=/tmp/drawio-render\n'
  );
  process.exit(2);
}

/*
 * Runs inside the headless page. `Graph`, `mxUtils`, and `mxCodec` come from the
 * draw.io viewer library injected by the caller.
 */
async function renderInPage(xml) {
  const div = document.createElement('div');
  div.style.position = 'absolute';
  div.style.visibility = 'hidden';
  document.body.appendChild(div);

  const graph = new Graph(div); // eslint-disable-line no-undef
  graph.setEnabled(false);
  const doc = mxUtils.parseXml(xml); // eslint-disable-line no-undef
  new mxCodec(doc).decode(doc.documentElement, graph.getModel()); // eslint-disable-line no-undef
  graph.refresh();

  // getSvg(background, scale, border, nocrop, crisp, ignoreSelection, showText).
  // nocrop=false crops the canvas to the drawn content, so deleting shapes at
  // the edges shrinks the image automatically - no manual size bookkeeping.
  const svg = graph.getSvg('#ffffff', 1, 0, false, false, true, true);

  // Re-embed every remote icon as a data URI so the file is self-contained.
  const cache = new Map();
  for (const img of [...svg.querySelectorAll('image')]) {
    const href = img.getAttribute('xlink:href') || img.getAttribute('href');
    if (!href || href.startsWith('data:')) continue;
    if (!cache.has(href)) {
      const blob = await (await fetch(href)).blob();
      cache.set(href, await new Promise((ok, err) => {
        const r = new FileReader();
        r.onload = () => ok(r.result);
        r.onerror = err;
        r.readAsDataURL(blob);
      }));
    }
    img.setAttribute('xlink:href', cache.get(href));
    img.removeAttribute('href');
  }

  // Expand the viewer's <symbol>/<use> icon de-duplication back into plain
  // <image> elements, matching draw.io's own export structure.
  const symbols = new Map();
  for (const sym of svg.querySelectorAll('defs > symbol')) {
    const inner = sym.querySelector('image');
    if (inner) symbols.set(sym.getAttribute('id'), inner);
  }
  for (const use of [...svg.querySelectorAll('use')]) {
    const ref = (use.getAttribute('xlink:href') || use.getAttribute('href') || '').replace(/^#/, '');
    const inner = symbols.get(ref);
    if (!inner) continue;
    const img = inner.cloneNode(false);
    for (const a of ['x', 'y', 'width', 'height']) {
      if (use.hasAttribute(a)) img.setAttribute(a, use.getAttribute(a));
    }
    use.parentNode.replaceChild(img, use);
  }
  for (const sym of [...svg.querySelectorAll('defs > symbol')]) sym.remove();

  // Inline draw.io's adaptive-background CSS custom property.
  //
  // The viewer emits a <style> block scoped by a RANDOM id on the root <svg>
  // (#ge-svg-XXXX) that defines --ge-adaptive-bg, then references it as
  // var(--ge-adaptive-bg, #ffffff). That random id makes otherwise identical
  // rebuilds differ, producing noisy no-op diffs. draw.io's own file export
  // instead writes the resolved light-dark(...) value inline and emits no
  // <style> block at all, so substituting the value and dropping the block is
  // both exactly equivalent and what the app itself produces.
  const styleEl = svg.querySelector('style');
  if (styleEl) {
    const decl = styleEl.textContent.match(/--ge-adaptive-bg:\s*([^;]+);/);
    if (decl) {
      const value = decl[1].trim();
      for (const el of [...svg.querySelectorAll('[style]')]) {
        const s = el.getAttribute('style');
        if (s.includes('--ge-adaptive-bg')) {
          el.setAttribute('style', s.replace(/var\(--ge-adaptive-bg[^)]*\)/g, value));
        }
      }
    }
    styleEl.remove();
  }
  svg.removeAttribute('id');

  return new XMLSerializer().serializeToString(svg);
}

(async () => {
  const [, , modelPath, outPath] = process.argv;
  if (!modelPath || !outPath) {
    console.error('usage: node scripts/render-drawio-svg.js <model.xml> <out.svg>');
    process.exit(1);
  }

  const puppeteer = loadPuppeteer();
  const model = fs.readFileSync(modelPath, 'utf8');

  const browser = await puppeteer.launch({ args: ['--no-sandbox', '--disable-dev-shm-usage'] });
  try {
    const page = await browser.newPage();
    await page.goto(DRAWIO_ORIGIN, { waitUntil: 'domcontentloaded', timeout: 60000 });

    // Clear the app shell first: we only need the origin (for icon paths) and
    // the mxGraph classes, not the editor UI.
    await page.evaluate(() => { document.body.innerHTML = ''; });
    if (process.env.DRAWIO_VIEWER_JS) {
      await page.addScriptTag({ content: fs.readFileSync(process.env.DRAWIO_VIEWER_JS, 'utf8') });
    } else {
      await page.addScriptTag({ url: VIEWER_URL });
    }
    await page.waitForFunction(
      'typeof Graph !== "undefined" && typeof mxCodec !== "undefined"',
      { timeout: 60000 }
    );

    const svgText = await page.evaluate(renderInPage, model);
    fs.writeFileSync(outPath, svgText);

    const m = svgText.match(/width="(\d+)px"\s+height="(\d+)px"/) || [];
    console.log(`rendered ${path.basename(outPath)} ${m[1] || '?'}x${m[2] || '?'}`);
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(`ERROR: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
