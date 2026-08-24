#!/usr/bin/env python3
"""Regenerate the per-module architecture diagrams from the root diagram.

Every base module's diagram is derived from the single root diagram
(images/azuresandbox.drawio.svg) so all of them share one canonical topology,
visual language, and set of labels. Refining the root diagram and re-running
this script propagates those refinements everywhere, instead of hand-editing
eight files and letting them drift apart.

THE METHOD (deliberately simple - do not "improve" it without asking)
---------------------------------------------------------------------
For each module:

  1. Read the root diagram's model - ALWAYS live from the working-tree copy of
     images/azuresandbox.drawio.svg, never from a cached or exported snapshot.
     A stale snapshot silently ships module diagrams that are missing the
     latest root refinements.
  2. Retitle the diagram (cell TITLE_CELL_ID) to "Azure Sandbox - <module> module".
  3. Delete every shape that belongs neither to a required module nor to the
     module being drawn, per SCOPES below.
  4. Re-render and write both halves of the *.drawio.svg file.

Geometry is NEVER touched. Deleting shapes leaves whitespace behind, and that
is intentional: shapes stay at the exact coordinates they occupy in the root
diagram, so the diagrams remain visually comparable and the script stays
predictable. Do not add auto-compaction/re-layout.

WHY *.drawio.svg NEEDS SPECIAL HANDLING
---------------------------------------
These files store the diagram twice: the editable mxGraph model in the root
<svg content="..."> attribute, and the rendered SVG body that browsers and
GitHub display. Writing only the model leaves the picture showing the old
topology. This script always rewrites both, delegating the redraw to
scripts/render-drawio-svg.js (draw.io's own renderer, headless).

MAINTAINING THE OWNERSHIP MAP
-----------------------------
SCOPES is keyed by mxGraph cell id. Those ids are stable across ordinary
draw.io edits (moving, restyling, relabelling a shape keeps its id), so the map
normally needs no attention. It DOES need updating when a shape is added to or
removed from the root diagram. To resync:

    ./scripts/build-module-diagrams.py list

prints every cell in the root diagram with its id, kind, geometry and label.
Find the new/changed ids, add them to the right group below, then run
`build` and `verify`. If a whole diagram looks wrong, `list` is the first
thing to check - a shape deleted and re-drawn in draw.io gets a NEW id and
will silently fall out of every scope.

Edge label cells are children of their edge and are handled automatically; they
must not be listed in SCOPES. Likewise, an edge whose source or target is
dropped is removed along with its label.

PREREQUISITES
-------------
  - python3 (standard library only)
  - Node.js + puppeteer, and network access to https://app.diagrams.net
    (see the header of scripts/render-drawio-svg.js for setup)

USAGE
-----
  ./scripts/build-module-diagrams.py list             # dump root diagram cells
  ./scripts/build-module-diagrams.py build            # rebuild all modules
  ./scripts/build-module-diagrams.py build mssql vwan # rebuild only these
  ./scripts/build-module-diagrams.py verify           # integrity-check outputs

`verify` re-reads the generated files and checks that the embedded model
round-trips, that no edge points at a deleted cell, that no cell is parented to
a deleted cell, and - most importantly - that the embedded model and the
rendered body agree (every model label appears in the picture, and the picture
contains no text that is absent from the model). Run it after every build.

Exit codes: 0 ok, 1 a build or verification failed, 2 bad usage.
"""

import base64
import html
import os
import re
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET
import zlib

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT_DIAGRAM = os.path.join(REPO_ROOT, 'images', 'azuresandbox.drawio.svg')
RENDERER = os.path.join(REPO_ROOT, 'scripts', 'render-drawio-svg.js')

# The root diagram's title cell. Retitled per module; see build_model().
TITLE_CELL_ID = '175'
TITLE_WIDTH = '240'

# --------------------------------------------------------------------------
# Shape ownership map.
#
# Groups of mxGraph cell ids, by the Terraform module that provisions them.
# Run `./scripts/build-module-diagrams.py list` to see id -> label.
# --------------------------------------------------------------------------

# Diagram furniture present on every module diagram: the title, the
# subscription and resource-group frames with their scope icons, and the
# Internet cloud.
GLOBAL = {
    149,  # "single azure subscription" frame
    177,  # "rg-sand-dev-xxx" frame
    175,  # title
    152,  # subscription scope icon
    248,  # resource group scope icon
    196,  # Internet cloud
}

# vnet_shared is the hub and is a REQUIRED module, so it appears on every
# diagram: the hub vnet and its subnets/NSGs, the centralized private endpoint
# subnet (with the key vault + Azure Monitor endpoints), the shared services it
# owns, and the bastion ingress / firewall egress flows.
SHARED = {
    180,  # vnet-sand-dev-shared
    186, 188, 192,  # AzureBastionSubnet, bastion host, NSG
    187, 189,       # AzureFirewallSubnet, firewall
    185, 190, 191,  # snet-adds-01, dc/dns (adds1), NSG
    225,            # snet-privatelink-01  (the centralized private endpoint subnet)
    226,            # private endpoint: vault
    236,            # private endpoint: azuremonitor
    181,            # private-link marker on the vnet corner
    155,            # key vault
    154,            # log analytics
    262,            # "network isolated services / private dns zones" frame
    265,            # edge: Internet -> bastion (ingress)
    266,            # edge: Internet <- firewall (inspected egress)
    276,            # edge: services frame -> snet-privatelink-01
}

# vnet_app: the spoke vnet, its subnets/NSGs, jumpwin1 (whose NIC this module
# creates), the services it provisions, and their private endpoints.
VNET_APP = {
    178,            # vnet-sand-dev-app
    164, 167, 169,  # snet-app-01, jumpbox (jumpwin1), NSG
    162, 170,       # snet-db-01, NSG
    165,            # private-link marker on the vnet corner
    156,            # storage
    233,            # container registry
    237,            # app insights
    179,            # private endpoint: blob
    166,            # private endpoint: file
    232,            # private endpoint: registry
    274,            # edge: vnet-app <-> vnet-shared peering
}

JUMPLINUX = {168}        # jumpbox (jumplinux1)
MSSQLWIN = {214}         # SQL VM (mssqlwin1)
MSSQL = {200, 205}       # sql db + its private endpoint
MYSQL = {210, 212}       # mysql db + its private endpoint
VWAN = {
    215,  # point-to-site vpn frame
    216,  # vwan hub
    268,  # edge: Internet <-> p2s vpn
    269,  # edge: vwan hub <-> vnet-shared peering
    279,  # edge: vwan hub <-> vnet-app peering
}

# --------------------------------------------------------------------------
# Per-module scope.
#
# Each entry is (path relative to the repo root, set of cell ids to keep).
#
# Scope rule: keep a shape if it belongs to the module itself, or to a module
# this one depends on. vnet_shared is the hub and is always included. vnet_app
# is a prerequisite for every optional module except vnet_shared itself, so it
# is included in all of them too - each optional module is only deployable on
# top of an already-deployed vnet_app (see the enable_module_* wiring and the
# depends_on edges in the root main.tf), and its smoke tests are driven from
# the jumpboxes that vnet_app hosts.
# --------------------------------------------------------------------------
SCOPES = {
    'vnet-shared': (
        'modules/vnet-shared/images/vnet-shared-diagram.drawio.svg',
        GLOBAL | SHARED,
    ),
    'vnet-app': (
        'modules/vnet-app/images/vnet-app-diagram.drawio.svg',
        GLOBAL | SHARED | VNET_APP,
    ),
    'vm-jumpbox-linux': (
        'modules/vm-jumpbox-linux/images/vm-jumpbox-linux-diagram.drawio.svg',
        GLOBAL | SHARED | VNET_APP | JUMPLINUX,
    ),
    'vm-mssql-win': (
        # NOTE: file is vm-mssql-diagram.drawio.svg, not vm-mssql-win-*.
        'modules/vm-mssql-win/images/vm-mssql-diagram.drawio.svg',
        GLOBAL | SHARED | VNET_APP | MSSQLWIN,
    ),
    'mssql': (
        'modules/mssql/images/mssql-diagram.drawio.svg',
        GLOBAL | SHARED | VNET_APP | MSSQL,
    ),
    'mysql': (
        'modules/mysql/images/mysql-diagram.drawio.svg',
        GLOBAL | SHARED | VNET_APP | MYSQL,
    ),
    'vwan': (
        # vwan requires every other base module to be deployed: it connects the
        # hub and spoke vnets to a virtual WAN hub so remote clients reach all
        # of the workloads, so its diagram keeps the full set of shapes.
        'modules/vwan/images/vwan-diagram.drawio.svg',
        GLOBAL | SHARED | VNET_APP | JUMPLINUX | MSSQLWIN | MSSQL | MYSQL | VWAN,
    ),
}


# --------------------------------------------------------------------------
# *.drawio.svg model codec
#
# The model lives in the root <svg content="..."> attribute, encoded as
# HTML-escaped -> <mxfile>/<diagram> wrapper -> base64 -> raw deflate ->
# percent-encoded mxGraphModel XML. Decode/encode are exact inverses; see
# roundtrip_ok() in verify.
# --------------------------------------------------------------------------

def read_svg(path):
    """Return (svg_text, raw_content_attr, diagram_open_tag, mxgraph_xml)."""
    svg = open(path, encoding='utf-8').read()
    m = re.search(r'content="(.*?)"\s', svg, re.S)
    if not m:
        raise ValueError(f'no content attribute in {path}')
    content = html.unescape(m.group(1))
    d = re.search(r'(<diagram[^>]*>)(.*?)</diagram>', content, re.S)
    if not d:
        raise ValueError(f'no diagram element in {path}')
    xml = urllib.parse.unquote(zlib.decompress(base64.b64decode(d.group(2)), -15).decode())
    return svg, m.group(1), d.group(1), xml


def encode_model(xml):
    """Inverse of the decode in read_svg(): mxGraphModel XML -> <diagram> payload."""
    quoted = urllib.parse.quote(xml, safe="~()*!.'")
    co = zlib.compressobj(9, zlib.DEFLATED, -15)
    return base64.b64encode(co.compress(quoted.encode()) + co.flush()).decode()


def svg_body(svg_text):
    """The rendered half of a *.drawio.svg: everything after the root <svg ...> tag."""
    return svg_text[svg_text.find('>', svg_text.find('<svg')) + 1:]


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------

def build_model(root_xml, module, keep):
    """Return the module's mxGraphModel XML: retitled, out-of-scope cells removed."""
    model = ET.fromstring(root_xml)
    croot = model.find('root')
    cells = {c.get('id'): c for c in croot.findall('mxCell')}

    missing = {str(i) for i in keep} - set(cells)
    if missing:
        raise SystemExit(
            f"ERROR: {module}: cell id(s) {sorted(missing)} are in SCOPES but not in the "
            f"root diagram.\nThe root diagram changed; re-run `list` and update the "
            f"ownership map at the top of this script."
        )

    kept = {'0', '1'} | {str(i) for i in keep}

    # Adopt label cells parented to a kept cell (edge labels are child cells).
    changed = True
    while changed:
        changed = False
        for cid, c in cells.items():
            p = c.get('parent')
            if cid not in kept and p in kept and p not in ('0', '1'):
                kept.add(cid)
                changed = True

    # Cascade removal: drop anything parented to, or connected to, a dropped cell.
    changed = True
    while changed:
        changed = False
        for cid, c in cells.items():
            if cid not in kept:
                continue
            if any(r is not None and r not in kept
                   for r in (c.get('parent'), c.get('source'), c.get('target'))):
                kept.discard(cid)
                changed = True

    for cid, c in list(cells.items()):
        if cid not in kept:
            croot.remove(c)

    title = cells[TITLE_CELL_ID]
    title.set('value', f'<b>Azure Sandbox - {module} module</b>')
    title.find('mxGeometry').set('width', TITLE_WIDTH)

    return ET.tostring(model, encoding='unicode'), sorted(kept - {'0', '1'}, key=int)


def assemble(rendered_svg, model_xml, diagram_tag):
    """Combine a freshly rendered body and a model into an editable *.drawio.svg."""
    payload = f'<mxfile>{diagram_tag}{encode_model(model_xml)}</diagram></mxfile>'
    escaped = (payload.replace('&', '&amp;').replace('<', '&lt;')
               .replace('>', '&gt;').replace('"', '&quot;'))

    m = re.match(r'<svg\b([^>]*)>', rendered_svg)
    attrs = dict(re.findall(r'([\w:-]+)="([^"]*)"', m.group(1)))
    attrs.setdefault('host', '65bd71144e')
    attrs['style'] = 'background: #FFFFFF; background-color: light-dark(#FFFFFF, #121212);'
    order = ['host', 'xmlns', 'style', 'xmlns:xlink', 'version', 'width', 'height', 'viewBox']
    parts = [f'{k}="{attrs[k]}"' for k in order if k in attrs]
    parts.append(f'content="{escaped}"')
    return f'<svg {" ".join(parts)}>' + rendered_svg[m.end():]


def cmd_build(modules):
    _, _, diagram_tag, root_xml = read_svg(ROOT_DIAGRAM)
    print(f'root diagram: {os.path.relpath(ROOT_DIAGRAM, REPO_ROOT)}')

    import tempfile
    failed = False
    for module in modules:
        rel, keep = SCOPES[module]
        model_xml, kept = build_model(root_xml, module, keep)
        with tempfile.TemporaryDirectory() as tmp:
            mp, sp = os.path.join(tmp, 'model.xml'), os.path.join(tmp, 'body.svg')
            with open(mp, 'w', encoding='utf-8') as fh:
                fh.write(model_xml)
            try:
                subprocess.run(['node', RENDERER, mp, sp], check=True,
                               stdout=subprocess.DEVNULL)
            except subprocess.CalledProcessError:
                print(f'{module:18} RENDER FAILED')
                failed = True
                continue
            out = assemble(open(sp, encoding='utf-8').read(), model_xml, diagram_tag)

        with open(os.path.join(REPO_ROOT, rel), 'w', encoding='utf-8') as fh:
            fh.write(out)
        dim = re.search(r'width="(\d+)px" height="(\d+)px"', out)
        print(f'{module:18} cells={len(kept):3}  {dim.group(1)}x{dim.group(2)}  -> {rel}')
    return 1 if failed else 0


# --------------------------------------------------------------------------
# List / verify
# --------------------------------------------------------------------------

def plain(value):
    """Strip markup from a cell value, keeping line breaks as newlines."""
    text = re.sub(r'<br\s*/?>|</div>|</p>', '\n', value or '')
    return html.unescape(re.sub(r'<[^>]+>', '', text))


def cmd_list():
    _, _, _, root_xml = read_svg(ROOT_DIAGRAM)
    croot = ET.fromstring(root_xml).find('root')
    owner = {}
    for name, group in (('GLOBAL', GLOBAL), ('SHARED', SHARED), ('VNET_APP', VNET_APP),
                        ('JUMPLINUX', JUMPLINUX), ('MSSQLWIN', MSSQLWIN), ('MSSQL', MSSQL),
                        ('MYSQL', MYSQL), ('VWAN', VWAN)):
        for cid in group:
            owner[str(cid)] = name

    print(f"{'id':>5} {'kind':5} {'group':10} {'x':>8} {'y':>8} {'w':>7} {'h':>7}  label")
    for c in croot.findall('mxCell'):
        cid = c.get('id')
        if cid in ('0', '1'):
            continue
        g = c.find('mxGeometry')
        get = (lambda k: (g.get(k) or '') if g is not None else '')
        if c.get('edge') == '1':
            kind = 'edge'
            geom = f"{'src ' + (c.get('source') or '?'):>17} {'-> ' + (c.get('target') or '?'):>15}"
        else:
            kind = 'label' if c.get('parent') not in ('1', None) else 'vtx'
            geom = f"{get('x'):>8} {get('y'):>8} {get('width'):>7} {get('height'):>7}"
        label = plain(c.get('value')).replace('\n', ' ').strip()
        print(f'{cid:>5} {kind:5} {owner.get(cid, "-"):10} {geom}  {label[:52]}')

    unmapped = sorted(
        (c.get('id') for c in croot.findall('mxCell')
         if c.get('id') not in ('0', '1')
         and c.get('id') not in owner
         and c.get('parent') in ('1', None)),
        key=int,
    )
    print(f'\nunmapped top-level cells (must be added to a group): {unmapped or "none"}')
    return 1 if unmapped else 0


def cmd_verify(modules):
    ok = True
    for module in modules:
        rel, _ = SCOPES[module]
        path = os.path.join(REPO_ROOT, rel)
        svg, content_raw, diagram_tag, xml = read_svg(path)
        problems = []

        # The embedded model must survive a decode -> encode -> decode cycle.
        d = re.search(r'<diagram[^>]*>(.*?)</diagram>', html.unescape(content_raw), re.S)
        again = urllib.parse.unquote(
            zlib.decompress(base64.b64decode(encode_model(xml)), -15).decode())
        if again != xml or d is None:
            problems.append('model does not round-trip')

        croot = ET.fromstring(xml).find('root')
        cells = {c.get('id'): c for c in croot.findall('mxCell')}
        ids = set(cells)

        dangling = sorted(i for i, c in cells.items() if c.get('edge') == '1'
                          and (c.get('source') not in ids or c.get('target') not in ids))
        if dangling:
            problems.append(f'edges with a deleted terminal: {dangling}')

        orphans = sorted(i for i, c in cells.items()
                         if c.get('parent') and c.get('parent') not in ids)
        if orphans:
            problems.append(f'cells parented to a deleted cell: {orphans}')

        # Model and rendered body must agree in both directions.
        norm = lambda s: re.sub(r'\s+', ' ', s.replace('\u00a0', ' ')
                                .replace('&nbsp;', ' ')).strip()
        body = norm(svg_body(svg))
        missing = [ln[:40] for c in cells.values()
                   for ln in map(norm, plain(c.get('value')).split('\n'))
                   if ln and ln not in body]
        if missing:
            problems.append(f'model labels absent from the picture: {missing}')

        model_text = norm(' '.join(plain(c.get('value')).replace('\n', ' ')
                                   for c in cells.values()))
        ghosts = sorted({t for t in
                         (norm(x) for x in re.findall(r'>([^<>]{2,})</div>', svg_body(svg)))
                         if t not in model_text and 'Text is not SVG' not in t})
        if ghosts:
            problems.append(f'picture shows text absent from the model: {ghosts}')

        expected = f'Azure Sandbox - {module} module'
        if norm(plain(cells[TITLE_CELL_ID].get('value'))) != expected:
            problems.append(f'title is not "{expected}"')

        print(f'{module:18} {"OK" if not problems else "FAILED"}')
        for p in problems:
            print(f'  - {p}')
        ok &= not problems
    print('\nall diagrams verified' if ok else '\nVERIFICATION FAILED')
    return 0 if ok else 1


def main(argv):
    if not argv or argv[0] not in ('list', 'build', 'verify'):
        print(__doc__.split('USAGE\n-----\n')[1].split('\nExit codes')[0])
        return 2
    cmd, rest = argv[0], argv[1:]
    for m in rest:
        if m not in SCOPES:
            print(f"ERROR: unknown module '{m}' (valid: {' '.join(SCOPES)})", file=sys.stderr)
            return 2
    modules = rest or list(SCOPES)
    if cmd == 'list':
        return cmd_list()
    if cmd == 'build':
        return cmd_build(modules)
    return cmd_verify(modules)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
