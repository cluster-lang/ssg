// ==============================================================================
// Module:      Main Application Driver (src/main.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Standalone CLI entrypoint parsing argc/argv directly with zero Python.
// ==============================================================================

import "src/strbuf.cl"
import "src/config.cl"
import "src/cli.cl"
import "src/importer.cl"
import "src/builder.cl"

fn _main_apply_cli_flags(cfg: SsgConfig, start_idx: int, argc: int) -> void:
    let mut i: int = start_idx
    while i < argc:
        arg := sys_arg(i)
        if arg == "--binary": cfg.output_binary = 1
        elif arg == "--clean": cfg.clean_dist = 1
        elif arg == "--drafts": cfg.include_drafts = 1
        elif arg == "--minify": cfg.minify = 1
        elif arg == "--hash-assets": cfg.hash_assets = 1
        elif arg == "--compress": cfg.compress = 1
        elif arg == "--incremental": cfg.incremental = 1
        elif arg == "--wasm-islands": cfg.wasm_islands = 1
        elif arg == "--view-transitions": cfg.view_transitions = 1
        elif arg == "--threads" and i + 1 < argc:
            i = i + 1
            t := ssg_parse_int(sys_arg(i), cfg.threads)
            if t > 0: cfg.threads = t
        elif arg == "--site" and i + 1 < argc:
            i = i + 1
            cfg.site_dir = sys_arg(i)
        elif arg == "--dist" and i + 1 < argc:
            i = i + 1
            cfg.dist_dir = sys_arg(i)
        elif arg == "--base-url" and i + 1 < argc:
            i = i + 1
            cfg.base_url = sys_arg(i)
        i = i + 1

fn main() -> int:
    argc := sys_argc()
    cfg := config_load(".")

    if argc == 0:
        cli_print_banner()
        return cli_run_build(cfg)

    cmd := sys_arg(0)

    if cmd == "-h" or cmd == "--help" or cmd == "help":
        cli_print_banner()
        cli_print_usage()
        return 0
    if cmd == "-v" or cmd == "--version" or cmd == "version":
        println("cluster-ssg 2.0.0 (Pure Cluster · Jekyll + Hugo + Astro)")
        return 0

    if cmd == "build":
        cli_print_banner()
        _main_apply_cli_flags(cfg, 1, argc)
        return cli_run_build(cfg)

    if cmd == "serve":
        cli_print_banner()
        let mut port: int = 3000
        let mut watch: int = 1
        let mut i: int = 1
        while i < argc:
            a := sys_arg(i)
            if a == "--port" and i + 1 < argc:
                i = i + 1
                port = ssg_parse_int(sys_arg(i), 3000)
            elif a == "-p" and i + 1 < argc:
                i = i + 1
                port = ssg_parse_int(sys_arg(i), 3000)
            elif a == "--no-watch":
                watch = 0
            elif ssg_parse_int(a, -1) > 0:
                port = ssg_parse_int(a, 3000)
            i = i + 1
        _main_apply_cli_flags(cfg, 1, argc)
        return cli_run_serve(cfg, port, watch)

    if cmd == "new" or cmd == "init":
        if argc < 2:
            println("Usage: cluster-ssg new <site-name> [--template blog|docs|portfolio|landing]")
            return 1
        name := sys_arg(1)
        let mut tmpl: string = "docs"
        let mut i: int = 2
        while i < argc:
            if sys_arg(i) == "--template" and i + 1 < argc:
                i = i + 1
                tmpl = sys_arg(i)
            i = i + 1
        return cli_run_new(name, tmpl)

    if cmd == "import":
        if argc < 2:
            println("Usage: cluster-ssg import <jekyll-or-hugo-or-markdown-dir>")
            return 1
        src_dir := sys_arg(1)
        rep := importer_run(src_dir, ".")
        println("✓ Imported " + str(rep.pages_imported) + " pages, " + str(rep.posts_imported) + " posts, " + str(rep.layouts_imported) + " layouts, " + str(rep.components_imported) + " components, " + str(rep.data_imported) + " data files, " + str(rep.assets_copied) + " assets.")
        return cli_run_build(config_load("."))

    if cmd == "check":
        _main_apply_cli_flags(cfg, 1, argc)
        errs := builder_check_site(cfg)
        if errs > 0:
            println("✗ Site check failed with " + str(errs) + " error(s)/warning(s).")
            return 1
        println("✓ Site check passed (0 schema errors, 0 broken internal links)!")
        return 0

    if cmd == "pack":
        if argc < 2:
            println("Usage: cluster-ssg pack <input.cld> [output.clb]")
            return 1
        inp := sys_arg(1)
        let mut outp: string = inp + ".clb"
        if argc >= 3: outp = sys_arg(2)
        return cli_run_pack(inp, outp)

    if cmd == "unpack":
        if argc < 2:
            println("Usage: cluster-ssg unpack <input.clb> [output.cld]")
            return 1
        inp := sys_arg(1)
        let mut outp: string = inp + ".cld"
        if argc >= 3: outp = sys_arg(2)
        return cli_run_unpack(inp, outp)

    if cmd == "bench":
        let mut n_pages: int = 500
        let mut on_disk: int = 0
        let mut i: int = 1
        while i < argc:
            a := sys_arg(i)
            if a == "--pages" and i + 1 < argc:
                i = i + 1
                n_pages = ssg_parse_int(sys_arg(i), 500)
            elif a == "--disk":
                on_disk = 1
            elif ssg_parse_int(a, -1) > 0:
                n_pages = ssg_parse_int(a, 500)
            i = i + 1
        return cli_run_bench(n_pages, on_disk)

    // Unknown flag-only call (e.g. cluster-ssg --binary) -> build with flags
    if ssg_starts_with(cmd, "--") == 1:
        cli_print_banner()
        _main_apply_cli_flags(cfg, 0, argc)
        return cli_run_build(cfg)

    println("Unknown command: " + cmd)
    cli_print_usage()
    return 1
