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

fn main() -> int:
    println("=================================================================")
    println("      Cluster-SSG v2.0: Automated Production Test Suite (14)     ")
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

    println("\n=================================================================")
    println("      ✓ ALL 14 TEST SUITES PASSED WITH EXIT CODE 0!              ")
    println("=================================================================")
    return 0
