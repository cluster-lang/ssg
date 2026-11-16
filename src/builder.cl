// ==============================================================================
// Module:      Static Site Build Pipeline (builder.cl)
// Project:     Cluster SSG (Static Site Generator & Binary Wire Engine)
// Author:      Zaid Alamgir (ZK Company)
// License:     MIT License
// Description: High-speed multi-page compilation engine, sitemap generator, and binary bundle packager.
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
    return SsgConfig("Cluster SSG", "Next-Gen Blazing Fast Static Site Generator", "http://localhost:3000", "site", "dist", 0)

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

    chap_layout_path := cfg.site_dir + "/layouts/chapter.html"
    if file_exists(chap_layout_path) == 1:
        template_register_layout(tr, "chapter", file_read(chap_layout_path))

    // Check and load components (includes)
    side_path := cfg.site_dir + "/components/sidebar.html"
    if file_exists(side_path) == 1:
        template_register_include(tr, "sidebar", file_read(side_path))

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

fn builder_compile_chapter(cfg: SsgConfig, tr: TemplateRegistry, islands: IslandRegistry, src_path: string, out_path: string, ci: int, total_chapters: int) -> int:
    doc := ssg_load_cld(src_path, out_path)
    
    // Build bottom chapter navigation bar
    let mut nav_html: string = "<div class=\"chapter-nav\">\n"
    if ci > 1:
        prev_idx := ci - 1
        nav_html = nav_html + "  <a href=\"/chapter" + str(prev_idx) + ".html\">&larr; Chapter " + str(prev_idx) + "</a>\n"
    else:
        nav_html = nav_html + "  <span></span>\n"
    
    if ci < total_chapters:
        next_idx := ci + 1
        nav_html = nav_html + "  <a href=\"/chapter" + str(next_idx) + ".html\">Chapter " + str(next_idx) + " &rarr;</a>\n"
    else:
        nav_html = nav_html + "  <span></span>\n"
    nav_html = nav_html + "</div>\n"
    
    // Append nav bar to chapter content body
    doc.html_body = doc.html_body + "\n" + nav_html
    
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
            if len(out_path) > 5 and substring(out_path, len(out_path) - 5, 5) == ".html":
                bin_out_path = substring(out_path, 0, len(out_path) - 5) + ".clb"
            else:
                bin_out_path = out_path + ".clb"
            file_write(bin_out_path, packed_bin)
            bytes_written = bytes_written + len(packed_bin)

    return bytes_written

fn ssg_scan_cld_dir(dir_path: string) -> vector[string]:
    tmp_file := ".ssg_scan.tmp"
    sys_run("ls -1 " + dir_path + "/*.cld 2>/dev/null > " + tmp_file)
    let mut files: vector[string] = []
    if file_exists(tmp_file) == 1:
        content := file_read(tmp_file)
        lines := cld_split(content, "\n")
        let mut i: int = 0
        while i < len(lines):
            line := cld_trim(lines[i])
            if len(line) > 0:
                files.push(line)
            i = i + 1
        sys_run("rm -f " + tmp_file)
    return files

fn ssg_extract_filename(full_path: string) -> string:
    let plen: int = len(full_path)
    let mut slash_idx: int = -1
    let mut i: int = plen - 1
    while i >= 0:
        if char_at(full_path, i) == "/":
            slash_idx = i
            break
        i = i - 1
    let mut name: string = full_path
    if slash_idx != -1:
        name = substring(full_path, slash_idx + 1, plen - (slash_idx + 1))
    let nlen: int = len(name)
    if nlen > 4 and substring(name, nlen - 4, 4) == ".cld":
        return substring(name, 0, nlen - 4)
    return name

fn ssg_escape_json(s: string) -> string:
    let slen: int = len(s)
    let mut out: string = ""
    let mut i: int = 0
    while i < slen:
        c := char_at(s, i)
        if c == "\"":
            out = out + "\\\""
        elif c == "\\":
            out = out + "\\\\"
        elif c == "\n":
            out = out + "\\n"
        elif c == "\r":
            out = out + ""
        elif c == "\t":
            out = out + "\\t"
        else:
            out = out + c
        i = i + 1
    return out

fn builder_run_all(cfg: SsgConfig) -> BuildReport:
    tr := builder_init_templates(cfg)
    islands := islands_registry_new()
    
    let mut total_pages: int = 0
    let mut total_bytes: int = 0
    let mut total_bins: int = 0

    // Dynamic Chapter Count Discovery (no hardcoding)
    let mut total_chapters: int = 0
    let mut ci_check: int = 1
    while ci_check <= 1000:
        ch_test := cfg.site_dir + "/pages/chapter" + str(ci_check) + ".cld"
        if file_exists(ch_test) == 1:
            total_chapters = total_chapters + 1
            ci_check = ci_check + 1
        else:
            break

    // Ensure dist/api directory exists
    sys_run("mkdir -p " + cfg.dist_dir + "/api")

    let mut search_items: vector[string] = []
    let mut chapters_api_items: vector[string] = []

    // 1. Dynamic Chapter Compilation with Previous / Next Navigation
    let mut ci: int = 1
    while ci <= total_chapters:
        ch_name := "chapter" + str(ci)
        src_path := cfg.site_dir + "/pages/" + ch_name + ".cld"
        out_path := cfg.dist_dir + "/" + ch_name + ".html"
        if file_exists(src_path) == 1:
            doc_info := ssg_load_cld(src_path, out_path)
            let mut ch_title: string = doc_info.cld.meta.title
            if len(ch_title) == 0:
                ch_title = "Chapter " + str(ci)
            let mut ch_desc: string = doc_info.cld.meta.description
            if len(ch_desc) == 0:
                ch_desc = "The Cluster Book documentation Chapter " + str(ci)

            search_json := "  {\"title\": \"" + ssg_escape_json(ch_title) + "\", \"url\": \"/" + ch_name + ".html\", \"desc\": \"" + ssg_escape_json(ch_desc) + "\", \"category\": \"chapter\"}"
            search_items.push(search_json)

            chap_api_json := "  {\"id\": " + str(ci) + ", \"slug\": \"" + ch_name + "\", \"title\": \"" + ssg_escape_json(ch_title) + "\", \"url\": \"/" + ch_name + ".html\"}"
            chapters_api_items.push(chap_api_json)

            single_chap_json := "{\n  \"id\": " + str(ci) + ",\n  \"slug\": \"" + ch_name + "\",\n  \"title\": \"" + ssg_escape_json(ch_title) + "\",\n  \"url\": \"/" + ch_name + ".html\",\n  \"tags\": \"" + ssg_escape_json(doc_info.cld.meta.tags) + "\",\n  \"description\": \"" + ssg_escape_json(ch_desc) + "\"\n}\n"
            file_write(cfg.dist_dir + "/api/" + ch_name + ".json", single_chap_json)

            bytes := builder_compile_chapter(cfg, tr, islands, src_path, out_path, ci, total_chapters)
            total_bytes = total_bytes + bytes
            total_pages = total_pages + 1
            if cfg.output_binary == 1:
                total_bins = total_bins + 1
        ci = ci + 1

    // 2. Dynamic Discovery & Compilation of Standard Pages (index, about, docs, etc.)
    page_files := ssg_scan_cld_dir(cfg.site_dir + "/pages")
    let mut pi: int = 0
    while pi < len(page_files):
        p_path := page_files[pi]
        slug := ssg_extract_filename(p_path)
        if cld_starts_with(slug, "chapter") == 0:
            out_path := cfg.dist_dir + "/" + slug + ".html"
            p_doc := ssg_load_cld(p_path, out_path)
            let mut p_title: string = p_doc.cld.meta.title
            if len(p_title) == 0:
                p_title = slug
            let mut p_desc: string = p_doc.cld.meta.description
            if len(p_desc) == 0:
                p_desc = "Cluster SSG static page: " + slug

            let mut page_url: string = "/" + slug + ".html"
            if slug == "index":
                page_url = "/index.html"

            search_json := "  {\"title\": \"" + ssg_escape_json(p_title) + "\", \"url\": \"" + page_url + "\", \"desc\": \"" + ssg_escape_json(p_desc) + "\", \"category\": \"page\"}"
            search_items.push(search_json)

            bytes := builder_compile_page(cfg, tr, islands, p_path, out_path)
            total_bytes = total_bytes + bytes
            total_pages = total_pages + 1
            if cfg.output_binary == 1:
                total_bins = total_bins + 1
        pi = pi + 1

    // 3. Dynamic Discovery & Compilation of Blog Posts
    post_files := ssg_scan_cld_dir(cfg.site_dir + "/posts")
    let mut pfi: int = 0
    while pfi < len(post_files):
        post_src := post_files[pfi]
        post_slug := ssg_extract_filename(post_src)
        post_out := cfg.dist_dir + "/" + post_slug + ".html"
        post_doc := ssg_load_cld(post_src, post_out)
        let mut post_title: string = post_doc.cld.meta.title
        if len(post_title) == 0:
            post_title = post_slug
        let mut post_desc: string = post_doc.cld.meta.description
        if len(post_desc) == 0:
            post_desc = "Cluster SSG post: " + post_slug

        search_json := "  {\"title\": \"" + ssg_escape_json(post_title) + "\", \"url\": \"/" + post_slug + ".html\", \"desc\": \"" + ssg_escape_json(post_desc) + "\", \"category\": \"post\"}"
        search_items.push(search_json)

        bytes := builder_compile_page(cfg, tr, islands, post_src, post_out)
        total_bytes = total_bytes + bytes
        total_pages = total_pages + 1
        if cfg.output_binary == 1:
            total_bins = total_bins + 1
        pfi = pfi + 1

    // 4. Tag Archives Generation (/tags/<tag>.html)
    sys_run("mkdir -p " + cfg.dist_dir + "/tags")
    tags := ["cluster", "systems", "compiler", "guide", "concurrency", "performance"]
    let mut ti: int = 0
    while ti < len(tags):
        tag_name := tags[ti]
        tag_out := cfg.dist_dir + "/tags/" + tag_name + ".html"
        let mut tag_body: string = "<h1>Tag Archive: #" + tag_name + "</h1>\n"
        tag_body = tag_body + "<p>Browse all chapters and documentation tagged with <strong>" + tag_name + "</strong>.</p><hr />\n"
        tag_body = tag_body + "<div class=\"chapter-grid\">\n"
        
        let mut tci: int = 1
        while tci <= total_chapters:
            tag_body = tag_body + "  <a class=\"chapter-card\" href=\"/chapter" + str(tci) + ".html\">\n"
            tag_body = tag_body + "    <div class=\"card-num\">Chapter " + str(tci) + "</div>\n"
            tag_body = tag_body + "    <div class=\"card-title\">Tagged with #" + tag_name + "</div>\n"
            tag_body = tag_body + "  </a>\n"
            tci = tci + 1
        tag_body = tag_body + "</div>\n"
        
        tag_cld := CldDoc(cld_meta_new("Tag: #" + tag_name, "default"), [], [])
        tag_doc := SsgDocument(tag_cld, tag_body, tag_out)
        tag_html := template_render_page(tr, tag_doc, cfg.site_name, cfg.site_tagline)
        file_write(tag_out, tag_html)
        total_bytes = total_bytes + len(tag_html)
        total_pages = total_pages + 1
        ti = ti + 1

    // Static Assets
    sys_run("mkdir -p " + cfg.dist_dir + "/static")
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

    main_js_src := cfg.site_dir + "/static/main.js"
    main_js_dst := cfg.dist_dir + "/static/main.js"
    if file_exists(main_js_src) == 1:
        main_js_content := file_read(main_js_src)
        file_write(main_js_dst, main_js_content)
        total_bytes = total_bytes + len(main_js_content)

    // Generate Sitemap
    sitemap_path := cfg.dist_dir + "/sitemap.xml"
    let mut sitemap: string = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
    sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/</loc><priority>1.0</priority></url>\n"
    sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/about.html</loc><priority>0.8</priority></url>\n"
    sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/docs.html</loc><priority>0.8</priority></url>\n"
    sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/hello-cluster-ssg.html</loc><priority>0.7</priority></url>\n"

    let mut si: int = 1
    while si <= total_chapters:
        sitemap = sitemap + "  <url><loc>" + cfg.base_url + "/chapter" + str(si) + ".html</loc><priority>0.9</priority></url>\n"
        si = si + 1

    sitemap = sitemap + "</urlset>\n"
    file_write(sitemap_path, sitemap)
    total_bytes = total_bytes + len(sitemap)

    // Generate RSS 2.0 Feed (feed.xml)
    feed_path := cfg.dist_dir + "/feed.xml"
    let mut feed: string = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n"
    feed = feed + "  <channel>\n"
    feed = feed + "    <title>" + cfg.site_name + "</title>\n"
    feed = feed + "    <link>" + cfg.base_url + "</link>\n"
    feed = feed + "    <description>" + cfg.site_tagline + "</description>\n"
    feed = feed + "    <atom:link href=\"" + cfg.base_url + "/feed.xml\" rel=\"self\" type=\"application/rss+xml\" />\n"
    feed = feed + "    <item>\n"
    feed = feed + "      <title>The Cluster Book &mdash; Official Guide</title>\n"
    feed = feed + "      <link>" + cfg.base_url + "/</link>\n"
    feed = feed + "      <description>" + cfg.site_tagline + "</description>\n"
    feed = feed + "    </item>\n"

    let mut fi: int = 1
    while fi <= total_chapters:
        feed = feed + "    <item>\n"
        feed = feed + "      <title>Cluster-lang: Chapter " + str(fi) + "</title>\n"
        feed = feed + "      <link>" + cfg.base_url + "/chapter" + str(fi) + ".html</link>\n"
        feed = feed + "      <description>The Cluster Book documentation Chapter " + str(fi) + "</description>\n"
        feed = feed + "    </item>\n"
        fi = fi + 1

    feed = feed + "  </channel>\n</rss>\n"
    file_write(feed_path, feed)
    total_bytes = total_bytes + len(feed)

    // Generate Search Index (dist/search-index.json)
    let mut search_index_content: string = "[\n"
    let mut sidx: int = 0
    while sidx < len(search_items):
        search_index_content = search_index_content + search_items[sidx]
        if sidx < len(search_items) - 1:
            search_index_content = search_index_content + ",\n"
        else:
            search_index_content = search_index_content + "\n"
        sidx = sidx + 1
    search_index_content = search_index_content + "]\n"
    file_write(cfg.dist_dir + "/search-index.json", search_index_content)
    total_bytes = total_bytes + len(search_index_content)

    // Generate Headless Chapters API (dist/api/chapters.json)
    let mut chapters_api_content: string = "[\n"
    let mut caidx: int = 0
    while caidx < len(chapters_api_items):
        chapters_api_content = chapters_api_content + chapters_api_items[caidx]
        if caidx < len(chapters_api_items) - 1:
            chapters_api_content = chapters_api_content + ",\n"
        else:
            chapters_api_content = chapters_api_content + "\n"
        caidx = caidx + 1
    chapters_api_content = chapters_api_content + "]\n"
    file_write(cfg.dist_dir + "/api/chapters.json", chapters_api_content)
    total_bytes = total_bytes + len(chapters_api_content)

    // Generate Headless Site API (dist/api/index.json)
    let mut site_api_content: string = "{\n"
    site_api_content = site_api_content + "  \"site_name\": \"" + ssg_escape_json(cfg.site_name) + "\",\n"
    site_api_content = site_api_content + "  \"tagline\": \"" + ssg_escape_json(cfg.site_tagline) + "\",\n"
    site_api_content = site_api_content + "  \"base_url\": \"" + ssg_escape_json(cfg.base_url) + "\",\n"
    site_api_content = site_api_content + "  \"total_chapters\": " + str(total_chapters) + ",\n"
    site_api_content = site_api_content + "  \"generator\": \"cluster-ssg\",\n"
    site_api_content = site_api_content + "  \"version\": \"1.0.0\"\n"
    site_api_content = site_api_content + "}\n"
    file_write(cfg.dist_dir + "/api/index.json", site_api_content)
    total_bytes = total_bytes + len(site_api_content)

    return BuildReport(total_pages, total_bins, 1, total_bytes)
