// ==============================================================================
// Module:      Document Models & Metric Pipeline (src/document.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Unified page representation combining .cld, Markdown (.md),
//              YAML/TOML frontmatter, TOC headings, word counts, and .clb wire format.
// ==============================================================================

import "std/cld.cl"
import "src/strbuf.cl"
import "src/fs_walk.cl"
import "src/frontmatter.cl"
import "src/markdown.cl"

model SsgDocMeta:
    title: string
    author: string
    date: string
    layout: string
    tags: string
    slug: string
    description: string
    reading_time_min: int

model SsgDocument:
    cld: CldDoc
    source_path: string
    out_rel_path: string
    html_body: string
    compiled_page: string
    is_binary: int

model SsgPageSource:
    abs_path: string
    rel_path: string
    collection: string
    permalink_url: string
    out_file_path: string
    is_clx: int

model SsgPageHeader:
    source: SsgPageSource
    fm_fields: dict[string, string]
    title: string
    author: string
    date: string
    layout: string
    tags: string
    categories: string
    slug: string
    description: string
    lang: string
    plain_excerpt: string
    reading_time_min: int
    is_draft: int

model SsgRichDoc:
    abs_path: string
    rel_path: string
    collection: string
    fm: FrontmatterData
    md: MarkdownResult
    title: string
    author: string
    date: string
    layout: string
    tags: string
    categories: string
    slug: string
    description: string
    permalink_url: string
    out_file_path: string
    lang: string
    is_draft: int
    reading_time_min: int

fn ssg_estimate_reading_time(word_count: int) -> int:
    if word_count < 200:
        return 1
    return (word_count / 200) + 1

fn _doc_scan_body_fast(raw: string, body_off: int, &first_h1: string, &excerpt_out: string, &words_out: int) -> void:
    first_h1 = ""
    excerpt_out = ""
    words_out = 0
    rlen := string_length(raw)
    if body_off >= rlen:
        return
    let mut in_word: int = 0
    let mut i: int = body_off
    ex_sb := sb_new_cap(192)
    let mut ex_len: int = 0
    let mut at_line_start: int = 1
    let mut in_code: int = 0
    while i < rlen:
        b := byte_at(raw, i)
        if b == 32 or b == 9 or b == 10 or b == 13:
            in_word = 0
            if b == 10:
                at_line_start = 1
                if ex_len > 0 and ex_len < 150:
                    sb_append_byte(ex_sb, 32)
                    ex_len = ex_len + 1
        else:
            if at_line_start == 1:
                if i + 2 < rlen and b == 96 and byte_at(raw, i + 1) == 96 and byte_at(raw, i + 2) == 96:
                    if in_code == 0: in_code = 1
                    else: in_code = 0
                elif in_code == 0 and string_length(first_h1) == 0 and b == 35 and i + 1 < rlen and byte_at(raw, i + 1) == 32:
                    eol := ssg_find_from(raw, "\n", i + 2)
                    if eol < 0: eol = rlen
                    first_h1 = ssg_trim(substring(raw, i + 2, eol - (i + 2)))
            at_line_start = 0
            if in_word == 0:
                words_out = words_out + 1
                in_word = 1
            if in_code == 0 and ex_len < 155 and b != 35 and b != 42 and b != 96:
                sb_append_byte(ex_sb, b)
                ex_len = ex_len + 1
        i = i + 1
    excerpt_out = ssg_trim(sb_to_str(ex_sb))
    sb_free(ex_sb)

fn ssg_scan_page_header(abs_path: string, rel_path: string, collection: string, permalink_tmpl: string, dist_dir: string) -> SsgPageHeader:
    raw := ssg_read_file_arena(abs_path)
    // Scan only YAML/TOML/CLD frontmatter header slice (avoid rendering full Markdown AST in Stage 1)
    rlen := string_length(raw)
    let mut header_raw: string = ""
    let mut body_off: int = 0
    if ssg_starts_with(raw, "---\n") == 1 or ssg_starts_with(raw, "---\r\n") == 1:
        end_m := ssg_find_from(raw, "\n---", 3)
        if end_m > 0:
            eol := ssg_find_from(raw, "\n", end_m + 1)
            if eol < 0: eol = rlen
            header_raw = substring(raw, 0, eol)
            body_off = eol + 1
    elif ssg_starts_with(raw, "+++\n") == 1 or ssg_starts_with(raw, "+++\r\n") == 1:
        end_m := ssg_find_from(raw, "\n+++", 3)
        if end_m > 0:
            eol := ssg_find_from(raw, "\n", end_m + 1)
            if eol < 0: eol = rlen
            header_raw = substring(raw, 0, eol)
            body_off = eol + 1
    else:
        eq_m := ssg_find_from(raw, "\n===", 0)
        if eq_m > 0 and eq_m < 2048:
            eol := ssg_find_from(raw, "\n", eq_m + 1)
            if eol < 0: eol = rlen
            header_raw = substring(raw, 0, eol)
            body_off = eol + 1

    fm := fm_parse_document(header_raw)
    let mut first_h1: string = ""
    let mut excerpt: string = ""
    let mut wc: int = 0
    _doc_scan_body_fast(raw, body_off, first_h1, excerpt, wc)

    stem := ssg_path_stem(rel_path)
    let mut file_date: string = ""
    let mut file_slug: string = stem
    fm_extract_date_from_stem(stem, file_date, file_slug)

    let mut title: string = _doc_get_meta(fm, "title", "")
    if string_length(title) == 0:
        if string_length(first_h1) > 0: title = first_h1
        else: title = file_slug
    author := _doc_get_meta(fm, "author", "")
    date := _doc_get_meta(fm, "date", file_date)
    let mut def_layout: string = "default"
    if collection == "posts": def_layout = "post"
    layout := _doc_get_meta(fm, "layout", def_layout)
    tags := _doc_get_meta(fm, "tags", "")
    cats := _doc_get_meta(fm, "categories", "")
    slug := ssg_slugify(_doc_get_meta(fm, "slug", file_slug))
    desc := _doc_get_meta(fm, "description", excerpt)
    let mut is_draft: int = 0
    if ssg_lower(_doc_get_meta(fm, "draft", "false")) == "true" or ssg_lower(_doc_get_meta(fm, "published", "true")) == "false":
        is_draft = 1
    let mut lang: string = _doc_get_meta(fm, "lang", "")
    if string_length(lang) == 0:
        slash := ssg_find_from(rel_path, "/", 0)
        if slash == 2: lang = substring(rel_path, 0, 2)

    let mut perm_override: string = ""
    if fm.fields.has("permalink") == 1:
        perm_override = fm.fields["permalink"]
    let mut url: string = ""
    if collection != "pages" and collection != "posts":
        url = "/" + collection + "/" + slug + ".html"
    else:
        url = _doc_resolve_permalink_parts(permalink_tmpl, perm_override, date, slug, collection, cats, rel_path)
    outp := ssg_url_to_dist_path(dist_dir, url)
    dict_free(fm.list_keys)
    return SsgPageHeader(SsgPageSource(abs_path, rel_path, collection, url, outp, 0), fm.fields, title, author, date, layout, tags, cats, slug, desc, lang, excerpt, ssg_estimate_reading_time(wc), is_draft)

fn ssg_count_words(text: string) -> int:
    tlen := string_length(text)
    if tlen == 0:
        return 0
    let mut words: int = 0
    let mut in_word: int = 0
    let mut i: int = 0
    while i < tlen:
        b := byte_at(text, i)
        if b == 32 or b == 9 or b == 10 or b == 13:
            in_word = 0
        else:
            if in_word == 0:
                words = words + 1
                in_word = 1
        i = i + 1
    return words

fn _doc_get_meta(fm: FrontmatterData, k: string, fallback: string) -> string:
    if fm.fields.has(k) == 1:
        v := fm.fields[k]
        if string_length(v) > 0:
            return v
    return fallback

fn ssg_parse_rich_doc(abs_path: string, rel_path: string, collection: string) -> SsgRichDoc:
    raw := ssg_read_file_arena(abs_path)
    fm := fm_parse_document(raw)
    md := md_parse_and_render(fm.body)

    stem := ssg_path_stem(rel_path)
    let mut file_date: string = ""
    let mut file_slug: string = stem
    fm_extract_date_from_stem(stem, file_date, file_slug)

    let mut title: string = _doc_get_meta(fm, "title", "")
    if string_length(title) == 0:
        if len(md.toc) > 0:
            title = md.toc[0].text
        else:
            title = file_slug
    author := _doc_get_meta(fm, "author", "")
    date := _doc_get_meta(fm, "date", file_date)
    let mut def_layout: string = "default"
    if collection == "posts":
        def_layout = "post"
    layout := _doc_get_meta(fm, "layout", def_layout)
    tags := _doc_get_meta(fm, "tags", "")
    cats := _doc_get_meta(fm, "categories", "")
    slug := ssg_slugify(_doc_get_meta(fm, "slug", file_slug))
    desc := _doc_get_meta(fm, "description", md.plain_excerpt)

    let mut is_draft: int = 0
    if ssg_lower(_doc_get_meta(fm, "draft", "false")) == "true" or ssg_lower(_doc_get_meta(fm, "published", "true")) == "false":
        is_draft = 1

    let mut lang: string = _doc_get_meta(fm, "lang", "")
    // Auto-detect i18n folder prefix e.g. en/docs.md, es/docs.md, ar/docs.md
    if string_length(lang) == 0:
        slash := ssg_find_from(rel_path, "/", 0)
        if slash == 2:
            lang = substring(rel_path, 0, 2)

    rt := ssg_estimate_reading_time(md.word_count)
    return SsgRichDoc(abs_path, rel_path, collection, fm, md, title, author, date, layout, tags, cats, slug, desc, "", "", lang, is_draft, rt)

// Resolve Hugo/Jekyll permalink template e.g. /:year/:month/:slug/ or /:collection/:slug.html
fn _doc_resolve_permalink_parts(template_str: string, perm_override: string, date_str: string, slug_str: string, col_str: string, cats_str: string, rel_path: string) -> string:
    let mut url: string = template_str
    if string_length(perm_override) > 0:
        url = perm_override
    elif col_str != "posts":
        rel_dir := ssg_path_dirname(rel_path)
        if string_length(rel_dir) > 0:
            return "/" + rel_dir + "/" + slug_str + ".html"
        return "/" + slug_str + ".html"

    let mut yr: string = "2026"
    let mut mo: string = "01"
    let mut dy: string = "01"
    if string_length(date_str) >= 10 and byte_at(date_str, 4) == 45 and byte_at(date_str, 7) == 45:
        yr = substring(date_str, 0, 4)
        mo = substring(date_str, 5, 2)
        dy = substring(date_str, 8, 2)
    elif string_length(date_str) >= 10:
        dparts := ssg_split(date_str, "-")
        if len(dparts) >= 3:
            yr = dparts[0]
            mo = dparts[1]
            dy = dparts[2]

    url = ssg_replace_all(url, ":year", yr)
    url = ssg_replace_all(url, ":month", mo)
    url = ssg_replace_all(url, ":day", dy)
    url = ssg_replace_all(url, ":slug", slug_str)
    url = ssg_replace_all(url, ":title", slug_str)
    url = ssg_replace_all(url, ":collection", col_str)
    if string_length(cats_str) > 0:
        c_comma := ssg_find_from(cats_str, ",", 0)
        let mut c_first: string = cats_str
        if c_comma >= 0:
            c_first = substring(cats_str, 0, c_comma)
        c0 := ssg_slugify(c_first)
        url = ssg_replace_all(url, ":categories", c0)
    else:
        url = ssg_replace_all(url, "/:categories", "")
    if ssg_starts_with(url, "/") == 0:
        url = "/" + url
    return url

fn ssg_resolve_permalink(template_str: string, doc: SsgRichDoc) -> string:
    let mut perm_override: string = ""
    if doc.fm.fields.has("permalink") == 1:
        perm_override = doc.fm.fields["permalink"]
    return _doc_resolve_permalink_parts(template_str, perm_override, doc.date, doc.slug, doc.collection, doc.categories, doc.rel_path)

// URL -> filesystem path inside dist/
fn ssg_url_to_dist_path(dist_dir: string, url: string) -> string:
    if url == "/" or url == "":
        return ssg_path_join(dist_dir, "index.html")
    let mut rel: string = url
    if ssg_starts_with(rel, "/") == 1:
        rel = substring(rel, 1, string_length(rel) - 1)
    if ssg_ends_with(rel, "/") == 1:
        return ssg_path_join(dist_dir, rel + "index.html")
    if ssg_ends_with(rel, ".html") == 0 and ssg_ends_with(rel, ".json") == 0 and ssg_ends_with(rel, ".xml") == 0:
        return ssg_path_join(dist_dir, rel + "/index.html")
    return ssg_path_join(dist_dir, rel)

// Legacy compatibility API for test_ssg.cl
fn ssg_load_cld(filepath: string, rel_out: string) -> SsgDocument:
    base_cld := cld_parse_file(filepath)
    body_html := cld_render_blocks(base_cld)
    return SsgDocument(base_cld, filepath, rel_out, body_html, "", 0)

fn ssg_doc_to_binary(doc: SsgDocument) -> string:
    return cld_pack(doc.cld)

fn ssg_doc_from_binary(raw_bytes: string, filepath: string, rel_out: string) -> SsgDocument:
    base_cld := cld_unpack(raw_bytes)
    body_html := cld_render_blocks(base_cld)
    return SsgDocument(base_cld, filepath, rel_out, body_html, "", 1)

fn ssg_rich_to_binary(doc: SsgRichDoc) -> string:
    sb := sb_new_cap(512)
    sb_append(sb, "CLD/2.0\n")
    sb_append(sb, "TITLE\t" + ssg_escape_json(doc.title) + "\n")
    sb_append(sb, "AUTHOR\t" + ssg_escape_json(doc.author) + "\n")
    sb_append(sb, "DATE\t" + ssg_escape_json(doc.date) + "\n")
    sb_append(sb, "SLUG\t" + ssg_escape_json(doc.slug) + "\n")
    sb_append(sb, "TAGS\t" + ssg_escape_json(doc.tags) + "\n")
    sb_append(sb, "HTML_LEN\t" + str(string_length(doc.md.html)) + "\n")
    sb_append(sb, "BODY\n")
    sb_append(sb, doc.md.html)
    out := sb_to_str(sb)
    sb_free(sb)
    return out
