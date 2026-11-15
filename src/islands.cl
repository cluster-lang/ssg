// ==============================================================================
// Cluster-SSG: Component Islands Architecture Engine (src/islands.cl)
// Astro-Style Partial Hydration & Zero-JS by Default
// 100% Pure Cluster Language · Zero External Dependencies
// ==============================================================================

import "std/cld.cl"
import "src/document.cl"

model IslandDefinition:
    name: string
    template_html: string
    client_script: string

model IslandRegistry:
    definitions: vector[IslandDefinition]

fn islands_registry_new() -> IslandRegistry:
    let defs: vector[IslandDefinition] = []
    reg := IslandRegistry(defs)
    
    // Built-in interactive islands:
    // 1. Interactive Counter
    counter_tmpl := "<div class=\"cluster-counter\"><button class=\"btn-dec\" onclick=\"window.clusterIslandDec(this)\">-</button><span class=\"count-val\">0</span><button class=\"btn-inc\" onclick=\"window.clusterIslandInc(this)\">+</button></div>"
    counter_js := "window.clusterIslandInc=function(b){var s=b.parentElement.querySelector('.count-val');s.innerText=parseInt(s.innerText)+1;};window.clusterIslandDec=function(b){var s=b.parentElement.querySelector('.count-val');s.innerText=parseInt(s.innerText)-1;};"
    def1 := IslandDefinition("Counter", counter_tmpl, counter_js)
    reg.definitions.push(def1)

    // 2. Fast Search Modal Island
    search_tmpl := "<div class=\"cluster-search-box\"><input type=\"text\" placeholder=\"Search static site...\" onkeyup=\"window.clusterSearch(this.value)\" /><div id=\"search-results\"></div></div>"
    search_js := "window.clusterSearch=function(q){var el=document.getElementById('search-results');if(!q){el.innerHTML='';return;}el.innerHTML='<div class=\"search-hit\">Searching for: <b>'+q+'</b>...</div>';};"
    def2 := IslandDefinition("SearchModal", search_tmpl, search_js)
    reg.definitions.push(def2)

    // 3. Dark/Light Theme Toggle Island
    theme_tmpl := "<button class=\"theme-toggle-btn\" onclick=\"window.clusterToggleTheme()\">🌓 Toggle Theme</button>"
    theme_js := "window.clusterToggleTheme=function(){var b=document.body;if(b.classList.contains('light-theme')){b.classList.remove('light-theme');localStorage.setItem('theme','dark');}else{b.classList.add('light-theme');localStorage.setItem('theme','light');}};"
    def3 := IslandDefinition("ThemeToggle", theme_tmpl, theme_js)
    reg.definitions.push(def3)

    return reg

fn islands_has_active_islands(doc: CldDoc) -> int:
    let mut i: int = 0
    while i < len(doc.islands):
        isl := doc.islands[i]
        if isl.directive != "zero-js":
            return 1
        i = i + 1
    return 0

// Injects the island HTML & hydration bundle into compiled page
fn islands_hydrate_page(reg: IslandRegistry, doc: CldDoc, html: string) -> string:
    if len(doc.islands) == 0:
        return html

    let mut out: string = html
    let mut combined_js: string = ""
    let mut ii: int = 0
    let total_islands: int = len(doc.islands)

    while ii < total_islands:
        isl := doc.islands[ii]
        
        // Find matching definition
        let mut def_found: int = 0
        let mut tmpl: string = "<div class=\"custom-island\">" + isl.name + "</div>"
        let mut js_code: string = ""
        
        let mut di: int = 0
        while di < len(reg.definitions):
            d := reg.definitions[di]
            if d.name == isl.name:
                tmpl = d.template_html
                js_code = d.client_script
                def_found = 1
                break
            di = di + 1

        // Replace placeholder in HTML
        placeholder := "<div class=\"cluster-island-placeholder\" id=\"island-" + cld_slugify(isl.name) + "\">\n    <span>[Interactive Island: " + isl.name + "]</span>\n  </div>"
        
        // Replace placeholder with island template
        out = cld_template_replace(out, "island-" + cld_slugify(isl.name) + "\">\n    <span>[Interactive Island: " + isl.name + "]</span>\n  </div>", "island-" + cld_slugify(isl.name) + "\">\n    " + tmpl + "\n  </div>")

        if isl.directive != "zero-js" and len(js_code) > 0:
            if cld_starts_with(combined_js, js_code) == 0:
                combined_js = combined_js + "\n" + js_code

        ii = ii + 1

    // If client hydration scripts exist, inject before </body>
    if len(combined_js) > 0:
        script_tag := "\n<script>\n// Cluster SSG Island Client Hydration Bundle\n(function(){\n" + combined_js + "\n})();\n</script>\n</body>"
        out = cld_template_replace(out, "</body>", script_tag)

    return out
