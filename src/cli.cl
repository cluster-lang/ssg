// ==============================================================================
// Module:      Pure-.cl Native CLI & Project Scaffolder (src/cli.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Zero-Python CLI dispatcher for build, serve, new, import, check,
//              pack, unpack, and Hugo-speed benchmark (in-memory & disk modes).
// ==============================================================================

import "std/cld.cl"
import "src/strbuf.cl"
import "src/fs_walk.cl"
import "src/config.cl"
import "src/document.cl"
import "src/template.cl"
import "src/islands.cl"
import "src/builder.cl"
import "src/importer.cl"
import "src/server.cl"

fn cli_print_banner() -> void:
    println("=================================================================")
    println("   CLUSTER-SSG v2.0: Jekyll + Hugo + Astro in 100% Pure .cl      ")
    println("   Zero Python/Ruby/Node · Parallel Multi-Core · WASM Islands    ")
    println("=================================================================")

fn cli_print_usage() -> void:
    println("Usage: cluster-ssg <command> [options]\n")
    println("Commands:")
    println("  new <dir> [--template blog|docs|portfolio|landing]  Scaffold site")
    println("  import <dir>                  Import Jekyll / Hugo / Markdown site")
    println("  build [flags]                 Compile static site into dist/")
    println("    --binary                    Emit .clb zero-scraping binary bundles")
    println("    --clean                     Clean dist/ before building")
    println("    --drafts                    Include draft: true posts & pages")
    println("    --minify                    Minify HTML, CSS & JS outputs")
    println("    --hash-assets               Content-hash CSS/JS URLs (fingerprinting)")
    println("    --compress                  Emit pre-compressed .gz asset sidecars")
    println("    --incremental               Reuse .ssg_cache/ hashes for fast rebuilds")
    println("    --wasm-islands              Compile site/islands/*.cl -> wasm32")
    println("    --threads <N>               Worker threads for parallel rendering")
    println("    --site <dir> --dist <dir>   Override input/output directories")
    println("  serve [--port 3000] [--binary] [--no-watch]   Live-reload dev server")
    println("  check                         Validate schemas & check internal links")
    println("  pack <file.cld> [out.clb]     Compile .cld to compact .clb binary")
    println("  unpack <file.clb> [out.cld]   Decompile .clb back to .cld text")
    println("  bench [--pages N] [--disk]    Run high-throughput compilation benchmark")

fn cli_run_build(cfg: SsgConfig) -> int:
    println("[1/3] Discovering layouts, components, data, collections & assets...")
    println("[2/3] Compiling .cld / .md / .clx pages and posts...")
    rep := builder_run_all(cfg)
    println("[3/3] Build finished cleanly!")
    println("  + Site Name:              " + cfg.site_name)
    println("  + Static Pages Built:     " + str(rep.pages_built) + " (posts: " + str(rep.posts_built) + ", skipped: " + str(rep.skipped_incremental) + ")")
    println("  + Static Assets Copied:   " + str(rep.assets_copied))
    println("  + Binary Bundles Packed:  " + str(rep.binary_bundles_packed))
    println("  + Total Payload Written:  " + str(rep.total_bytes_written) + " bytes")
    println("  + Build Time (CPU):       " + str(rep.build_time_ms) + " ms")
    println("  + Output Directory:       " + cfg.dist_dir + "/")
    if rep.schema_errors > 0:
        println("  ! Collection Schema Errors: " + str(rep.schema_errors))
        return 1
    return 0

fn cli_run_new(target_name: string, tmpl_kind: string) -> int:
    dir_cache := dict[string, int]()
    if fs_is_dir(target_name) == 1:
        println("Error: directory already exists: " + target_name)
        return 1

    ssg_ensure_dir(ssg_path_join(target_name, "site/layouts"), dir_cache)
    ssg_ensure_dir(ssg_path_join(target_name, "site/components"), dir_cache)
    ssg_ensure_dir(ssg_path_join(target_name, "site/pages"), dir_cache)
    ssg_ensure_dir(ssg_path_join(target_name, "site/posts"), dir_cache)
    ssg_ensure_dir(ssg_path_join(target_name, "site/data"), dir_cache)
    ssg_ensure_dir(ssg_path_join(target_name, "site/content"), dir_cache)
    ssg_ensure_dir(ssg_path_join(target_name, "site/static"), dir_cache)
    ssg_ensure_dir(ssg_path_join(target_name, "site/islands"), dir_cache)

    ob := "{" + "{"
    cb := "}" + "}"
    op := "{" + "%"
    cp := "%" + "}"

    toml_cfg := "[site]\nsite_name = \"" + target_name + "\"\nsite_tagline = \"Built with Cluster-SSG (" + tmpl_kind + ")\"\nbase_url = \"http://localhost:3000\"\npermalink = \"/blog/:year/:month/:slug.html\"\npaginate = 10\nminify = false\nhash_assets = false\nview_transitions = true\n"
    file_write(ssg_path_join(target_name, "cluster-site.toml"), toml_cfg)

    // Typed content schema
    file_write(ssg_path_join(target_name, "site/content/config.toml"), "[posts]\ntitle = \"string\"\ndate = \"date\"\nauthor = \"string?\"\ntags = \"list\"\ndraft = \"bool?\"\n")

    // Data file
    file_write(ssg_path_join(target_name, "site/data/nav.yml"), "- label: Home\n  url: /index.html\n- label: Blog\n  url: /blog/index.html\n- label: Tags\n  url: /tags/index.html\n")

    // Layout
    layout_html := "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>" + ob + " title " + cb + " - " + ob + " site_name " + cb + "</title>\n  <link rel=\"stylesheet\" href=\"/static/style.css\">\n</head>\n<body>\n  " + op + " include \"navbar\" " + cp + "\n  <main class=\"container\">\n    " + ob + " content " + cb + "\n  </main>\n  " + op + " include \"footer\" " + cp + "\n</body>\n</html>\n"
    file_write(ssg_path_join(target_name, "site/layouts/default.html"), layout_html)

    // Navbar include using Liquid {% for %} over site.data.nav
    nav_html := "<header class=\"site-header\"><nav class=\"nav-bar\"><a class=\"brand\" href=\"/\">" + ob + " site_name " + cb + "</a><div class=\"links\">" + op + " for item in site.data.nav " + cp + "<a href=\"" + ob + " item.url " + cb + "\">" + ob + " item.label " + cb + "</a>" + op + " endfor " + cp + "</div></nav></header>\n"
    file_write(ssg_path_join(target_name, "site/components/navbar.html"), nav_html)
    file_write(ssg_path_join(target_name, "site/components/footer.html"), "<footer class=\"site-footer\"><p>&copy; 2026 " + ob + " site_name " + cb + " &middot; Built with pure Cluster-SSG</p></footer>\n")

    // Scoped Astro-style .clx component
    lbr := "{"
    rbr := "}"
    clx_src := "---\nbadge := \"Cluster\"\n---\n<div class=\"card\">\n  <span class=\"badge\">" + lbr + "badge" + rbr + "</span>\n  <h3>" + lbr + "title" + rbr + "</h3>\n  <div class=\"body\"><slot /></div>\n</div>\n<style scoped>\n.card " + lbr + " border: 1px solid #334155; border-radius: 10px; padding: 16px; margin: 12px 0; " + rbr + "\n.badge " + lbr + " background: #2563eb; color: #fff; font-size: 12px; padding: 2px 8px; border-radius: 99px; " + rbr + "\n</style>\n"
    file_write(ssg_path_join(target_name, "site/components/FeatureCard.clx"), clx_src)

    // Static CSS
    file_write(ssg_path_join(target_name, "site/static/style.css"), "body { font-family: system-ui, sans-serif; margin: 0; background: #0f172a; color: #e2e8f0; }\n.container { max-width: 860px; margin: 0 auto; padding: 24px; }\n.nav-bar { display: flex; justify-content: space-between; padding: 16px 24px; background: #1e293b; }\n.nav-bar a { color: #e2e8f0; text-decoration: none; margin-left: 16px; }\n.site-footer { text-align: center; padding: 24px; color: #94a3b8; }\n")

    // Sample index page
    index_md := "---\ntitle: Welcome to " + target_name + "\nlayout: default\ndescription: A production static site powered by Cluster-SSG (" + tmpl_kind + ")\n---\n\n# " + target_name + "\n\nGenerated with **Cluster-SSG v2.0** (" + tmpl_kind + " starter template) — zero Python, Ruby, or Node.\n\n<FeatureCard title=\"Astro + Hugo + Jekyll in Pure .cl\">\nWrite Markdown, `.cld` directives, Liquid loops, and `.clx` scoped components with sub-millisecond builds.\n</FeatureCard>\n\n<island name=\"Counter\" client:load count=\"0\" />\n\n::: callout type=\"tip\" title=\"Next Steps\"\nRun `cluster-ssg serve` to preview with live reload, or `cluster-ssg check` to validate links and schemas.\n:::\n"
    file_write(ssg_path_join(target_name, "site/pages/index.md"), index_md)

    // Sample post
    file_write(ssg_path_join(target_name, "site/posts/2026-11-27-hello-cluster.md"), "---\ntitle: Hello Cluster-SSG\nauthor: Developer\ndate: 2026-11-27\ntags: [cluster, ssg, announcement]\nlayout: post\n---\n\n# Hello World\n\nThis is your first typed blog post!\n\n```cluster\nfn main() -> int:\n    println(\"Zero dependencies!\")\n    return 0\n```\n")

    println("✓ Scaffolded new '" + tmpl_kind + "' site in: " + target_name + "/")
    println("  Run: cd " + target_name + " && cluster-ssg build && cluster-ssg serve")
    return 0

fn cli_run_pack(input_path: string, output_path: string) -> int:
    if file_exists(input_path) == 0:
        println("Error: input file does not exist: " + input_path)
        return 1
    doc := cld_parse_file(input_path)
    cld_save_binary(output_path, doc)
    println("✓ Packed " + doc.meta.title + " -> " + output_path)
    return 0

fn cli_run_unpack(input_path: string, output_path: string) -> int:
    if file_exists(input_path) == 0:
        println("Error: input binary file does not exist: " + input_path)
        return 1
    doc := cld_load_binary(input_path)
    sb := sb_new_cap(512)
    sb_append(sb, "title: " + doc.meta.title + "\nauthor: " + doc.meta.author + "\ndate: " + doc.meta.date + "\nlayout: " + doc.meta.layout + "\ntags: " + doc.meta.tags + "\ndescription: " + doc.meta.description + "\n===\n\n")
    let mut bi: int = 0
    while bi < len(doc.blocks):
        b := doc.blocks[bi]
        if b.kind == "h1": sb_append(sb, "# " + b.content + "\n\n")
        elif b.kind == "h2": sb_append(sb, "## " + b.content + "\n\n")
        elif b.kind == "h3": sb_append(sb, "### " + b.content + "\n\n")
        elif b.kind == "p": sb_append(sb, b.content + "\n\n")
        elif b.kind == "quote": sb_append(sb, "> " + b.content + "\n\n")
        elif b.kind == "code": sb_append(sb, "```" + b.extra + "\n" + b.content + "\n```\n\n")
        elif b.kind == "island": sb_append(sb, "<island name=\"" + b.content + "\" " + b.extra + " />\n\n")
        bi = bi + 1
    file_write(output_path, sb_to_str(sb))
    sb_free(sb)
    println("✓ Decompiled " + input_path + " -> " + output_path)
    return 0

fn cli_run_serve(cfg: SsgConfig, port: int, watch: int) -> int:
    // Initial build
    builder_run_all(cfg)
    srv := ssg_server_new(port, cfg.dist_dir, cfg.output_binary)
    srv.live_reload = watch
    let mut watch_dirs: vector[string] = []
    watch_dirs.push(cfg.site_dir)
    let mut ifd: i32 = -1
    if watch == 1:
        srv.reload_token = fs_max_source_signature(watch_dirs)
        ifd = fs_inotify_open(watch_dirs)

    lfd := net_listen(port)
    if lfd < 0:
        if ifd >= 0: close(ifd)
        println("Error: failed to bind TCP port " + str(port))
        return 1

    println("⚡ Cluster-SSG Dev Server listening on http://localhost:" + str(port))
    println("   Serving: " + cfg.dist_dir + " (watching " + cfg.site_dir + " | inotify_fd=" + str(ifd) + " | sse=on | binary=" + str(cfg.output_binary) + ")")
    let mut sse_fds: vector[i32] = []
    while 1 == 1:
        ev := fs_poll_fd2(lfd, ifd, 250)
        if watch == 1 and (ev & 2) != 0:
            if fs_inotify_drain(ifd, watch_dirs) == 1:
                cur_sig := fs_max_source_signature(watch_dirs)
                if cur_sig != srv.reload_token:
                    println("[Watcher] Change detected via inotify! Rebuilding...")
                    cfg.incremental = 1
                    builder_run_all(cfg)
                    srv.reload_token = cur_sig
                    msg := "event: reload\ndata: " + cur_sig + "\n\n"
                    let mut kept: vector[i32] = []
                    let mut si: int = 0
                    while si < len(sse_fds):
                        sfd := sse_fds[si]
                        nw := net_write(sfd, msg)
                        if nw > 0:
                            kept.push(sfd)
                        else:
                            net_close(sfd)
                        si = si + 1
                    sse_fds = kept
        if (ev & 1) != 0:
            cfd := net_accept(lfd)
            if cfd >= 0:
                raw := net_read(cfd, 8192)
                req_path := ssg_parse_request_path(raw)
                if watch == 1 and req_path == "/_cluster_sse":
                    hdr := "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nX-Cluster-SSE: 1\r\n\r\nretry: 500\nevent: token\ndata: " + srv.reload_token + "\n\n"
                    if net_write(cfd, hdr) > 0:
                        sse_fds.push(cfd)
                    else:
                        net_close(cfd)
                else:
                    if watch == 1 and req_path == "/_cluster_reload":
                        cur_sig := fs_max_source_signature(watch_dirs)
                        if cur_sig != srv.reload_token:
                            println("[Watcher] Change detected! Rebuilding...")
                            cfg.incremental = 1
                            builder_run_all(cfg)
                            srv.reload_token = cur_sig
                    resp := ssg_handle_http(srv, raw)
                    net_write(cfd, resp)
                    net_close(cfd)
    if ifd >= 0: close(ifd)
    net_close(lfd)
    return 0

fn cli_run_bench(page_count: int, on_disk: int) -> int:
    cfg := config_default()
    tr := builder_init_templates(cfg)
    islands := islands_registry_new()

    if on_disk == 1:
        dir_cache := dict[string, int]()
        broot := "/tmp/cl_ssg_bench_site"
        bsite := ssg_path_join(broot, "site/pages")
        bdist := ssg_path_join(broot, "dist")
        fs_remove_rf(broot)
        ssg_ensure_dir(bsite, dir_cache)
        sample_md := "---\ntitle: Disk Bench Page\nauthor: Cluster Bench\ndate: 2026-11-27\ntags: [perf, bench, cluster]\n---\n\n# Performance Test\n\nBenchmarking real disk compilation in pure Cluster.\n\n```cluster\nfn sum(n: int) -> int:\n    return n * (n + 1) / 2\n```\n"
        let mut gi: int = 0
        while gi < page_count:
            file_write(ssg_path_join(bsite, "page_" + str(gi) + ".md"), sample_md)
            gi = gi + 1
        cfg.site_dir = ssg_path_join(broot, "site")
        cfg.dist_dir = bdist
        cfg.threads = 4
        t0 := ssg_clock_us()
        rep := builder_run_all(cfg)
        t1 := ssg_clock_us()
        dt_us := t1 - t0
        let mut ms: int = dt_us / 1000
        if ms <= 0: ms = 1
        println("✓ Real-Disk Benchmark Complete!")
        println("  + Pages Compiled to Disk: " + str(rep.pages_built))
        println("  + Bytes Written:          " + str(rep.total_bytes_written))
        println("  + Elapsed (us/ms):        " + str(dt_us) + " us (" + str(ms) + " ms)")
        fs_remove_rf(broot)
        return 0

    sample := "---\ntitle: Bench Page\nauthor: Cluster Bot\ndate: 2026-11-27\n---\n# Performance Test\n\nThis benchmarks pure `.cl` Markdown, frontmatter, template & island hydration.\n\n<island name=\"Counter\" client:load count=\"0\" />\n\n> Zero dependencies, compiled native ELF64."
    t0 := ssg_clock_us()
    let mut i: int = 0
    let mut total_bytes: int = 0
    empty_fm := fm_parse_document(sample)
    md := md_parse_and_render(empty_fm.body)
    vars := dict[string, string]()
    vars["title"] = "Bench Page"
    vars["author"] = "Cluster Bot"
    vars["date"] = "2026-11-27"
    let lists := dict[string, string]()
    let items: vector[PageSummary] = []
    let p_idx: vector[int] = []
    let pg_idx: vector[int] = []
    let pgn_idx: vector[int] = []
    let pools: vector[vector[int]] = []
    ctx := RenderContext(vars, lists, items, p_idx, pg_idx, pgn_idx, pools, dict[string, int](), dict[string, int](), dict[string, int](), DataRegistry(dict[string, string](), dict[string, int]()), cfg)

    while i < page_count:
        arena:
            fm := fm_parse_document(sample)
            mr := md_parse_and_render(fm.body)
            html := template_v2_render(tr, "default", mr.html, vars, ctx)
            hyd := islands_hydrate_v2(islands, mr.islands, html, 0)
            total_bytes = total_bytes + string_length(hyd)
        i = i + 1
    t1 := ssg_clock_us()
    dt_us := t1 - t0
    if dt_us <= 0: dt_us = 1
    pps := (page_count * 1000000) / dt_us
    println("✓ In-Memory Full-Pipeline Benchmark Complete!")
    println("  + Pages Compiled:         " + str(page_count))
    println("  + Total HTML Generated:   " + str(total_bytes) + " bytes")
    println("  + Elapsed Time:           " + str(dt_us) + " us")
    println("  + Throughput:             " + str(pps) + " pages / sec")
    return 0
