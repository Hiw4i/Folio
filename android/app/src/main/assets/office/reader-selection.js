/* Native browser selection, Flutter-owned toolbar. Only normalized endpoint
   geometry crosses the bridge during a drag; selected text is read on Copy. */
(() => {
  'use strict';
  function create({ viewport, content, post, cancelMotion }) {
    let disposed = false, frame = 0, settleTimer = 0, lastMessage = JSON.stringify({ active: false });
    let pointerDown = false, scrolling = false, changing = false, selectionTimer = 0;
    let geometry = { x: 0.5, top: 0.2, bottom: 0.25 };
    const pointers = new Set();
    const selection = () => window.getSelection();
    function isActive() {
      const value = selection();
      return !!value && !value.isCollapsed && value.rangeCount > 0
        && content.contains(value.anchorNode) && content.contains(value.focusNode);
    }
    function endpoint(node, offset, end) {
      const range = document.createRange();
      range.setStart(node, offset); range.collapse(true);
      let rect = range.getBoundingClientRect();
      // Some WebViews return an empty rectangle for a collapsed range. Measure
      // one adjacent character, never all glyphs in a multi-page selection.
      if (!rect.height && node.nodeType === Node.TEXT_NODE && node.length) {
        const index = Math.min(Math.max(0, offset - (end ? 1 : 0)), node.length - 1);
        range.setStart(node, index); range.setEnd(node, index + 1);
        rect = range.getBoundingClientRect();
      }
      return rect;
    }
    function publish() {
      frame = 0;
      if (disposed) return;
      let payload = { active: false };
      if (isActive()) {
        const showMenu = !pointerDown && !scrolling && !changing;
        // Native Android handles do not reliably emit DOM pointer events.
        // A short quiet-period keeps the pill hidden during their drag and
        // avoids measuring/rebuilding glass on every selected-character change.
        if (showMenu) {
          const value = selection(), range = value.getRangeAt(0);
          const first = endpoint(range.startContainer, range.startOffset, false);
          const last = endpoint(range.endContainer, range.endOffset, true);
          const visual = window.visualViewport;
          const width = Math.max(1, visual?.width || viewport.clientWidth);
          const height = Math.max(1, visual?.height || viewport.clientHeight);
          const left = visual?.offsetLeft || 0, top = visual?.offsetTop || 0;
          const visible = (r) => r.height > 0 && r.bottom > top && r.top < top + height
            && r.right >= left && r.left <= left + width;
          // Do not walk the document to find a visible character when both ends
          // are off-screen (Select all). A stable viewport anchor is sufficient.
          const anchor = visible(first) ? first : visible(last) ? last : null;
          const x = anchor ? (anchor.left - left) / width : 0.5;
          const above = anchor ? (anchor.top - top) / height : 0.2;
          const below = visible(last) ? (last.bottom - top) / height
            : anchor ? (anchor.bottom - top) / height : 0.25;
          geometry = { x: Math.max(0, Math.min(1, x)),
            top: Math.max(0, Math.min(1, above)),
            bottom: Math.max(0, Math.min(1, below)) };
        }
        payload = { active: true, showMenu, ...geometry };
      }
      const encoded = JSON.stringify(payload);
      if (encoded === lastMessage) return;
      lastMessage = encoded; post('selection', payload);
    }
    function schedule() {
      if (!disposed && !frame) frame = requestAnimationFrame(publish);
    }
    function changed() {
      clearTimeout(selectionTimer);
      changing = isActive();
      if (changing) {
        cancelMotion();
        selectionTimer = setTimeout(() => { changing = false; schedule(); }, 80);
      }
      schedule();
    }
    function down(event) {
      pointers.add(event.pointerId); pointerDown = true; schedule();
    }
    function up(event) {
      pointers.delete(event.pointerId); pointerDown = pointers.size > 0; schedule();
    }
    function onScroll() {
      if (!isActive()) return;
      scrolling = true; schedule(); clearTimeout(settleTimer);
      settleTimer = setTimeout(() => { scrolling = false; schedule(); }, 100);
    }
    function clear() {
      if (isActive()) selection().removeAllRanges();
      schedule();
    }
    function selectAll() {
      if (disposed) return;
      cancelMotion();
      const value = selection();
      if (!value) return;
      value.selectAllChildren(content); schedule();
    }
    function copyText() {
      return !disposed && isActive() ? selection().toString() : '';
    }
    function resume() {
      // Native selection handles are not DOM pointer targets on every WebView.
      // A selectionchange still updates the anchor; resuming after focus/resize
      // makes the menu recover from an interrupted native gesture.
      pointers.clear(); pointerDown = false; scrolling = false; schedule();
    }
    function dispose() {
      disposed = true; cancelAnimationFrame(frame); clearTimeout(settleTimer);
      clearTimeout(selectionTimer);
      pointers.clear();
      document.removeEventListener('selectionchange', changed);
      viewport.removeEventListener('pointerdown', down);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', up);
      viewport.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', resume);
      window.removeEventListener('focus', resume);
      window.visualViewport?.removeEventListener('resize', schedule);
      window.visualViewport?.removeEventListener('scroll', schedule);
    }
    document.addEventListener('selectionchange', changed);
    viewport.addEventListener('pointerdown', down, { passive: true });
    window.addEventListener('pointerup', up, { passive: true });
    window.addEventListener('pointercancel', up, { passive: true });
    viewport.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', resume);
    window.addEventListener('focus', resume);
    window.visualViewport?.addEventListener('resize', schedule);
    window.visualViewport?.addEventListener('scroll', schedule);
    return { isActive, selectAll, clear, copyText, refresh: schedule, dispose };
  }
  window.FolioReaderSelection = { create };
})();
