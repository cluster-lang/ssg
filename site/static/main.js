// Mobile sidebar toggle & backdrop overlay
document.addEventListener('DOMContentLoaded', function() {
    const toggle = document.querySelector('.mobile-toggle');
    const sidebar = document.querySelector('.sidebar');
    const backdrop = document.querySelector('.sidebar-backdrop');
    
    function closeSidebar() {
        if (sidebar) sidebar.classList.remove('open');
        if (backdrop) backdrop.classList.remove('active');
        if (toggle) toggle.innerHTML = '☰';
    }

    function openSidebar() {
        if (sidebar) sidebar.classList.add('open');
        if (backdrop) backdrop.classList.add('active');
        if (toggle) toggle.innerHTML = '✕';
    }

    if (toggle && sidebar) {
        toggle.addEventListener('click', function() {
            if (sidebar.classList.contains('open')) {
                closeSidebar();
            } else {
                openSidebar();
            }
        });
        
        if (backdrop) {
            backdrop.addEventListener('click', closeSidebar);
        }

        sidebar.querySelectorAll('a').forEach(function(link) {
            link.addEventListener('click', function() {
                if (window.innerWidth <= 768) {
                    closeSidebar();
                }
            });
        });
    }
    
    // Highlight active sidebar link
    const rawPath = window.location.pathname;
    let normPath = rawPath.replace(/\/$/, '') || '/';
    if (normPath === '') normPath = '/';
    
    document.querySelectorAll('.sidebar-nav a').forEach(function(link) {
        const linkHref = link.getAttribute('href');
        if (!linkHref) return;
        let normLink = linkHref.replace(/\/$/, '') || '/';
        
        const isCurrentHome = normPath === '/' || normPath === '/index.html';
        const isLinkHome = normLink === '/' || normLink === '/index.html';
        
        if (isCurrentHome && isLinkHome) {
            link.classList.add('active');
            return;
        }
        
        const baseCurrent = normPath.replace('.html', '').replace(/^\//, '');
        const baseLink = normLink.replace('.html', '').replace(/^\//, '');
        
        if (!isCurrentHome && !isLinkHome && (baseCurrent === baseLink || (baseCurrent && baseCurrent.endsWith(baseLink)))) {
            link.classList.add('active');
        }
    });

    // High-Speed Syntax Highlighting
    highlightCodeBlocks();

    // 1-Click Code Copy Buttons
    initCodeCopyButtons();

    // Reading Progress Bar
    initReadingProgressBar();

    // Static In-Memory Search Engine (Ctrl + K)
    initClusterSearchModal();
});

function escapeHtml(str) {
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

function highlightCodeBlocks() {
    const keywords = new Set([
        'fn', 'model', 'if', 'else', 'elif', 'while', 'for', 'in', 'return',
        'import', 'let', 'mut', 'const', 'constexpr', 'True', 'False', 'None',
        'break', 'continue', 'and', 'or', 'not', 'put', 'assert', 'def', 'class',
        'struct', 'async', 'await', 'match', 'case', 'defer', 'select', 'owned',
        'borrow', 'qualifier', 'type', 'print'
    ]);
    const types = new Set([
        'int', 'float', 'string', 'bool', 'void', 'vector', 'map', 'dict', 'list', 'ptr', 'i64', 'f64', 'byte'
    ]);

    document.querySelectorAll('pre code').forEach(function(block) {
        if (block.dataset.highlighted) return;
        block.dataset.highlighted = 'true';

        const lines = block.textContent.split('\n');
        const highlighted = lines.map(function(line) {
            // Check for single-line comments
            let comment = '';
            let code = line;
            
            const slashIdx = line.indexOf('//');
            const hashIdx = line.indexOf('#');
            let commentStart = -1;
            
            if (slashIdx !== -1) {
                commentStart = slashIdx;
            } else if (hashIdx !== -1 && !line.trim().startsWith('#include') && !line.trim().startsWith('#define')) {
                if (line.trim().startsWith('#')) commentStart = hashIdx;
            }

            if (commentStart !== -1) {
                code = line.substring(0, commentStart);
                comment = '<span class="c">' + escapeHtml(line.substring(commentStart)) + '</span>';
            }

            // Tokenize strings vs code
            let out = '';
            let inString = false;
            let quoteChar = '';
            let strBuf = '';
            let codeBuf = '';

            for (let i = 0; i < code.length; i++) {
                const ch = code[i];
                if (!inString && (ch === '"' || ch === "'")) {
                    if (codeBuf.length > 0) {
                        out += tokenizeText(codeBuf, keywords, types);
                        codeBuf = '';
                    }
                    inString = true;
                    quoteChar = ch;
                    strBuf = ch;
                } else if (inString && ch === quoteChar && (i === 0 || code[i-1] !== '\\')) {
                    strBuf += ch;
                    out += '<span class="s">' + escapeHtml(strBuf) + '</span>';
                    inString = false;
                    strBuf = '';
                } else if (inString) {
                    strBuf += ch;
                } else {
                    codeBuf += ch;
                }
            }

            if (strBuf.length > 0) {
                out += '<span class="s">' + escapeHtml(strBuf) + '</span>';
            }
            if (codeBuf.length > 0) {
                out += tokenizeText(codeBuf, keywords, types);
            }

            return out + comment;
        });

        block.innerHTML = highlighted.join('\n');
    });
}

function tokenizeText(text, keywords, types) {
    // Replace identifiers, numbers, operators
    return text.replace(/([a-zA-Z_][a-zA-Z0-9_]*|\b\d+(\.\d+)?\b|:=|->|=>|==|!=|<=|>=|[+\-*\/=<>!])/g, function(match) {
        if (keywords.has(match)) {
            return '<span class="k">' + escapeHtml(match) + '</span>';
        } else if (types.has(match)) {
            return '<span class="kt">' + escapeHtml(match) + '</span>';
        } else if (/^\d+(\.\d+)?$/.test(match)) {
            return '<span class="m">' + escapeHtml(match) + '</span>';
        } else if (match === ':=' || match === '->' || match === '=>') {
            return '<span class="o">' + escapeHtml(match) + '</span>';
        }
        return escapeHtml(match);
    });
}

// Interactive Sheet Support (Filter, Sort, Export CSV)
window.clusterSheetFilter = function(input) {
    const query = input.value.toLowerCase();
    const wrapper = input.closest('.cluster-sheet-wrapper');
    if (!wrapper) return;
    const rows = wrapper.querySelectorAll('tbody tr');
    let visible = 0;
    rows.forEach(function(row) {
        const text = row.textContent.toLowerCase();
        if (text.includes(query)) {
            row.style.display = '';
            visible++;
        } else {
            row.style.display = 'none';
        }
    });
    const countEl = wrapper.querySelector('.cluster-sheet-count');
    if (countEl) countEl.textContent = 'Showing ' + visible + ' of ' + rows.length + ' entries';
};

window.clusterSheetSort = function(th, colIdx) {
    const table = th.closest('table');
    const tbody = table.querySelector('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));
    const isAsc = th.dataset.order !== 'asc';
    th.dataset.order = isAsc ? 'asc' : 'desc';
    
    th.closest('tr').querySelectorAll('th .sort-icon').forEach(function(icon) { icon.textContent = '⇅'; });
    const icon = th.querySelector('.sort-icon');
    if (icon) icon.textContent = isAsc ? '▲' : '▼';

    rows.sort(function(a, b) {
        const aCell = a.children[colIdx] ? a.children[colIdx].innerText.trim() : '';
        const bCell = b.children[colIdx] ? b.children[colIdx].innerText.trim() : '';
        const aNum = parseFloat(aCell.replace(/[^0-9.-]/g, ''));
        const bNum = parseFloat(bCell.replace(/[^0-9.-]/g, ''));
        if (!isNaN(aNum) && !isNaN(bNum)) {
            return isAsc ? aNum - bNum : bNum - aNum;
        }
        return isAsc ? aCell.localeCompare(bCell) : bCell.localeCompare(aCell);
    });

    rows.forEach(function(r) { tbody.appendChild(r); });
};

window.clusterSheetExportCSV = function(btn) {
    const wrapper = btn.closest('.cluster-sheet-wrapper');
    if (!wrapper) return;
    const table = wrapper.querySelector('table');
    let csv = [];
    table.querySelectorAll('tr').forEach(function(row) {
        if (row.style.display === 'none') return;
        const cols = Array.from(row.querySelectorAll('th, td')).map(function(cell) {
            let text = cell.innerText.replace(/[\u21C5\u25B2\u25BC]/g, '').trim().replace(/"/g, '""').replace(/[\r\n]+/g, ' ');
            return '"' + text + '"';
        });
        csv.push(cols.join(','));
    });
    const blob = new Blob([csv.join('\n')], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = (wrapper.querySelector('.cluster-sheet-title') ? wrapper.querySelector('.cluster-sheet-title').textContent.replace(/[^a-zA-Z0-9_-]/g, '_') : 'sheet') + '.csv';
    link.click();
};


// ========== MULTI-LANGUAGE TABS WIDGET ==========
window.clusterSwitchTab = function(btn, idx) {
    const wrapper = btn.closest('.cluster-tabs-wrapper');
    if (!wrapper) return;
    wrapper.querySelectorAll('.cluster-tab-btn').forEach(function(b) {
        b.classList.remove('active');
    });
    btn.classList.add('active');
    const panes = wrapper.querySelectorAll('.cluster-tab-pane');
    panes.forEach(function(pane) {
        if (pane.getAttribute('data-tab-idx') == idx) {
            pane.style.display = 'block';
        } else {
            pane.style.display = 'none';
        }
    });
};

// ========== 1-CLICK CODE COPY BUTTONS ==========
function initCodeCopyButtons() {
    document.querySelectorAll('pre').forEach(function(pre) {
        if (pre.querySelector('.code-copy-btn')) return;
        const btn = document.createElement('button');
        btn.className = 'code-copy-btn';
        btn.setAttribute('aria-label', 'Copy code to clipboard');
        btn.innerHTML = '<span class="copy-icon">📋</span><span class="copy-label">Copy</span>';
        btn.addEventListener('click', function(e) {
            e.stopPropagation();
            const codeEl = pre.querySelector('code') || pre;
            const textToCopy = codeEl.innerText;
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(textToCopy).then(function() {
                    setCopiedState(btn);
                }).catch(function() {
                    fallbackCopy(textToCopy, btn);
                });
            } else {
                fallbackCopy(textToCopy, btn);
            }
        });
        pre.appendChild(btn);
    });
}

function setCopiedState(btn) {
    btn.innerHTML = '<span class="copy-icon">✓</span><span class="copy-label">Copied!</span>';
    btn.classList.add('copied');
    setTimeout(function() {
        btn.innerHTML = '<span class="copy-icon">📋</span><span class="copy-label">Copy</span>';
        btn.classList.remove('copied');
    }, 2000);
}

function fallbackCopy(text, btn) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try {
        document.execCommand('copy');
        setCopiedState(btn);
    } catch(err) {}
    document.body.removeChild(ta);
}

// ========== READING PROGRESS BAR ==========
function initReadingProgressBar() {
    let bar = document.getElementById('reading-progress-bar');
    if (!bar) {
        bar = document.createElement('div');
        bar.id = 'reading-progress-bar';
        document.body.prepend(bar);
    }
    window.addEventListener('scroll', function() {
        const h = document.documentElement;
        const total = h.scrollHeight - h.clientHeight;
        const progress = total > 0 ? (h.scrollTop / total) * 100 : 0;
        bar.style.width = Math.min(100, Math.max(0, progress)) + '%';
    }, { passive: true });
}

// ========== STATIC IN-MEMORY SEARCH ENGINE (CTRL+K) ==========
let clusterSearchIndex = null;
let clusterSearchSelectedIndex = -1;

function initClusterSearchModal() {
    // Ensure modal DOM exists
    if (!document.getElementById('cluster-search-modal')) {
        const modal = document.createElement('div');
        modal.id = 'cluster-search-modal';
        modal.innerHTML = '<div class="cluster-search-box">' +
            '<div class="cluster-search-input-wrap">' +
                '<span class="cluster-search-icon">🔍</span>' +
                '<input type="text" class="cluster-search-input" placeholder="Search chapters, guides, code snippets..." autocomplete="off" spellcheck="false" />' +
                '<button class="cluster-search-close" onclick="closeClusterSearch()">ESC</button>' +
            '</div>' +
            '<div class="cluster-search-results">' +
                '<div class="cluster-search-empty">Type to search across the entire Cluster Book...</div>' +
            '</div>' +
            '<div class="cluster-search-footer">' +
                '<span><kbd>↑</kbd> <kbd>↓</kbd> to navigate</span>' +
                '<span><kbd>ENTER</kbd> to select</span>' +
                '<span><kbd>ESC</kbd> to dismiss</span>' +
            '</div>' +
        '</div>';
        document.body.appendChild(modal);

        modal.addEventListener('click', function(e) {
            if (e.target === modal) closeClusterSearch();
        });

        const input = modal.querySelector('.cluster-search-input');
        input.addEventListener('input', function() {
            handleClusterSearch(input.value.trim());
        });

        input.addEventListener('keydown', function(e) {
            const resultsContainer = modal.querySelector('.cluster-search-results');
            const items = resultsContainer.querySelectorAll('.cluster-search-item');
            if (items.length === 0) return;

            if (e.key === 'ArrowDown') {
                e.preventDefault();
                clusterSearchSelectedIndex = (clusterSearchSelectedIndex + 1) % items.length;
                updateSelectedSearchItem(items);
            } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                clusterSearchSelectedIndex = (clusterSearchSelectedIndex - 1 + items.length) % items.length;
                updateSelectedSearchItem(items);
            } else if (e.key === 'Enter') {
                e.preventDefault();
                if (clusterSearchSelectedIndex >= 0 && clusterSearchSelectedIndex < items.length) {
                    items[clusterSearchSelectedIndex].click();
                } else if (items.length > 0) {
                    items[0].click();
                }
            }
        });
    }

    // Global shortcut listener (Ctrl+K, Cmd+K, '/')
    document.addEventListener('keydown', function(e) {
        if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
            e.preventDefault();
            toggleClusterSearch();
        } else if (e.key === '/' && document.activeElement && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {
            e.preventDefault();
            openClusterSearch();
        } else if (e.key === 'Escape') {
            closeClusterSearch();
        }
    });
}

function updateSelectedSearchItem(items) {
    items.forEach(function(item, idx) {
        if (idx === clusterSearchSelectedIndex) {
            item.classList.add('selected');
            item.scrollIntoView({ block: 'nearest' });
        } else {
            item.classList.remove('selected');
        }
    });
}

window.openClusterSearch = function() {
    const modal = document.getElementById('cluster-search-modal');
    if (!modal) return;
    modal.classList.add('active');
    const input = modal.querySelector('.cluster-search-input');
    if (input) {
        input.focus();
        input.select();
    }
    clusterSearchSelectedIndex = -1;
    loadSearchIndex();
};

window.closeClusterSearch = function() {
    const modal = document.getElementById('cluster-search-modal');
    if (!modal) return;
    modal.classList.remove('active');
};

window.toggleClusterSearch = function() {
    const modal = document.getElementById('cluster-search-modal');
    if (!modal) return;
    if (modal.classList.contains('active')) {
        closeClusterSearch();
    } else {
        openClusterSearch();
    }
};

function loadSearchIndex() {
    if (clusterSearchIndex !== null) return;
    fetch('/search-index.json')
        .then(function(res) { return res.json(); })
        .then(function(data) {
            clusterSearchIndex = data;
        })
        .catch(function(err) {
            console.error('Failed to load search index:', err);
        });
}

function handleClusterSearch(query) {
    const modal = document.getElementById('cluster-search-modal');
    if (!modal) return;
    const resultsContainer = modal.querySelector('.cluster-search-results');
    clusterSearchSelectedIndex = -1;

    if (!query) {
        resultsContainer.innerHTML = '<div class="cluster-search-empty">Type to search across the entire Cluster Book...</div>';
        return;
    }

    if (!clusterSearchIndex) {
        resultsContainer.innerHTML = '<div class="cluster-search-empty">Loading index...</div>';
        return;
    }

    const q = query.toLowerCase();
    const tokens = q.split(/\s+/).filter(Boolean);
    const matches = [];

    for (let i = 0; i < clusterSearchIndex.length; i++) {
        const item = clusterSearchIndex[i];
        const titleLower = (item.title || '').toLowerCase();
        const descLower = (item.desc || '').toLowerCase();
        const catLower = (item.category || '').toLowerCase();

        let score = 0;
        let matchedAll = true;

        for (let t = 0; t < tokens.length; t++) {
            const tok = tokens[t];
            if (titleLower.includes(tok)) {
                score += 10;
            } else if (descLower.includes(tok)) {
                score += 5;
            } else if (catLower.includes(tok)) {
                score += 2;
            } else {
                matchedAll = false;
                break;
            }
        }

        if (matchedAll) {
            matches.push({ item: item, score: score });
        }
    }

    matches.sort(function(a, b) { return b.score - a.score; });

    if (matches.length === 0) {
        resultsContainer.innerHTML = '<div class="cluster-search-empty">No results found for "' + escapeHtml(query) + '"</div>';
        return;
    }

    let html = '';
    const maxResults = Math.min(15, matches.length);
    for (let i = 0; i < maxResults; i++) {
        const m = matches[i].item;
        const catBadge = m.category ? '<span class="cluster-search-item-category">' + escapeHtml(m.category) + '</span>' : '';
        const descHtml = m.desc ? '<div class="cluster-search-item-desc">' + escapeHtml(m.desc) + '</div>' : '';
        html += '<a href="' + m.url + '" class="cluster-search-item" data-index="' + i + '">' +
            '<div class="cluster-search-item-title">' +
                '<span>' + escapeHtml(m.title) + '</span>' +
                catBadge +
            '</div>' +
            descHtml +
        '</a>';
    }

    resultsContainer.innerHTML = html;
}
