// ==============================================================================
// Module:      Universal Site Configuration Parser (src/config.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Parses cluster-site.toml, site.toml, _config.yml, and cl.toml
//              into a unified SsgConfig with CLI flag overrides.
// ==============================================================================

import "src/strbuf.cl"

model SsgConfig:
    site_name: string
    site_tagline: string
    base_url: string
    theme: string
    site_dir: string
    dist_dir: string
    permalink: string
    paginate: int
    output_binary: int
    include_drafts: int
    minify: int
    hash_assets: int
    compress: int
    incremental: int
    clean_dist: int
    wasm_islands: int
    view_transitions: int
    threads: int
    default_lang: string
    languages: string
    collections: string
    custom: dict[string, string]

fn config_default() -> SsgConfig:
    cust := dict[string, string]()
    return SsgConfig("Cluster SSG Site", "Blazing-Fast Pure Cluster Static Site", "http://localhost:3000", "default", "site", "dist", "/:slug.html", 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, "en", "", "posts", cust)

fn _cfg_parse_bool(val: string, fallback: int) -> int:
    v := ssg_lower(ssg_strip_quotes(val))
    if v == "true" or v == "1" or v == "yes" or v == "on":
        return 1
    if v == "false" or v == "0" or v == "no" or v == "off":
        return 0
    return fallback

fn _cfg_apply_kv(cfg: SsgConfig, k_raw: string, v_raw: string) -> void:
    k := ssg_lower(ssg_trim(k_raw))
    v := ssg_strip_quotes(v_raw)
    if string_length(k) == 0:
        return
    cfg.custom[k] = v
    if k == "site_name" or k == "title" or k == "name":
        if string_length(v) > 0:
            cfg.site_name = v
    elif k == "site_tagline" or k == "tagline" or k == "subtitle" or k == "description":
        if string_length(v) > 0:
            cfg.site_tagline = v
    elif k == "base_url" or k == "baseurl" or k == "url":
        if string_length(v) > 0:
            let mut u: string = v
            while string_length(u) > 1 and ssg_ends_with(u, "/") == 1:
                u = substring(u, 0, string_length(u) - 1)
            cfg.base_url = u
    elif k == "theme":
        cfg.theme = v
    elif k == "site_dir" or k == "source" or k == "content_dir":
        if string_length(v) > 0:
            cfg.site_dir = v
    elif k == "dist_dir" or k == "destination" or k == "out_dir" or k == "publish_dir":
        if string_length(v) > 0:
            cfg.dist_dir = v
    elif k == "permalink":
        if string_length(v) > 0:
            cfg.permalink = v
    elif k == "paginate" or k == "per_page":
        p := ssg_parse_int(v, cfg.paginate)
        if p > 0:
            cfg.paginate = p
    elif k == "binary_wire" or k == "output_binary" or k == "binary":
        cfg.output_binary = _cfg_parse_bool(v, cfg.output_binary)
    elif k == "drafts" or k == "include_drafts" or k == "build_drafts":
        cfg.include_drafts = _cfg_parse_bool(v, cfg.include_drafts)
    elif k == "minify":
        cfg.minify = _cfg_parse_bool(v, cfg.minify)
    elif k == "hash_assets" or k == "fingerprint":
        cfg.hash_assets = _cfg_parse_bool(v, cfg.hash_assets)
    elif k == "compress" or k == "gzip":
        cfg.compress = _cfg_parse_bool(v, cfg.compress)
    elif k == "incremental":
        cfg.incremental = _cfg_parse_bool(v, cfg.incremental)
    elif k == "wasm_islands":
        cfg.wasm_islands = _cfg_parse_bool(v, cfg.wasm_islands)
    elif k == "view_transitions":
        cfg.view_transitions = _cfg_parse_bool(v, cfg.view_transitions)
    elif k == "threads" or k == "workers":
        t := ssg_parse_int(v, cfg.threads)
        if t > 0 and t <= 64:
            cfg.threads = t
    elif k == "default_lang" or k == "lang":
        if string_length(v) > 0:
            cfg.default_lang = v
    elif k == "languages":
        cfg.languages = v
    elif k == "collections":
        cfg.collections = v

fn _cfg_parse_toml_file(cfg: SsgConfig, path: string, only_site_section: int) -> void:
    if file_exists(path) == 0:
        return
    raw := file_read(path)
    lines := ssg_split_lines(raw)
    let mut section: string = ""
    let mut i: int = 0
    while i < len(lines):
        ln := ssg_trim(lines[i])
        if string_length(ln) == 0 or ssg_starts_with(ln, "#") == 1:
            i = i + 1
            continue
        if ssg_starts_with(ln, "[") == 1 and ssg_ends_with(ln, "]") == 1:
            section = ssg_lower(ssg_trim(substring(ln, 1, string_length(ln) - 2)))
            i = i + 1
            continue
        if only_site_section == 1 and section != "site" and section != "ssg":
            i = i + 1
            continue
        if section == "package" or section == "build":
            // cl.toml package metadata should not clobber site_name unless site_name absent
            i = i + 1
            continue
        eq := ssg_find_from(ln, "=", 0)
        if eq > 0:
            k := substring(ln, 0, eq)
            v := substring(ln, eq + 1, string_length(ln) - eq - 1)
            // Strip inline # comment outside quotes
            let mut v_clean: string = ssg_trim(v)
            if ssg_starts_with(v_clean, "\"") == 0 and ssg_starts_with(v_clean, "'") == 0:
                hc := ssg_find_from(v_clean, "#", 0)
                if hc >= 0:
                    v_clean = ssg_trim(substring(v_clean, 0, hc))
            _cfg_apply_kv(cfg, k, v_clean)
        i = i + 1

fn _cfg_parse_yaml_file(cfg: SsgConfig, path: string) -> void:
    if file_exists(path) == 0:
        return
    raw := file_read(path)
    lines := ssg_split_lines(raw)
    let mut i: int = 0
    while i < len(lines):
        ln := ssg_trim(lines[i])
        if string_length(ln) == 0 or ssg_starts_with(ln, "#") == 1:
            i = i + 1
            continue
        col := ssg_find_from(ln, ":", 0)
        if col > 0:
            k := substring(ln, 0, col)
            v := substring(ln, col + 1, string_length(ln) - col - 1)
            _cfg_apply_kv(cfg, k, v)
        i = i + 1

fn config_load(project_root: string) -> SsgConfig:
    cfg := config_default()

    // Support both Jekyll (_config.yml, _posts, _layouts, _includes) and Cluster-SSG (site/) auto-detection
    yml_path := ssg_path_join(project_root, "_config.yml")
    site_toml := ssg_path_join(project_root, "site.toml")
    cluster_site_toml := ssg_path_join(project_root, "cluster-site.toml")
    cl_toml := ssg_path_join(project_root, "cl.toml")
    hugo_toml := ssg_path_join(project_root, "hugo.toml")

    if file_exists(yml_path) == 1:
        _cfg_parse_yaml_file(cfg, yml_path)
    if file_exists(hugo_toml) == 1:
        _cfg_parse_toml_file(cfg, hugo_toml, 0)
    if file_exists(cl_toml) == 1:
        _cfg_parse_toml_file(cfg, cl_toml, 1)
    if file_exists(site_toml) == 1:
        _cfg_parse_toml_file(cfg, site_toml, 0)
    if file_exists(cluster_site_toml) == 1:
        _cfg_parse_toml_file(cfg, cluster_site_toml, 0)

    // Auto-detect Jekyll/Hugo directory if site/ doesn't exist
    if fs_is_dir(ssg_path_join(project_root, cfg.site_dir)) == 0:
        if fs_is_dir(ssg_path_join(project_root, "_posts")) == 1 or fs_is_dir(ssg_path_join(project_root, "_layouts")) == 1:
            cfg.site_dir = project_root
        elif fs_is_dir(ssg_path_join(project_root, "content")) == 1:
            cfg.site_dir = project_root

    if file_exists(".binary") == 1 or file_exists(ssg_path_join(cfg.site_dir, ".binary")) == 1:
        cfg.output_binary = 1

    return cfg
