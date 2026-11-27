// ==============================================================================
// Module:      Document Models & Metric Pipeline (src/document.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Unified page representation combining .cld, Markdown (.md),
//              YAML/TOML frontmatter, TOC headings, word counts, and .clb wire format.
// ==============================================================================

import "std/cld.cl"
import "src/strbuf.cl"
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
    raw := file_read(abs_path)
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
fn ssg_resolve_permalink(template_str: string, doc: SsgRichDoc) -> string:
    let mut url: string = template_str
    if doc.fm.fields.has("permalink") == 1:
        url = doc.fm.fields["permalink"]
    elif doc.collection != "posts":
        // Preserve nested directory hierarchy for pages/docs/collections
        rel_dir := ssg_path_dirname(doc.rel_path)
        if string_length(rel_dir) > 0:
            return "/" + rel_dir + "/" + doc.slug + ".html"
        return "/" + doc.slug + ".html"

    let mut yr: string = "2026"
    let mut mo: string = "01"
    let mut dy: string = "01"
    if string_length(doc.date) >= 10:
        dparts := ssg_split(doc.date, "-")
        if len(dparts) >= 3:
            yr = dparts[0]
            mo = dparts[1]
            dy = dparts[2]

    url = ssg_replace_all(url, ":year", yr)
    url = ssg_replace_all(url, ":month", mo)
    url = ssg_replace_all(url, ":day", dy)
    url = ssg_replace_all(url, ":slug", doc.slug)
    url = ssg_replace_all(url, ":title", doc.slug)
    url = ssg_replace_all(url, ":collection", doc.collection)
    if string_length(doc.categories) > 0:
        c0 := ssg_slugify(ssg_split(doc.categories, ",")[0])
        url = ssg_replace_all(url, ":categories", c0)
    else:
        url = ssg_replace_all(url, "/:categories", "")
    if ssg_starts_with(url, "/") == 0:
        url = "/" + url
    return url

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
