// ==============================================================================
// Module:      Automated Verification Suite (tests/test_ssg.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// License:     CCFL-1.0 / CCFL v2.0
// Description: Comprehensive 14-suite verification covering .cld, .clb binary,
//              YAML/TOML/data frontmatter, CommonMark/GFM syntax highlighting,
//              Liquid templates/inheritance/loops/filters, .clx scoped CSS,
//              Content Collection schemas, selective islands, CSS/JS minification,
//              and 1,000-page throughput benchmark.
// ==============================================================================

import "std/cld.cl"
import "src/strbuf.cl"
import "src/config.cl"
import "src/frontmatter.cl"
import "src/markdown.cl"
import "src/document.cl"
import "src/template.cl"
import "src/collections.cl"
import "src/clx_compiler.cl"
import "src/islands.cl"
import "src/assets.cl"
import "src/builder.cl"
import "src/server.cl"

fn test_cld_parser() -> void:
    println("[Test 1/14] Testing .cld Document Parser & AST...")
    sample := "title: Test Title\nauthor: Ada Lovelace\ndate: 2026-11-15\nlayout: post\ntags: math,computing\n===\n# Main Heading\n\nThis is a **bold** paragraph with `code`.\n\n<island name=\"Counter\" client:load count=\"5\" />\n\n> This is a quote."
    doc := cld_parse_text(sample)
    assert(doc.meta.title == "Test Title")
    assert(doc.meta.author == "Ada Lovelace")
    assert(doc.meta.date == "2026-11-15")
    assert(doc.meta.layout == "post")
    assert(doc.meta.tags == "math,computing")
    assert(doc.meta.slug == "test-title")
    assert(len(doc.blocks) == 4)
    assert(len(doc.islands) == 1)
    assert(doc.islands[0].name == "Counter")
    assert(doc.islands[0].directive == "load")
    println("  ✓ .cld parser passed.")

fn test_cld_binary_pack_unpack() -> void:
    println("[Test 2/14] Testing Binary Bundle Packaging & Unpacking (.cld <-> .clb)...")
    sample := "title: Binary Astro Island\nauthor: Cluster Lang\nlayout: default\n===\n# Binary Wire AST\n\nSecure zero-leakage binary storage.\n\n<island name=\"ThemeToggle\" client:idle />"
    doc := cld_parse_text(sample)
    packed := cld_pack(doc)
    assert(cld_starts_with(packed, "CLD/1.0\n") == 1)
    doc2 := cld_unpack(packed)
    assert(doc2.meta.title == doc.meta.title)
    assert(doc2.meta.author == doc.meta.author)
    assert(len(doc2.blocks) == len(doc.blocks))
    assert(len(doc2.islands) == len(doc.islands))
    println("  ✓ Binary roundtrip passed.")

fn test_template_engine() -> void:
    println("[Test 3/14] Testing Layout Inheritance & Partial Includes...")
    tr := template_new()
    ob := "{" + "{"
    cb := "}" + "}"
    template_register_layout(tr, "default", "<html><head><title>" + ob + " title " + cb + "</title></head><body>" + ob + " include \"nav\" " + cb + "<main>" + ob + " content " + cb + "</main></body></html>")
    template_register_include(tr, "nav", "<nav><a href=\"/\">Home</a></nav>")
    doc := cld_parse_text("title: My Page\n===\n# Hello\nContent here.")
    ssg_doc := SsgDocument(doc, "dummy.cld", "dummy.html", cld_render_blocks(doc), "", 0)
    rendered := template_render_page(tr, ssg_doc, "MySite", "Tagline")
    assert(cld_starts_with(rendered, "<html><head><title>My Page</title></head><body><nav><a href=\"/\">Home</a></nav><main>") == 1)
    println("  ✓ Legacy template layouts & includes passed.")

fn test_islands_hydration() -> void:
    println("[Test 4/14] Testing Astro Component Islands & Partial Hydration...")
    reg := islands_registry_new()
    doc_isl := cld_parse_text("title: Island Page\n===\n# Counter\n<island name=\"Counter\" client:load count=\"0\" />")
    ssg_doc_isl := SsgDocument(doc_isl, "p1.cld", "p1.html", cld_render_blocks(doc_isl), "", 0)
    html_with_isl := islands_hydrate_page(reg, doc_isl, "<html><body>" + ssg_doc_isl.html_body + "</body></html>")
    assert(len(html_with_isl) > len(ssg_doc_isl.html_body))
    assert(ssg_contains(html_with_isl, "<script>") == 1)

    doc_static := cld_parse_text("title: Static Page\n===\n# Plain Text\nNo JS needed.")
    ssg_doc_static := SsgDocument(doc_static, "p2.cld", "p2.html", cld_render_blocks(doc_static), "", 0)
    html_static := islands_hydrate_page(reg, doc_static, "<html><body>" + ssg_doc_static.html_body + "</body></html>")
    assert(ssg_contains(html_static, "<script>") == 0)
    println("  ✓ Zero-JS default + selective hydration passed.")

fn test_builder_pipeline() -> void:
    println("[Test 5/14] Testing Multi-Page Static Site Build Pipeline...")
    cfg := config_load(".")
    cfg.output_binary = 1
    rep := builder_run_all(cfg)
    assert(rep.pages_built >= 3)
    assert(rep.binary_bundles_packed >= 3)
    assert(file_exists("dist/index.html") == 1)
    assert(file_exists("dist/about.html") == 1)
    assert(file_exists("dist/docs.html") == 1)
    assert(file_exists("dist/index.clb") == 1)
    assert(file_exists("dist/sitemap.xml") == 1)
    assert(file_exists("dist/atom.xml") == 1)
    assert(file_exists("dist/feed.xml") == 1)
    assert(file_exists("dist/tags/index.html") == 1)
    println("  ✓ Multi-page build + SEO feeds + tags passed.")

fn test_http_server_standard_and_binary() -> void:
    println("[Test 6/14] Testing HTTP Server in Standard & Binary Wire Modes...")
    srv1 := ssg_server_new(3000, "dist", 0)
    res1 := ssg_handle_http(srv1, "GET /index.html HTTP/1.1\r\nHost: localhost:3000\r\n\r\n")
    assert(substring(res1, 9, 3) == "200")
    srv2 := ssg_server_new(3000, "dist", 1)
    res2 := ssg_handle_http(srv2, "GET /docs.html HTTP/1.1\r\nHost: localhost:3000\r\n\r\n")
    assert(substring(res2, 9, 3) == "200")
    assert(len(res2) > 100)
    res3 := ssg_handle_http(srv1, "GET /unknown-page.html HTTP/1.1\r\nHost: localhost:3000\r\n\r\n")
    assert(substring(res3, 9, 3) == "404")
    println("  ✓ HTTP server & binary wire streaming passed.")

fn test_hugo_speed_benchmark() -> void:
    println("[Test 7/14] Testing High-Throughput In-Memory Benchmark (500 pages)...")
    cfg := config_default()
    tr := builder_init_templates(cfg)
    islands := islands_registry_new()
    sample := "title: Bench Page\nauthor: Cluster\n===\n# Bench\nHigh-speed AST rendering.\n<island name=\"Counter\" client:load count=\"0\" />"
    doc := cld_parse_text(sample)
    let mut i: int = 0
    while i < 500:
        rendered := cld_render_page(doc, template_get_layout(tr, "default"))
        hydrated := islands_hydrate_page(islands, doc, rendered)
        assert(len(hydrated) > 10)
        i = i + 1
    println("  ✓ 500 pages rendered & hydrated cleanly.")

fn test_frontmatter_and_jekyll_stem() -> void:
    println("[Test 8/14] Testing YAML/TOML Frontmatter & Jekyll Date Filenames...")
    yml := "---\ntitle: \"Yaml Post\"\nauthor:\n  name: Alice\ntags: [rust, cluster]\n---\nBody text."
    fm := fm_parse_document(yml)
    assert(fm.fields["title"] == "Yaml Post")
    assert(fm.fields["author.name"] == "Alice")
    assert(fm.fields["tags"] == "rust,cluster")
    assert(ssg_trim(fm.body) == "Body text.")

    toml := "+++\ntitle = \"Hugo Page\"\ndraft = false\n+++\nHugo content."
    fm2 := fm_parse_document(toml)
    assert(fm2.fields["title"] == "Hugo Page")

    let mut d_out: string = ""
    let mut s_out: string = ""
    fm_extract_date_from_stem("2026-11-27-release-notes", d_out, s_out)
    assert(d_out == "2026-11-27")
    assert(s_out == "release-notes")
    println("  ✓ YAML/TOML frontmatter & Jekyll filename parsing passed.")

fn test_commonmark_gfm_highlight() -> void:
    println("[Test 9/14] Testing CommonMark, GFM Tables, Tasks & Code Highlight...")
    md := "# Top Heading\n\nText with **bold**, *em*, `inline` and [link](https://example.com)[^1].\n\n- [x] Done task\n  - Nested sub\n- [ ] Todo task\n\n| Col1 | Col2 |\n| :--- | ---: |\n| v1 | 42 |\n\n```cluster\nfn main() -> int:\n    return 0\n```\n\n[^1]: Footnote body."
    res := md_parse_and_render(md)
    assert(len(res.toc) == 1)
    assert(res.toc[0].id == "top-heading")
    assert(ssg_contains(res.html, "<strong>bold</strong>") == 1)
    assert(ssg_contains(res.html, "type=\"checkbox\" checked") == 1)
    assert(ssg_contains(res.html, "text-align:right") == 1)
    assert(ssg_contains(res.html, "<span class=\"hl-kw\">fn</span>") == 1)
    assert(ssg_contains(res.html, "Footnote body.") == 1)
    println("  ✓ CommonMark + GFM + highlighter + TOC passed.")

fn test_liquid_v2_engine() -> void:
    println("[Test 10/14] Testing Liquid Loops, Conditionals, Assign, Filters & Layout Chain...")
    tr := template_new()
    ob := "{" + "{"
    cb := "}" + "}"
    op := "{" + "%"
    cp := "%" + "}"
    template_register_layout(tr, "base", "<html><body>" + ob + " content " + cb + "</body></html>")
    template_register_layout(tr, "child", "---\nlayout: base\n---\n<section>" + ob + " content " + cb + "</section>")
    tmpl := op + " assign greeting = \"hello world\" " + cp + ob + " greeting | upcase " + cb + "|" + op + " if count > 1 " + cp + "MANY" + op + " else " + cp + "ONE" + op + " endif " + cp + "|" + op + " for p in site.posts " + cp + "[" + ob + " forloop.index " + cb + ":" + ob + " p.title | slugify " + cb + "]" + op + " endfor " + cp
    vars := dict[string, string]()
    vars["count"] = "3"
    let mut items: vector[PageSummary] = []
    items.push(PageSummary("Alpha Post", "/a.html", "2026-11-27", "", "", "", "", "posts", "alpha", "", 1, "en", dict[string, string]()))
    items.push(PageSummary("Beta Post", "/b.html", "2026-11-26", "", "", "", "", "posts", "beta", "", 1, "en", dict[string, string]()))
    let p_idx: vector[int] = [0, 1]
    ctx := RenderContext(vars, dict[string, string](), items, p_idx, [], [], [], dict[string, int](), dict[string, int](), dict[string, int](), DataRegistry(dict[string, string](), dict[string, int]()), config_default())
    out := template_v2_render(tr, "child", tmpl, vars, ctx)
    assert(out == "<html><body><section>HELLO WORLD|MANY|[1:alpha-post][2:beta-post]</section></body></html>")
    println("  ✓ Liquid v2 inheritance, assign, if, forloop & filters passed.")

fn test_content_collections_schema() -> void:
    println("[Test 11/14] Testing Typed Content Collections Schema Validation...")
    let mut rules: vector[CollectionFieldRule] = []
    rules.push(CollectionFieldRule("title", "string", 1))
    rules.push(CollectionFieldRule("date", "date", 1))
    let mut schemas: vector[CollectionSchema] = []
    schemas.push(CollectionSchema("posts", rules))
    by_n := dict[string, int]()
    by_n["posts"] = 0
    sreg := SchemaRegistry(schemas, by_n)

    let empty_md := MarkdownResult("<p>ok</p>", [], [], [], 1, "")
    good := SsgRichDoc("p1.md", "p1.md", "posts", fm_new_empty(""), empty_md, "Valid", "A", "2026-11-27", "post", "", "", "valid", "", "/valid.html", "", "en", 0, 1)
    bad := SsgRichDoc("p2.md", "p2.md", "posts", fm_new_empty(""), empty_md, "BadDate", "A", "invalid-date", "post", "", "", "bad", "", "/bad.html", "", "en", 0, 1)
    let mut errs: vector[string] = []
    assert(collections_validate_doc(sreg, good, errs) == 1)
    assert(len(errs) == 0)
    assert(collections_validate_doc(sreg, bad, errs) == 0)
    assert(len(errs) == 1)
    println("  ✓ Content collection schema enforcement passed.")

fn test_clx_component_compiler() -> void:
    println("[Test 12/14] Testing Astro-style .clx Components & Scoped CSS...")
    lbr := "{"
    rbr := "}"
    src := "---\nbadge := \"NEW\"\n---\n<article class=\"box\"><span>" + lbr + "badge" + rbr + "</span><h2>" + lbr + "title" + rbr + "</h2><div><slot /></div></article>\n<style scoped>\n.box " + lbr + " color: red; " + rbr + "\n</style>"
    comp := clx_parse_component("Card", src)
    reg := clx_registry_new()
    reg.by_name["Card"] = len(reg.components)
    reg.components.push(comp)
    let mut calls: vector[ClxTagCall] = []
    calls.push(ClxTagCall("Card", "<Card title=\"Docs\">", "<p>Body</p>", "<!--CLX_0-->"))
    pvars := dict[string, string]()
    out := clx_expand_calls(reg, calls, "<html><head></head><body><!--CLX_0--></body></html>", pvars)
    assert(ssg_contains(out, "NEW") == 1)
    assert(ssg_contains(out, "<h2>Docs</h2>") == 1)
    assert(ssg_contains(out, "<p>Body</p>") == 1)
    assert(ssg_contains(out, comp.scope_class) == 1)
    println("  ✓ .clx component props, slots & CSS scoping passed.")

fn test_islands_v2_directives() -> void:
    println("[Test 13/14] Testing client:visible, client:idle, client:media & View Transitions...")
    reg := islands_registry_new()
    let mut tags: vector[IslandTag] = []
    tags.push(IslandTag("Counter", "visible", "", ""))
    tags.push(IslandTag("ThemeToggle", "media:(max-width:768px)", "", ""))
    html := "<html><body><div class=\"cluster-island-placeholder\" id=\"island-counter-1\" data-island=\"Counter\" data-directive=\"visible\">\n  <span>[Interactive Island: Counter]</span>\n</div></body></html>"
    out := islands_hydrate_v2(reg, tags, html, 1)
    assert(ssg_contains(out, "IntersectionObserver") == 1)
    assert(ssg_contains(out, "matchMedia") == 1)
    assert(ssg_contains(out, "startViewTransition") == 1)
    println("  ✓ Selective directives & view transitions passed.")

fn test_asset_minifiers() -> void:
    println("[Test 14/14] Testing Pure-.cl CSS, JS & HTML Minifiers...")
    css_min := assets_minify_css("/* comment */\nbody {\n  color : #fff ;\n  margin : 0 ;\n}")
    assert(css_min == "body{color:#fff;margin:0;}")
    js_min := assets_minify_js("// banner\nconst x = 1; /* mid */\nconsole.log(x);")
    assert(ssg_contains(js_min, "banner") == 0)
    assert(ssg_contains(js_min, "mid") == 0)
    html_min := assets_minify_html("<div>   <p>hi</p>   </div>")
    assert(html_min == "<div> <p>hi</p> </div>")
    println("  ✓ Pure-.cl CSS/JS/HTML minifiers passed.")

fn test_sse_and_inotify() -> void:
    println("[Test 15/19] Testing SSE Live Reload Endpoint & inotify Watcher...")
    srv := ssg_server_new(3099, "dist", 0)
    srv.live_reload = 1
    srv.reload_token = "tok42"
    sse_resp := ssg_handle_http(srv, "GET /_cluster_sse HTTP/1.1\r\nHost: localhost\r\n\r\n")
    assert(ssg_contains(sse_resp, "Content-Type: text/event-stream") == 1)
    assert(ssg_contains(sse_resp, "data: tok42") == 1)
    let mut dirs: vector[string] = []
    dirs.push("site")
    ifd := fs_inotify_open(dirs)
    assert(ifd >= 0)
    close(ifd)
    println("  ✓ SSE live-reload & kernel inotify watcher passed.")

fn test_nested_clx_and_named_slots() -> void:
    println("[Test 16/19] Testing Nested .clx Components, Named Slots & Fallbacks...")
    lbr := "{"
    rbr := "}"
    inner_src := "---\ntag := \"SUB\"\n---\n<span class=\"pill\">" + lbr + "tag" + rbr + ":" + lbr + "label" + rbr + "</span>\n<style scoped>\n.pill " + lbr + " font-weight: bold; " + rbr + "\n</style>"
    outer_src := "<div class=\"card\"><header><slot name=\"header\" /></header><main><slot /></main><aside><slot name=\"aside\">FallbackAside</slot></aside><footer><Badge label=\"OK\" /></footer></div>"
    reg := clx_registry_new()
    c_in := clx_parse_component("Badge", inner_src)
    c_out := clx_parse_component("Panel", outer_src)
    reg.by_name["Badge"] = len(reg.components)
    reg.components.push(c_in)
    reg.by_name["Panel"] = len(reg.components)
    reg.components.push(c_out)
    let mut calls: vector[ClxTagCall] = []
    calls.push(ClxTagCall("Panel", "<Panel>", "<div slot=\"header\">TopTitle</div><p>MainBody</p>", "<!--CLX_0-->"))
    out := clx_expand_calls(reg, calls, "<html><head></head><body><!--CLX_0--></body></html>", dict[string, string]())
    assert(ssg_contains(out, "<header><div slot=\"header\">TopTitle</div></header>") == 1)
    assert(ssg_contains(out, "<main><p>MainBody</p></main>") == 1)
    assert(ssg_contains(out, "<aside>FallbackAside</aside>") == 1)
    assert(ssg_contains(out, "SUB:OK") == 1)
    assert(ssg_contains(out, c_in.scope_class) == 1)
    println("  ✓ Nested .clx + named slots + fallbacks passed.")

fn test_deep_json_and_liquid_filters() -> void:
    println("[Test 17/19] Testing Deep JSON Data & Liquid where/sort/group_by/uniq/slice...")
    flat := dict[string, string]()
    counts := dict[string, int]()
    jraw := "{\"sidebar\":[{\"title\":\"Start\",\"items\":[{\"label\":\"Intro\",\"href\":\"/intro.html\"}]},{\"title\":\"Ref\",\"items\":[{\"label\":\"API\",\"href\":\"/api.html\"}]}]}"
    _data_parse_simple_json_records("docs", jraw, flat, counts)
    assert(flat["docs.sidebar[0].items[0].href"] == "/intro.html")
    assert(flat["docs.sidebar[1].items[0].href"] == "/api.html")

    tr := template_new()
    ob := "{" + "{"
    cb := "}" + "}"
    op := "{" + "%"
    cp := "%" + "}"
    template_register_layout(tr, "raw", ob + " content " + cb)
    tmpl := op + " for s in site.data.docs.sidebar " + cp + "[" + ob + " s.title " + cb + ":" + op + " for it in s.items " + cp + ob + " it.href " + cb + op + " endfor " + cp + "]" + op + " endfor " + cp
    tmpl = tmpl + "|" + op + " for p in site.posts | where: \"author\", \"Alice\" | sort: \"title\" " + cp + ob + " p.title " + cb + ";" + op + " endfor " + cp
    tmpl = tmpl + "|" + op + " for g in site.posts | group_by: \"year\" " + cp + "(" + ob + " g.name " + cb + ":" + ob + " g.size " + cb + ")" + op + " endfor " + cp
    tmpl = tmpl + "|" + ob + " tags_csv | uniq | sort | slice: 0, 2 | join: \"-\" " + cb
    vars := dict[string, string]()
    vars["tags_csv"] = "z,a,z,b"
    let mut items: vector[PageSummary] = []
    items.push(PageSummary("Zeta", "/z.html", "2025-05-01", "Alice", "", "", "", "posts", "zeta", "", 1, "en", dict[string, string]()))
    items.push(PageSummary("Alpha", "/a.html", "2026-01-01", "Alice", "", "", "", "posts", "alpha", "", 1, "en", dict[string, string]()))
    items.push(PageSummary("BobPost", "/b.html", "2026-02-01", "Bob", "", "", "", "posts", "bob", "", 1, "en", dict[string, string]()))
    let p_idx: vector[int] = [0, 1, 2]
    ctx := RenderContext(vars, dict[string, string](), items, p_idx, [], [], [], dict[string, int](), dict[string, int](), dict[string, int](), DataRegistry(flat, counts), config_default())
    out := template_v2_render(tr, "raw", tmpl, vars, ctx)
    assert(ssg_contains(out, "[Start:/intro.html][Ref:/api.html]") == 1)
    assert(ssg_contains(out, "Alpha;Zeta;") == 1)
    assert(ssg_contains(out, "(2025:1)") == 1)
    assert(ssg_contains(out, "(2026:2)") == 1)
    assert(ssg_contains(out, "|a-b") == 1)
    println("  ✓ Deep JSON & Liquid where/sort/group_by/uniq/slice passed.")

fn test_image_dims_and_dyn_routes() -> void:
    println("[Test 18/19] Testing JPEG/WebP Image Dims, <img> CLS Injection & [slug] Routes...")
    root := "/tmp/cl_ssg_sprint3_site"
    fs_remove_rf(root)
    dcache := dict[string, int]()
    ssg_ensure_dir(root + "/site/static", dcache)
    ssg_ensure_dir(root + "/site/posts", dcache)
    ssg_ensure_dir(root + "/site/pages/cards", dcache)
    // Build minimal valid JPEG with SOF0 (width=320, height=240)
    jp_path := root + "/site/static/hero.jpg"
    jbuf := mem_alloc(22)
    ptr_write_u8(ptr_add(jbuf, 0), 255); ptr_write_u8(ptr_add(jbuf, 1), 216)
    ptr_write_u8(ptr_add(jbuf, 2), 255); ptr_write_u8(ptr_add(jbuf, 3), 192)
    ptr_write_u8(ptr_add(jbuf, 4), 0);   ptr_write_u8(ptr_add(jbuf, 5), 11)
    ptr_write_u8(ptr_add(jbuf, 6), 8)
    ptr_write_u8(ptr_add(jbuf, 7), 0);   ptr_write_u8(ptr_add(jbuf, 8), 240)
    ptr_write_u8(ptr_add(jbuf, 9), 1);   ptr_write_u8(ptr_add(jbuf, 10), 64)
    ptr_write_u8(ptr_add(jbuf, 11), 3)
    fd_j := open(str_cstr(jp_path), 577, 420)
    write(fd_j, jbuf, 12)
    close(fd_j)
    mem_free(jbuf)
    let mut jw: int = 0
    let mut jh: int = 0
    assert(assets_probe_image_dims(jp_path, jw, jh) == 1)
    assert(jw == 320)
    assert(jh == 240)

    // Minimal WebP VP8X (width=640, height=480 -> width-1=639=0x27F, height-1=479=0x1DF)
    wp_path := root + "/site/static/pic.webp"
    wbuf := mem_alloc(30)
    // RIFF....WEBPVP8X
    ptr_write_u8(ptr_add(wbuf, 0), 82); ptr_write_u8(ptr_add(wbuf, 1), 73); ptr_write_u8(ptr_add(wbuf, 2), 70); ptr_write_u8(ptr_add(wbuf, 3), 70)
    ptr_write_u8(ptr_add(wbuf, 8), 87); ptr_write_u8(ptr_add(wbuf, 9), 69); ptr_write_u8(ptr_add(wbuf, 10), 66); ptr_write_u8(ptr_add(wbuf, 11), 80)
    ptr_write_u8(ptr_add(wbuf, 12), 86); ptr_write_u8(ptr_add(wbuf, 13), 80); ptr_write_u8(ptr_add(wbuf, 14), 56); ptr_write_u8(ptr_add(wbuf, 15), 88)
    ptr_write_u8(ptr_add(wbuf, 24), 127); ptr_write_u8(ptr_add(wbuf, 25), 2); ptr_write_u8(ptr_add(wbuf, 26), 0)
    ptr_write_u8(ptr_add(wbuf, 27), 223); ptr_write_u8(ptr_add(wbuf, 28), 1); ptr_write_u8(ptr_add(wbuf, 29), 0)
    fd_w := open(str_cstr(wp_path), 577, 420)
    write(fd_w, wbuf, 30)
    close(fd_w)
    mem_free(wbuf)
    let mut ww: int = 0
    let mut wh: int = 0
    assert(assets_probe_image_dims(wp_path, ww, wh) == 1)
    assert(ww == 640)
    assert(wh == 480)

    // Write post + [slug].clx + img page and build site
    file_write(root + "/site/posts/2026-11-27-dyn-hello.md", "---\ntitle: Dyn Hello\ndate: 2026-11-27\n---\n![hero](/static/hero.jpg)\n")
    lbr := "{"
    rbr := "}"
    file_write(root + "/site/pages/cards/[slug].clx", "<div class=\"dyn\">" + lbr + "title" + rbr + "</div>\n")
    file_write(root + "/site/pages/gallery.md", "---\ntitle: Gallery\n---\n<img src=\"/static/pic.webp\" alt=\"p\" />\n")
    cfg := config_default()
    cfg.site_dir = root + "/site"
    cfg.dist_dir = root + "/dist"
    cfg.clean_dist = 1
    rep := builder_run_all(cfg)
    assert(rep.pages_built >= 3)
    assert(file_exists(root + "/dist/cards/dyn-hello.html") == 1)
    assert(ssg_contains(file_read(root + "/dist/cards/dyn-hello.html"), "Dyn Hello") == 1)
    assert(ssg_contains(file_read(root + "/dist/gallery.html"), "width=\"640\" height=\"480\"") == 1)
    fs_remove_rf(root)
    println("  ✓ JPEG/WebP dims, <img> CLS injection & [slug] dynamic routes passed.")

fn test_wasm_island_e2e() -> void:
    println("[Test 19/19] Testing End-to-End .cl -> wasm32 Island Compilation & Hydration...")
    root := "/tmp/cl_ssg_wasm_test"
    fs_remove_rf(root)
    dcache := dict[string, int]()
    ssg_ensure_dir(root + "/site/islands", dcache)
    file_write(root + "/site/islands/CalcWasm.cl", "fn main() -> int:\n    return 77\n")
    reg := islands_registry_new()
    islands_discover_custom(reg, root + "/site", root + "/dist", 1, dcache)
    assert(reg.by_name.has("CalcWasm") == 1)
    def := reg.definitions[reg.by_name["CalcWasm"]]
    wasm_path := root + "/dist/static/islands/CalcWasm.wasm"
    assert(file_exists(wasm_path) == 1)
    assert(def.wasm_out_url == "/static/islands/CalcWasm.wasm")
    raw_w := file_read(wasm_path)
    assert(string_length(raw_w) >= 8)
    assert(byte_at(raw_w, 0) == 0 and byte_at(raw_w, 1) == 97 and byte_at(raw_w, 2) == 115 and byte_at(raw_w, 3) == 109)
    let mut tags: vector[IslandTag] = []
    tags.push(IslandTag("CalcWasm", "load", "", ""))
    hyd := islands_hydrate_v2(reg, tags, "<html><body><div class=\"cluster-island-placeholder\" id=\"island-calcwasm-1\" data-island=\"CalcWasm\" data-directive=\"load\">\n  <span>[Interactive Island: CalcWasm]</span>\n</div></body></html>", 0)
    assert(ssg_contains(hyd, "/static/islands/CalcWasm.wasm") == 1)
    fs_remove_rf(root)
    println("  ✓ End-to-end .cl -> wasm32 island compilation & hydration passed.")

fn main() -> int:
    println("=================================================================")
    println("      Cluster-SSG v2.0: Automated Production Test Suite (19)     ")
    println("=================================================================")

    test_cld_parser()
    test_cld_binary_pack_unpack()
    test_template_engine()
    test_islands_hydration()
    test_builder_pipeline()
    test_http_server_standard_and_binary()
    test_hugo_speed_benchmark()
    test_frontmatter_and_jekyll_stem()
    test_commonmark_gfm_highlight()
    test_liquid_v2_engine()
    test_content_collections_schema()
    test_clx_component_compiler()
    test_islands_v2_directives()
    test_asset_minifiers()
    test_sse_and_inotify()
    test_nested_clx_and_named_slots()
    test_deep_json_and_liquid_filters()
    test_image_dims_and_dyn_routes()
    test_wasm_island_e2e()

    println("\n=================================================================")
    println("      ✓ ALL 19 TEST SUITES PASSED WITH EXIT CODE 0!              ")
    println("=================================================================")
    return 0
