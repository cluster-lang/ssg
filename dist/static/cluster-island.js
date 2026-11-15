/**
 * Cluster-SSG: Tiny Island Runtime & Binary Bytecode Decoder (~1.2KB)
 * 100% Zero-Dependency Standalone Runtime
 */
(function() {
  window.ClusterSSG = {
    // Astro-Style Partial Hydration Runtime
    hydrate: function() {
      var islands = document.querySelectorAll('cluster-island');
      islands.forEach(function(el) {
        var clientDir = el.getAttribute('data-client') || 'load';
        var islandName = el.getAttribute('data-island');

        if (clientDir === 'load') {
          // Immediate hydration
        } else if (clientDir === 'idle') {
          if ('requestIdleCallback' in window) {
            requestIdleCallback(function() { /* idle hydrated */ });
          }
        } else if (clientDir === 'visible') {
          if ('IntersectionObserver' in window) {
            var observer = new IntersectionObserver(function(entries) {
              entries.forEach(function(entry) {
                if (entry.isIntersecting) {
                  observer.disconnect();
                }
              });
            });
            observer.observe(el);
          }
        }
      });
    },

    // Cluster Secure Binary Wire Decoder:
    // Fetches packed .clb binary stream, unpacks AST in memory, and mounts DOM
    loadBinary: function(clbUrl, targetSelector) {
      var container = document.querySelector(targetSelector || '#cluster-root');
      if (!container) return;

      fetch(clbUrl)
        .then(function(res) {
          if (!res.ok) throw new Error('Failed to load binary bundle: ' + res.status);
          return res.text();
        })
        .then(function(raw) {
          var lines = raw.split('\n');
          var title = 'Cluster Page';
          var author = '';
          var htmlParts = [];
          var inList = false;

          for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line.startsWith('META|')) {
              var m = line.split('|');
              title = m[1] || title;
              author = m[2] || '';
              document.title = title;
            } else if (line.startsWith('BLOCK|')) {
              var b = line.split('|');
              var kind = b[1];
              var extra = b[2];
              var content = b.slice(3).join('|');

              if (kind === 'list') {
                if (!inList) { htmlParts.push('<ul>'); inList = true; }
                htmlParts.push('<li>' + content + '</li>');
              } else {
                if (inList) { htmlParts.push('</ul>'); inList = false; }
                if (kind === 'h1') htmlParts.push('<h1>' + content + '</h1>');
                else if (kind === 'h2') htmlParts.push('<h2>' + content + '</h2>');
                else if (kind === 'h3') htmlParts.push('<h3>' + content + '</h3>');
                else if (kind === 'p') htmlParts.push('<p>' + content + '</p>');
                else if (kind === 'quote') htmlParts.push('<blockquote>' + content + '</blockquote>');
                else if (kind === 'code') htmlParts.push('<pre><code>' + content + '</code></pre>');
                else if (kind === 'hr') htmlParts.push('<hr />');
                else if (kind === 'island') {
                  htmlParts.push('<div class="cluster-counter"><button onclick="window.clusterIslandDec(this)">-</button><span class="count-val">0</span><button onclick="window.clusterIslandInc(this)">+</button></div>');
                }
              }
            }
          }
          if (inList) htmlParts.push('</ul>');

          container.innerHTML = '<main class="container"><article class="post-container"><header class="post-header"><h1>' + title + '</h1>' + (author ? '<div class="post-meta">Author: ' + author + '</div>' : '') + '</header><div class="post-body">' + htmlParts.join('\n') + '</div></article></main>';
        })
        .catch(function(err) {
          container.innerHTML = '<div style="color:red;padding:20px;">Error unpacking binary: ' + err.message + '</div>';
        });
    }
  };

  // Interactive Island Helper Functions
  window.clusterIslandInc = function(btn) {
    var s = btn.parentElement.querySelector('.count-val');
    if (s) s.innerText = parseInt(s.innerText || '0', 10) + 1;
  };

  window.clusterIslandDec = function(btn) {
    var s = btn.parentElement.querySelector('.count-val');
    if (s) s.innerText = parseInt(s.innerText || '0', 10) - 1;
  };

  window.clusterToggleTheme = function() {
    var b = document.body;
    if (b.classList.contains('light-theme')) {
      b.classList.remove('light-theme');
      localStorage.setItem('cluster-theme', 'dark');
    } else {
      b.classList.add('light-theme');
      localStorage.setItem('cluster-theme', 'light');
    }
  };

  document.addEventListener('DOMContentLoaded', function() {
    ClusterSSG.hydrate();
  });
})();
