// ==============================================================================
// Module:      Universal Multi-Core Static Site Builder (src/builder.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Zero-hardcoding static site compiler uniting:
//              - Recursive .cld/.md/.clx content discovery
//              - Multi-level Liquid layouts & partial includes + data/*.yml|toml|json
//              - Typed Content Collections schema validation & [slug] dynamic routes
//              - Hugo-speed parallel multi-core compilation + per-page arena reset
//              - Dynamic tags, categories, blog pagination, i18n hreflang, SEO tags,
//                sitemap.xml, feed.xml (RSS 2.0), atom.xml, robots.txt, search-index.json
//              - Asset minification, content hashing, .gz compression & .ssg_cache
// ==============================================================================

import "std/cld.cl"
import "src/strbuf.cl"
import "src/fs_walk.cl"
import "src/config.cl"
import "src/frontmatter.cl"
import "src/markdown.cl"
import "src/template_v2.cl"
import "src/collections.cl"
import "src/clx_compiler.cl"
import "src/islands_v2.cl"
import "src/assets.cl"
import "src/document.cl"

model BuildReport:
    pages_built: int
    posts_built: int
    assets_copied: int
    binary_bundles_packed: int
    build_time_ms: int
    total_bytes_written: int
    skipped_incremental: int
    schema_errors: int

model SsgDynRoute:
    abs_path: string
    rel_path: string
    collection: string
    is_clx: int

fn builder_init_templates(cfg: SsgConfig) -> TemplateRegistry:
    tr := template_new()
    ob := "{" + "{"
    cb := "}" + "}"

    // Built-in default fallbacks (overridden automatically by site/layouts/* & site/components/*)
    built_in_nav := "<header class=\"site-header\"><nav class=\"nav-bar\"><div class=\"brand\"><a href=\"/\"><strong>" + ob + " site_name " + cb + "</strong></a></div><div class=\"nav-links\"><a href=\"/\">Home</a><a href=\"/blog/index.html\">Blog</a><a href=\"/tags/index.html\">Tags</a><a href=\"/about.html\">About</a><a href=\"/docs.html\">Docs</a></div></nav></header>"
    built_in_foot := "<footer class=\"site-footer\"><p>&copy; " + ob + " year " + cb + " " + ob + " site_name " + cb + " &middot; Powered by Cluster-SSG</p></footer>"
    built_in_default := "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>" + ob + " title " + cb + " - " + ob + " site_name " + cb + "</title>\n  <meta name=\"description\" content=\"" + ob + " description | escape " + cb + "\">\n  <link rel=\"stylesheet\" href=\"/static/style.css\">\n</head>\n<body>\n  " + ob + " include \"navbar\" " + cb + "\n  <main class=\"main-content\">\n    " + ob + " content " + cb + "\n  </main>\n  " + ob + " include \"footer\" " + cb + "\n</body>\n</html>"
    built_in_post := "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>" + ob + " title " + cb + " - " + ob + " site_name " + cb + "</title>\n  <meta name=\"description\" content=\"" + ob + " description | escape " + cb + "\">\n  <link rel=\"stylesheet\" href=\"/static/style.css\">\n</head>\n<body>\n  " + ob + " include \"navbar\" " + cb + "\n  <article class=\"post-container\">\n    <header class=\"post-header\">\n      <h1>" + ob + " title " + cb + "</h1>\n      <div class=\"post-meta\">By <strong>" + ob + " author | default: \"Author\" " + cb + "</strong> &middot; " + ob + " date " + cb + "</div>\n    </header>\n    <div class=\"post-body\">\n      " + ob + " content " + cb + "\n    </div>\n  </article>\n  " + ob + " include \"footer\" " + cb + "\n</body>\n</html>"

    template_register_layout(tr, "default", built_in_default)
    template_register_layout(tr, "post", built_in_post)
    template_register_include(tr, "navbar", built_in_nav)
    template_register_include(tr, "footer", built_in_foot)

    let mut html_exts: vector[string] = []
    html_exts.push(".html")
    html_exts.push(".htm")

    // Auto-discover all layouts recursively
    let mut ldirs: vector[string] = []
    ldirs.push(ssg_path_join(cfg.site_dir, "layouts"))
    ldirs.push(ssg_path_join(cfg.site_dir, "_layouts"))
    let mut ldi: int = 0
    while ldi < len(ldirs):
        d := ldirs[ldi]
        if fs_is_dir(d) == 1:
            scan := fs_walk_tree(d, html_exts)
            let mut fi: int = 0
            while fi < len(scan.abs_paths):
                ap := scan.abs_paths[fi]
                rel := scan.rel_paths[fi]
                ext := ssg_path_ext(rel)
                name_no_ext := substring(rel, 0, string_length(rel) - string_length(ext))
                content := file_read(ap)
                template_register_layout(tr, name_no_ext, content)
                template_register_layout(tr, rel, content)
                fi = fi + 1
        ldi = ldi + 1

    // Auto-discover all includes / components / partials recursively
    let mut idirs: vector[string] = []
    idirs.push(ssg_path_join(cfg.site_dir, "components"))
    idirs.push(ssg_path_join(cfg.site_dir, "_components"))
    idirs.push(ssg_path_join(cfg.site_dir, "includes"))
    idirs.push(ssg_path_join(cfg.site_dir, "_includes"))
    idirs.push(ssg_path_join(cfg.site_dir, "layouts/partials"))
    let mut idi: int = 0
    while idi < len(idirs):
        d := idirs[idi]
        if fs_is_dir(d) == 1:
            scan := fs_walk_tree(d, html_exts)
            let mut fi: int = 0
            while fi < len(scan.abs_paths):
                ap := scan.abs_paths[fi]
                rel := scan.rel_paths[fi]
                ext := ssg_path_ext(rel)
                name_no_ext := substring(rel, 0, string_length(rel) - string_length(ext))
                content := file_read(ap)
                template_register_include(tr, name_no_ext, content)
                template_register_include(tr, rel, content)
                fi = fi + 1
        idi = idi + 1

    return tr

fn _builder_extract_chapter_num(slug: string) -> int:
    if ssg_starts_with(slug, "chapter") == 0:
        return -1
    rest := substring(slug, 7, string_length(slug) - 7)
    n := ssg_parse_int(rest, -1)
    if n > 0:
        return n
    return -1

fn _builder_inject_seo(html: string, cfg: SsgConfig, title: string, desc: string, page_url: string, alt_langs_html: string) -> string:
    if ssg_contains(html, "</head>") == 0 or ssg_contains(html, "property=\"og:title\"") == 1:
        return html
    canonical := cfg.base_url + page_url
    sb := sb_new_cap(512)
    sb_append(sb, "  <link rel=\"canonical\" href=\"" + ssg_escape_html(canonical) + "\" />\n")
    sb_append(sb, "  <meta property=\"og:title\" content=\"" + ssg_escape_html(title) + "\" />\n")
    sb_append(sb, "  <meta property=\"og:description\" content=\"" + ssg_escape_html(desc) + "\" />\n")
    sb_append(sb, "  <meta property=\"og:url\" content=\"" + ssg_escape_html(canonical) + "\" />\n")
    sb_append(sb, "  <meta property=\"og:type\" content=\"website\" />\n")
    sb_append(sb, "  <meta name=\"twitter:card\" content=\"summary\" />\n")
    sb_append(sb, alt_langs_html)
    sb_append(sb, "</head>")
    inj := sb_to_str(sb)
    sb_free(sb)
    return ssg_replace_all(html, "</head>", inj)

fn _builder_render_single_doc(doc: SsgRichDoc, cfg: SsgConfig, tr: TemplateRegistry, clx_reg: ClxRegistry, islands: IslandRegistry, asset_man: AssetManifest, ctx: RenderContext, total_chapters: int, alt_langs_html: string, zcodec: ZlibCodec) -> int:
    let mut written: int = 0
    arena:
        let mut body: string = doc.md.html
        // Inject dynamic chapter Prev/Next nav ONLY when document is a chapterN page
        chap_n := _builder_extract_chapter_num(doc.slug)
        if chap_n > 0 and total_chapters > 0:
            nsb := sb_new_cap(256)
            sb_append(nsb, "<div class=\"chapter-nav\">\n")
            if chap_n > 1:
                sb_append(nsb, "  <a href=\"/chapter" + str(chap_n - 1) + ".html\">&larr; Chapter " + str(chap_n - 1) + "</a>\n")
            else:
                sb_append(nsb, "  <span></span>\n")
            if chap_n < total_chapters:
                sb_append(nsb, "  <a href=\"/chapter" + str(chap_n + 1) + ".html\">Chapter " + str(chap_n + 1) + " &rarr;</a>\n")
            else:
                sb_append(nsb, "  <span></span>\n")
            sb_append(nsb, "</div>\n")
            body = body + "\n" + sb_to_str(nsb)
            sb_free(nsb)

        vars := dict[string, string]()
        fks := doc.fm.fields.keys()
        let mut fi: int = 0
        while fi < len(fks):
            vars[fks[fi]] = doc.fm.fields[fks[fi]]
            fi = fi + 1
        vars["title"] = doc.title
        vars["author"] = doc.author
        vars["date"] = doc.date
        vars["description"] = doc.description
        vars["tags"] = doc.tags
        vars["categories"] = doc.categories
        vars["slug"] = doc.slug
        vars["url"] = doc.permalink_url
        vars["excerpt"] = doc.md.plain_excerpt
        vars["reading_time"] = str(doc.reading_time_min)
        vars["toc"] = md_toc_to_html(doc.md.toc)
        vars["lang"] = doc.lang

        // Expand Astro-style .clx components in body
        body = clx_expand_calls(clx_reg, doc.md.clx_calls, body, vars)

        let mut html: string = template_v2_render_owned(tr, doc.layout, body, vars, ctx)
        html = islands_hydrate_v2(islands, doc.md.islands, html, cfg.view_transitions)
        html = _builder_inject_seo(html, cfg, doc.title, doc.description, doc.permalink_url, alt_langs_html)
        html = assets_rewrite_html_urls(html, asset_man)
        if cfg.minify == 1:
            html = assets_minify_html(html)

        ssg_write_file_raw(doc.out_file_path, html)
        written = string_length(html)

        if cfg.compress == 1:
            if ssg_gzip_write(zcodec, doc.out_file_path + ".gz", html) != 0:
                sys_run("gzip -kf -9 \"" + doc.out_file_path + "\" 2>/dev/null || true")

        if cfg.output_binary == 1:
            packed := ssg_rich_to_binary(doc)
            let mut bin_out: string = doc.out_file_path + ".clb"
            if ssg_ends_with(doc.out_file_path, ".html") == 1:
                bin_out = substring(doc.out_file_path, 0, string_length(doc.out_file_path) - 5) + ".clb"
            file_write(bin_out, packed)
            written = written + string_length(packed)

        dict_free(vars)
        dict_free(doc.fm.fields)
        dict_free(doc.fm.list_keys)
        list_free(doc.md.toc)
        list_free(doc.md.islands)
        list_free(doc.md.clx_calls)

    return written

fn _builder_render_clx_source(src: SsgPageSource, cfg: SsgConfig, tr: TemplateRegistry, asset_man: AssetManifest, ctx: RenderContext, alt_langs_html: string, zcodec: ZlibCodec) -> int:
    let mut written: int = 0
    arena:
        comp := clx_parse_component(ssg_path_stem(src.abs_path), file_read(src.abs_path))
        env := dict[string, string]()
        _clx_eval_frontmatter_vars(comp.script_src, env)
        let mut body_html: string = comp.template_html
        eks := env.keys()
        let mut ki: int = 0
        while ki < len(eks):
            body_html = ssg_replace_all(body_html, "{" + eks[ki] + "}", env[eks[ki]])
            ki = ki + 1
        if string_length(comp.scoped_css) > 0:
            body_html = "<div class=\"" + comp.scope_class + "\"><style>" + comp.scoped_css + "</style>" + body_html + "</div>"
        let mut title: string = comp.name
        if env.has("title") == 1: title = env["title"]
        let mut layout: string = "default"
        if env.has("layout") == 1: layout = env["layout"]
        slug := ssg_slugify(ssg_path_stem(src.rel_path))
        env["title"] = title
        env["slug"] = slug
        env["url"] = src.permalink_url
        let mut html: string = template_v2_render_owned(tr, layout, body_html, env, ctx)
        html = _builder_inject_seo(html, cfg, title, "", src.permalink_url, alt_langs_html)
        html = assets_rewrite_html_urls(html, asset_man)
        if cfg.minify == 1:
            html = assets_minify_html(html)
        ssg_write_file_raw(src.out_file_path, html)
        written = string_length(html)
        if cfg.compress == 1:
            if ssg_gzip_write(zcodec, src.out_file_path + ".gz", html) != 0:
                sys_run("gzip -kf -9 \"" + src.out_file_path + "\" 2>/dev/null || true")
    return written

fn _builder_render_source(src: SsgPageSource, cfg: SsgConfig, tr: TemplateRegistry, clx_reg: ClxRegistry, islands: IslandRegistry, asset_man: AssetManifest, ctx: RenderContext, total_chapters: int, alt_langs_html: string, zcodec: ZlibCodec) -> int:
    if src.is_clx == 1:
        return _builder_render_clx_source(src, cfg, tr, asset_man, ctx, alt_langs_html, zcodec)
    let mut wb: int = 0
    arena:
        doc := ssg_parse_rich_doc(src.abs_path, src.rel_path, src.collection)
        doc.permalink_url = src.permalink_url
        doc.out_file_path = src.out_file_path
        wb = _builder_render_single_doc(doc, cfg, tr, clx_reg, islands, asset_man, ctx, total_chapters, alt_langs_html, zcodec)
    return wb

fn _builder_str_lt(a: string, b: string) -> int:
    if a < b:
        return 1
    return 0

fn _builder_sort_indices_by_date_desc(indices: vector[int], items: vector[PageSummary]) -> void:
    n := len(indices)
    let mut i: int = 1
    while i < n:
        key_idx := indices[i]
        key_date := items[key_idx].date
        let mut j: int = i - 1
        while j >= 0:
            if items[indices[j]].date >= key_date:
                break
            indices[j + 1] = indices[j]
            j = j - 1
        indices[j + 1] = key_idx
        i = i + 1

fn _pack_push(sb: StrBuf, lens: vector[int], s: string) -> void:
    sl := string_length(s)
    lens.push(sl)
    if sl > 0:
        sb_append(sb, s)

fn _pack_pop(sb: StrBuf, lens: vector[int], &idx: int, &off: int) -> string:
    sl := lens[idx]
    idx = idx + 1
    if sl <= 0:
        return ""
    p: ptr := int_to_ptr(arena_alloc(sl + 1))
    mem_copy(p, ptr_add(sb.buf, off), sl)
    ptr_write_u8(ptr_add(p, sl), 0)
    off = off + sl
    return str_from_parts(p, sl)

fn _builder_is_standard_meta_key(k: string) -> int:
    if k == "title" or k == "author" or k == "date" or k == "layout" or k == "tags":
        return 1
    if k == "categories" or k == "slug" or k == "description" or k == "lang":
        return 1
    if k == "draft" or k == "published" or k == "permalink":
        return 1
    return 0

fn _builder_scan_and_record(
    ap: string,
    rel: string,
    col: string,
    is_clx: int,
    cfg: SsgConfig,
    dir_cache: dict[string, int],
    schema_reg: SchemaRegistry,
    sources: vector[SsgPageSource],
    items: vector[PageSummary],
    post_indices: vector[int],
    page_indices: vector[int],
    index_pools: vector[vector[int]],
    col_indices: dict[string, int],
    tag_indices: dict[string, int],
    cat_indices: dict[string, int],
    schema_errors: vector[string],
    shared_empty_meta: dict[string, string],
    &total_chapters: int
) -> void:
    pack_sb := sb_new_cap(1024)
    let mut pack_lens: vector[int] = []
    let mut keep_entry: int = 1
    let mut rt_min: int = 1
    let mut n_meta: int = 0
    let mut n_errs: int = 0

    arena:
        if is_clx == 1:
            comp := clx_parse_component(ssg_path_stem(ap), file_read(ap))
            env := dict[string, string]()
            _clx_eval_frontmatter_vars(comp.script_src, env)
            let mut title: string = comp.name
            if env.has("title") == 1: title = env["title"]
            slug := ssg_slugify(ssg_path_stem(rel))
            url := "/" + slug + ".html"
            outp := ssg_url_to_dist_path(cfg.dist_dir, url)

            _pack_push(pack_sb, pack_lens, url)
            _pack_push(pack_sb, pack_lens, outp)
            _pack_push(pack_sb, pack_lens, title)
            _pack_push(pack_sb, pack_lens, "")
            _pack_push(pack_sb, pack_lens, "")
            _pack_push(pack_sb, pack_lens, "")
            _pack_push(pack_sb, pack_lens, "")
            _pack_push(pack_sb, pack_lens, "")
            _pack_push(pack_sb, pack_lens, slug)
            _pack_push(pack_sb, pack_lens, "")
            _pack_push(pack_sb, pack_lens, "")
        else:
            hdr := ssg_scan_page_header(ap, rel, col, cfg.permalink, cfg.dist_dir)
            if hdr.is_draft == 1 and cfg.include_drafts == 0:
                keep_entry = 0
            else:
                let mut n_errs_local: int = 0
                if len(schema_reg.schemas) > 0:
                    let mut local_errs: vector[string] = []
                    collections_validate_header(schema_reg, hdr, local_errs)
                    n_errs_local = len(local_errs)
                    n_errs = n_errs_local
                    let mut lei: int = 0
                    while lei < n_errs_local:
                        _pack_push(pack_sb, pack_lens, local_errs[lei])
                        lei = lei + 1
                    list_free(local_errs)
                rt_min = hdr.reading_time_min

                _pack_push(pack_sb, pack_lens, hdr.source.permalink_url)
                _pack_push(pack_sb, pack_lens, hdr.source.out_file_path)
                _pack_push(pack_sb, pack_lens, hdr.title)
                _pack_push(pack_sb, pack_lens, hdr.date)
                _pack_push(pack_sb, pack_lens, hdr.author)
                _pack_push(pack_sb, pack_lens, hdr.description)
                _pack_push(pack_sb, pack_lens, hdr.tags)
                _pack_push(pack_sb, pack_lens, hdr.categories)
                _pack_push(pack_sb, pack_lens, hdr.slug)
                _pack_push(pack_sb, pack_lens, hdr.plain_excerpt)
                _pack_push(pack_sb, pack_lens, hdr.lang)

                fks := hdr.fm_fields.keys()
                let mut fki: int = 0
                while fki < len(fks):
                    fk := fks[fki]
                    if _builder_is_standard_meta_key(fk) == 0:
                        _pack_push(pack_sb, pack_lens, fk)
                        _pack_push(pack_sb, pack_lens, hdr.fm_fields[fk])
                        n_meta = n_meta + 1
                    fki = fki + 1
                list_free(fks)
                dict_free(hdr.fm_fields)

    if keep_entry == 0:
        sb_free(pack_sb)
        return

    let mut pidx: int = 0
    let mut poff: int = 0
    let mut ei: int = 0
    while ei < n_errs:
        schema_errors.push(_pack_pop(pack_sb, pack_lens, pidx, poff))
        ei = ei + 1

    let mut p_url: string = ""
    let mut p_outp: string = ""
    let mut p_title: string = ""
    let mut p_date: string = ""
    let mut p_author: string = ""
    let mut p_desc: string = ""
    let mut p_tags: string = ""
    let mut p_cats: string = ""
    let mut p_slug: string = ""
    let mut p_excerpt: string = ""
    let mut p_lang: string = ""

    if is_clx == 1:
        p_url = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_outp = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_title = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_date = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_author = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_desc = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_tags = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_cats = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_slug = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_excerpt = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_lang = _pack_pop(pack_sb, pack_lens, pidx, poff)
    else:
        p_url = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_outp = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_title = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_date = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_author = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_desc = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_tags = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_cats = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_slug = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_excerpt = _pack_pop(pack_sb, pack_lens, pidx, poff)
        p_lang = _pack_pop(pack_sb, pack_lens, pidx, poff)

    let mut sum_meta: dict[string, string] = shared_empty_meta
    if n_meta > 0:
        sum_meta = dict[string, string]()
        let mut mi: int = 0
        while mi < n_meta:
            mk := _pack_pop(pack_sb, pack_lens, pidx, poff)
            mv := _pack_pop(pack_sb, pack_lens, pidx, poff)
            sum_meta[mk] = mv
            mi = mi + 1

    sb_free(pack_sb)

    let mut p_col: string = col
    if is_clx == 1:
        p_col = "pages"
    out_src := SsgPageSource(ap, rel, p_col, p_url, p_outp, is_clx)
    out_sum := PageSummary(p_title, p_url, p_date, p_author, p_desc, p_tags, p_cats, p_col, p_slug, p_excerpt, rt_min, p_lang, sum_meta)

    arena:
        ch_n := _builder_extract_chapter_num(out_sum.slug)
        if ch_n > total_chapters:
            total_chapters = ch_n
        ssg_ensure_dir(ssg_path_dirname(out_src.out_file_path), dir_cache)

    di := len(items)
    items.push(out_sum)
    sources.push(out_src)

    if out_src.collection == "posts":
        post_indices.push(di)
    else:
        page_indices.push(di)

    if col_indices.has(out_src.collection) == 0:
        let cnew: vector[int] = []
        col_indices[out_src.collection] = len(index_pools)
        index_pools.push(cnew)
    c_slot := col_indices[out_src.collection]
    cvec := index_pools[c_slot]
    cvec.push(di)
    index_pools[c_slot] = cvec

    _builder_add_csv_index(out_sum.tags, di, index_pools, tag_indices)
    _builder_add_csv_index(out_sum.categories, di, index_pools, cat_indices)

fn _builder_add_csv_index(csv_str: string, di: int, index_pools: vector[vector[int]], idx_map: dict[string, int]) -> void:
    slen := string_length(csv_str)
    if slen <= 0:
        return
    let mut start: int = 0
    while start <= slen:
        comma := ssg_find_from(csv_str, ",", start)
        let mut end_p: int = slen
        if comma >= 0:
            end_p = comma
        tok := ssg_slugify(ssg_trim(substring(csv_str, start, end_p - start)))
        if string_length(tok) > 0 and tok != "untitled":
            if idx_map.has(tok) == 0:
                let nvec: vector[int] = []
                idx_map[tok] = len(index_pools)
                index_pools.push(nvec)
            slot := idx_map[tok]
            pvec := index_pools[slot]
            pvec.push(di)
            index_pools[slot] = pvec
        if comma < 0:
            break
        start = comma + 1

fn _builder_scan_sources_streaming(
    cfg: SsgConfig,
    dir_cache: dict[string, int],
    schema_reg: SchemaRegistry,
    items: vector[PageSummary],
    post_indices: vector[int],
    page_indices: vector[int],
    index_pools: vector[vector[int]],
    col_indices: dict[string, int],
    tag_indices: dict[string, int],
    cat_indices: dict[string, int],
    schema_errors: vector[string],
    dyn_routes: vector[SsgDynRoute],
    &total_chapters: int
) -> vector[SsgPageSource]:
    let mut exts: vector[string] = []
    exts.push(".cld")
    exts.push(".md")
    exts.push(".markdown")

    let mut sources: vector[SsgPageSource] = []
    seen_paths := dict[string, int]()
    shared_empty_meta := dict[string, string]()

    // 1. Scan pages/
    let mut pdirs: vector[string] = []
    pdirs.push(ssg_path_join(cfg.site_dir, "pages"))
    pdirs.push(ssg_path_join(cfg.site_dir, "content/pages"))
    let mut pdi: int = 0
    while pdi < len(pdirs):
        d := pdirs[pdi]
        if fs_is_dir(d) == 1:
            scan := fs_walk_tree(d, exts)
            let mut i: int = 0
            while i < len(scan.abs_paths):
                ap := scan.abs_paths[i]
                rel := scan.rel_paths[i]
                if seen_paths.has(ap) == 0:
                    seen_paths[ap] = 1
                    if ssg_contains(rel, "[slug]") == 1:
                        dyn_routes.push(SsgDynRoute(ap, rel, "pages", 0))
                    else:
                        _builder_scan_and_record(ap, rel, "pages", 0, cfg, dir_cache, schema_reg, sources, items, post_indices, page_indices, index_pools, col_indices, tag_indices, cat_indices, schema_errors, shared_empty_meta, total_chapters)
                i = i + 1
            list_free(scan.abs_paths)
            list_free(scan.rel_paths)
        pdi = pdi + 1

    // 2. Scan posts/ and _posts/
    let mut post_dirs: vector[string] = []
    post_dirs.push(ssg_path_join(cfg.site_dir, "posts"))
    post_dirs.push(ssg_path_join(cfg.site_dir, "_posts"))
    post_dirs.push(ssg_path_join(cfg.site_dir, "content/posts"))
    let mut pti: int = 0
    while pti < len(post_dirs):
        d := post_dirs[pti]
        if fs_is_dir(d) == 1:
            scan := fs_walk_tree(d, exts)
            let mut i: int = 0
            while i < len(scan.abs_paths):
                ap := scan.abs_paths[i]
                rel := scan.rel_paths[i]
                if seen_paths.has(ap) == 0:
                    seen_paths[ap] = 1
                    if ssg_contains(rel, "[slug]") == 1:
                        dyn_routes.push(SsgDynRoute(ap, rel, "posts", 0))
                    else:
                        _builder_scan_and_record(ap, rel, "posts", 0, cfg, dir_cache, schema_reg, sources, items, post_indices, page_indices, index_pools, col_indices, tag_indices, cat_indices, schema_errors, shared_empty_meta, total_chapters)
                i = i + 1
            list_free(scan.abs_paths)
            list_free(scan.rel_paths)
        pti = pti + 1

    // 3. Scan custom collections under site/content/<col>/** or site/collections/<col>/**
    let mut cdirs: vector[string] = []
    cdirs.push(ssg_path_join(cfg.site_dir, "collections"))
    cdirs.push(ssg_path_join(cfg.site_dir, "content"))
    let mut cdi: int = 0
    while cdi < len(cdirs):
        root_c := cdirs[cdi]
        if fs_is_dir(root_c) == 1:
            subs := fs_list_dir(root_c)
            let mut si: int = 0
            while si < len(subs):
                col := subs[si]
                if col != "pages" and col != "posts":
                    col_dir := ssg_path_join(root_c, col)
                    if fs_is_dir(col_dir) == 1:
                        scan := fs_walk_tree(col_dir, exts)
                        let mut i: int = 0
                        while i < len(scan.abs_paths):
                            ap := scan.abs_paths[i]
                            rel := scan.rel_paths[i]
                            if seen_paths.has(ap) == 0:
                                seen_paths[ap] = 1
                                if ssg_contains(rel, "[slug]") == 1:
                                    dyn_routes.push(SsgDynRoute(ap, rel, col, 0))
                                else:
                                    _builder_scan_and_record(ap, rel, col, 0, cfg, dir_cache, schema_reg, sources, items, post_indices, page_indices, index_pools, col_indices, tag_indices, cat_indices, schema_errors, shared_empty_meta, total_chapters)
                            i = i + 1
                        list_free(scan.abs_paths)
                        list_free(scan.rel_paths)
                si = si + 1
        cdi = cdi + 1

    // 4. Support .clx pages directly under site/pages/*.clx
    let mut clx_exts: vector[string] = []
    clx_exts.push(".clx")
    clx_pdir := ssg_path_join(cfg.site_dir, "pages")
    if fs_is_dir(clx_pdir) == 1:
        scan := fs_walk_tree(clx_pdir, clx_exts)
        let mut i: int = 0
        while i < len(scan.abs_paths):
            ap := scan.abs_paths[i]
            rel := scan.rel_paths[i]
            if ssg_contains(rel, "[slug]") == 1:
                dyn_routes.push(SsgDynRoute(ap, rel, "pages", 1))
            else:
                _builder_scan_and_record(ap, rel, "pages", 1, cfg, dir_cache, schema_reg, sources, items, post_indices, page_indices, index_pools, col_indices, tag_indices, cat_indices, schema_errors, shared_empty_meta, total_chapters)
            i = i + 1
        list_free(scan.abs_paths)
        list_free(scan.rel_paths)

    dict_free(seen_paths)
    return sources

fn _builder_expand_dyn_routes(
    dyn_routes: vector[SsgDynRoute],
    cfg: SsgConfig,
    dir_cache: dict[string, int],
    tr: TemplateRegistry,
    clx_reg: ClxRegistry,
    islands: IslandRegistry,
    asset_man: AssetManifest,
    ctx: RenderContext,
    items: vector[PageSummary],
    post_indices: vector[int],
    index_pools: vector[vector[int]],
    col_indices: dict[string, int],
    total_chapters: int,
    alt_langs_html: string,
    zcodec: ZlibCodec,
    &pages_built: int,
    &total_bytes: int
) -> void:
    let mut di: int = 0
    while di < len(dyn_routes):
        dr := dyn_routes[di]
        // Choose target items: posts for blog/[slug], or matching collection folder, else all items
        let mut target_pool: vector[int] = []
        rel_dir := ssg_path_dirname(dr.rel_path)
        if dr.collection == "posts" or rel_dir == "blog" or rel_dir == "posts":
            target_pool = post_indices
        elif string_length(rel_dir) > 0 and col_indices.has(rel_dir) == 1:
            target_pool = index_pools[col_indices[rel_dir]]
        elif col_indices.has(dr.collection) == 1 and dr.collection != "pages":
            target_pool = index_pools[col_indices[dr.collection]]
        else:
            let mut ai: int = 0
            while ai < len(items):
                target_pool.push(ai)
                ai = ai + 1

        raw_tmpl := ssg_read_file_arena(dr.abs_path)
        let mut ti: int = 0
        while ti < len(target_pool):
            arena:
                p := items[target_pool[ti]]
                let mut gen_rel: string = ssg_replace_all(dr.rel_path, "[slug]", p.slug)
                if ssg_ends_with(gen_rel, ".clx") == 1:
                    gen_rel = substring(gen_rel, 0, string_length(gen_rel) - 4) + ".html"
                elif ssg_ends_with(gen_rel, ".md") == 1:
                    gen_rel = substring(gen_rel, 0, string_length(gen_rel) - 3) + ".html"
                elif ssg_ends_with(gen_rel, ".cld") == 1:
                    gen_rel = substring(gen_rel, 0, string_length(gen_rel) - 4) + ".html"
                elif ssg_ends_with(gen_rel, ".markdown") == 1:
                    gen_rel = substring(gen_rel, 0, string_length(gen_rel) - 9) + ".html"
                gen_url := "/" + gen_rel
                out_p := ssg_url_to_dist_path(cfg.dist_dir, gen_url)
                ssg_ensure_dir(ssg_path_dirname(out_p), dir_cache)

                vars := dict[string, string]()
                vars["title"] = p.title
                vars["url"] = gen_url
                vars["item.url"] = p.url
                vars["date"] = p.date
                vars["author"] = p.author
                vars["description"] = p.description
                vars["tags"] = p.tags
                vars["categories"] = p.categories
                vars["collection"] = p.collection
                vars["slug"] = p.slug
                vars["excerpt"] = p.excerpt
                vars["reading_time"] = str(p.reading_time)
                vars["lang"] = p.lang

                let mut html: string = ""
                if dr.is_clx == 1:
                    comp := clx_parse_component(ssg_path_stem(dr.abs_path), raw_tmpl)
                    _clx_eval_frontmatter_vars(comp.script_src, vars)
                    let mut body_html: string = comp.template_html
                    eks := vars.keys()
                    let mut ki: int = 0
                    while ki < len(eks):
                        body_html = ssg_replace_all(body_html, "{" + eks[ki] + "}", ssg_escape_html(vars[eks[ki]]))
                        ki = ki + 1
                    if string_length(comp.scoped_css) > 0:
                        body_html = "<div class=\"" + comp.scope_class + "\"><style>" + comp.scoped_css + "</style>" + body_html + "</div>"
                    let mut layout: string = "default"
                    if vars.has("layout") == 1: layout = vars["layout"]
                    html = template_v2_render_owned(tr, layout, body_html, vars, ctx)
                else:
                    fm := fm_parse_document(raw_tmpl)
                    let mut lay: string = "default"
                    if fm.fields.has("layout") == 1: lay = fm.fields["layout"]
                    md := md_parse_and_render(fm.body)
                    body := clx_expand_calls(clx_reg, md.clx_calls, md.html, vars)
                    html = template_v2_render_owned(tr, lay, body, vars, ctx)
                    html = islands_hydrate_v2(islands, md.islands, html, cfg.view_transitions)

                html = _builder_inject_seo(html, cfg, p.title, p.description, gen_url, alt_langs_html)
                html = assets_rewrite_html_urls(html, asset_man)
                if cfg.minify == 1:
                    html = assets_minify_html(html)
                ssg_write_file_raw(out_p, html)
                total_bytes = total_bytes + string_length(html)
                pages_built = pages_built + 1
                if cfg.compress == 1:
                    if ssg_gzip_write(zcodec, out_p + ".gz", html) != 0:
                        sys_run("gzip -kf -9 \"" + out_p + "\" 2>/dev/null || true")
            ti = ti + 1
        di = di + 1

fn _builder_stream_worker(
    sources: vector[SsgPageSource],
    s_idx: int,
    e_idx: int,
    cfg: SsgConfig,
    tr: TemplateRegistry,
    clx_reg: ClxRegistry,
    islands: IslandRegistry,
    asset_man: AssetManifest,
    ctx: RenderContext,
    total_chapters: int,
    alt_langs_html: string,
    zcodec: ZlibCodec,
    ch_pages: Channel[int],
    ch_posts: Channel[int],
    ch_bins: Channel[int],
    ch_bytes: Channel[int]
) -> void:
    let mut cnt: int = 0
    let mut posts: int = 0
    let mut bins: int = 0
    let mut wb: int = 0
    let mut k: int = s_idx
    while k < e_idx:
        src := sources[k]
        b := _builder_render_source(src, cfg, tr, clx_reg, islands, asset_man, ctx, total_chapters, alt_langs_html, zcodec)
        wb = wb + b
        cnt = cnt + 1
        if src.collection == "posts":
            posts = posts + 1
        if cfg.output_binary == 1 and src.is_clx == 0:
            bins = bins + 1
        k = k + 1
    ch_pages.send(cnt)
    ch_posts.send(posts)
    ch_bins.send(bins)
    ch_bytes.send(wb)

fn builder_run_all(cfg: SsgConfig) -> BuildReport:
    t0 := ssg_clock_us()
    dir_cache := dict[string, int]()
    zcodec := ssg_zlib_init()

    if cfg.clean_dist == 1 and fs_is_dir(cfg.dist_dir) == 1:
        fs_remove_rf(cfg.dist_dir)

    ssg_ensure_dir(cfg.dist_dir, dir_cache)
    ssg_ensure_dir(ssg_path_join(cfg.dist_dir, "api"), dir_cache)

    // 1. Load templates, includes, data files, schemas, .clx components, islands & assets
    tr := builder_init_templates(cfg)
    data_reg := data_load_all(cfg.site_dir)
    schema_reg := collections_load_schemas(cfg.site_dir)
    clx_reg := clx_load_all(cfg.site_dir)
    islands := islands_registry_new()
    islands_discover_custom(islands, cfg.site_dir, cfg.dist_dir, cfg.wasm_islands, dir_cache)
    asset_man := assets_process_all(cfg.site_dir, cfg.dist_dir, cfg.minify, cfg.hash_assets, cfg.compress, dir_cache)

    // 2. Stage 1 Streaming Metadata Discovery & Schema Validation (per-file arena rewind)
    let mut schema_errors: vector[string] = []
    let mut items: vector[PageSummary] = []
    let mut post_indices: vector[int] = []
    let mut page_indices: vector[int] = []
    let mut pgn_indices: vector[int] = []
    let mut index_pools: vector[vector[int]] = []
    col_indices := dict[string, int]()
    tag_indices := dict[string, int]()
    cat_indices := dict[string, int]()
    let mut dyn_routes: vector[SsgDynRoute] = []
    let mut total_chapters: int = 0

    sources := _builder_scan_sources_streaming(cfg, dir_cache, schema_reg, items, post_indices, page_indices, index_pools, col_indices, tag_indices, cat_indices, schema_errors, dyn_routes, total_chapters)

    if len(schema_errors) > 0:
        let mut ei: int = 0
        while ei < len(schema_errors):
            println(schema_errors[ei])
            ei = ei + 1

    _builder_sort_indices_by_date_desc(post_indices, items)

    // Precompute optional i18n hreflang alternate links
    let mut alt_langs_html: string = ""
    if string_length(cfg.languages) > 0:
        lcodes := ssg_split(cfg.languages, ",")
        let mut lki: int = 0
        while lki < len(lcodes):
            lc := ssg_trim(lcodes[lki])
            if string_length(lc) > 0:
                alt_langs_html = alt_langs_html + "  <link rel=\"alternate\" hreflang=\"" + ssg_escape_html(lc) + "\" href=\"" + ssg_escape_html(cfg.base_url + "/" + lc + "/") + "\" />\n"
            lki = lki + 1

    // Global layout/data signature for incremental cache invalidation
    let mut inc_cache := ssg_cache_load(".ssg_cache", "")
    if cfg.incremental == 1:
        let mut watch_dirs: vector[string] = []
        watch_dirs.push(ssg_path_join(cfg.site_dir, "layouts"))
        watch_dirs.push(ssg_path_join(cfg.site_dir, "layouts/partials"))
        watch_dirs.push(ssg_path_join(cfg.site_dir, "_layouts"))
        watch_dirs.push(ssg_path_join(cfg.site_dir, "components"))
        watch_dirs.push(ssg_path_join(cfg.site_dir, "includes"))
        watch_dirs.push(ssg_path_join(cfg.site_dir, "_includes"))
        watch_dirs.push(ssg_path_join(cfg.site_dir, "data"))
        gsig := ssg_fnv1a_hash(cfg.site_name + "|" + cfg.base_url + "|" + fs_max_source_signature(watch_dirs))
        inc_cache = ssg_cache_load(".ssg_cache", gsig)

    base_vars := dict[string, string]()
    base_lists := dict[string, string]()
    ctx := RenderContext(base_vars, base_lists, items, post_indices, page_indices, pgn_indices, index_pools, col_indices, tag_indices, cat_indices, data_reg, cfg)

    // 3. Stage 2 Streaming Page & Post Compilation (Parallel TLS-arena workers when batch >= 32 and non-incremental)
    let mut pages_built: int = 0
    let mut posts_built: int = 0
    let mut total_bins: int = 0
    let mut total_bytes: int = asset_man.bytes_written
    let mut skipped_inc: int = 0

    let n_docs: int = len(sources)
    let mut n_workers: int = cfg.threads
    if n_workers <= 0: n_workers = 4
    if n_workers > 8: n_workers = 8
    if n_workers > 1 and n_docs >= 32 and cfg.incremental == 0:
        ch_pages := Channel[int](n_workers)
        ch_posts := Channel[int](n_workers)
        ch_bins := Channel[int](n_workers)
        ch_bytes := Channel[int](n_workers)
        chunk := (n_docs + n_workers - 1) / n_workers
        let mut launched: int = 0
        let mut wi: int = 0
        while wi < n_workers:
            s_i := wi * chunk
            if s_i < n_docs:
                let mut e_i: int = s_i + chunk
                if e_i > n_docs: e_i = n_docs
                launched = launched + 1
                spawn _builder_stream_worker(sources, s_i, e_i, cfg, tr, clx_reg, islands, asset_man, ctx, total_chapters, alt_langs_html, zcodec, ch_pages, ch_posts, ch_bins, ch_bytes)
            wi = wi + 1
        let mut ri2: int = 0
        while ri2 < launched:
            pages_built = pages_built + ch_pages.recv()
            posts_built = posts_built + ch_posts.recv()
            total_bins = total_bins + ch_bins.recv()
            total_bytes = total_bytes + ch_bytes.recv()
            ri2 = ri2 + 1
    else:
        let mut ri: int = 0
        while ri < n_docs:
            src := sources[ri]
            let mut dirty: int = 1
            if cfg.incremental == 1:
                mt_key := str(fs_mtime_ns(src.abs_path))
                dirty = ssg_cache_is_dirty(inc_cache, src.abs_path, mt_key, src.out_file_path)
            if dirty == 1:
                wb := _builder_render_source(src, cfg, tr, clx_reg, islands, asset_man, ctx, total_chapters, alt_langs_html, zcodec)
                total_bytes = total_bytes + wb
                pages_built = pages_built + 1
                if src.collection == "posts":
                    posts_built = posts_built + 1
                if cfg.output_binary == 1 and src.is_clx == 0:
                    total_bins = total_bins + 1
            else:
                skipped_inc = skipped_inc + 1
            ri = ri + 1

    if cfg.incremental == 1:
        ssg_cache_save(inc_cache, ".ssg_cache", dir_cache)

    // 3b. Dynamic [slug] Route Expansion
    if len(dyn_routes) > 0:
        _builder_expand_dyn_routes(dyn_routes, cfg, dir_cache, tr, clx_reg, islands, asset_man, ctx, items, post_indices, index_pools, col_indices, total_chapters, alt_langs_html, zcodec, pages_built, total_bytes)

    // 4. Execute Static JSON API Endpoints (site/pages/api/*.json.cl)
    api_src_dir := ssg_path_join(cfg.site_dir, "pages/api")
    if fs_is_dir(api_src_dir) == 1:
        let mut ep_exts: vector[string] = []
        ep_exts.push(".cl")
        ep_scan := fs_walk_tree(api_src_dir, ep_exts)
        let mut epi: int = 0
        while epi < len(ep_scan.abs_paths):
            ap := ep_scan.abs_paths[epi]
            rel := ep_scan.rel_paths[epi]
            if ssg_ends_with(rel, ".json.cl") == 1:
                json_name := substring(rel, 0, string_length(rel) - 3)
                out_json := ssg_path_join(cfg.dist_dir, "api/" + json_name)
                ssg_ensure_dir(ssg_path_dirname(out_json), dir_cache)
                sys_run("cl run \"" + ap + "\" > \"" + out_json + "\" 2>/dev/null || true")
            epi = epi + 1

    // 5. Dynamic Tags Index & Tag Archive Pages (/tags/index.html, /tags/<tag>.html, /tags/<tag>/index.html)
    tags_dir := ssg_path_join(cfg.dist_dir, "tags")
    ssg_ensure_dir(tags_dir, dir_cache)
    tag_keys := tag_indices.keys()

    idx_sb := sb_new_cap(1024)
    sb_append(idx_sb, "<h1>All Tags (" + str(len(tag_keys)) + ")</h1>\n<div class=\"tag-cloud\">\n")
    let mut tki: int = 0
    while tki < len(tag_keys):
        tname := tag_keys[tki]
        idx_list := index_pools[tag_indices[tname]]
        sb_append(idx_sb, "  <a class=\"tag-pill\" href=\"/tags/" + tname + ".html\">#" + ssg_escape_html(tname) + " (" + str(len(idx_list)) + ")</a>\n")

        tb := sb_new_cap(1024)
        sb_append(tb, "<h1>Tag: #" + ssg_escape_html(tname) + "</h1>\n")
        sb_append(tb, "<p>" + str(len(idx_list)) + " tagged entries &middot; <a href=\"/tags/index.html\">All tags</a></p><hr />\n<div class=\"chapter-grid\">\n")
        let mut ti2: int = 0
        while ti2 < len(idx_list):
            p := items[idx_list[ti2]]
            sb_append(tb, "  <a class=\"chapter-card\" href=\"" + ssg_escape_html(p.url) + "\">\n")
            sb_append(tb, "    <div class=\"card-title\">" + ssg_escape_html(p.title) + "</div>\n")
            if string_length(p.date) > 0:
                sb_append(tb, "    <div class=\"card-num\">" + ssg_escape_html(p.date) + "</div>\n")
            sb_append(tb, "  </a>\n")
            ti2 = ti2 + 1
        sb_append(tb, "</div>\n")

        tv := dict[string, string]()
        tv["title"] = "Tag: #" + tname
        tv["description"] = "Pages and posts tagged #" + tname
        tv["slug"] = "tag-" + tname
        t_html := assets_rewrite_html_urls(template_v2_render(tr, "default", sb_to_str(tb), tv, ctx), asset_man)
        sb_free(tb)

        tag_html_path := ssg_path_join(tags_dir, tname + ".html")
        file_write(tag_html_path, t_html)
        tag_sub_dir := ssg_path_join(tags_dir, tname)
        ssg_ensure_dir(tag_sub_dir, dir_cache)
        file_write(ssg_path_join(tag_sub_dir, "index.html"), t_html)
        total_bytes = total_bytes + string_length(t_html) * 2
        pages_built = pages_built + 1
        tki = tki + 1
    sb_append(idx_sb, "</div>\n")
    tidx_v := dict[string, string]()
    tidx_v["title"] = "Tags"
    tidx_v["description"] = "Browse all site tags"
    tidx_v["slug"] = "tags"
    tidx_html := assets_rewrite_html_urls(template_v2_render(tr, "default", sb_to_str(idx_sb), tidx_v, ctx), asset_man)
    sb_free(idx_sb)
    file_write(ssg_path_join(tags_dir, "index.html"), tidx_html)
    total_bytes = total_bytes + string_length(tidx_html)

    // 6. Blog Pagination (/blog/index.html & /blog/page/2/index.html ...)
    if len(post_indices) > 0:
        per_page := cfg.paginate
        total_posts := len(post_indices)
        total_pg_pages := (total_posts + per_page - 1) / per_page
        let mut pgn: int = 1
        while pgn <= total_pg_pages:
            start_p := (pgn - 1) * per_page
            let mut end_p: int = start_p + per_page
            if end_p > total_posts: end_p = total_posts
            psb := sb_new_cap(1024)
            sb_append(psb, "<h1>Articles (Page " + str(pgn) + " of " + str(total_pg_pages) + ")</h1>\n<div class=\"post-list\">\n")
            let mut k: int = start_p
            while k < end_p:
                p := items[post_indices[k]]
                sb_append(psb, "  <article class=\"post-card\">\n")
                sb_append(psb, "    <h2><a href=\"" + ssg_escape_html(p.url) + "\">" + ssg_escape_html(p.title) + "</a></h2>\n")
                sb_append(psb, "    <div class=\"post-meta\">" + ssg_escape_html(p.date) + " &middot; " + str(p.reading_time) + " min read</div>\n")
                sb_append(psb, "    <p>" + ssg_escape_html(p.description) + "</p>\n")
                sb_append(psb, "  </article>\n")
                k = k + 1
            sb_append(psb, "</div>\n<nav class=\"pagination\">\n")
            if pgn > 1:
                if pgn == 2: sb_append(psb, "  <a href=\"/blog/index.html\">&larr; Newer</a>\n")
                else: sb_append(psb, "  <a href=\"/blog/page/" + str(pgn - 1) + "/index.html\">&larr; Newer</a>\n")
            if pgn < total_pg_pages:
                sb_append(psb, "  <a href=\"/blog/page/" + str(pgn + 1) + "/index.html\">Older &rarr;</a>\n")
            sb_append(psb, "</nav>\n")
            pv := dict[string, string]()
            pv["title"] = "Blog - Page " + str(pgn)
            pv["description"] = cfg.site_tagline
            pv["slug"] = "blog"
            phtml := assets_rewrite_html_urls(template_v2_render(tr, "default", sb_to_str(psb), pv, ctx), asset_man)
            sb_free(psb)
            let mut pout: string = ssg_path_join(cfg.dist_dir, "blog/index.html")
            if pgn > 1:
                pout = ssg_path_join(cfg.dist_dir, "blog/page/" + str(pgn) + "/index.html")
            ssg_ensure_dir(ssg_path_dirname(pout), dir_cache)
            file_write(pout, phtml)
            if pgn == 1 and file_exists(ssg_path_join(cfg.dist_dir, "index.html")) == 0:
                file_write(ssg_path_join(cfg.dist_dir, "index.html"), phtml)
            total_bytes = total_bytes + string_length(phtml)
            pgn = pgn + 1

    // 7. Dynamic sitemap.xml, feed.xml (RSS 2.0), atom.xml, robots.txt, search-index.json & APIs
    // Stream one artifact at a time using a single reused StrBuf to keep peak RSS minimal.
    let total_items: int = len(items)
    let mut chap_api_count: int = 0
    let mut post_api_count: int = 0
    g_sb := sb_new_cap(4096)

    // 7a. sitemap.xml
    sb_append(g_sb, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n")
    let mut si: int = 0
    while si < total_items:
        arena:
            let mut end_si: int = si + 256
            if end_si > total_items: end_si = total_items
            while si < end_si:
                it := items[si]
                let mut prio: string = "0.8"
                if it.url == "/index.html" or it.url == "/": prio = "1.0"
                elif it.collection == "posts": prio = "0.9"
                sb_append(g_sb, "  <url><loc>" + ssg_escape_xml(cfg.base_url + it.url) + "</loc>")
                if string_length(it.date) > 0:
                    sb_append(g_sb, "<lastmod>" + ssg_escape_xml(it.date) + "</lastmod>")
                sb_append(g_sb, "<priority>" + prio + "</priority></url>\n")
                si = si + 1
    sb_append(g_sb, "</urlset>\n")
    sm_len := g_sb.len
    ssg_write_file_sb(ssg_path_join(cfg.dist_dir, "sitemap.xml"), g_sb)

    // 7b. feed.xml (RSS 2.0)
    g_sb.len = 0
    sb_append(g_sb, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<rss version=\"2.0\" xmlns:atom=\"http://www.w3.org/2005/Atom\">\n  <channel>\n")
    sb_append(g_sb, "    <title>" + ssg_escape_xml(cfg.site_name) + "</title>\n")
    sb_append(g_sb, "    <link>" + ssg_escape_xml(cfg.base_url) + "</link>\n")
    sb_append(g_sb, "    <description>" + ssg_escape_xml(cfg.site_tagline) + "</description>\n")
    sb_append(g_sb, "    <atom:link href=\"" + ssg_escape_xml(cfg.base_url) + "/feed.xml\" rel=\"self\" type=\"application/rss+xml\" />\n")
    si = 0
    while si < total_items:
        arena:
            let mut end_si: int = si + 256
            if end_si > total_items: end_si = total_items
            while si < end_si:
                it := items[si]
                if it.collection == "posts" or len(post_indices) == 0:
                    sb_append(g_sb, "    <item>\n      <title>" + ssg_escape_xml(it.title) + "</title>\n")
                    sb_append(g_sb, "      <link>" + ssg_escape_xml(cfg.base_url + it.url) + "</link>\n")
                    sb_append(g_sb, "      <description>" + ssg_escape_xml(it.description) + "</description>\n")
                    if string_length(it.date) > 0:
                        sb_append(g_sb, "      <pubDate>" + ssg_escape_xml(it.date) + "</pubDate>\n")
                    sb_append(g_sb, "    </item>\n")
                si = si + 1
    sb_append(g_sb, "  </channel>\n</rss>\n")
    fd_len := g_sb.len
    ssg_write_file_sb(ssg_path_join(cfg.dist_dir, "feed.xml"), g_sb)

    // 7c. atom.xml
    g_sb.len = 0
    sb_append(g_sb, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\">\n")
    sb_append(g_sb, "  <title>" + ssg_escape_xml(cfg.site_name) + "</title>\n")
    sb_append(g_sb, "  <id>" + ssg_escape_xml(cfg.base_url) + "/</id>\n")
    sb_append(g_sb, "  <link href=\"" + ssg_escape_xml(cfg.base_url) + "/atom.xml\" rel=\"self\" />\n")
    si = 0
    while si < total_items:
        arena:
            let mut end_si: int = si + 256
            if end_si > total_items: end_si = total_items
            while si < end_si:
                it := items[si]
                if it.collection == "posts" or len(post_indices) == 0:
                    full_u := cfg.base_url + it.url
                    sb_append(g_sb, "  <entry>\n    <title>" + ssg_escape_xml(it.title) + "</title>\n")
                    sb_append(g_sb, "    <id>" + ssg_escape_xml(full_u) + "</id>\n")
                    sb_append(g_sb, "    <link href=\"" + ssg_escape_xml(full_u) + "\" />\n")
                    sb_append(g_sb, "    <summary>" + ssg_escape_xml(it.description) + "</summary>\n  </entry>\n")
                si = si + 1
    sb_append(g_sb, "</feed>\n")
    at_len := g_sb.len
    ssg_write_file_sb(ssg_path_join(cfg.dist_dir, "atom.xml"), g_sb)

    // 7d. search-index.json
    g_sb.len = 0
    sb_append(g_sb, "[\n")
    si = 0
    while si < total_items:
        arena:
            let mut end_si: int = si + 256
            if end_si > total_items: end_si = total_items
            while si < end_si:
                it := items[si]
                if si > 0: sb_append(g_sb, ",\n")
                sb_append(g_sb, "  {\"title\": \"" + ssg_escape_json(it.title) + "\", \"url\": \"" + ssg_escape_json(it.url) + "\", \"desc\": \"" + ssg_escape_json(it.description) + "\", \"category\": \"" + ssg_escape_json(it.collection) + "\"}")
                si = si + 1
    sb_append(g_sb, "\n]\n")
    sr_len := g_sb.len
    ssg_write_file_sb(ssg_path_join(cfg.dist_dir, "search-index.json"), g_sb)

    // 7e. api/posts.json
    g_sb.len = 0
    sb_append(g_sb, "[\n")
    si = 0
    while si < total_items:
        arena:
            let mut end_si: int = si + 256
            if end_si > total_items: end_si = total_items
            while si < end_si:
                it := items[si]
                if it.collection == "posts":
                    if post_api_count > 0: sb_append(g_sb, ",\n")
                    sb_append(g_sb, "  {\"title\": \"" + ssg_escape_json(it.title) + "\", \"url\": \"" + ssg_escape_json(it.url) + "\", \"date\": \"" + ssg_escape_json(it.date) + "\", \"tags\": \"" + ssg_escape_json(it.tags) + "\"}")
                    post_api_count = post_api_count + 1
                si = si + 1
    sb_append(g_sb, "\n]\n")
    pa_len := g_sb.len
    ssg_write_file_sb(ssg_path_join(cfg.dist_dir, "api/posts.json"), g_sb)

    // 7f. api/chapters.json & per-chapter json
    g_sb.len = 0
    sb_append(g_sb, "[\n")
    si = 0
    while si < total_items:
        arena:
            let mut end_si: int = si + 256
            if end_si > total_items: end_si = total_items
            while si < end_si:
                it := items[si]
                cn := _builder_extract_chapter_num(it.slug)
                if cn > 0:
                    if chap_api_count > 0: sb_append(g_sb, ",\n")
                    sb_append(g_sb, "  {\"id\": " + str(cn) + ", \"slug\": \"" + ssg_escape_json(it.slug) + "\", \"title\": \"" + ssg_escape_json(it.title) + "\", \"url\": \"" + ssg_escape_json(it.url) + "\"}")
                    chap_api_count = chap_api_count + 1
                    ssg_write_file_raw(ssg_path_join(cfg.dist_dir, "api/" + it.slug + ".json"), "{\n  \"id\": " + str(cn) + ",\n  \"slug\": \"" + ssg_escape_json(it.slug) + "\",\n  \"title\": \"" + ssg_escape_json(it.title) + "\",\n  \"url\": \"" + ssg_escape_json(it.url) + "\"\n}\n")
                si = si + 1
    sb_append(g_sb, "\n]\n")
    ca_len := g_sb.len
    ssg_write_file_sb(ssg_path_join(cfg.dist_dir, "api/chapters.json"), g_sb)
    sb_free(g_sb)

    robots := "User-agent: *\nAllow: /\nSitemap: " + cfg.base_url + "/sitemap.xml\n"
    if file_exists(ssg_path_join(cfg.dist_dir, "robots.txt")) == 0:
        file_write(ssg_path_join(cfg.dist_dir, "robots.txt"), robots)

    site_api := "{\n  \"site_name\": \"" + ssg_escape_json(cfg.site_name) + "\",\n  \"tagline\": \"" + ssg_escape_json(cfg.site_tagline) + "\",\n  \"base_url\": \"" + ssg_escape_json(cfg.base_url) + "\",\n  \"pages\": " + str(pages_built) + ",\n  \"posts\": " + str(posts_built) + ",\n  \"total_chapters\": " + str(total_chapters) + ",\n  \"generator\": \"cluster-ssg\",\n  \"version\": \"2.0.0\"\n}\n"
    file_write(ssg_path_join(cfg.dist_dir, "api/index.json"), site_api)

    total_bytes = total_bytes + sm_len + fd_len + at_len + sr_len + pa_len + ca_len + string_length(site_api)

    t1 := ssg_clock_us()
    let mut ms: int = (t1 - t0) / 1000
    if ms <= 0: ms = 1

    return BuildReport(pages_built, posts_built, asset_man.files_copied, total_bins, ms, total_bytes, skipped_inc, len(schema_errors))

// Validate collection schemas + check internal links across built dist/
fn builder_check_site(cfg: SsgConfig) -> int:
    rep := builder_run_all(cfg)
    let mut errs: int = rep.schema_errors
    let mut html_exts: vector[string] = []
    html_exts.push(".html")
    scan := fs_walk_tree(cfg.dist_dir, html_exts)

    let mut i: int = 0
    while i < len(scan.abs_paths):
        ap := scan.abs_paths[i]
        html := file_read(ap)
        let mut pos: int = 0
        while 1 == 1:
            idx := ssg_find_from(html, "href=\"/", pos)
            if idx < 0:
                break
            end_q := ssg_find_from(html, "\"", idx + 7)
            if end_q < 0:
                break
            target := substring(html, idx + 6, end_q - (idx + 6))
            pos = end_q + 1
            if ssg_starts_with(target, "/_") == 1 or ssg_contains(target, "#") == 1:
                continue
            let mut fpath: string = ssg_path_join(cfg.dist_dir, target)
            if target == "/":
                fpath = ssg_path_join(cfg.dist_dir, "index.html")
            elif fs_is_dir(fpath) == 1:
                fpath = ssg_path_join(fpath, "index.html")
            if file_exists(fpath) == 0 and file_exists(fpath + ".html") == 0:
                println(ap + ": warning[SSG-LINK]: broken internal link -> " + target)
                errs = errs + 1
        i = i + 1
    return errs
