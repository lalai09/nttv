(function () {
  if (document.getElementById('noitu-helper')) {
    document.getElementById('noitu-helper').remove();
  }

  const isMobile = window.matchMedia('(max-width: 640px)').matches || ('ontouchstart' in window && window.innerWidth < 900);

  const panel = document.createElement('div');
  panel.id = 'noitu-helper';
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
      <div style="margin-top:12px;font-size:11px;color:#6b7280;text-align:center;">
        ★ = bẫy đã đánh dấu • ✗ đỏ = cụt • ✗ cam = không nên dùng<br>
        (sau là cụt hoặc từ bẫy) • Chạm chữ → copy/dán<br>
        🪤 = đánh dấu bẫy • 🗑 = xoá • Kho Firebase
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
    background: '#ffffff', border: '2px solid #10b981', borderRadius: '16px',
    padding: isMobile ? '12px 14px' : '16px', zIndex: '999999',
    boxShadow: '0 12px 40px rgba(16,185,129,0.25)',
    fontFamily: 'system-ui, -apple-system, sans-serif', userSelect: 'none',
    touchAction: 'none',
    boxSizing: 'border-box'
  });
  document.body.appendChild(panel);

  const currentEl = document.getElementById('noitu-current');
  const resultEl = document.getElementById('noitu-result');
  const statusEl = document.getElementById('noitu-status');
  const bodyEl = document.getElementById('noitu-body');
  const toggleBtn = document.getElementById('noitu-toggle');
  const headerEl = document.getElementById('noitu-header');

  // Thu gọn / mở rộng (hữu ích trên điện thoại để tránh che bàn phím/nội dung)
  let collapsed = isMobile; // mặc định thu gọn trên điện thoại
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

  // ===== Kho từ: nạp từ Firebase Realtime Database =====
  const FIREBASE_DB_URL = "https://khotu-fc3e7-default-rtdb.asia-southeast1.firebasedatabase.app";

  const byFirst = new Map();   // âm đầu -> [từ đầy đủ, ...]
  const trapSet = new Set();   // các từ được đánh dấu thủ công là "nên dùng để bẫy"
  let lastWord = '';
  let isReady = false;

  statusEl.textContent = 'Đang tải kho từ...';
  statusEl.style.color = '#d97706';

  // Firebase key không được chứa . # $ [ ] / — chuẩn hoá giống hệt trang quản lý
  function toKey(word) {
    return encodeURIComponent(word.trim().toLowerCase()).replace(/\./g, '%2E');
  }

  function buildIndex(entries) {
    byFirst.clear();
    trapSet.clear();
    for (const entry of entries) {
      const word = (typeof entry === 'string') ? entry : entry.w;
      const trap = (typeof entry === 'object' && entry) ? !!entry.trap : false;
      if (!word) continue;
      if (trap) trapSet.add(word);
      const parts = word.trim().toLowerCase().split(/\s+/);
      if (parts.length !== 2) continue;
      const first = parts[0];
      if (!byFirst.has(first)) byFirst.set(first, []);
      byFirst.get(first).push(word);
    }
    // Giới hạn 80 gợi ý mỗi âm để tránh quá tải
    for (const [k, arr] of byFirst) {
      byFirst.set(k, arr.slice(0, 80));
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
        if (lastWord) suggest(lastWord); // gợi ý lại nếu đã có từ đang chờ
      })
      .catch(err => {
        isReady = false;
        statusEl.textContent = 'Lỗi tải kho từ - thử lại...';
        statusEl.style.color = '#dc2626';
        console.error('[Nối từ] Lỗi tải Firebase:', err);
      });
  }

  // Xoá một từ khỏi kho (đồng bộ với trang quản lý)
  function deleteWordRemote(word) {
    return fetch(`${FIREBASE_DB_URL}/words/${toKey(word)}.json`, { method: 'DELETE' })
      .then(() => loadWords());
  }

  // Bật/tắt đánh dấu "nên dùng để bẫy" cho một từ
  function toggleTrapRemote(word, newTrap) {
    return fetch(`${FIREBASE_DB_URL}/words/${toKey(word)}.json`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ w: word, trap: newTrap })
    }).then(() => loadWords());
  }

  loadWords();

  // Đồng bộ theo thời gian thực: khi ai đó thêm/xoá/đánh dấu từ trên trang quản lý,
  // tool sẽ tự cập nhật mà không cần tải lại trang (kiểm tra mỗi 15 giây).
  setInterval(loadWords, 15000);

  // ===== Logic đánh dấu đỏ =====
  function lastSyllable(w) {
    return w.trim().toLowerCase().split(/\s+/).pop();
  }
  function continuationsOf(word) {
    const ns = lastSyllable(word);
    return (byFirst.get(ns) || []).filter(x => x !== word);
  }
  function isDeadEndWord(word) {
    return continuationsOf(word).length === 0;
  }
  function isRiskyTrap(word) {
    const opts = continuationsOf(word);
    if (opts.length === 0) return false;
    // Không nên dùng nếu đối thủ có thể:
    // 1) chọn ngay một từ khiến lượt sau của bạn bị cụt, HOẶC
    // 2) chọn ngay một từ bẫy đã đánh dấu (🪤) — giống trang Nối Từ
    return opts.some(opt => isDeadEndWord(opt) || trapSet.has(opt));
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
    let list = byFirst.get(key) || [];

    // Sắp xếp y chang trang Nối Từ:
    // 1) từ đã đánh dấu bẫy (trap) lên trước
    // 2) trong cùng nhóm: ưu tiên từ có ít đường nối tiếp hơn (cụt / gần cụt)
    list = list.slice().sort((a, b) => {
      const aTrap = trapSet.has(a) ? 0 : 1;
      const bTrap = trapSet.has(b) ? 0 : 1;
      if (aTrap !== bTrap) return aTrap - bTrap;
      const aCount = continuationsOf(a).length;
      const bCount = continuationsOf(b).length;
      return aCount - bCount;
    });

    if (!list.length) {
      resultEl.innerHTML = `<div style="color:#d97706;font-size:13px;padding:6px;">Chưa có gợi ý cho "${key}"</div>`;
      return;
    }

    resultEl.innerHTML = list.map(full => {
      const second = full.split(/\s+/)[1];
      const marked = trapSet.has(full);
      const canContinue = continuationsOf(full).length > 0;
      const dead = !canContinue;
      const risky = canContinue && isRiskyTrap(full);

      // Màu & dấu y chang trang Nối Từ:
      // ★ / 🪤 = bẫy đã đánh dấu | ✗ đỏ = cụt | ✗ cam = không nên dùng (sau là cụt hoặc bẫy)
      let bg = '#f0fdf4', border = '#86efac', color = '#166534', mark = '';
      if (marked) {
        bg = 'rgba(255,215,0,.14)'; border = '#ffd54a'; color = '#b45309';
        mark = '<span style="font-weight:800;margin-right:3px;">★</span>';
      } else if (dead) {
        bg = 'rgba(255,92,122,.15)'; border = 'rgba(255,92,122,.6)'; color = '#e11d48';
        mark = '<span style="font-weight:800;margin-right:3px;">✗</span>';
      } else if (risky) {
        bg = 'rgba(255,183,0,.15)'; border = 'rgba(255,183,0,.6)'; color = '#d97706';
        mark = '<span style="font-weight:800;margin-right:3px;">✗</span>';
      }

      return `<div class="sugg" data-word="${second}" data-full="${full}" style="
        display:inline-flex; align-items:center; gap:6px;
        padding: ${isMobile ? '7px 8px 7px 14px' : '5px 6px 5px 12px'}; background: ${bg}; border: 1.5px solid ${border};
        border-radius: 999px; cursor: pointer; font-size: ${isMobile ? '14.5px' : '13.5px'}; font-weight: ${marked ? '700' : '500'};
        color: ${color}; transition: all 0.15s; white-space: nowrap;
      ">
        <span class="sugg-text">${mark}${second}</span>
        <button class="act-trap" data-full="${full}" title="Đánh dấu / bỏ đánh dấu bẫy" style="
          border:none;background:transparent;cursor:pointer;font-size:${isMobile ? '13px' : '12px'};
          padding:2px;line-height:1;opacity:${marked ? '1' : '0.35'};
        ">🪤</button>
        <button class="act-del" data-full="${full}" title="Xoá từ khỏi kho" style="
          border:none;background:transparent;cursor:pointer;font-size:${isMobile ? '13px' : '12px'};
          padding:2px;line-height:1;opacity:0.35;color:#dc2626;
        ">🗑</button>
      </div>`;
    }).join('');

    resultEl.querySelectorAll('.act-trap').forEach(btn => {
      btn.onclick = (e) => {
        e.stopPropagation();
        const word = btn.dataset.full;
        const newTrap = !trapSet.has(word);
        btn.style.opacity = '0.5';
        toggleTrapRemote(word, newTrap).then(() => suggest(lastWord));
      };
    });
    resultEl.querySelectorAll('.act-del').forEach(btn => {
      btn.onclick = (e) => {
        e.stopPropagation();
        const word = btn.dataset.full;
        if (!confirm(`Xoá "${word}" khỏi kho từ?`)) return;
        btn.style.opacity = '0.5';
        deleteWordRemote(word).then(() => suggest(lastWord));
      };
    });

    resultEl.querySelectorAll('.sugg').forEach(el => {
      el.onmouseenter = () => { el.style.filter = 'brightness(0.92)'; el.style.transform = 'translateY(-1px)'; };
      el.onmouseleave = () => { el.style.filter = ''; el.style.transform = ''; };
      el.onclick = (e) => {
        if (e.target.closest('.act-trap') || e.target.closest('.act-del')) return;
        // Ưu tiên dán CẢ TỪ (full word) vì noitu.fun yêu cầu nhập đủ 2 âm tiết
        // Nếu muốn chỉ dán âm tiết sau thì đổi thành el.dataset.word
        const textToPaste = el.dataset.full || el.dataset.word;
        
        // 1. Copy vào clipboard
        navigator.clipboard.writeText(textToPaste).catch(() => {});

        // 2. Tự động tìm ô input/textarea và dán
        autoPaste(textToPaste);

        // 3. Hiệu ứng visual
        const oldBg = el.style.background;
        el.style.background = '#059669';
        el.querySelector('.sugg-text').style.color = 'white';
        setTimeout(() => {
          el.style.background = oldBg;
        }, 400);
      };
    });
  }



  // ===== Tự động tìm ô nhập và dán (phiên bản mạnh) =====
  function autoPaste(text) {
    console.log('[NOITU] Đang cố dán:', text);

    // 0. Ưu tiên đặc biệt cho noitu.fun
    const noituInput = document.querySelector('input.word-link-answer-input, input[class*="word-link-answer"]');
    if (noituInput && isEditable(noituInput)) {
      if (fillEditable(noituInput, text)) {
        console.log('[NOITU] Đã dán vào ô noitu.fun (word-link-answer-input)');
        noituInput.focus();
        return true;
      }
    }

    // 1. Ưu tiên element đang focus
    let target = document.activeElement;
    if (isEditable(target)) {
      if (fillEditable(target, text)) {
        console.log('[NOITU] Đã dán vào element đang focus');
        return true;
      }
    }

    // 2. Tìm tất cả input / textarea / contenteditable
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
      
      // Ưu tiên nằm giữa màn hình
      if (rect.top > 80 && rect.top < window.innerHeight - 120) score += 40;
      // Ưu tiên placeholder liên quan
      if (/từ|nhập|word|câu|trả lời|answer|type|điền/.test(placeholder)) score += 50;
      // Ưu tiên input type text
      if (el.tagName === 'INPUT' && (el.type === 'text' || el.type === '' || !el.type)) score += 20;
      if (el.tagName === 'TEXTAREA') score += 15;
      if (el.isContentEditable) score += 10;
      // Phạt nếu nằm quá trên hoặc quá dưới
      if (rect.top < 50) score -= 30;
      if (rect.top > window.innerHeight - 80) score -= 20;

      candidates.push({ el, score, rect });
    });

    if (candidates.length === 0) {
      console.warn('[NOITU] Không tìm thấy ô nhập nào');
      // Fallback: thử dán bằng execCommand vào document
      try {
        document.execCommand('insertText', false, text);
      } catch(e) {}
      return false;
    }

    // Sắp xếp theo score cao → thấp
    candidates.sort((a, b) => b.score - a.score);
    
    // Thử lần lượt các ứng viên tốt nhất
    for (const cand of candidates.slice(0, 5)) {
      if (fillEditable(cand.el, text)) {
        console.log('[NOITU] Đã dán thành công vào', cand.el.tagName, cand.el.className || cand.el.id);
        cand.el.focus();
        return true;
      }
    }

    console.warn('[NOITU] Thử dán nhưng không thành công');
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

      // ===== Cách 1: contenteditable =====
      if (el.isContentEditable) {
        // Xóa nội dung cũ
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

      // ===== Cách 2: input / textarea thông thường =====
      // Dùng native setter để vượt qua React
      const proto = el.tagName === 'TEXTAREA' 
        ? window.HTMLTextAreaElement.prototype 
        : window.HTMLInputElement.prototype;
      
      const nativeSetter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
      
      if (nativeSetter) {
        nativeSetter.call(el, text);
      } else {
        el.value = text;
      }

      // Trigger nhiều loại event để chắc chắn
      el.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
      el.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
      el.dispatchEvent(new InputEvent('input', { 
        bubbles: true, 
        cancelable: true, 
        data: text, 
        inputType: 'insertText' 
      }));
      
      // Một số framework cần key events
      el.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Unidentified', code: '' }));
      el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: 'Unidentified', code: '' }));

      // Thử thêm cả paste event
      try {
        const pasteEvent = new ClipboardEvent('paste', {
          bubbles: true,
          cancelable: true,
          clipboardData: new DataTransfer()
        });
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

  // Kéo thả (chuột)
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
  }
  panel.addEventListener('mousedown', e => {
    isDragging = startDrag(e.clientX, e.clientY, e.target);
  });
  document.addEventListener('mousemove', e => {
    if (!isDragging) return;
    moveDrag(e.clientX, e.clientY);
  });
  document.addEventListener('mouseup', () => isDragging = false);

  // Kéo thả (chạm - điện thoại/máy tính bảng)
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
  setInterval(tick, 1100);

  console.log('%c✅ Tool Nối Từ (kho từ Firebase, hỗ trợ đánh dấu bẫy) đã sẵn sàng', 'color:#10b981;font-weight:bold');
})();
