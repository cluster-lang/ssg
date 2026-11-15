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
