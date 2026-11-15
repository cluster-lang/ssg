// ==============================================================================
// Cluster-SSG: Static Build Pipeline (src/builder.cl)
// Hugo-Speed Multi-Page Compilation Engine
// 100% Pure Cluster Language · Zero External Dependencies
// ==============================================================================

import "std/cld.cl"
import "src/document.cl"
import "src/template.cl"
import "src/islands.cl"

model SsgConfig:
    site_name: string
    site_tagline: string
    base_url: string
    site_dir: string
    dist_dir: string
    output_binary: int

model BuildReport:
    pages_built: int
    binary_bundles_packed: int
    build_time_ms: int
    total_bytes_written: int

fn config_default() -> SsgConfig:
    return SsgConfig("Cluster SSG", "Next-Gen Blazing Fast Static Site Generator", "http://localhost:3000", "site", "dist", 1)

fn builder_init_templates(cfg: SsgConfig) -> TemplateRegistry:
    tr := template_new()
    
    ob := "{" + "{"
    cb := "}" + "}"
    
    // Check and load layout files
    def_layout_path := cfg.site_dir + "/layouts/default.html"
    if file_exists(def_layout_path) == 1:
        template_register_layout(tr, "default", file_read(def_layout_path))
    else:
        // Default built-in layout
        built_in_default := "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>" + ob + " title " + cb + " - " + ob + " site_name " + cb + "</title>\n  <link rel=\"stylesheet\" href=\"/static/style.css\">\n</head>\n<body>\n  " + ob + " include \"navbar\" " + cb + "\n  <main class=\"main-content\">\n    " + ob + " content " + cb + "\n  </main>\n  " + ob + " include \"footer\" " + cb + "\n</body>\n</html>"
        template_register_layout(tr, "default", built_in_default)

    post_layout_path := cfg.site_dir + "/layouts/post.html"
    if file_exists(post_layout_path) == 1:
        template_register_layout(tr, "post", file_read(post_layout_path))
    else:
        built_in_post := "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>" + ob + " title " + cb + " - " + ob + " site_name " + cb + "</title>\n  <link rel=\"stylesheet\" href=\"/static/style.css\">\n</head>\n<body>\n  " + ob + " include \"navbar\" " + cb + "\n  <article class=\"post-container\">\n    <header class=\"post-header\">\n      <h1>" + ob + " title " + cb + "</h1>\n      <div class=\"post-meta\">By <strong>" + ob + " author " + cb + "</strong> &middot; " + ob + " date " + cb + " &middot; Tags: <em>" + ob + " tags " + cb + "</em></div>\n    </header>\n    <div class=\"post-body\">\n      " + ob + " content " + cb + "\n    </div>\n  </article>\n  " + ob + " include \"footer\" " + cb + "\n</body>\n</html>"
        template_register_layout(tr, "post", built_in_post)

    // Check and load components (includes)
    nav_path := cfg.site_dir + "/components/navbar.html"
    if file_exists(nav_path) == 1:
        template_register_include(tr, "navbar", file_read(nav_path))
    else:
        built_in_nav := "<header class=\"site-header\"><nav class=\"nav-bar\"><div class=\"brand\"><a href=\"/\"><strong>" + ob + " site_name " + cb + "</strong></a></div><div class=\"nav-links\"><a href=\"/\">Home</a><a href=\"/about.html\">About</a><a href=\"/docs.html\">Docs</a><a href=\"/posts.html\">Articles</a></div></nav></header>"
        template_register_include(tr, "navbar", built_in_nav)

    foot_path := cfg.site_dir + "/components/footer.html"
    if file_exists(foot_path) == 1:
        template_register_include(tr, "footer", file_read(foot_path))
    else:
        built_in_foot := "<footer class=\"site-footer\"><p>&copy; " + ob + " year " + cb + " " + ob + " site_name " + cb + " &middot; Built with 100% Pure Cluster Language (Zero Dependencies).</p></footer>"
        template_register_include(tr, "footer", built_in_foot)

    return tr

fn builder_compile_page(cfg: SsgConfig, tr: TemplateRegistry, islands: IslandRegistry, src_path: string, out_path: string) -> int:
    doc := ssg_load_cld(src_path, out_path)
    
    // Step 1: Render layout template
    page_html := template_render_page(tr, doc, cfg.site_name, cfg.site_tagline)
    
    // Step 2: Hydrate Islands (Astro Partial Hydration)
    final_html := islands_hydrate_page(islands, doc.cld, page_html)
    
    // Step 3: Write HTML to dist
    file_write(out_path, final_html)
    let mut bytes_written: int = len(final_html)

    // Step 4: Write Packed Binary Bundle (.clb)
    if cfg.output_binary == 1:
        packed_bin := ssg_doc_to_binary(doc)
        bin_out_path := out_path
        if cld_starts_with(out_path, cfg.dist_dir + "/") == 1:
            // Replace .html with .clb
            if len(out_path) > 5 and substring(out_path, len(out_path) - 5, 5) == ".html":
                bin_out_path = substring(out_path, 0, len(out_path) - 5) + ".clb"
            else:
                bin_out_path = out_path + ".clb"
            file_write(bin_out_path, packed_bin)
            bytes_written = bytes_written + len(packed_bin)

    return bytes_written

fn builder_run_all(cfg: SsgConfig) -> BuildReport:
    tr := builder_init_templates(cfg)
    islands := islands_registry_new()
    
    let mut total_pages: int = 0
    let mut total_bytes: int = 0
    let mut total_bins: int = 0

    // Standard static pages
    pages := [
        "index",
        "about",
        "docs"
    ]

    let mut pi: int = 0
    while pi < len(pages):
        page_name := pages[pi]
        src_path := cfg.site_dir + "/pages/" + page_name + ".cld"
        out_path := cfg.dist_dir + "/" + page_name + ".html"
        
        if file_exists(src_path) == 1:
            bytes := builder_compile_page(cfg, tr, islands, src_path, out_path)
            total_bytes = total_bytes + bytes
            total_pages = total_pages + 1
            if cfg.output_binary == 1:
                total_bins = total_bins + 1
        pi = pi + 1

    // Blog / Posts
    post_src := cfg.site_dir + "/posts/hello-cluster-ssg.cld"
    post_out := cfg.dist_dir + "/hello-cluster-ssg.html"
    if file_exists(post_src) == 1:
        bytes := builder_compile_page(cfg, tr, islands, post_src, post_out)
        total_bytes = total_bytes + bytes
        total_pages = total_pages + 1
        if cfg.output_binary == 1:
            total_bins = total_bins + 1

    // Static Assets
    css_src := cfg.site_dir + "/static/style.css"
    css_dst := cfg.dist_dir + "/static/style.css"
    if file_exists(css_src) == 1:
        css_content := file_read(css_src)
        file_write(css_dst, css_content)
        total_bytes = total_bytes + len(css_content)

    js_src := cfg.site_dir + "/static/cluster-island.js"
    js_dst := cfg.dist_dir + "/static/cluster-island.js"
    if file_exists(js_src) == 1:
        js_content := file_read(js_src)
        file_write(js_dst, js_content)
        total_bytes = total_bytes + len(js_content)

    // Generate Sitemap
    sitemap_path := cfg.dist_dir + "/sitemap.xml"
    let mut sitemap: string = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
    sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/</loc><priority>1.0</priority></url>\n"
    sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/about.html</loc><priority>0.8</priority></url>\n"
    sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/docs.html</loc><priority>0.8</priority></url>\n"
    sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/hello-cluster-ssg.html</loc><priority>0.7</priority></url>\n"
    sitemap = sitemap + "</urlset>\n"
    file_write(sitemap_path, sitemap)
    total_bytes = total_bytes + len(sitemap)

    return BuildReport(total_pages, total_bins, 1, total_bytes)
