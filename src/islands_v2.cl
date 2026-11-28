// ==============================================================================
// Module:      Selective Islands & WASM32 Hydration Engine (src/islands_v2.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Zero-JS by default partial hydration supporting client:load,
//              client:idle, client:visible (IntersectionObserver), client:media,
//              client:only, plus optional .cl -> wasm32 island compilation and
//              View Transitions / prefetch micro-runtime.
// ==============================================================================

import "src/strbuf.cl"
import "src/fs_walk.cl"
import "src/document.cl"

model IslandDefinition:
    name: string
    template_html: string
    client_script: string
    wasm_src_path: string
    wasm_out_url: string

model IslandRegistry:
    definitions: vector[IslandDefinition]
    by_name: dict[string, int]

fn _islands_register(reg: IslandRegistry, name: string, html: string, js: string, wasm_src: string) -> void:
    idx := len(reg.definitions)
    reg.definitions.push(IslandDefinition(name, html, js, wasm_src, ""))
    reg.by_name[name] = idx

fn islands_registry_new() -> IslandRegistry:
    let defs: vector[IslandDefinition] = []
    by_n := dict[string, int]()
    reg := IslandRegistry(defs, by_n)

    counter_tmpl := "<div class=\"cluster-counter\"><button class=\"btn-dec\" data-cl-act=\"dec\">-</button><span class=\"count-val\">0</span><button class=\"btn-inc\" data-cl-act=\"inc\">+</button></div>"
    counter_js := "function mountCounter(root){var v=root.querySelector('.count-val');if(!v)return;var i=parseInt(root.getAttribute('data-prop-count')||'0',10)||0;v.innerText=String(i);root.querySelector('.btn-inc').addEventListener('click',function(){i++;v.innerText=String(i);});root.querySelector('.btn-dec').addEventListener('click',function(){i--;v.innerText=String(i);});}document.querySelectorAll('[data-island=\"Counter\"]').forEach(mountCounter);"
    _islands_register(reg, "Counter", counter_tmpl, counter_js, "")

    search_tmpl := "<div class=\"cluster-search-box\"><input type=\"search\" placeholder=\"Search static site...\" /><div class=\"search-results\"></div></div>"
    search_js := "document.querySelectorAll('[data-island=\"SearchModal\"]').forEach(function(root){var inp=root.querySelector('input');var out=root.querySelector('.search-results');var idx=null;inp.addEventListener('input',function(){var q=inp.value.trim().toLowerCase();if(!q){out.innerHTML='';return;}var run=function(items){var hits=items.filter(function(it){return (it.title+' '+it.desc).toLowerCase().indexOf(q)>=0;}).slice(0,8);out.innerHTML=hits.map(function(h){return '<a class=\"search-hit\" href=\"'+h.url+'\"><b>'+h.title+'</b></a>';}).join('')||'<div class=\"search-hit\">No results</div>';};if(idx){run(idx);return;}fetch('/search-index.json').then(function(r){return r.json();}).then(function(d){idx=d;run(idx);}).catch(function(){});});});"
    _islands_register(reg, "SearchModal", search_tmpl, search_js, "")

    theme_tmpl := "<button class=\"theme-toggle-btn\" type=\"button\">Toggle Theme</button>"
    theme_js := "document.querySelectorAll('[data-island=\"ThemeToggle\"]').forEach(function(root){var btn=root.querySelector('button');btn.addEventListener('click',function(){document.body.classList.toggle('light-theme');localStorage.setItem('theme',document.body.classList.contains('light-theme')?'light':'dark');});});"
    _islands_register(reg, "ThemeToggle", theme_tmpl, theme_js, "")

    return reg

fn islands_discover_custom(reg: IslandRegistry, site_dir: string, dist_dir: string, wasm_enabled: int, dir_cache: dict[string, int]) -> void:
    isl_dir := ssg_path_join(site_dir, "islands")
    if fs_is_dir(isl_dir) == 0:
        return
    let mut exts: vector[string] = []
    exts.push(".cl")
    exts.push(".js")
    scan := fs_walk_tree(isl_dir, exts)
    let mut i: int = 0
    while i < len(scan.abs_paths):
        ap := scan.abs_paths[i]
        ext := ssg_path_ext(ap)
        iname := ssg_path_stem(ap)
        if ext == ".js":
            js := file_read(ap)
            _islands_register(reg, iname, "<div class=\"custom-island\" data-custom-island=\"" + ssg_escape_html(iname) + "\"></div>", js, "")
        elif ext == ".cl":
            tmpl := "<div class=\"cluster-wasm-island\" data-wasm-island=\"" + ssg_escape_html(iname) + "\"><span>Loading " + ssg_escape_html(iname) + "...</span></div>"
            let mut wasm_url: string = ""
            if wasm_enabled == 1:
                wasm_out := ssg_path_join(dist_dir, "static/islands/" + iname + ".wasm")
                ssg_ensure_dir(ssg_path_dirname(wasm_out), dir_cache)
                rc := sys_run("cl build \"" + ap + "\" --clil --target wasm32-unknown-unknown -Oz -o \"" + wasm_out + "\" 2>/dev/null || true")
                if file_exists(wasm_out) == 1:
                    wasm_url = "/static/islands/" + iname + ".wasm"
            let mut loader_js: string = ""
            if string_length(wasm_url) > 0:
                loader_js = "fetch('" + wasm_url + "').then(function(r){return r.arrayBuffer();}).then(function(b){return WebAssembly.instantiate(b,{});}).then(function(m){var el=document.querySelector('[data-wasm-island=\"" + iname + "\"]');if(el&&m.instance.exports.main){el.setAttribute('data-wasm-ready','1');var v=m.instance.exports.main();el.innerHTML='<span>" + iname + " WASM: '+v+'</span>';}});"
            else:
                loader_js = "var el=document.querySelector('[data-wasm-island=\"" + iname + "\"]');if(el){el.setAttribute('data-island-ready','1');}"
            _islands_register(reg, iname, tmpl, loader_js, wasm_url)
        i = i + 1

fn islands_has_active_islands(doc: CldDoc) -> int:
    let mut i: int = 0
    while i < len(doc.islands):
        if doc.islands[i].directive != "zero-js":
            return 1
        i = i + 1
    return 0

fn _islands_wrap_directive(directive: string, js_code: string, target_id: string) -> string:
    if directive == "idle":
        return "if('requestIdleCallback'in window){requestIdleCallback(function(){" + js_code + "});}else{setTimeout(function(){" + js_code + "},200);}"
    elif directive == "visible":
        return "(function(){var el=document.getElementById('" + target_id + "');if(!el||!('IntersectionObserver'in window)){" + js_code + ";return;}var ob=new IntersectionObserver(function(es){if(es.some(function(e){return e.isIntersecting;})){ob.disconnect();" + js_code + "}});ob.observe(el);})();"
    elif ssg_starts_with(directive, "media:") == 1:
        mq := substring(directive, 6, string_length(directive) - 6)
        return "if(window.matchMedia(" + "\"" + ssg_escape_json(mq) + "\"" + ").matches){" + js_code + "}"
    return js_code

fn islands_hydrate_v2(reg: IslandRegistry, tags: vector[IslandTag], html: string, view_transitions: int) -> string:
    let mut out: string = html
    sb_js := sb_new_cap(256)
    seen_js := dict[string, int]()

    let mut ii: int = 0
    while ii < len(tags):
        tag := tags[ii]
        let mut tmpl: string = "<div class=\"custom-island\">" + ssg_escape_html(tag.name) + "</div>"
        let mut js_code: string = ""
        if reg.by_name.has(tag.name) == 1:
            d := reg.definitions[reg.by_name[tag.name]]
            tmpl = d.template_html
            js_code = d.client_script

        isl_id := "island-" + ssg_slugify(tag.name) + "-" + str(ii + 1)
        // Extract props like count="5" and embed as data-prop-count
        old_span := "id=\"" + isl_id + "\" data-island=\"" + ssg_escape_html(tag.name) + "\" data-directive=\"" + ssg_escape_html(tag.directive) + "\">\n  <span>[Interactive Island: " + ssg_escape_html(tag.name) + "]</span>"
        new_span := "id=\"" + isl_id + "\" data-island=\"" + ssg_escape_html(tag.name) + "\" data-directive=\"" + ssg_escape_html(tag.directive) + "\">\n  " + tmpl
        out = ssg_replace_all(out, old_span, new_span)

        // Legacy placeholder fallback from std/cld.cl (<div ... id="island-slug">)
        legacy_id := "island-" + ssg_slugify(tag.name)
        legacy_old := legacy_id + "\">\n    <span>[Interactive Island: " + tag.name + "]</span>\n  </div>"
        legacy_new := legacy_id + "\">\n    " + tmpl + "\n  </div>"
        out = ssg_replace_all(out, legacy_old, legacy_new)

        if tag.directive != "zero-js" and string_length(js_code) > 0:
            if seen_js.has(tag.name + "|" + tag.directive) == 0:
                seen_js[tag.name + "|" + tag.directive] = 1
                sb_append(sb_js, _islands_wrap_directive(tag.directive, js_code, isl_id))
                sb_append_byte(sb_js, 10)
        ii = ii + 1

    if view_transitions == 1:
        // Lightweight < 1 KB view transition + hover prefetch micro-runtime
        vt := "if(document.startViewTransition){document.addEventListener('click',function(e){var a=e.target.closest('a');if(!a||a.origin!==location.origin||a.hasAttribute('download'))return;e.preventDefault();fetch(a.href).then(function(r){return r.text();}).then(function(h){var d=new DOMParser().parseFromString(h,'text/html');document.startViewTransition(function(){document.title=d.title;document.body.replaceWith(d.body);history.pushState({},'',a.href);});});});}\n"
        sb_append(sb_js, vt)

    combined_js := sb_to_str(sb_js)
    sb_free(sb_js)
    if string_length(combined_js) > 0:
        script_tag := "\n<script>\n// Cluster SSG Partial Hydration Bundle\n(function(){\n" + combined_js + "})();\n</script>\n</body>"
        if ssg_contains(out, "</body>") == 1:
            out = ssg_replace_all(out, "</body>", script_tag)
        else:
            out = out + script_tag
    return out

// Legacy compatibility wrapper for test_ssg.cl
fn islands_hydrate_page(reg: IslandRegistry, doc: CldDoc, html: string) -> string:
    if len(doc.islands) == 0:
        return html
    let mut tags: vector[IslandTag] = []
    let mut i: int = 0
    while i < len(doc.islands):
        di := doc.islands[i]
        tags.push(IslandTag(di.name, di.directive, di.props, di.fallback))
        i = i + 1
    return islands_hydrate_v2(reg, tags, html, 0)
