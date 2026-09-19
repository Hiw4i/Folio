/* Folio's compatibility layer for the pinned PPTXjs 1.21.1 renderer.
 * Geometry remains in document pixels (96 CSS pixels per inch). No UI styles
 * or animations belong here. See docs/OFFICE_ENGINE_UPDATE.md for limitations.
 */
(() => {
  'use strict';
  const EMU = 96 / 914400;
  const xmlCaches = new WeakMap();
  const mediaCaches = new WeakMap();
  const ownedUrls = new Set();
  const asList = (v) => v == null ? [] : Array.isArray(v) ? v : [v];
  const get = (v, ...keys) => keys.reduce((o, k) => o?.[k], v);
  const number = (v, fallback = 0) => Number.isFinite(Number(v)) ? Number(v) : fallback;
  const flag = (v) => v === '1' || v === 'true' || v === true;
  const escape = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[c]);
  const copy = (v) => v == null ? v : JSON.parse(JSON.stringify(v));

  function relationshipPart(part) {
    const slash = part.lastIndexOf('/');
    return `${part.slice(0, slash + 1)}_rels/${part.slice(slash + 1)}.rels`;
  }

  function resolvePart(owner, target) {
    if (!target || /[\\\u0000]/.test(target) || /^[a-z][a-z\d+.-]*:/i.test(target)) return '';
    let decoded;
    try { decoded = decodeURI(target); } catch (_) { return ''; }
    const path = decoded.startsWith('/') ? decoded.slice(1)
      : owner.slice(0, owner.lastIndexOf('/') + 1) + decoded;
    const parts = [];
    for (const segment of path.split('/')) {
      if (segment === '..') { if (!parts.length) return ''; parts.pop(); }
      else if (segment && segment !== '.') parts.push(segment);
    }
    return parts.join('/');
  }

  function readPart(zip, path, parse) {
    if (!path) return null;
    let cache = xmlCaches.get(zip);
    if (!cache) { cache = new Map(); xmlCaches.set(zip, cache); }
    if (cache.has(path)) {
      const entry = cache.get(path);
      cache.delete(path); cache.set(path, entry);
      // PPTXjs mutates inherited styles: never share a cached mutable tree.
      return copy(entry);
    }
    const entry = zip.file(path);
    if (!entry) return null;
    const text = entry.asText();
    const value = parse(text.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, (_, content) => escape(content)));
    if (path.endsWith('.rels')) {
      const owner = path.replace(/(^|\/)_rels\//, '$1').slice(0, -5);
      for (const rel of asList(value?.Relationships?.Relationship)) {
        if (rel.attrs?.TargetMode !== 'External') {
          rel.attrs.Target = resolvePart(owner, rel.attrs.Target);
        }
      }
    }
    // Bound retained metadata; one-off slide trees do not accumulate forever.
    const reusable = /\.rels$/.test(path) || /(?:presentation|tableStyles)\.xml$/.test(path) ||
      /\/(?:slideMasters|slideLayouts|theme)\//.test(path);
    if (reusable && text.length < 512 * 1024) {
      cache.set(path, copy(value));
      while (cache.size > 16) cache.delete(cache.keys().next().value);
    }
    return value;
  }

  function slideOrder(zip, read) {
    const presentation = read(zip, 'ppt/presentation.xml')?.['p:presentation'];
    const relationships = asList(read(zip, 'ppt/_rels/presentation.xml.rels')?.Relationships?.Relationship);
    const targets = new Map(relationships.filter((r) => r.attrs?.TargetMode !== 'External')
      .map((r) => [r.attrs?.Id, r.attrs]));
    const slides = asList(presentation?.['p:sldIdLst']?.['p:sldId']).map((id) => {
      const rel = targets.get(id.attrs?.['r:id']);
      if (!rel?.Type?.endsWith('/slide') || !zip.file(rel.Target)) {
        throw new Error('A PowerPoint slide relationship is missing or damaged.');
      }
      return rel.Target;
    });
    return { slides, slideLayouts: [] };
  }

  function mediaUrl(zip, path) {
    if (!path || /^[a-z][a-z\d+.-]*:/i.test(path)) return '';
    let cache = mediaCaches.get(zip);
    if (!cache) { cache = new Map(); mediaCaches.set(zip, cache); }
    if (cache.has(path)) return cache.get(path);
    const types = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
      gif: 'image/gif', svg: 'image/svg+xml', webp: 'image/webp', bmp: 'image/bmp' };
    const mime = types[path.split('.').pop().toLowerCase()];
    const entry = zip.file(path);
    if (!mime || !entry) return '';
    const url = URL.createObjectURL(new Blob([entry.asArrayBuffer()], { type: mime }));
    cache.set(path, url); ownedUrls.add(url);
    return url;
  }

  function imageFill(layer, fill, context) {
    const tables = { slideBg: 'slideResObj', slide: 'slideResObj',
      slideLayoutBg: 'layoutResObj', slideMasterBg: 'masterResObj',
      themeBg: 'themeResObj', diagramBg: 'diagramResObj' };
    const relation = context[tables[layer] || 'slideResObj']?.[fill?.['a:blip']?.attrs?.['r:embed']];
    return relation?.type === 'image' ? mediaUrl(context.zip, relation.target) : '';
  }

  function orderedChildren(node) {
    return Object.entries(node || {}).filter(([key]) => key !== 'attrs')
      .flatMap(([key, value]) => asList(value).map((child) => [key, child]))
      .sort((a, b) => number(a[1]?.attrs?.order) - number(b[1]?.attrs?.order));
  }

  function group(node, context, layer, render) {
    if (!node) return '';
    const inner = orderedChildren(node).map(([key, child]) => render(key, child, node, context, layer)).join('');
    const xfrm = node['p:grpSpPr']?.['a:xfrm'];
    if (!xfrm) return inner; // AlternateContent / OLE fallback, not a real group.
    const off = xfrm['a:off']?.attrs || {}, ext = xfrm['a:ext']?.attrs || {};
    const childOff = xfrm['a:chOff']?.attrs || {}, childExt = xfrm['a:chExt']?.attrs || {};
    const width = Math.max(0, number(ext.cx)) * EMU, height = Math.max(0, number(ext.cy)) * EMU;
    const childWidth = number(childExt.cx, number(ext.cx)), childHeight = number(childExt.cy, number(ext.cy));
    const sx = childWidth > 0 ? number(ext.cx) / childWidth : 1;
    const sy = childHeight > 0 ? number(ext.cy) / childHeight : 1;
    const rotation = number(xfrm.attrs?.rot) / 60000;
    return `<div class="block folio-group" style="left:${number(off.x) * EMU}px;top:${number(off.y) * EMU}px;` +
      `width:${width}px;height:${height}px;z-index:${number(node.attrs?.order)};` +
      `transform:rotate(${rotation}deg) scale(${flag(xfrm.attrs?.flipH) ? -1 : 1},${flag(xfrm.attrs?.flipV) ? -1 : 1});">` +
      `<div style="position:absolute;left:0;top:0;width:${childWidth * EMU}px;height:${childHeight * EMU}px;` +
      `transform-origin:0 0;transform:scale(${sx},${sy}) translate(${-number(childOff.x) * EMU}px,${-number(childOff.y) * EMU}px);">` +
      inner + '</div></div>';
  }

  function picture(node, context, layer) {
    const fill = node['p:blipFill'];
    if (!fill) return '';
    const idx = get(node, 'p:nvPicPr', 'p:nvPr', 'p:ph', 'attrs', 'idx');
    const xfrm = node['p:spPr']?.['a:xfrm'] || get(context.slideLayoutTables, 'idxTable', idx, 'p:spPr', 'a:xfrm');
    if (!xfrm) return '';
    const off = xfrm['a:off']?.attrs || {}, ext = xfrm['a:ext']?.attrs || {};
    const crop = fill['a:srcRect']?.attrs || {};
    const fraction = (v) => typeof v === 'string' && v.endsWith('%') ? number(v.slice(0, -1)) / 100 : number(v) / 100000;
    const left = fraction(crop.l), top = fraction(crop.t);
    const remainingX = 1 - left - fraction(crop.r), remainingY = 1 - top - fraction(crop.b);
    if (remainingX <= 0 || remainingY <= 0) return '';
    let url = imageFill(layer, fill, context);
    const svg = asList(fill['a:blip']?.['a:extLst']?.['a:ext'])
      .find((e) => e['asvg:svgBlip'])?.['asvg:svgBlip'];
    if (svg) url = imageFill(layer, { 'a:blip': svg }, context) || url;
    const opacity = Math.max(0, Math.min(1, number(fill['a:blip']?.['a:alphaModFix']?.attrs?.amt, 100000) / 100000));
    const alt = escape(get(node, 'p:nvPicPr', 'p:cNvPr', 'attrs', 'descr') || '');
    const rounded = node['p:spPr']?.['a:prstGeom']?.attrs?.prst === 'ellipse' ? 'border-radius:50%;' : '';
    return `<div class="block folio-picture" style="left:${number(off.x) * EMU}px;top:${number(off.y) * EMU}px;` +
      `width:${Math.max(0, number(ext.cx)) * EMU}px;height:${Math.max(0, number(ext.cy)) * EMU}px;` +
      `z-index:${number(node.attrs?.order)};overflow:hidden;${rounded}` +
      `transform:rotate(${number(xfrm.attrs?.rot) / 60000}deg) scale(${flag(xfrm.attrs?.flipH) ? -1 : 1},${flag(xfrm.attrs?.flipV) ? -1 : 1});">` +
      `<img ${url ? `src="${escape(url)}"` : ''} alt="${alt}" style="position:absolute;max-width:none;` +
      `width:${100 / remainingX}%;height:${100 / remainingY}%;left:${-100 * left / remainingX}%;` +
      `top:${-100 * top / remainingY}%;opacity:${opacity};"></div>`;
  }

  function colorMap(context) {
    const master = context.slideMasterContent?.['p:sldMaster']?.['p:clrMap']?.attrs || {};
    let map = master;
    for (const root of [context.slideLayoutContent?.['p:sldLayout'], context.slideContent?.['p:sld']]) {
      const override = root?.['p:clrMapOvr'];
      if (override?.['a:overrideClrMapping']) map = { ...master, ...override['a:overrideClrMapping'].attrs };
      else if (override?.['a:masterClrMapping']) map = master;
    }
    return map;
  }

  function schemeColor(name, map, placeholder, context) {
    name = name.replace(/^a:/, '');
    if (name === 'phClr' && placeholder != null) return placeholder;
    map ||= colorMap(context);
    const defaults = { tx1: 'dk1', tx2: 'dk2', bg1: 'lt1', bg2: 'lt2' };
    const key = map[name] || defaults[name] || name;
    const value = get(context.themeContent, 'a:theme', 'a:themeElements', 'a:clrScheme', `a:${key}`);
    return value?.['a:srgbClr']?.attrs?.val || value?.['a:sysClr']?.attrs?.lastClr;
  }

  function background(context, readColor, gradient, image) {
    for (const [root, layer] of [[context.slideContent?.['p:sld'], 'slideBg'],
      [context.slideLayoutContent?.['p:sldLayout'], 'slideLayoutBg'],
      [context.slideMasterContent?.['p:sldMaster'], 'slideMasterBg']]) {
      const bg = root?.['p:cSld']?.['p:bg'];
      if (!bg) continue;
      let fill = bg['p:bgPr'], placeholder, fillLayer = layer;
      if (!fill && bg['p:bgRef']) {
        const reference = bg['p:bgRef'];
        placeholder = readColor(reference, colorMap(context), undefined, context);
        const index = number(reference.attrs?.idx);
        const list = get(context.themeContent, 'a:theme', 'a:themeElements', 'a:fmtScheme',
          index >= 1001 ? 'a:bgFillStyleLst' : 'a:fillStyleLst');
        const item = orderedChildren(list)[index >= 1001 ? index - 1001 : index - 1];
        fill = item ? { [item[0]]: item[1], attrs: item[1]?.attrs || {} } : null;
        fillLayer = 'themeBg';
      }
      if (fill?.['a:solidFill']) {
        const color = readColor(fill['a:solidFill'], colorMap(context), placeholder, context);
        return color ? `background-color:#${color};` : 'background-color:#fff;';
      }
      if (fill?.['a:gradFill']) return gradient(fill, placeholder, context.slideMasterContent, context);
      if (fill?.['a:blipFill']) return 'background-color:#fff;' + image(fill, fillLayer, context, placeholder);
      if (fill?.['a:noFill']) return 'background-color:transparent;';
      if (placeholder) return `background-color:#${placeholder};`;
      return 'background-color:#fff;';
    }
    return 'background-color:#fff;';
  }

  function backgroundLayers(context, size, index, render, backgroundStyle) {
    let html = `<div class="slide-background-${index} folio-slide-background" style="width:${size.width}px;height:${size.height}px;"><div class="folio-background-paint" style="position:absolute;inset:0;${backgroundStyle}"></div>`;
    const showMaster = context.slideContent?.['p:sld']?.attrs?.showMasterSp;
    const layoutMaster = context.slideLayoutContent?.['p:sldLayout']?.attrs?.showMasterSp;
    const layers = [];
    if (showMaster !== '0' && showMaster !== 'false' && layoutMaster !== '0' && layoutMaster !== 'false') {
      layers.push([context.slideMasterContent?.['p:sldMaster'], 'slideMasterBg']);
    }
    layers.push([context.slideLayoutContent?.['p:sldLayout'], 'slideLayoutBg']);
    for (const [root, layer] of layers) {
      html += '<div class="folio-master-layer">';
      const tree = root?.['p:cSld']?.['p:spTree'];
      for (const [key, child] of orderedChildren(tree)) {
        const nv = child?.['p:nvSpPr'] || child?.['p:nvPicPr'] || child?.['p:nvGraphicFramePr'];
        // Placeholder sample text belongs to editing mode, not the slide.
        if (nv?.['p:nvPr']?.['p:ph']) continue;
        html += render(key, child, tree, context, layer);
      }
      html += '</div>';
    }
    return html; // The pinned renderer closes this wrapper after slide shapes.
  }

  function mergeProperties(...values) {
    const merged = { attrs: {} };
    const fills = ['a:noFill', 'a:solidFill', 'a:gradFill', 'a:blipFill', 'a:pattFill', 'a:grpFill'];
    for (const value of values) {
      if (!value) continue;
      if (fills.some((key) => value[key])) for (const key of fills) delete merged[key];
      for (const key of Object.keys(value)) if (key !== 'attrs') merged[key] = value[key];
      Object.assign(merged.attrs, value.attrs || {});
    }
    return merged;
  }

  function effectiveRun(run, paragraph, body, index, type, context, inherited) {
    if (Array.isArray(run)) run = run[0];
    const level = Math.max(1, Math.min(9, number(paragraph?.['a:pPr']?.attrs?.lvl) + 1));
    const key = `a:lvl${level}pPr`;
    const parent = inherited(paragraph, index, type, context);
    const rPr = mergeProperties(
      context.defaultTextStyle?.[key]?.['a:defRPr'], parent.nodeMaster?.['a:defRPr'],
      parent.nodeLaout?.['a:defRPr'], body?.['a:lstStyle']?.[key]?.['a:defRPr'],
      paragraph?.['a:pPr']?.['a:defRPr'], run?.['a:rPr'],
    );
    return { ...run, 'a:rPr': rPr };
  }

  function fontFamily(run, type, context, reference) {
    let family = run?.['a:rPr']?.['a:latin']?.attrs?.typeface;
    const major = type === 'title' || type === 'ctrTitle';
    let theme = reference?.attrs?.idx || (major ? 'major' : 'minor');
    let script = 'latin';
    const token = /^\+(mj|mn)-(lt|ea|cs)$/.exec(family || '');
    if (token) {
      theme = token[1] === 'mj' ? 'major' : 'minor';
      script = { lt: 'latin', ea: 'ea', cs: 'cs' }[token[2]];
      family = null;
    }
    family ||= get(context.themeContent, 'a:theme', 'a:themeElements', 'a:fontScheme', `a:${theme}Font`, `a:${script}`, 'attrs', 'typeface');
    // Quote a single font family; document strings must not become CSS rules.
    return family ? `&quot;${escape(family).replace(/;/g, '')}&quot;,sans-serif` : 'sans-serif';
  }

  function fontSize(run, body) {
    let size = number(run?.['a:rPr']?.attrs?.sz, 1800) / 100;
    // kern is a kerning threshold, not a value to subtract from font size.
    const scale = number(body?.['a:bodyPr']?.['a:normAutofit']?.attrs?.fontScale, 100000) / 100000;
    size *= scale > 0 ? scale : 1;
    return `${Math.max(1, size) * 96 / 72}px`;
  }

  function gradientData(fill, context, readColor) {
    const stops = asList(fill?.['a:gsLst']?.['a:gs']).map((stop) => ({
      color: readColor(stop, undefined, undefined, context) || '00000000',
      position: Math.max(0, Math.min(1, number(stop.attrs?.pos) / 100000)),
    })).sort((a, b) => a.position - b.position);
    const angle = number(fill?.['a:lin']?.attrs?.ang) / 60000;
    return { color: stops.map((stop) => stop.color), positions: stops.map((stop) => stop.position),
      angle, rot: angle + 90, scaled: flag(fill?.['a:lin']?.attrs?.scaled) };
  }

  function svgGradient(width, height, gradient, id) {
    const angle = gradient.angle * Math.PI / 180;
    let dx = Math.cos(angle), dy = Math.sin(angle);
    // `scaled` applies the gradient direction in the shape's normalized space.
    if (gradient.scaled) { dx *= width; dy *= height; }
    const magnitude = Math.hypot(dx, dy) || 1; dx /= magnitude; dy /= magnitude;
    const length = Math.abs(width * dx) + Math.abs(height * dy);
    let markup = `<linearGradient id="linGrd_${id}" gradientUnits="userSpaceOnUse" ` +
      `x1="${width / 2 - dx * length / 2}" y1="${height / 2 - dy * length / 2}" ` +
      `x2="${width / 2 + dx * length / 2}" y2="${height / 2 + dy * length / 2}">`;
    gradient.color.forEach((color, index) => {
      const value = window.tinycolor(`#${color}`);
      markup += `<stop offset="${gradient.positions[index]}" stop-color="${value.toHexString()}" stop-opacity="${value.getAlpha()}"></stop>`;
    });
    return markup + '</linearGradient>';
  }

  function textBoxMarkup(html, shape, layout, master) {
    if (!shape?.['p:txBody']) return html;
    const props = { ...master?.['p:txBody']?.['a:bodyPr']?.attrs,
      ...layout?.['p:txBody']?.['a:bodyPr']?.attrs, ...shape['p:txBody']?.['a:bodyPr']?.attrs };
    const padding = [number(props.tIns, 45720), number(props.rIns, 91440),
      number(props.bIns, 45720), number(props.lIns, 91440)].map((value) => value * EMU);
    const metadata = encodeURIComponent(JSON.stringify({ padding, noWrap: props.wrap === 'none' }));
    return html.replace("<div class='block ", `<div data-folio-text-box="${metadata}" class='block `);
  }

  function applyTextInsets(fragment) {
    for (const box of fragment.querySelectorAll('[data-folio-text-box]')) {
      const { padding, noWrap } = JSON.parse(decodeURIComponent(box.dataset.folioTextBox));
      const horizontal = padding[1] + padding[3];
      box.style.boxSizing = 'border-box';
      box.style.padding = padding.map((value) => `${value}px`).join(' ');
      for (const paragraph of box.querySelectorAll(':scope > .slide-prgrph')) {
        const width = parseFloat(paragraph.style.width) || parseFloat(box.style.width);
        if (Number.isFinite(width)) paragraph.style.width = `${Math.max(1, width - horizontal)}px`;
        const text = paragraph.lastElementChild;
        if (text) {
          const inner = parseFloat(text.style.width);
          if (Number.isFinite(inner)) text.style.width = `${Math.max(1, inner - horizontal)}px`;
        }
      }
      if (noWrap) box.querySelectorAll('.text-block').forEach((run) => { run.style.whiteSpace = 'pre'; });
      delete box.dataset.folioTextBox;
    }
  }

  function appendSlide(root, markup, index) {
    const template = document.createElement('template');
    template.innerHTML = markup;
    // Local documents are data, never executable HTML. Do this before insertion.
    template.content.querySelectorAll('script,iframe,object,embed,link,meta,base,form,audio,video').forEach((el) => el.remove());
    for (const el of template.content.querySelectorAll('*')) {
      for (const attr of Array.from(el.attributes)) {
        if (/^on/i.test(attr.name) || attr.name === 'srcdoc' ||
            /^(?:href|xlink:href|src)$/i.test(attr.name) && /^\s*(?:javascript|vbscript):/i.test(attr.value)) {
          el.removeAttribute(attr.name);
        }
      }
    }
    // PPTXjs reuses IDs in different SVGs. Scope paint servers to their SVG.
    template.content.querySelectorAll('svg').forEach((svg, svgIndex) => {
      const ids = new Map();
      svg.querySelectorAll('[id]').forEach((el, idIndex) => {
        const name = `folio-s${index}-v${svgIndex}-r${idIndex}`;
        ids.set(el.id, name); el.id = name;
      });
      svg.querySelectorAll('*').forEach((el) => {
        for (const attr of Array.from(el.attributes)) {
          let value = attr.value.replace(/url\(#([^)]*)\)/g, (match, id) => ids.has(id) ? `url(#${ids.get(id)})` : match);
          if ((attr.name === 'href' || attr.name === 'xlink:href') && value.startsWith('#') && ids.has(value.slice(1))) value = `#${ids.get(value.slice(1))}`;
          if (value !== attr.value) el.setAttribute(attr.name, value);
        }
      });
    });
    applyTextInsets(template.content);
    root.appendChild(template.content);
  }

  function dispose() {
    for (const url of ownedUrls) URL.revokeObjectURL(url);
    ownedUrls.clear();
  }

  window.FolioPptx = Object.freeze({ readPart, relationshipPart, resolvePart, slideOrder,
    mediaUrl, imageFill, group, picture, schemeColor, background, backgroundLayers,
    effectiveRun, fontFamily, fontSize, gradientData, svgGradient, textBoxMarkup, appendSlide, dispose });
  window.addEventListener('pagehide', dispose, { once: true });
})();
