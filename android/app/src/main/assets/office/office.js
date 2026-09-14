(() => {
  'use strict';

  const params = new URLSearchParams(window.location.search);
  const format = params.get('format');
  const viewport = document.getElementById('viewport');
  const documentRoot = document.getElementById('document');
  const status = document.getElementById('status');
  const documentUrl = '/document/active';
  const state = {
    format,
    ready: false,
    position: 0,
    count: 0,
    hits: [],
    activeHit: -1,
    searchRevision: 0,
    lastScroll: 0,
    scrollFrame: 0,
    pointer: null,
  };

  document.body.dataset.format = format || 'unknown';

  function post(type, payload = {}) {
    const message = JSON.stringify({ type, ...payload });
    if (window.FolioBridge && typeof window.FolioBridge.postMessage === 'function') {
      window.FolioBridge.postMessage(message);
    }
  }

  function fail(message, recoverable = true) {
    status.hidden = false;
    status.textContent = message;
    post('error', { message, recoverable });
  }

  function pageElements() {
    if (format === 'docx') {
      return Array.from(documentRoot.querySelectorAll('.docx-wrapper > section.docx'));
    }
    return Array.from(documentRoot.querySelectorAll('.folio-slide-frame'));
  }

  function publishPosition(force = false) {
    const pages = pageElements();
    if (!pages.length) return;
    const viewportRect = viewport.getBoundingClientRect();
    const center = format === 'pptx'
      ? viewportRect.left + viewportRect.width / 2
      : viewportRect.top + viewportRect.height / 2;
    let closest = 0;
    let closestDistance = Number.POSITIVE_INFINITY;
    pages.forEach((page, index) => {
      const rect = page.getBoundingClientRect();
      const pageCenter = format === 'pptx'
        ? rect.left + rect.width / 2
        : rect.top + rect.height / 2;
      const distance = Math.abs(pageCenter - center);
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = index;
      }
    });
    if (force || closest !== state.position || pages.length !== state.count) {
      state.position = closest;
      state.count = pages.length;
      post('position', { current: closest + 1, count: pages.length });
    }
  }

  function onScroll() {
    if (state.scrollFrame) return;
    state.scrollFrame = requestAnimationFrame(() => {
      state.scrollFrame = 0;
      const current = format === 'pptx' ? viewport.scrollLeft : viewport.scrollTop;
      const delta = current - state.lastScroll;
      state.lastScroll = current;
      if (Math.abs(delta) > 0.5) post('scroll', { delta });
      publishPosition(false);
    });
  }

  function wrapSlides() {
    const slides = Array.from(documentRoot.querySelectorAll('.slide'));
    slides.forEach((slide) => {
      if (slide.parentElement?.classList.contains('folio-slide-frame')) return;
      const frame = document.createElement('section');
      frame.className = 'folio-slide-frame';
      slide.parentNode.insertBefore(frame, slide);
      frame.appendChild(slide);
    });
    layoutSlides();
  }

  function numericStyle(element, name, fallback) {
    const value = Number.parseFloat(element.style[name] || getComputedStyle(element)[name]);
    return Number.isFinite(value) && value > 0 ? value : fallback;
  }

  function layoutSlides() {
    if (format !== 'pptx') return;
    // Landscape is immersive: the viewport keeps no chrome padding (see the
    // orientation query in office.css), so slides fit the full viewport edge
    // to edge. Portrait keeps the top/bottom chrome reservation but also
    // goes edge to edge horizontally. All math is viewport-based, never
    // per-frame: off-screen frames skipped by `content-visibility: auto`
    // would otherwise report estimated sizes and mis-scale their slides.
    const landscape = viewport.clientWidth > viewport.clientHeight;
    const padTop = landscape ? 0 : 74;
    const padBottom = landscape ? 0 : 108;
    const availableWidth = Math.max(1, viewport.clientWidth);
    const availableHeight = Math.max(
      1,
      viewport.clientHeight - padTop - padBottom,
    );
    documentRoot.querySelectorAll('.folio-slide-frame > .slide').forEach((slide) => {
      const width = numericStyle(slide, 'width', 960);
      const height = numericStyle(slide, 'height', 540);
      const scale = Math.min(availableWidth / width, availableHeight / height);
      slide.style.transform = `scale(${scale})`;
      slide.style.left = `${(viewport.clientWidth - width * scale) / 2}px`;
      slide.style.top = `${(viewport.clientHeight - height * scale) / 2}px`;
    });
  }

  function waitForSlides() {
    let stablePasses = 0;
    let previousCount = 0;
    const started = performance.now();
    const check = () => {
      const count = documentRoot.querySelectorAll('.slide').length;
      stablePasses = count > 0 && count === previousCount ? stablePasses + 1 : 0;
      previousCount = count;
      if (stablePasses >= 3) {
        wrapSlides();
        finishReady();
        return;
      }
      if (performance.now() - started > 30000) {
        fail('PowerPoint rendering did not finish.', true);
        return;
      }
      window.setTimeout(check, 120);
    };
    check();
  }

  function paginateDocx() {
    const wrapper = documentRoot.querySelector('.docx-wrapper');
    if (!wrapper) return;
    const sourcePages = Array.from(wrapper.querySelectorAll(':scope > section.docx'));
    sourcePages.forEach((sourcePage) => {
      sourcePage.style.contentVisibility = 'visible';
      const style = getComputedStyle(sourcePage);
      const pageHeight = Number.parseFloat(style.minHeight);
      const paddingTop = Number.parseFloat(style.paddingTop) || 0;
      const paddingBottom = Number.parseFloat(style.paddingBottom) || 0;
      const contentHeight = pageHeight - paddingTop - paddingBottom;
      const articles = Array.from(sourcePage.querySelectorAll(':scope > article'));
      const blocks = articles.flatMap((article) => Array.from(article.children));
      if (!Number.isFinite(pageHeight) || pageHeight <= 0 || !blocks.length) return;

      const header = sourcePage.querySelector(':scope > header');
      const footer = sourcePage.querySelector(':scope > footer');
      const trailing = Array.from(sourcePage.children).filter((child) =>
        child.tagName !== 'HEADER' && child.tagName !== 'ARTICLE' && child.tagName !== 'FOOTER');
      const articleTemplate = articles[0];
      const pages = [];

      function newPage() {
        const page = sourcePage.cloneNode(false);
        page.dataset.folioPage = 'true';
        page.style.height = `${pageHeight}px`;
        page.style.minHeight = `${pageHeight}px`;
        page.style.contentVisibility = 'visible';
        if (header) page.appendChild(header.cloneNode(true));
        const article = articleTemplate.cloneNode(false);
        page.appendChild(article);
        if (footer) page.appendChild(footer.cloneNode(true));
        wrapper.insertBefore(page, sourcePage);
        pages.push({ page, article });
        return pages[pages.length - 1];
      }

      let current = newPage();
      blocks.forEach((block) => {
        current.article.appendChild(block);
        const overflow = current.article.scrollHeight > contentHeight + 1;
        if (overflow && current.article.children.length > 1) {
          current.article.removeChild(block);
          current = newPage();
          current.article.appendChild(block);
        }
        if (current.article.scrollHeight > contentHeight + 1 &&
            current.article.children.length === 1) {
          // Keep a single oversized table or drawing visible instead of clipping it.
          current.page.style.height = 'auto';
          current.page.style.minHeight = `${pageHeight}px`;
        }
      });
      trailing.forEach((child) => current.page.appendChild(child));
      sourcePage.remove();
      pages.forEach(({ page }) => { page.style.contentVisibility = ''; });
    });
  }

  function finishReady() {
    const count = pageElements().length;
    if (!count) {
      fail('The document contains no displayable pages.', false);
      return;
    }
    state.ready = true;
    state.count = count;
    status.hidden = true;
    publishPosition(true);
    post('ready', {
      count,
      hasText: documentRoot.innerText.trim().length > 0,
    });
  }

  async function renderDocx() {
    const response = await fetch(documentUrl, { cache: 'no-store', credentials: 'omit' });
    if (!response.ok) throw new Error('The Word source is unavailable.');
    const buffer = await response.arrayBuffer();
    await window.docx.renderAsync(buffer, documentRoot, documentRoot, {
      className: 'docx',
      inWrapper: true,
      ignoreWidth: false,
      ignoreHeight: false,
      ignoreFonts: false,
      breakPages: true,
      renderHeaders: true,
      renderFooters: true,
      renderFootnotes: true,
      renderEndnotes: true,
      useBase64URL: true,
    });
    paginateDocx();
    finishReady();
  }

  function renderPptx() {
    const pptxJsZip = window.JSZip;
    if (!window.jQuery?.fn?.pptxToHtml) {
      throw new Error('The PowerPoint renderer is unavailable.');
    }
    // PPTXjs requires JSZip 2; docx-preview is loaded after it with JSZip 3.
    window.JSZip = window.folioPptxJsZip || pptxJsZip;
    window.jQuery(documentRoot).pptxToHtml({
      pptxFileUrl: documentUrl,
      slideMode: false,
      keyBoardShortCut: false,
      mediaProcess: false,
      themeProcess: true,
      incSlide: { height: 0, width: 0 },
    });
    waitForSlides();
  }

  function clearSearch() {
    documentRoot.querySelectorAll('mark[data-folio-search]').forEach((mark) => {
      mark.replaceWith(document.createTextNode(mark.textContent || ''));
    });
    documentRoot.normalize();
    state.hits = [];
    state.activeHit = -1;
  }

  function searchableTextNodes() {
    const walker = document.createTreeWalker(documentRoot, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || !node.nodeValue?.trim()) return NodeFilter.FILTER_REJECT;
        if (parent.closest('script, style, mark[data-folio-search], [aria-hidden="true"]')) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    return nodes;
  }

  function search(query) {
    const revision = ++state.searchRevision;
    clearSearch();
    const normalized = String(query || '').trim().toLocaleLowerCase('en-US');
    if (!normalized) {
      post('search', { count: 0, active: -1, searching: false });
      return;
    }
    post('search', { count: 0, active: -1, searching: true });
    requestAnimationFrame(() => {
      if (revision !== state.searchRevision) return;
      searchableTextNodes().forEach((node) => {
        const text = node.nodeValue || '';
        const lower = text.toLocaleLowerCase('en-US');
        const indexes = [];
        let from = 0;
        while (from <= lower.length - normalized.length) {
          const index = lower.indexOf(normalized, from);
          if (index < 0) break;
          indexes.push(index);
          from = index + Math.max(1, normalized.length);
        }
        for (let i = indexes.length - 1; i >= 0; i -= 1) {
          const index = indexes[i];
          const range = document.createRange();
          range.setStart(node, index);
          range.setEnd(node, index + normalized.length);
          const mark = document.createElement('mark');
          mark.dataset.folioSearch = 'match';
          range.surroundContents(mark);
        }
      });
      state.hits = Array.from(documentRoot.querySelectorAll('mark[data-folio-search]'));
      state.activeHit = state.hits.length ? 0 : -1;
      revealActiveHit(false);
      post('search', {
        count: state.hits.length,
        active: state.activeHit,
        searching: false,
      });
    });
  }

  function revealActiveHit(smooth = true) {
    state.hits.forEach((hit, index) => {
      hit.dataset.folioSearch = index === state.activeHit ? 'active' : 'match';
    });
    const hit = state.hits[state.activeHit];
    if (!hit) return;
    if (format === 'pptx') {
      const frame = hit.closest('.folio-slide-frame');
      frame?.scrollIntoView({ behavior: smooth ? 'smooth' : 'auto', inline: 'center' });
    } else {
      hit.scrollIntoView({ behavior: smooth ? 'smooth' : 'auto', block: 'center' });
    }
    window.setTimeout(() => publishPosition(true), smooth ? 260 : 0);
  }

  function stepHit(delta) {
    if (!state.hits.length) return;
    state.activeHit = (state.activeHit + delta + state.hits.length) % state.hits.length;
    revealActiveHit(true);
    post('search', {
      count: state.hits.length,
      active: state.activeHit,
      searching: false,
    });
  }

  function goToPosition(index, smooth = true) {
    const pages = pageElements();
    const target = pages[Math.max(0, Math.min(Number(index) || 0, pages.length - 1))];
    if (!target) return;
    target.scrollIntoView({
      behavior: smooth ? 'smooth' : 'auto',
      block: format === 'docx' ? 'start' : 'nearest',
      inline: format === 'pptx' ? 'center' : 'nearest',
    });
  }

  window.FolioOffice = {
    search,
    nextHit: () => stepHit(1),
    previousHit: () => stepHit(-1),
    goToPosition,
  };

  document.addEventListener('click', (event) => {
    const link = event.target.closest?.('a');
    if (link) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);
  document.addEventListener('dragstart', (event) => event.preventDefault(), true);
  viewport.addEventListener('scroll', onScroll, { passive: true });
  viewport.addEventListener('pointerdown', (event) => {
    state.pointer = { id: event.pointerId, x: event.clientX, y: event.clientY };
  }, { passive: true });
  viewport.addEventListener('pointerup', (event) => {
    const pointer = state.pointer;
    state.pointer = null;
    if (!pointer || pointer.id !== event.pointerId) return;
    const distance = Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y);
    if (distance > 10 || !window.getSelection()?.isCollapsed) return;
    if (format === 'pptx') {
      if (event.clientX < viewport.clientWidth * 0.24) goToPosition(state.position - 1);
      else if (event.clientX > viewport.clientWidth * 0.76) goToPosition(state.position + 1);
      else post('tap');
    } else {
      post('tap');
    }
  }, { passive: true });
  window.addEventListener('resize', () => {
    layoutSlides();
    publishPosition(true);
  });

  Promise.resolve()
    .then(() => {
      if (format === 'docx') return renderDocx();
      if (format === 'pptx') return renderPptx();
      throw new Error('Unsupported Office document format.');
    })
    .catch((error) => fail(error?.message || 'The document could not be rendered.', true));
})();
