// ==============================================================================
// Module:      CommonMark + GFM + .cld Hybrid Parser & Syntax Highlighter (src/markdown.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Spec-compliant block & inline rendering backed by O(N) StrBuf,
//              ATX/Setext headings with slug IDs & TOC extraction, nested lists
//              (ul/ol/task), GFM aligned tables, footnotes, pure-.cl syntax
//              highlighting, .cld directives (callout/tabs/sheet/video), and islands.
// ==============================================================================

import "src/strbuf.cl"

model TocEntry:
    level: int
    id: string
    text: string

model IslandTag:
    name: string
    directive: string
    props: string
    fallback: string

model ClxTagCall:
    name: string
    props: string
    inner_html: string
    placeholder_id: string

model MarkdownResult:
    html: string
    toc: vector[TocEntry]
    islands: vector[IslandTag]
    clx_calls: vector[ClxTagCall]
    word_count: int
    plain_excerpt: string

// ------------------------------------------------------------------------------
// Pure-.cl Lexical Code Highlighter
// ------------------------------------------------------------------------------

fn _hl_is_ident_char(b: int) -> int:
    if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57) or b == 95:
        return 1
    return 0

fn _hl_is_keyword(lang: string, word: string) -> int:
    if word == "fn" or word == "let" or word == "mut" or word == "if" or word == "elif" or word == "else" or word == "while" or word == "for" or word == "in" or word == "return" or word == "break" or word == "continue" or word == "import" or word == "model" or word == "struct" or word == "enum" or word == "match" or word == "spawn" or word == "arena" or word == "gpu" or word == "comptime" or word == "pub" or word == "use" or word == "mod" or word == "impl" or word == "trait" or word == "def" or word == "class" or word == "async" or word == "await" or word == "function" or word == "const" or word == "var" or word == "export" or word == "from" or word == "true" or word == "false" or word == "null" or word == "none" or word == "and" or word == "or" or word == "not" or word == "SELECT" or word == "FROM" or word == "WHERE" or word == "INSERT" or word == "CREATE" or word == "TABLE":
        return 1
    return 0

fn _hl_is_type(word: string) -> int:
    if word == "int" or word == "float" or word == "string" or word == "bool" or word == "void" or word == "ptr" or word == "vector" or word == "dict" or word == "tensor" or word == "i32" or word == "i64" or word == "u8" or word == "u32" or word == "u64" or word == "f32" or word == "f64" or word == "usize" or word == "String" or word == "Vec" or word == "Option" or word == "Result" or word == "Channel" or word == "StrBuf":
        return 1
    return 0

fn md_highlight_code(code: string, lang_raw: string) -> string:
    lang := ssg_lower(ssg_trim(lang_raw))
    if lang == "txt" or lang == "text" or lang == "plaintext":
        return ssg_escape_html(code)
    clen := string_length(code)
    if clen == 0:
        return ""
    sb := sb_new_cap(clen * 2 + 32)
    let mut i: int = 0
    while i < clen:
        b := byte_at(code, i)
        // Line comment // or # (for py/sh/yaml/toml)
        if b == 47 and i + 1 < clen and byte_at(code, i + 1) == 47:
            let mut end_c: int = i
            while end_c < clen and byte_at(code, end_c) != 10:
                end_c = end_c + 1
            sb_append(sb, "<span class=\"hl-cm\">")
            sb_append(sb, ssg_escape_html(substring(code, i, end_c - i)))
            sb_append(sb, "</span>")
            i = end_c
            continue
        if b == 35 and (lang == "py" or lang == "python" or lang == "sh" or lang == "bash" or lang == "yaml" or lang == "yml" or lang == "toml"):
            let mut end_c: int = i
            while end_c < clen and byte_at(code, end_c) != 10:
                end_c = end_c + 1
            sb_append(sb, "<span class=\"hl-cm\">")
            sb_append(sb, ssg_escape_html(substring(code, i, end_c - i)))
            sb_append(sb, "</span>")
            i = end_c
            continue
        // String literal "..." or '...'
        if b == 34 or b == 39:
            q := b
            let mut end_s: int = i + 1
            while end_s < clen:
                sb_c := byte_at(code, end_s)
                if sb_c == 92 and end_s + 1 < clen:
                    end_s = end_s + 2
                    continue
                if sb_c == q or sb_c == 10:
                    if sb_c == q:
                        end_s = end_s + 1
                    break
                end_s = end_s + 1
            sb_append(sb, "<span class=\"hl-str\">")
            sb_append(sb, ssg_escape_html(substring(code, i, end_s - i)))
            sb_append(sb, "</span>")
            i = end_s
            continue
        // Numeric literal
        if b >= 48 and b <= 57 and (i == 0 or _hl_is_ident_char(byte_at(code, i - 1)) == 0):
            let mut end_n: int = i + 1
            while end_n < clen:
                nb := byte_at(code, end_n)
                if (nb >= 48 and nb <= 57) or (nb >= 65 and nb <= 70) or (nb >= 97 and nb <= 102) or nb == 120 or nb == 88 or nb == 46 or nb == 95:
                    end_n = end_n + 1
                else:
                    break
            sb_append(sb, "<span class=\"hl-num\">")
            sb_append(sb, ssg_escape_html(substring(code, i, end_n - i)))
            sb_append(sb, "</span>")
            i = end_n
            continue
        // Identifier / keyword / type
        if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95:
            let mut end_id: int = i + 1
            while end_id < clen and _hl_is_ident_char(byte_at(code, end_id)) == 1:
                end_id = end_id + 1
            word := substring(code, i, end_id - i)
            if _hl_is_keyword(lang, word) == 1:
                sb_append(sb, "<span class=\"hl-kw\">")
                sb_append(sb, ssg_escape_html(word))
                sb_append(sb, "</span>")
            elif _hl_is_type(word) == 1:
                sb_append(sb, "<span class=\"hl-type\">")
                sb_append(sb, ssg_escape_html(word))
                sb_append(sb, "</span>")
            else:
                sb_append(sb, ssg_escape_html(word))
            i = end_id
            continue

        // HTML escape single byte
        if b == 38: sb_append(sb, "&amp;")
        elif b == 60: sb_append(sb, "&lt;")
        elif b == 62: sb_append(sb, "&gt;")
        else: sb_append_byte(sb, b)
        i = i + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

// ------------------------------------------------------------------------------
// Attribute Parser Helper for <island ... /> & <Component ... />
// ------------------------------------------------------------------------------

fn md_extract_attr(tag_src: string, attr_name: string) -> string:
    tlen := string_length(tag_src)
    let mut pos: int = 0
    while pos < tlen:
        idx := ssg_find_from(tag_src, attr_name + "=", pos)
        if idx < 0:
            return ""
        if idx > 0:
            prev := byte_at(tag_src, idx - 1)
            if prev != 32 and prev != 9 and prev != 10:
                pos = idx + 1
                continue
        val_start := idx + string_length(attr_name) + 1
        if val_start >= tlen:
            return ""
        q := byte_at(tag_src, val_start)
        if q == 34 or q == 39:
            let mut end_q: int = val_start + 1
            while end_q < tlen and byte_at(tag_src, end_q) != q:
                end_q = end_q + 1
            return substring(tag_src, val_start + 1, end_q - val_start - 1)
        elif q == 123:
            let mut end_b: int = val_start + 1
            while end_b < tlen and byte_at(tag_src, end_b) != 125:
                end_b = end_b + 1
            return substring(tag_src, val_start, end_b - val_start + 1)
        else:
            let mut end_sp: int = val_start
            while end_sp < tlen and byte_at(tag_src, end_sp) != 32 and byte_at(tag_src, end_sp) != 62 and byte_at(tag_src, end_sp) != 47:
                end_sp = end_sp + 1
            return substring(tag_src, val_start, end_sp - val_start)
    return ""

// ------------------------------------------------------------------------------
// Spec-Compliant Inline Formatter
// ------------------------------------------------------------------------------

fn md_render_inline(raw: string) -> string:
    rlen := string_length(raw)
    if rlen == 0:
        return ""
    sb := sb_new_cap(rlen + 32)
    let mut i: int = 0
    while i < rlen:
        b := byte_at(raw, i)

        // Backslash escape \* \[ \` etc.
        if b == 92 and i + 1 < rlen:
            nb := byte_at(raw, i + 1)
            if nb == 42 or nb == 95 or nb == 96 or nb == 91 or nb == 93 or nb == 92 or nb == 126 or nb == 35 or nb == 62:
                sb_append_byte(sb, nb)
                i = i + 2
                continue

        // Inline code `...`
        if b == 96:
            end_bt := ssg_find_from(raw, "`", i + 1)
            if end_bt > i:
                sb_append(sb, "<code>")
                sb_append(sb, ssg_escape_html(substring(raw, i + 1, end_bt - i - 1)))
                sb_append(sb, "</code>")
                i = end_bt + 1
                continue

        // Raw HTML / inline tags passthrough (<span, <a, <strong, <em, <br, <img, </...)
        if b == 60:
            // Autolink <https://...> or <http://...>
            if ssg_starts_with(substring(raw, i, rlen - i), "<http://") == 1 or ssg_starts_with(substring(raw, i, rlen - i), "<https://") == 1:
                gt := ssg_find_from(raw, ">", i + 1)
                if gt > i:
                    url := substring(raw, i + 1, gt - i - 1)
                    sb_append(sb, "<a href=\"" + ssg_escape_html(url) + "\">" + ssg_escape_html(url) + "</a>")
                    i = gt + 1
                    continue
            // Preserved inline HTML tag
            gt := ssg_find_from(raw, ">", i + 1)
            if gt > i and gt - i < 512:
                next_ch := byte_at(raw, i + 1)
                if (next_ch >= 97 and next_ch <= 122) or (next_ch >= 65 and next_ch <= 90) or next_ch == 47 or next_ch == 33:
                    sb_append_slice(sb, raw, i, gt - i + 1)
                    i = gt + 1
                    continue

        // Image ![alt](url "title")
        if b == 33 and i + 1 < rlen and byte_at(raw, i + 1) == 91:
            cb := ssg_find_from(raw, "]", i + 2)
            if cb > i + 1 and cb + 1 < rlen and byte_at(raw, cb + 1) == 40:
                cp := ssg_find_from(raw, ")", cb + 2)
                if cp > cb + 1:
                    alt := substring(raw, i + 2, cb - i - 2)
                    dest := ssg_trim(substring(raw, cb + 2, cp - cb - 2))
                    let mut img_url: string = dest
                    let mut img_title: string = ""
                    q1 := ssg_find_from(dest, "\"", 0)
                    if q1 > 0:
                        img_url = ssg_trim(substring(dest, 0, q1))
                        q2 := ssg_find_from(dest, "\"", q1 + 1)
                        if q2 > q1:
                            img_title = substring(dest, q1 + 1, q2 - q1 - 1)
                    sb_append(sb, "<img src=\"" + ssg_escape_html(img_url) + "\" alt=\"" + ssg_escape_html(alt) + "\" loading=\"lazy\"")
                    if string_length(img_title) > 0:
                        sb_append(sb, " title=\"" + ssg_escape_html(img_title) + "\"")
                    sb_append(sb, " />")
                    i = cp + 1
                    continue

        // Link [text](url) or footnote ref [^id]
        if b == 91:
            if i + 1 < rlen and byte_at(raw, i + 1) == 94:
                cb_fn := ssg_find_from(raw, "]", i + 2)
                if cb_fn > i + 2:
                    fn_id := substring(raw, i + 2, cb_fn - i - 2)
                    sb_append(sb, "<sup id=\"fnref-" + ssg_slugify(fn_id) + "\"><a href=\"#fn-" + ssg_slugify(fn_id) + "\" class=\"footnote-ref\">" + ssg_escape_html(fn_id) + "</a></sup>")
                    i = cb_fn + 1
                    continue
            cb := ssg_find_from(raw, "]", i + 1)
            if cb > i and cb + 1 < rlen and byte_at(raw, cb + 1) == 40:
                cp := ssg_find_from(raw, ")", cb + 2)
                if cp > cb + 1:
                    ltext := substring(raw, i + 1, cb - i - 1)
                    dest := ssg_trim(substring(raw, cb + 2, cp - cb - 2))
                    let mut lurl: string = dest
                    let mut ltitle: string = ""
                    q1 := ssg_find_from(dest, "\"", 0)
                    if q1 > 0:
                        lurl = ssg_trim(substring(dest, 0, q1))
                        q2 := ssg_find_from(dest, "\"", q1 + 1)
                        if q2 > q1:
                            ltitle = substring(dest, q1 + 1, q2 - q1 - 1)
                    sb_append(sb, "<a href=\"" + ssg_escape_html(lurl) + "\"")
                    if string_length(ltitle) > 0:
                        sb_append(sb, " title=\"" + ssg_escape_html(ltitle) + "\"")
                    sb_append(sb, ">" + md_render_inline(ltext) + "</a>")
                    i = cp + 1
                    continue

        // Strikethrough ~~...~~
        if b == 126 and i + 1 < rlen and byte_at(raw, i + 1) == 126:
            end_st := ssg_find_from(raw, "~~", i + 2)
            if end_st > i + 2:
                sb_append(sb, "<del>" + md_render_inline(substring(raw, i + 2, end_st - i - 2)) + "</del>")
                i = end_st + 2
                continue

        // Bold+Italic ***...***
        if b == 42 and i + 2 < rlen and byte_at(raw, i + 1) == 42 and byte_at(raw, i + 2) == 42:
            end_bi := ssg_find_from(raw, "***", i + 3)
            if end_bi > i + 3:
                sb_append(sb, "<strong><em>" + md_render_inline(substring(raw, i + 3, end_bi - i - 3)) + "</em></strong>")
                i = end_bi + 3
                continue

        // Bold **...** or __...__
        if (b == 42 and i + 1 < rlen and byte_at(raw, i + 1) == 42) or (b == 95 and i + 1 < rlen and byte_at(raw, i + 1) == 95):
            marker := substring(raw, i, 2)
            end_b := ssg_find_from(raw, marker, i + 2)
            if end_b > i + 2:
                sb_append(sb, "<strong>" + md_render_inline(substring(raw, i + 2, end_b - i - 2)) + "</strong>")
                i = end_b + 2
                continue

        // Italic *...*
        if b == 42:
            end_it := ssg_find_from(raw, "*", i + 1)
            if end_it > i + 1:
                inner_em := substring(raw, i + 1, end_it - i - 1)
                if ssg_starts_with(inner_em, " ") == 0 and ssg_ends_with(inner_em, " ") == 0:
                    sb_append(sb, "<em>" + md_render_inline(inner_em) + "</em>")
                    i = end_it + 1
                    continue

        if b == 38:
            // Preserve pre-escaped HTML entities like &amp; &middot; &rarr;
            semi := ssg_find_from(raw, ";", i + 1)
            if semi > i + 1 and semi - i <= 10:
                sb_append_byte(sb, b)
            else:
                sb_append(sb, "&amp;")
        elif b == 60:
            sb_append(sb, "&lt;")
        elif b == 62:
            sb_append(sb, "&gt;")
        else:
            sb_append_byte(sb, b)
        i = i + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

// ------------------------------------------------------------------------------
// Table & Helper Parsing
// ------------------------------------------------------------------------------

fn _md_split_table_row(ln: string) -> vector[string]:
    t := ssg_trim(ln)
    if ssg_starts_with(t, "|") == 1:
        t = substring(t, 1, string_length(t) - 1)
    if ssg_ends_with(t, "|") == 1 and string_length(t) > 0:
        t = substring(t, 0, string_length(t) - 1)
    raw_cells := ssg_split(t, "|")
    let mut out: vector[string] = []
    let mut i: int = 0
    while i < len(raw_cells):
        out.push(ssg_trim(raw_cells[i]))
        i = i + 1
    return out

fn _md_is_table_sep(ln: string) -> int:
    t := ssg_trim(ln)
    if ssg_contains(t, "-") == 0:
        return 0
    if ssg_contains(t, "|") == 0:
        return 0
    cells := _md_split_table_row(t)
    if len(cells) == 0:
        return 0
    let mut i: int = 0
    while i < len(cells):
        c := cells[i]
        if string_length(c) == 0:
            i = i + 1
            continue
        let mut j: int = 0
        let mut dashes: int = 0
        while j < string_length(c):
            ch := byte_at(c, j)
            if ch == 45:
                dashes = dashes + 1
            elif ch != 58 and ch != 32:
                return 0
            j = j + 1
        if dashes == 0:
            return 0
        i = i + 1
    return 1

fn _md_parse_table_aligns(sep_ln: string) -> vector[string]:
    cells := _md_split_table_row(sep_ln)
    let mut aligns: vector[string] = []
    let mut i: int = 0
    while i < len(cells):
        c := ssg_trim(cells[i])
        lc := ssg_starts_with(c, ":")
        rc := ssg_ends_with(c, ":")
        if lc == 1 and rc == 1:
            aligns.push(" style=\"text-align:center\"")
        elif rc == 1:
            aligns.push(" style=\"text-align:right\"")
        elif lc == 1:
            aligns.push(" style=\"text-align:left\"")
        else:
            aligns.push("")
        i = i + 1
    return aligns

fn _md_count_list_depth(raw: string) -> int:
    n := string_length(raw)
    let mut sp: int = 0
    let mut i: int = 0
    while i < n:
        b := byte_at(raw, i)
        if b == 32: sp = sp + 1
        elif b == 9: sp = sp + 2
        else: break
        i = i + 1
    return sp / 2

fn _md_is_ol_prefix(t: string, &body_out: string) -> int:
    tlen := string_length(t)
    let mut i: int = 0
    while i < tlen and byte_at(t, i) >= 48 and byte_at(t, i) <= 57:
        i = i + 1
    if i > 0 and i + 1 < tlen and (byte_at(t, i) == 46 or byte_at(t, i) == 41) and byte_at(t, i + 1) == 32:
        body_out = ssg_trim(substring(t, i + 2, tlen - i - 2))
        return 1
    return 0

// ------------------------------------------------------------------------------
// Main Block & Directive Parser
// ------------------------------------------------------------------------------

fn _md_count_words_inline(s: string) -> int:
    n := string_length(s)
    if n == 0:
        return 0
    let mut cnt: int = 0
    let mut in_w: int = 0
    let mut k: int = 0
    while k < n:
        c := byte_at(s, k)
        if c == 32 or c == 9 or c == 10 or c == 13:
            in_w = 0
        else:
            if in_w == 0:
                cnt = cnt + 1
                in_w = 1
        k = k + 1
    return cnt

fn md_parse_and_render(body: string) -> MarkdownResult:
    lines := ssg_split_lines(body)
    n := len(lines)
    sb := sb_new_cap(string_length(body) * 2 + 256)
    let mut toc: vector[TocEntry] = []
    let mut islands: vector[IslandTag] = []
    let mut clx_calls: vector[ClxTagCall] = []
    let mut footnotes_ids: vector[string] = []
    let mut footnotes_html: vector[string] = []
    let mut word_count: int = 0
    plain_sb := sb_new_cap(512)

    let mut i: int = 0
    while i < n:
        raw := lines[i]
        t := ssg_trim(raw)

        if string_length(t) == 0:
            i = i + 1
            continue

        // 1. Footnote definitions: [^id]: text
        if ssg_starts_with(t, "[^") == 1:
            cb_fn := ssg_find_from(t, "]:", 2)
            if cb_fn > 2:
                fid := substring(t, 2, cb_fn - 2)
                ftxt := ssg_trim(substring(t, cb_fn + 2, string_length(t) - cb_fn - 2))
                footnotes_ids.push(fid)
                footnotes_html.push(md_render_inline(ftxt))
                i = i + 1
                continue

        // 2. Native <island ... />
        if ssg_starts_with(t, "<island ") == 1 or ssg_starts_with(t, "<island\t") == 1:
            let mut tag_full: string = t
            while ssg_contains(tag_full, ">") == 0 and i + 1 < n:
                i = i + 1
                tag_full = tag_full + " " + ssg_trim(lines[i])
            iname := md_extract_attr(tag_full, "name")
            let mut dir_val: string = "zero-js"
            if ssg_contains(tag_full, "client:load") == 1: dir_val = "load"
            elif ssg_contains(tag_full, "client:idle") == 1: dir_val = "idle"
            elif ssg_contains(tag_full, "client:visible") == 1: dir_val = "visible"
            elif ssg_contains(tag_full, "client:only") == 1: dir_val = "only"
            elif ssg_contains(tag_full, "client:media") == 1:
                mval := md_extract_attr(tag_full, "client:media")
                dir_val = "media:" + mval
            islands.push(IslandTag(iname, dir_val, tag_full, ""))
            isl_id := "island-" + ssg_slugify(iname) + "-" + str(len(islands))
            sb_append(sb, "<div class=\"cluster-island-placeholder\" id=\"" + isl_id + "\" data-island=\"" + ssg_escape_html(iname) + "\" data-directive=\"" + ssg_escape_html(dir_val) + "\">\n  <span>[Interactive Island: " + ssg_escape_html(iname) + "]</span>\n</div>\n")
            i = i + 1
            continue

        // 3. Astro-style <ComponentName ... /> or <ComponentName ...>...</ComponentName>
        if string_length(t) >= 3 and byte_at(t, 0) == 60 and byte_at(t, 1) >= 65 and byte_at(t, 1) <= 90:
            // Extract PascalCase tag name
            let mut sp: int = 1
            while sp < string_length(t):
                ch := byte_at(t, sp)
                if ch == 32 or ch == 47 or ch == 62:
                    break
                sp = sp + 1
            cname := substring(t, 1, sp - 1)
            let mut tag_hdr: string = t
            while ssg_contains(tag_hdr, ">") == 0 and i + 1 < n:
                i = i + 1
                tag_hdr = tag_hdr + " " + ssg_trim(lines[i])
            let mut inner_slot: string = ""
            if ssg_contains(tag_hdr, "/>") == 0:
                close_tag := "</" + cname + ">"
                let mut inner_lines: string = ""
                let mut found_end: int = 0
                i = i + 1
                while i < n:
                    lt := ssg_trim(lines[i])
                    if ssg_contains(lt, close_tag) == 1:
                        found_end = 1
                        break
                    inner_lines = inner_lines + lines[i] + "\n"
                    i = i + 1
                if found_end == 1 and string_length(ssg_trim(inner_lines)) > 0:
                    sub_md := md_parse_and_render(inner_lines)
                    inner_slot = sub_md.html
            pid := "<!--CLX_CALL_" + str(len(clx_calls)) + "-->"
            clx_calls.push(ClxTagCall(cname, tag_hdr, inner_slot, pid))
            sb_append(sb, pid + "\n")
            i = i + 1
            continue

        // 4. .cld Directives (::: callout, ::: sheet, ::: tabs, ::: video)
        if ssg_starts_with(t, ":::") == 1:
            dir_hdr := ssg_trim(substring(t, 3, string_length(t) - 3))
            dir_sb := sb_new_cap(256)
            i = i + 1
            while i < n:
                dt := ssg_trim(lines[i])
                if dt == ":::":
                    break
                sb_append(dir_sb, lines[i])
                sb_append_byte(dir_sb, 10)
                i = i + 1
            dir_body := sb_to_str(dir_sb)
            sb_free(dir_sb)

            if ssg_starts_with(dir_hdr, "callout") == 1 or ssg_starts_with(dir_hdr, "note") == 1:
                let mut ctype: string = md_extract_attr(dir_hdr, "type")
                if string_length(ctype) == 0: ctype = "info"
                let mut ctitle: string = md_extract_attr(dir_hdr, "title")
                if string_length(ctitle) == 0: ctitle = "Note"
                sub := md_parse_and_render(dir_body)
                sb_append(sb, "<div class=\"cld-callout cld-callout-" + ssg_slugify(ctype) + "\"><div class=\"cld-callout-title\">" + ssg_escape_html(ctitle) + "</div><div class=\"cld-callout-body\">" + sub.html + "</div></div>\n")
            elif ssg_starts_with(dir_hdr, "sheet") == 1:
                stitle := md_extract_attr(dir_hdr, "title")
                sb_append(sb, "<div class=\"cld-sheet\">")
                if string_length(stitle) > 0:
                    sb_append(sb, "<div class=\"cld-sheet-title\">" + ssg_escape_html(stitle) + "</div>")
                sb_append(sb, "<table>\n")
                srows := ssg_split_lines(ssg_trim(dir_body))
                let mut ri: int = 0
                while ri < len(srows):
                    rl := ssg_trim(srows[ri])
                    if string_length(rl) > 0:
                        cells := ssg_split(rl, "|")
                        sb_append(sb, "<tr>")
                        let mut ci: int = 0
                        while ci < len(cells):
                            if ri == 0:
                                sb_append(sb, "<th>" + md_render_inline(ssg_trim(cells[ci])) + "</th>")
                            else:
                                sb_append(sb, "<td>" + md_render_inline(ssg_trim(cells[ci])) + "</td>")
                            ci = ci + 1
                        sb_append(sb, "</tr>\n")
                    ri = ri + 1
                sb_append(sb, "</table></div>\n")
            elif ssg_starts_with(dir_hdr, "tabs") == 1:
                sub := md_parse_and_render(dir_body)
                sb_append(sb, "<div class=\"cld-tabs\">" + sub.html + "</div>\n")
            elif ssg_starts_with(dir_hdr, "video") == 1:
                vsrc := md_extract_attr(dir_hdr, "src")
                sb_append(sb, "<div class=\"cld-video\"><video controls src=\"" + ssg_escape_html(vsrc) + "\"></video></div>\n")
            else:
                sub := md_parse_and_render(dir_body)
                sb_append(sb, "<div class=\"cld-block cld-" + ssg_slugify(dir_hdr) + "\">" + sub.html + "</div>\n")
            i = i + 1
            continue

        // 5. Hugo-style shortcode {{< name attr="val" >}}
        if ssg_starts_with(t, "{{<") == 1 and ssg_contains(t, ">}}") == 1:
            sname := ssg_trim(substring(t, 3, ssg_find_from(t, ">}}", 3) - 3))
            sb_append(sb, "<div class=\"cld-shortcode\" data-shortcode=\"" + ssg_escape_html(sname) + "\">" + ssg_escape_html(sname) + "</div>\n")
            i = i + 1
            continue

        // 6. Fenced Code Blocks (```lang or ~~~lang)
        if ssg_starts_with(t, "```") == 1 or ssg_starts_with(t, "~~~") == 1:
            fence := substring(t, 0, 3)
            lang := ssg_trim(substring(t, 3, string_length(t) - 3))
            code_sb := sb_new_cap(256)
            i = i + 1
            while i < n:
                lt := ssg_trim(lines[i])
                if ssg_starts_with(lt, fence) == 1:
                    break
                sb_append(code_sb, lines[i])
                sb_append_byte(code_sb, 10)
                i = i + 1
            raw_code := sb_to_str(code_sb)
            sb_free(code_sb)
            hl := md_highlight_code(raw_code, lang)
            let mut lang_cls: string = ""
            if string_length(lang) > 0:
                lang_cls = " class=\"language-" + ssg_slugify(lang) + "\" data-lang=\"" + ssg_escape_html(lang) + "\""
            sb_append(sb, "<pre class=\"code-block\"><code" + lang_cls + ">" + hl + "</code></pre>\n")
            i = i + 1
            continue

        // 7. Horizontal Rules (---, ***, ___)
        if t == "---" or t == "***" or t == "___" or t == "- - -" or t == "* * *":
            sb_append(sb, "<hr />\n")
            i = i + 1
            continue

        // 8. ATX Headings (# .. ######)
        if byte_at(t, 0) == 35:
            let mut lvl: int = 0
            while lvl < string_length(t) and lvl < 6 and byte_at(t, lvl) == 35:
                lvl = lvl + 1
            if lvl < string_length(t) and byte_at(t, lvl) == 32:
                htxt := ssg_trim(substring(t, lvl + 1, string_length(t) - lvl - 1))
                // Strip trailing optional ###
                let mut clean_h: string = htxt
                hid := ssg_slugify(clean_h)
                toc.push(TocEntry(lvl, hid, clean_h))
                word_count = word_count + len(ssg_split(clean_h, " "))
                sb_append(sb, "<h" + str(lvl) + " id=\"" + hid + "\">" + md_render_inline(clean_h) + "<a class=\"heading-anchor\" href=\"#" + hid + "\" aria-hidden=\"true\">#</a></h" + str(lvl) + ">\n")
                i = i + 1
                continue

        // 9. Setext Headings (next line === or ---)
        if i + 1 < n:
            nxt_t := ssg_trim(lines[i + 1])
            if string_length(nxt_t) >= 3 and (ssg_starts_with(nxt_t, "===") == 1 or ssg_starts_with(nxt_t, "---") == 1):
                let mut is_setext: int = 1
                let mut sep_ch: int = byte_at(nxt_t, 0)
                let mut si: int = 0
                while si < string_length(nxt_t):
                    if byte_at(nxt_t, si) != sep_ch:
                        is_setext = 0
                        break
                    si = si + 1
                if is_setext == 1:
                    let mut lvl: int = 2
                    if sep_ch == 61:
                        lvl = 1
                    hid := ssg_slugify(t)
                    toc.push(TocEntry(lvl, hid, t))
                    sb_append(sb, "<h" + str(lvl) + " id=\"" + hid + "\">" + md_render_inline(t) + "</h" + str(lvl) + ">\n")
                    i = i + 2
                    continue

        // 10. GFM Table
        if i + 1 < n:
            if ssg_contains(t, "|") == 1 and _md_is_table_sep(lines[i + 1]) == 1:
                hdr_cells := _md_split_table_row(t)
                aligns := _md_parse_table_aligns(lines[i + 1])
                sb_append(sb, "<div class=\"table-wrap\"><table>\n<thead><tr>")
                let mut ci: int = 0
                while ci < len(hdr_cells):
                    let mut al: string = ""
                    if ci < len(aligns): al = aligns[ci]
                    sb_append(sb, "<th" + al + ">" + md_render_inline(hdr_cells[ci]) + "</th>")
                    ci = ci + 1
                sb_append(sb, "</tr></thead>\n<tbody>\n")
                i = i + 2
                while i < n:
                    rt := ssg_trim(lines[i])
                    if string_length(rt) == 0 or ssg_contains(rt, "|") == 0:
                        break
                    rcells := _md_split_table_row(rt)
                    sb_append(sb, "<tr>")
                    let mut rci: int = 0
                    while rci < len(hdr_cells):
                        let mut al: string = ""
                        if rci < len(aligns): al = aligns[rci]
                        let mut cval: string = ""
                        if rci < len(rcells): cval = rcells[rci]
                        sb_append(sb, "<td" + al + ">" + md_render_inline(cval) + "</td>")
                        rci = rci + 1
                    sb_append(sb, "</tr>\n")
                    i = i + 1
                sb_append(sb, "</tbody></table></div>\n")
                continue

        // 11. Blockquotes (> ...)
        if ssg_starts_with(t, ">") == 1:
            bq_sb := sb_new_cap(128)
            while i < n:
                bt := ssg_trim(lines[i])
                if ssg_starts_with(bt, ">") == 0:
                    break
                let mut b_inner: string = ""
                if string_length(bt) > 1:
                    b_inner = ssg_trim(substring(bt, 1, string_length(bt) - 1))
                sb_append(bq_sb, b_inner)
                sb_append_byte(bq_sb, 10)
                i = i + 1
            sub_bq := md_parse_and_render(sb_to_str(bq_sb))
            sb_free(bq_sb)
            sb_append(sb, "<blockquote>" + sub_bq.html + "</blockquote>\n")
            continue

        // 12. Nested Unordered / Ordered / Task Lists
        let mut ol_body: string = ""
        is_ul := ssg_starts_with(t, "- ") == 1 or ssg_starts_with(t, "* ") == 1 or ssg_starts_with(t, "+ ") == 1
        is_ol := _md_is_ol_prefix(t, ol_body) == 1
        if is_ul or is_ol:
            let mut stack_tags: vector[string] = []
            let mut stack_depths: vector[int] = []
            while i < n:
                lt := ssg_trim(lines[i])
                if string_length(lt) == 0:
                    break
                let mut item_ol_b: string = ""
                cur_ul := ssg_starts_with(lt, "- ") == 1 or ssg_starts_with(lt, "* ") == 1 or ssg_starts_with(lt, "+ ") == 1
                cur_ol := _md_is_ol_prefix(lt, item_ol_b) == 1
                if cur_ul == 0 and cur_ol == 0:
                    break
                depth := _md_count_list_depth(lines[i])
                let mut want_tag: string = "ul"
                if cur_ol == 1:
                    want_tag = "ol"
                let mut item_txt: string = item_ol_b
                if cur_ul == 1:
                    item_txt = ssg_trim(substring(lt, 2, string_length(lt) - 2))

                // Close deeper lists
                while len(stack_depths) > 0:
                    if stack_depths[len(stack_depths) - 1] <= depth:
                        break
                    ctag := stack_tags.pop()
                    stack_depths.pop()
                    sb_append(sb, "</" + ctag + ">\n")

                if len(stack_depths) == 0 or stack_depths[len(stack_depths) - 1] < depth:
                    sb_append(sb, "<" + want_tag + ">\n")
                    stack_tags.push(want_tag)
                    stack_depths.push(depth)
                elif stack_tags[len(stack_tags) - 1] != want_tag:
                    ctag := stack_tags.pop()
                    stack_depths.pop()
                    sb_append(sb, "</" + ctag + "><" + want_tag + ">\n")
                    stack_tags.push(want_tag)
                    stack_depths.push(depth)

                // Task list support: [x] or [ ]
                if ssg_starts_with(item_txt, "[x] ") == 1 or ssg_starts_with(item_txt, "[X] ") == 1:
                    rest := substring(item_txt, 4, string_length(item_txt) - 4)
                    sb_append(sb, "<li class=\"task-list-item\"><input type=\"checkbox\" checked disabled /> " + md_render_inline(rest) + "</li>\n")
                elif ssg_starts_with(item_txt, "[ ] ") == 1:
                    rest := substring(item_txt, 4, string_length(item_txt) - 4)
                    sb_append(sb, "<li class=\"task-list-item\"><input type=\"checkbox\" disabled /> " + md_render_inline(rest) + "</li>\n")
                else:
                    sb_append(sb, "<li>" + md_render_inline(item_txt) + "</li>\n")
                word_count = word_count + len(ssg_split(item_txt, " "))
                i = i + 1

            while len(stack_tags) > 0:
                ctag := stack_tags.pop()
                stack_depths.pop()
                sb_append(sb, "</" + ctag + ">\n")
            continue

        // 13. Raw HTML Block Passthrough (<div>, <section>, <details>, <style>, <script>, etc.)
        if byte_at(t, 0) == 60:
            sb_append(sb, raw + "\n")
            i = i + 1
            continue

        // 14. Paragraph (coalesce contiguous plain lines until blank or block start)
        para_sb := sb_new_cap(128)
        while i < n:
            pt := ssg_trim(lines[i])
            if string_length(pt) == 0:
                break
            if byte_at(pt, 0) == 35 or byte_at(pt, 0) == 62 or byte_at(pt, 0) == 60 or ssg_starts_with(pt, "```") == 1 or ssg_starts_with(pt, "~~~") == 1 or ssg_starts_with(pt, ":::") == 1 or ssg_starts_with(pt, "- ") == 1 or ssg_starts_with(pt, "* ") == 1 or pt == "---" or pt == "***":
                break
            let mut dummy_ol: string = ""
            if _md_is_ol_prefix(pt, dummy_ol) == 1:
                break
            if para_sb.len > 0:
                sb_append_byte(para_sb, 32)
            sb_append(para_sb, pt)
            word_count = word_count + _md_count_words_inline(pt)
            i = i + 1
        para_txt := sb_to_str(para_sb)
        sb_free(para_sb)
        if string_length(para_txt) > 0:
            if plain_sb.len < 220:
                if plain_sb.len > 0:
                    sb_append_byte(plain_sb, 32)
                sb_append(plain_sb, para_txt)
            sb_append(sb, "<p>" + md_render_inline(para_txt) + "</p>\n")
        else:
            i = i + 1

    // Append rendered footnotes section if present
    if len(footnotes_ids) > 0:
        sb_append(sb, "<section class=\"footnotes\"><hr /><ol>\n")
        let mut fni: int = 0
        while fni < len(footnotes_ids):
            fid := footnotes_ids[fni]
            sb_append(sb, "<li id=\"fn-" + ssg_slugify(fid) + "\">" + footnotes_html[fni] + " <a href=\"#fnref-" + ssg_slugify(fid) + "\">&#8617;</a></li>\n")
            fni = fni + 1
        sb_append(sb, "</ol></section>\n")

    html_out := sb_to_str(sb)
    sb_free(sb)
    let mut excerpt: string = sb_to_str(plain_sb)
    sb_free(plain_sb)
    if string_length(excerpt) > 180:
        excerpt = substring(excerpt, 0, 177) + "..."
    return MarkdownResult(html_out, toc, islands, clx_calls, word_count, excerpt)

fn md_toc_to_html(toc: vector[TocEntry]) -> string:
    if len(toc) == 0:
        return ""
    sb := sb_new_cap(256)
    sb_append(sb, "<nav class=\"table-of-contents\"><ul>\n")
    let mut i: int = 0
    while i < len(toc):
        e := toc[i]
        sb_append(sb, "<li class=\"toc-level-" + str(e.level) + "\"><a href=\"#" + e.id + "\">" + ssg_escape_html(e.text) + "</a></li>\n")
        i = i + 1
    sb_append(sb, "</ul></nav>\n")
    out := sb_to_str(sb)
    sb_free(sb)
    return out
