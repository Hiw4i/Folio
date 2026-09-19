/* Layout/fidelity corrections for the pinned docx-preview 0.4.0 build.
 * This is a paginated preview, not Word's proprietary layout engine.
 */
(() => {
  'use strict';
  const finite = (value, fallback = 0) => Number.isFinite(Number.parseFloat(value)) ? Number.parseFloat(value) : fallback;
  const child = (node, name) => Array.from(node?.children || []).find((el) => el.localName === name);
  const attr = (node, name) => node?.getAttribute(name);
  const EMU = 96 / 914400;
  const isTrue = (value) => value === '1' || value === 'true';

  function imageProperties(node, model) {
    const xfrm = child(child(node, 'spPr'), 'xfrm');
    model.folioFlipH = isTrue(attr(xfrm, 'flipH'));
    model.folioFlipV = isTrue(attr(xfrm, 'flipV'));
    return model;
  }

  function renderImage(model, img) {
    const crop = model.srcRect || [0, 0, 0, 0];
    const width = 1 - crop[0] - crop[2], height = 1 - crop[1] - crop[3];
    if (!crop.some(Boolean) && !model.folioFlipH && !model.folioFlipV) {
      if (model.rotation) img.style.transform = `rotate(${model.rotation}deg) ${img.style.transform || ''}`;
      return img;
    }
    const box = document.createElement('span');
    box.className = 'folio-docx-picture';
    Object.assign(box.style, model.cssStyle || {}, { display: 'inline-block', overflow: 'hidden', verticalAlign: 'bottom' });
    box.style.transform = `rotate(${finite(model.rotation)}deg) scale(${model.folioFlipH ? -1 : 1},${model.folioFlipV ? -1 : 1})`;
    // Crop in source-image space, then fit the remaining source into the frame.
    // Scaling a clipped image about its centre shifts asymmetrical crops.
    Object.assign(img.style, { position: 'absolute', transform: 'none', maxWidth: 'none',
      width: `${100 / Math.max(width, .0001)}%`, height: `${100 / Math.max(height, .0001)}%`,
      left: `${-100 * crop[0] / Math.max(width, .0001)}%`, top: `${-100 * crop[1] / Math.max(height, .0001)}%` });
    if (width <= 0 || height <= 0) img.style.visibility = 'hidden';
    box.appendChild(img);
    return box;
  }

  function drawingProperties(node, model) {
    if (node.localName !== 'anchor' || !child(node, 'wrapNone')) return model;
    const axis = (name) => {
      const value = child(node, name);
      return { relative: attr(value, 'relativeFrom') || 'page',
        align: child(value, 'align')?.textContent || '',
        offset: finite(child(value, 'posOffset')?.textContent) * EMU };
    };
    const extent = child(node, 'extent');
    model.folioAnchor = { h: axis('positionH'), v: axis('positionV'),
      width: finite(attr(extent, 'cx')) * EMU, height: finite(attr(extent, 'cy')) * EMU,
      behind: isTrue(attr(node, 'behindDoc')) };
    if (isTrue(attr(node, 'simplePos'))) {
      const pos = child(node, 'simplePos');
      model.folioAnchor.h = { relative: 'page', offset: finite(attr(pos, 'x')) * EMU };
      model.folioAnchor.v = { relative: 'page', offset: finite(attr(pos, 'y')) * EMU };
    }
    Object.assign(model.cssStyle, { width: '0px', height: '0px', left: '0px', top: '0px' });
    return model;
  }

  function renderDrawing(model, element) {
    if (model.folioAnchor) element.dataset.folioAnchor = JSON.stringify(model.folioAnchor);
    return element;
  }

  function positionAnchors(root) {
    // Read all geometry before moving any anchors to avoid repeated reflows.
    const placements = Array.from(root.querySelectorAll('[data-folio-anchor]')).map((el) => {
      const page = el.closest('section.docx');
      if (!page) return null;
      const data = JSON.parse(el.dataset.folioAnchor), rect = page.getBoundingClientRect();
      const style = getComputedStyle(page), paragraph = (el.closest('p') || el.parentElement).getBoundingClientRect();
      const article = (el.closest('article') || page).getBoundingClientRect();
      const position = (axis, horizontal) => {
        const size = horizontal ? data.width : data.height;
        const full = horizontal ? rect.width : rect.height;
        const before = finite(horizontal ? style.paddingLeft : style.paddingTop);
        const after = finite(horizontal ? style.paddingRight : style.paddingBottom);
        let start = 0, end = full;
        if (axis.relative === 'margin' || axis.relative === 'insideMargin' || axis.relative === 'outsideMargin') { start = before; end -= after; }
        else if (axis.relative === 'leftMargin' || axis.relative === 'topMargin') end = before;
        else if (axis.relative === 'rightMargin' || axis.relative === 'bottomMargin') start = full - after;
        else if (axis.relative === 'column') { start = horizontal ? article.left - rect.left : article.top - rect.top; end = start + (horizontal ? article.width : article.height); }
        else if (axis.relative === 'paragraph' || axis.relative === 'line' || axis.relative === 'character') {
          start = horizontal ? paragraph.left - rect.left : paragraph.top - rect.top;
          end = start + (horizontal ? paragraph.width : paragraph.height);
        }
        if (axis.align === 'center') return start + (end - start - size) / 2;
        if (axis.align === 'right' || axis.align === 'bottom' || axis.align === 'outside') return end - size;
        return start + (axis.align ? 0 : axis.offset || 0);
      };
      return { el, page, data, left: position(data.h, true), top: position(data.v, false) };
    });
    for (const placement of placements) {
      if (!placement) continue;
      const { el, page, data, left, top } = placement;
      Object.assign(el.style, { position: 'absolute', left: `${left}px`, top: `${top}px`,
        width: `${data.width}px`, height: `${data.height}px`, zIndex: data.behind ? '0' : '2', margin: '0' });
      page.appendChild(el);
      delete el.dataset.folioAnchor;
    }
  }

  function orderStyles(styles) {
    // OOXML does not require a base style to precede the derived style.
    const byId = new Map(styles.filter((s) => s.id).map((s) => [s.id, s]));
    const visited = new Set(), visiting = new Set(), ordered = [];
    const visit = (style) => {
      if (visited.has(style) || visiting.has(style)) return;
      visiting.add(style);
      if (byId.has(style.basedOn)) visit(byId.get(style.basedOn));
      visiting.delete(style); visited.add(style); ordered.push(style);
    };
    styles.forEach(visit);
    return ordered;
  }

  function pageParts(page) {
    return Array.from(page.children).filter((el) => el.tagName === 'ARTICLE');
  }

  function occupiedHeight(el) {
    if (!el) return 0;
    const s = getComputedStyle(el);
    return el.getBoundingClientRect().height + finite(s.marginTop) + finite(s.marginBottom);
  }

  function tableUnits(table, limit) {
    const rows = Array.from(table.rows);
    if (rows.length < 2 || table.getBoundingClientRect().height <= limit) return [table];
    const groups = [];
    // Never split a vertically merged cell between pages.
    for (let i = 0; i < rows.length;) {
      let end = i + 1;
      for (let row = i; row < end; row++) for (const cell of rows[row].cells) {
        end = Math.min(rows.length, Math.max(end, cell.rowSpan === 0 ? rows.length : row + cell.rowSpan));
      }
      groups.push(rows.slice(i, end)); i = end;
    }
    const result = [], width = table.getBoundingClientRect().width;
    let batch = [], height = 0;
    const emit = () => {
      if (!batch.length) return;
      const clone = table.cloneNode(false);
      clone.style.width = `${width}px`; clone.style.tableLayout = 'fixed';
      for (const item of table.children) if (item.tagName === 'COLGROUP') clone.appendChild(item.cloneNode(true));
      const body = document.createElement('tbody');
      batch.forEach((row) => body.appendChild(row)); clone.appendChild(body);
      result.push(clone); batch = []; height = 0;
    };
    // Measure before detaching any row.
    const heights = groups.map((group) => group.reduce((sum, row) => sum + row.getBoundingClientRect().height, 0));
    groups.forEach((group, index) => {
      if (batch.length && height + heights[index] > limit) emit();
      batch.push(...group); height += heights[index];
    });
    emit(); table.replaceWith(...result);
    return result;
  }

  async function paginate(root) {
    const wrapper = root.querySelector('.docx-wrapper');
    if (!wrapper) return;
    const sourcePages = Array.from(wrapper.querySelectorAll(':scope > section.docx'));
    for (const source of sourcePages) {
      const articles = pageParts(source), style = getComputedStyle(source);
      const pageHeight = finite(style.minHeight), padding = finite(style.paddingTop) + finite(style.paddingBottom);
      const header = source.querySelector(':scope > header'), footer = source.querySelector(':scope > footer');
      const notes = Array.from(source.children).filter((el) => !['ARTICLE', 'HEADER', 'FOOTER'].includes(el.tagName));
      // Preserve continuous sections, columns and footnote placement as emitted
      // by the renderer. Flattening these structures destroys reading order.
      if (articles.length !== 1 || finite(getComputedStyle(articles[0]).columnCount, 1) > 1 || notes.length || pageHeight <= 0) continue;
      const article = articles[0], limit = pageHeight - padding - occupiedHeight(header) - occupiedHeight(footer);
      if (limit <= 0 || article.getBoundingClientRect().height <= limit + 1) continue;
      const blocks = Array.from(article.children).flatMap((block) => block.tagName === 'TABLE' ? tableUnits(block, limit) : [block]);
      const metrics = blocks.map((block) => {
        const r = block.getBoundingClientRect(), css = getComputedStyle(block);
        return { block, height: r.height, before: finite(css.marginTop), after: finite(css.marginBottom),
          keep: css.breakAfter === 'avoid' || css.breakAfter === 'avoid-page' };
      });
      const batches = []; let current = [], used = 0, margin = 0;
      metrics.forEach((item, index) => {
        const gap = current.length ? Math.max(margin, item.before) : item.before;
        const next = metrics[index + 1];
        const keptHeight = item.keep && next ? Math.max(item.after, next.before) + next.height : 0;
        if (current.length && used + gap + item.height + keptHeight > limit + 1) {
          batches.push(current); current = []; used = 0; margin = 0;
        }
        used += (current.length ? Math.max(margin, item.before) : item.before) + item.height;
        margin = item.after; current.push(item.block);
      });
      if (current.length) batches.push(current);
      const fragment = document.createDocumentFragment();
      for (const blocks of batches) {
        const page = source.cloneNode(false), body = article.cloneNode(false);
        page.dataset.folioPage = 'true';
        page.style.minHeight = `${pageHeight}px`;
        // No fixed height: an unbreakable drawing/merged row remains visible.
        page.style.height = 'auto';
        if (header) page.appendChild(header.cloneNode(true));
        blocks.forEach((block) => body.appendChild(block)); page.appendChild(body);
        if (footer) page.appendChild(footer.cloneNode(true));
        fragment.appendChild(page);
      }
      source.replaceWith(fragment);
      // Yield between source pages, not once for every paragraph.
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    positionAnchors(root);
  }

  function fit(root, viewport) {
    const style = getComputedStyle(viewport);
    const width = Math.max(1, viewport.clientWidth - finite(style.paddingLeft) - finite(style.paddingRight));
    const pages = Array.from(root.querySelectorAll('.docx-wrapper > section.docx'));
    // Read all unzoomed widths first; interleaving zoom writes and width reads
    // would force a new layout once per page on a long document.
    const widths = pages.map((page) => page.offsetWidth);
    pages.forEach((page, index) => {
      page.style.zoom = String(Math.min(1, width / Math.max(1, widths[index])));
    });
  }

  window.FolioDocx = Object.freeze({ imageProperties, renderImage, drawingProperties,
    renderDrawing, positionAnchors, orderStyles, paginate, fit });
})();
