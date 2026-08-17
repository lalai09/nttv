(function () {
  // ===== Tự phục hồi nếu bị xóa =====
  const HELPER_ID = 'noitu-helper';
  let savedPosition = null; // nhớ vị trí kéo thả

  function createHelper() {
    if (document.getElementById(HELPER_ID)) return; // đã có rồi thì thôi

    const isMobile = window.matchMedia('(max-width: 640px)').matches || ('ontouchstart' in window && window.innerWidth < 900);
    const panel = document.createElement('div');
    panel.id = HELPER_ID;
    panel.innerHTML = `
      <div id="noitu-header" style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;cursor:grab;">
        <div style="font-weight:700;font-size:15px;">🧠 Gợi ý Nối Từ</div>
        <div style="display:flex;align-items:center;gap:8px;">
          <div id="noitu-status" style="font-size:11px;color:#10b981;">Sẵn sàng</div>
          <button id="noitu-toggle" style="
            border:none;background:#ecfdf5;color:#065f46;border-radius:8px;
            width:28px;height:28px;font-size:15px;font-weight:700;cursor:pointer;
            display:flex;align-items:center;justify-content:center;
          ">−</button>
        </div>
      </div>
      <div id="noitu-body">
        <div id="noitu-current" style="
          background: linear-gradient(135deg, #ecfdf5, #d1fae5);
          padding: 10px 12px; border-radius: 10px; margin-bottom: 12px;
          font-size: 16px; font-weight: 600; text-align: center;
          border: 1px solid #6ee7b7; color: #065f46;
        ">Đang tìm từ...</div>
        <div id="noitu-result" style="
          display: flex; flex-wrap: wrap; gap: 8px;
          max-height: ${isMobile ? '38vh' : '380px'}; overflow-y: auto; padding: 2px;
          -webkit-overflow-scrolling: touch;
        "></div>
        <div style="margin-top:10px;font-size:11px;color:#6b7280;text-align:center;line-height:1.45;">
          Chạm chữ → copy/dán
        </div>
      </div>
    `;

    Object.assign(panel.style, {
      position: 'fixed',
      top: isMobile ? 'auto' : '90px',
      bottom: isMobile ? '12px' : 'auto',
      right: isMobile ? '8px' : '20px',
      left: isMobile ? '8px' : 'auto',
      width: isMobile ? 'auto' : '320px',
      maxWidth: isMobile ? 'none' : '320px',
      background: '#ffffff',
      border: '2px solid #10b981',
      borderRadius: '16px',
      padding: isMobile ? '12px 14px' : '16px',
      zIndex: '999999',
      boxShadow: '0 12px 40px rgba(16,185,129,0.25)',
      fontFamily: 'system-ui, -apple-system, sans-serif',
      userSelect: 'none',
      touchAction: 'none',
      boxSizing: 'border-box'
    });

    // Khôi phục vị trí đã kéo trước đó (nếu có)
    if (savedPosition) {
      panel.style.left = savedPosition.left;
      panel.style.top = savedPosition.top;
      panel.style.right = 'auto';
      panel.style.bottom = 'auto';
    }

    document.body.appendChild(panel);

    // ===== Các biến DOM =====
    const currentEl = document.getElementById('noitu-current');
    const resultEl = document.getElementById('noitu-result');
    const statusEl = document.getElementById('noitu-status');
    const bodyEl = document.getElementById('noitu-body');
    const toggleBtn = document.getElementById('noitu-toggle');
    const headerEl = document.getElementById('noitu-header');

    // Thu gọn / mở rộng
    let collapsed = isMobile;
    function applyCollapsed() {
      bodyEl.style.display = collapsed ? 'none' : 'block';
      toggleBtn.textContent = collapsed ? '+' : '−';
    }
    applyCollapsed();
    toggleBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      collapsed = !collapsed;
      applyCollapsed();
    });

    // ===== Kho từ Firebase =====
    const FIREBASE_DB_URL = "https://khotu-fc3e7-default-rtdb.asia-southeast1.firebasedatabase.app";
    const byFirst = new Map();
    const contCount = new Map();
    const trapFirst = new Map();
    const trapSet = new Set();
    let lastWord = '';
    let isReady = false;

    statusEl.textContent = 'Đang tải kho từ...';
    statusEl.style.color = '#d97706';

    function buildIndex(entries) {
      byFirst.clear();
      contCount.clear();
      trapFirst.clear();
      trapSet.clear();
      for (const entry of entries) {
        const word = (typeof entry === 'string') ? entry : entry.w;
        const trap = (typeof entry === 'object' && entry) ? !!entry.trap : false;
        if (!word) continue;
        const norm = word.trim().toLowerCase().replace(/\s+/g, ' ');
        if (trap) trapSet.add(norm);
        const parts = norm.split(/\s+/);
        if (parts.length !== 2) continue;
        const first = parts[0];
        if (!byFirst.has(first)) byFirst.set(first, []);
        byFirst.get(first).push(norm);
      }
      for (const [k, arr] of byFirst) {
        contCount.set(k, arr.length);
        trapFirst.set(k, arr.some(w => trapSet.has(w)));
      }
    }

    function loadWords() {
      return fetch(`${FIREBASE_DB_URL}/words.json`)
        .then(res => {
          if (!res.ok) throw new Error('HTTP ' + res.status);
          return res.json();
        })
        .then(data => {
          const entries = data ? Object.values(data) : [];
          buildIndex(entries);
          isReady = true;
          statusEl.textContent = `Sẵn sàng (${entries.length} từ · ${byFirst.size} âm)`;
          statusEl.style.color = '#10b981';
          if (lastWord) suggest(lastWord);
        })
        .catch(err => {
          isReady = false;
          statusEl.textContent = 'Lỗi tải kho từ - thử lại...';
          statusEl.style.color = '#dc2626';
          console.error('[Nối từ] Lỗi tải Firebase:', err);
        });
    }
    loadWords();
    setInterval(loadWords, 15000);

    // ===== Logic gợi ý =====
    function lastSyllable(w) {
      return w.trim().toLowerCase().split(/\s+/).pop();
    }
    function contCountOf(word) {
      return contCount.get(lastSyllable(word)) || 0;
    }
    function isDeadEndWord(word) {
      return contCountOf(word) === 0;
    }
    function isRiskyTrap(word) {
      const ns = lastSyllable(word);
      const opts = byFirst.get(ns) || [];
      if (opts.length === 0) return false;
      if (trapFirst.get(ns)) return true;
      for (let i = 0; i < opts.length; i++) {
        if (isDeadEndWord(opts[i])) return true;
      }
      return false;
    }
    function getLastSyllable(text) {
      if (!text) return '';
      text = text.trim().toLowerCase().replace(/[.,!?]/g, '');
      return text.split(/\s+/).pop() || '';
    }
    function findCurrentWord() {
      const candidates = [];
      document.querySelectorAll('div, span, p, h1, h2, h3, h4').forEach(el => {
        const text = (el.innerText || el.textContent || '').trim();
        if (/^[a-záàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ\s]{3,22}$/i.test(text) &&
            text.split(/\s+/).length === 2 && el.offsetParent !== null) {
          const style = window.getComputedStyle(el);
          const fontSize = parseFloat(style.fontSize) || 0;
          const rect = el.getBoundingClientRect();
          if (fontSize >= 18 && rect.top > 80 && rect.top < window.innerHeight - 120) {
            candidates.push({ text, fontSize, top: rect.top });
          }
        }
      });
      if (!candidates.length) return null;
      candidates.sort((a, b) => b.fontSize - a.fontSize || Math.abs(a.top - 280) - Math.abs(b.top - 280));
      return candidates[0].text;
    }

    function chipHtml(full, kind) {
      const second = full.split(/\s+/)[1];
      const marked = kind === 'trap';
      const styles = {
        trap: { bg: 'rgba(255,215,0,.16)', border: '#f5c518', color: '#92400e', mark: '★' },
        dead: { bg: 'rgba(255,92,122,.12)', border: 'rgba(255,92,122,.55)', color: '#be123c', mark: '✗' },
        risk: { bg: 'rgba(255,183,0,.12)', border: 'rgba(255,183,0,.5)', color: '#b45309', mark: '✗' },
        ok: { bg: '#f0fdf4', border: '#86efac', color: '#166534', mark: '' }
      };
      const s = styles[kind] || styles.ok;
      const mark = s.mark ? `<span style="font-weight:800;margin-right:3px;">${s.mark}</span>` : '';
      return `<div class="sugg" data-word="${second}" data-full="${full}" style="
        display:inline-flex;align-items:center;
        padding:${isMobile ? '7px 12px' : '5px 11px'};
        background:${s.bg};border:1.5px solid ${s.border};border-radius:999px;
        cursor:pointer;font-size:${isMobile ? '14px' : '13px'};
        font-weight:${marked ? '700' : '500'};color:${s.color};white-space:nowrap;
      ">
        <span class="sugg-text">${mark}${second}</span>
      </div>`;
    }

    function sectionHtml(title, color, items, kind) {
      if (!items.length) return '';
      const chips = items.map(w => chipHtml(w, kind)).join('');
      return `<div style="margin-bottom:10px;">
        <div style="
          font-size:11px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;
          color:${color};margin:0 0 6px;display:flex;align-items:center;gap:6px;
        ">
          <span style="width:6px;height:6px;border-radius:50%;background:${color};display:inline-block;"></span>
          ${title}
          <span style="font-weight:500;opacity:.7;">(${items.length})</span>
        </div>
        <div style="display:flex;flex-wrap:wrap;gap:6px;">${chips}</div>
      </div>`;
    }

    function suggest(word) {
      if (!word) {
        currentEl.textContent = 'Chưa tìm thấy từ';
        resultEl.innerHTML = '';
        return;
      }
      currentEl.textContent = word;
      if (!isReady) {
        resultEl.innerHTML = `<div style="color:#d97706;font-size:13px;">Đang tải từ điển...</div>`;
        return;
      }
      const key = getLastSyllable(word);
      const list = byFirst.get(key) || [];
      if (!list.length) {
        resultEl.innerHTML = `<div style="color:#d97706;font-size:13px;padding:6px;">Chưa có gợi ý cho "${key}"</div>`;
        return;
      }
      const traps = [], deads = [], risks = [], oks = [];
      for (let i = 0; i < list.length; i++) {
        const full = list[i];
        if (trapSet.has(full)) { traps.push(full); continue; }
        if (isDeadEndWord(full)) { deads.push(full); continue; }
        if (isRiskyTrap(full)) { risks.push(full); continue; }
        oks.push(full);
      }
      const byCont = (a, b) => contCountOf(a) - contCountOf(b);
      traps.sort(byCont);
      deads.sort(byCont);
      risks.sort(byCont);
      oks.sort(byCont);
      const lim = isMobile ? 12 : 20;
      const more = (arr) => arr.length > lim ? arr.length - lim : 0;
      resultEl.innerHTML =
        sectionHtml('★ Nên dùng (bẫy)', '#b45309', traps.slice(0, lim), 'trap') +
        sectionHtml('✗ Cụt — hết đường', '#be123c', deads.slice(0, lim), 'dead') +
        sectionHtml('Gợi ý thường', '#166534', oks.slice(0, lim), 'ok') +
        sectionHtml('✗ Không nên dùng', '#d97706', risks.slice(0, lim), 'risk') +
        ((more(traps) + more(deads) + more(risks) + more(oks)) > 0
          ? `<div style="font-size:11px;color:#9ca3af;text-align:center;margin-top:4px;">
              Tổng ${list.length} từ · chỉ hiện tối đa ${lim}/nhóm
            </div>`
          : `<div style="font-size:11px;color:#9ca3af;text-align:center;margin-top:4px;">
              Tổng ${list.length} từ
            </div>`);

      resultEl.querySelectorAll('.sugg').forEach(el => {
        el.onmouseenter = () => { el.style.filter = 'brightness(0.92)'; el.style.transform = 'translateY(-1px)'; };
        el.onmouseleave = () => { el.style.filter = ''; el.style.transform = ''; };
        el.onclick = () => {
          const textToPaste = el.dataset.full || el.dataset.word;
          navigator.clipboard.writeText(textToPaste).catch(() => {});
          autoPaste(textToPaste);
          const oldBg = el.style.background;
          el.style.background = '#059669';
          el.querySelector('.sugg-text').style.color = 'white';
          setTimeout(() => { el.style.background = oldBg; }, 400);
        };
      });
    }

    // ===== Auto paste =====
    function autoPaste(text) {
      const noituInput = document.querySelector('input.word-link-answer-input, input[class*="word-link-answer"]');
      if (noituInput && isEditable(noituInput)) {
        if (fillEditable(noituInput, text)) {
          noituInput.focus();
          return true;
        }
      }
      let target = document.activeElement;
      if (isEditable(target)) {
        if (fillEditable(target, text)) return true;
      }
      const candidates = [];
      const all = document.querySelectorAll('input, textarea, [contenteditable="true"], [contenteditable=""], [role="textbox"]');
      all.forEach(el => {
        if (!isVisible(el) || el.readOnly || el.disabled) return;
        const rect = el.getBoundingClientRect();
        if (rect.width < 60 || rect.height < 18) return;
        const style = window.getComputedStyle(el);
        const fontSize = parseFloat(style.fontSize) || 14;
        const placeholder = ((el.placeholder || el.getAttribute('aria-label') || el.getAttribute('data-placeholder') || '') + '').toLowerCase();
        let score = fontSize * 3;
        if (rect.top > 80 && rect.top < window.innerHeight - 120) score += 40;
        if (/từ|nhập|word|câu|trả lời|answer|type|điền/.test(placeholder)) score += 50;
        if (el.tagName === 'INPUT' && (el.type === 'text' || el.type === '' || !el.type)) score += 20;
        if (el.tagName === 'TEXTAREA') score += 15;
        if (el.isContentEditable) score += 10;
        if (rect.top < 50) score -= 30;
        if (rect.top > window.innerHeight - 80) score -= 20;
        candidates.push({ el, score });
      });
      if (candidates.length === 0) {
        try { document.execCommand('insertText', false, text); } catch(e) {}
        return false;
      }
      candidates.sort((a, b) => b.score - a.score);
      for (const cand of candidates.slice(0, 5)) {
        if (fillEditable(cand.el, text)) {
          cand.el.focus();
          return true;
        }
      }
      return false;
    }

    function isEditable(el) {
      if (!el || el === document.body || el === document.documentElement) return false;
      if (el.readOnly || el.disabled) return false;
      if (el.tagName === 'INPUT') {
        const t = (el.type || 'text').toLowerCase();
        return ['text', 'search', 'url', 'tel', 'email', ''].includes(t);
      }
      if (el.tagName === 'TEXTAREA') return true;
      if (el.isContentEditable) return true;
      return false;
    }
    function isVisible(el) {
      if (!el || el.offsetParent === null) return false;
      const style = window.getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') return false;
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    }
    function fillEditable(el, text) {
      try {
        el.focus();
        if (el.isContentEditable) {
          const selection = window.getSelection();
          const range = document.createRange();
          range.selectNodeContents(el);
          selection.removeAllRanges();
          selection.addRange(range);
          document.execCommand('delete', false, null);
          document.execCommand('insertText', false, text);
          el.dispatchEvent(new InputEvent('input', { bubbles: true, data: text, inputType: 'insertText' }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        }
        const proto = el.tagName === 'TEXTAREA'
          ? window.HTMLTextAreaElement.prototype
          : window.HTMLInputElement.prototype;
        const nativeSetter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
        if (nativeSetter) nativeSetter.call(el, text);
        else el.value = text;
        el.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
        el.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
        el.dispatchEvent(new InputEvent('input', { bubbles: true, cancelable: true, data: text, inputType: 'insertText' }));
        el.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Unidentified', code: '' }));
        el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: 'Unidentified', code: '' }));
        try {
          const pasteEvent = new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: new DataTransfer() });
          pasteEvent.clipboardData.setData('text/plain', text);
          el.dispatchEvent(pasteEvent);
        } catch(e) {}
        return true;
      } catch (err) {
        console.warn('[NOITU] Lỗi khi fill:', err);
        return false;
      }
    }

    function tick() {
      const word = findCurrentWord();
      if (word && word !== lastWord) {
        lastWord = word;
        suggest(word);
      }
    }

    // ===== Kéo thả =====
    let isDragging = false, ox, oy;
    function startDrag(clientX, clientY, target) {
      if (target.closest('.sugg') || target.closest('#noitu-toggle')) return false;
      const rect = panel.getBoundingClientRect();
      ox = clientX - rect.left;
      oy = clientY - rect.top;
      panel.style.left = rect.left + 'px';
      panel.style.top = rect.top + 'px';
      panel.style.right = 'auto';
      panel.style.bottom = 'auto';
      return true;
    }
    function moveDrag(clientX, clientY) {
      const w = panel.offsetWidth, h = panel.offsetHeight;
      let left = clientX - ox, top = clientY - oy;
      left = Math.max(4, Math.min(window.innerWidth - w - 4, left));
      top = Math.max(4, Math.min(window.innerHeight - h - 4, top));
      panel.style.left = left + 'px';
      panel.style.top = top + 'px';
      // Lưu vị trí để khôi phục sau khi bị xóa
      savedPosition = { left: panel.style.left, top: panel.style.top };
    }
    panel.addEventListener('mousedown', e => {
      isDragging = startDrag(e.clientX, e.clientY, e.target);
    });
    document.addEventListener('mousemove', e => {
      if (!isDragging) return;
      moveDrag(e.clientX, e.clientY);
    });
    document.addEventListener('mouseup', () => isDragging = false);

    headerEl.addEventListener('touchstart', e => {
      const t = e.touches[0];
      isDragging = startDrag(t.clientX, t.clientY, e.target);
    }, { passive: true });
    panel.addEventListener('touchmove', e => {
      if (!isDragging) return;
      const t = e.touches[0];
      moveDrag(t.clientX, t.clientY);
      e.preventDefault();
    }, { passive: false });
    panel.addEventListener('touchend', () => isDragging = false);

    tick();
    // Lưu interval để tránh tạo nhiều lần
    if (!window.__noituTickInterval) {
      window.__noituTickInterval = setInterval(tick, 1100);
    }

    console.log('%c✅ Tool Nối Từ đã sẵn sàng (có tự phục hồi)', 'color:#10b981;font-weight:bold');
  }

  // Chạy lần đầu
  createHelper();

  // ===== Cơ chế tự phục hồi =====
  if (!window.__noituWatchdog) {
    window.__noituWatchdog = setInterval(() => {
      if (!document.getElementById(HELPER_ID)) {
        console.log('%c🔄 Panel bị mất → tự tạo lại...', 'color:#f59e0b');
        createHelper();
      }
    }, 1500);
  }
})();
