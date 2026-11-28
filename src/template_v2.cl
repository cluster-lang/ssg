// ==============================================================================
// Module:      Turing-Complete Liquid + Hugo Template Engine (src/template_v2.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Layout inheritance chains, nested scoped includes, {% assign %},
//              {% capture %}, {% if/elif/else %}, nested {% for %} with
//              forloop.* & collection filters, and 20+ Liquid/Hugo pipe filters.
// ==============================================================================

import "src/strbuf.cl"
import "src/config.cl"
import "src/frontmatter.cl"
import "src/markdown.cl"

model TemplateRegistry:
    layout_names: vector[string]
    layout_contents: vector[string]
    layout_map: dict[string, string]
    layout_bodies: dict[string, string]
    layout_parents: dict[string, string]
    include_names: vector[string]
    include_contents: vector[string]
    include_map: dict[string, string]

model PageSummary:
    title: string
    url: string
    date: string
    author: string
    description: string
    tags: string
    categories: string
    collection: string
    slug: string
    excerpt: string
    reading_time: int
    lang: string
    meta: dict[string, string]

model RenderContext:
    vars: dict[string, string]
    lists: dict[string, string]
    items: vector[PageSummary]
    post_indices: vector[int]
    page_indices: vector[int]
    paginator_indices: vector[int]
    index_pools: vector[vector[int]]
    col_indices: dict[string, int]
    tag_indices: dict[string, int]
    cat_indices: dict[string, int]
    data: DataRegistry
    config: SsgConfig

fn template_new() -> TemplateRegistry:
    return TemplateRegistry()

fn template_register_layout(tr: TemplateRegistry, name: string, content: string) -> void:
    tr.layout_names.push(name)
    tr.layout_contents.push(content)
    tr.layout_map[name] = content
    fm := fm_parse_document(content)
    tr.layout_bodies[name] = fm.body
    let mut p_lay: string = ""
    if fm.fields.has("layout") == 1:
        p_lay = fm.fields["layout"]
    tr.layout_parents[name] = p_lay

fn template_register_include(tr: TemplateRegistry, name: string, content: string) -> void:
    tr.include_names.push(name)
    tr.include_contents.push(content)
    tr.include_map[name] = content

fn template_get_layout(tr: TemplateRegistry, name: string) -> string:
    if tr.layout_map.has(name) == 1:
        return tr.layout_map[name]
    let mut base: string = ssg_path_stem(name)
    if tr.layout_map.has(base) == 1:
        return tr.layout_map[base]
    if tr.layout_map.has("default") == 1:
        return tr.layout_map["default"]
    if len(tr.layout_contents) > 0:
        return tr.layout_contents[0]
    ob := "{" + "{"
    cb := "}" + "}"
    return "<!DOCTYPE html><html><body>" + ob + " content " + cb + "</body></html>"

fn template_get_include(tr: TemplateRegistry, name: string) -> string:
    if tr.include_map.has(name) == 1:
        return tr.include_map[name]
    let mut alt: string = ssg_path_stem(name)
    if tr.include_map.has(alt) == 1:
        return tr.include_map[alt]
    if tr.include_map.has(name + ".html") == 1:
        return tr.include_map[name + ".html"]
    return "<!-- Include not found: " + name + " -->"

fn _tmpl_clone_dict(src: dict[string, string]) -> dict[string, string]:
    out := dict[string, string]()
    ks := src.keys()
    let mut i: int = 0
    while i < len(ks):
        k := ks[i]
        out[k] = src[k]
        i = i + 1
    return out

// ------------------------------------------------------------------------------
// Variable Lookup & Expression Resolution
// ------------------------------------------------------------------------------

fn _tmpl_resolve_expr(expr_raw: string, vars: dict[string, string], ctx: RenderContext) -> string:
    e := ssg_trim(expr_raw)
    if string_length(e) == 0:
        return ""
    if (ssg_starts_with(e, "\"") == 1 and ssg_ends_with(e, "\"") == 1) or (ssg_starts_with(e, "'") == 1 and ssg_ends_with(e, "'") == 1):
        return ssg_strip_quotes(e)
    if e == "true": return "true"
    if e == "false": return "false"
    if e == "nil" or e == "null": return ""

    if vars.has(e) == 1:
        return vars[e]
    // Short aliases: page.title -> title, site.title -> site_name
    if ssg_starts_with(e, "page.") == 1:
        short := substring(e, 5, string_length(e) - 5)
        if vars.has(short) == 1:
            return vars[short]
    if e == "site.title" or e == "site.name":
        return ctx.config.site_name
    if e == "site.tagline" or e == "site.description":
        return ctx.config.site_tagline
    if e == "site.baseurl" or e == "site.base_url" or e == "site.url":
        return ctx.config.base_url
    if ssg_starts_with(e, "site.data.") == 1:
        dk := substring(e, 10, string_length(e) - 10)
        if ctx.data.flat.has(dk) == 1:
            return ctx.data.flat[dk]
    dot_pos := ssg_find_from(e, ".", 0)
    if dot_pos > 0:
        rname := substring(e, 0, dot_pos)
        rrest := substring(e, dot_pos + 1, string_length(e) - dot_pos - 1)
        if vars.has("__prefix:" + rname) == 1:
            fk := vars["__prefix:" + rname] + "." + rrest
            if ctx.data.flat.has(fk) == 1:
                return ctx.data.flat[fk]
    if ssg_starts_with(e, "site.") == 1:
        ck := substring(e, 5, string_length(e) - 5)
        if ctx.config.custom.has(ck) == 1:
            return ctx.config.custom[ck]
    if ctx.data.flat.has(e) == 1:
        return ctx.data.flat[e]
    // Check numeric literal
    let mut is_num: int = 1
    let mut ni: int = 0
    while ni < string_length(e):
        b := byte_at(e, ni)
        if (b < 48 or b > 57) and b != 45:
            is_num = 0
            break
        ni = ni + 1
    if is_num == 1:
        return e
    return ""

// ------------------------------------------------------------------------------
// Pipe Filters (| date | slugify | truncate | escape | default | ...)
// ------------------------------------------------------------------------------

fn _tmpl_apply_single_filter(val: string, filter_raw: string, vars: dict[string, string], ctx: RenderContext) -> string:
    f := ssg_trim(filter_raw)
    let mut fname: string = f
    let mut farg: string = ""
    col := ssg_find_from(f, ":", 0)
    if col > 0:
        fname = ssg_lower(ssg_trim(substring(f, 0, col)))
        farg_raw := ssg_trim(substring(f, col + 1, string_length(f) - col - 1))
        farg = _tmpl_resolve_expr(farg_raw, vars, ctx)
        if string_length(farg) == 0:
            farg = ssg_strip_quotes(farg_raw)
    else:
        fname = ssg_lower(f)

    if fname == "slugify":
        return ssg_slugify(val)
    elif fname == "upcase" or fname == "upper":
        return ssg_upper(val)
    elif fname == "downcase" or fname == "lower":
        return ssg_lower(val)
    elif fname == "capitalize":
        if string_length(val) == 0: return ""
        return ssg_upper(substring(val, 0, 1)) + ssg_lower(substring(val, 1, string_length(val) - 1))
    elif fname == "strip_html":
        return ssg_strip_html(val)
    elif fname == "escape" or fname == "xml_escape" or fname == "h":
        return ssg_escape_html(val)
    elif fname == "jsonify":
        return "\"" + ssg_escape_json(val) + "\""
    elif fname == "default":
        if string_length(ssg_trim(val)) == 0:
            return farg
        return val
    elif fname == "truncate":
        lim := ssg_parse_int(farg, 50)
        if lim > 3 and string_length(val) > lim:
            return substring(val, 0, lim - 3) + "..."
        return val
    elif fname == "truncatewords":
        wlim := ssg_parse_int(farg, 20)
        ws := ssg_split(val, " ")
        if len(ws) <= wlim:
            return val
        sb := sb_new_cap(128)
        let mut wi: int = 0
        while wi < wlim and wi < len(ws):
            if wi > 0: sb_append_byte(sb, 32)
            sb_append(sb, ws[wi])
            wi = wi + 1
        sb_append(sb, "...")
        out := sb_to_str(sb)
        sb_free(sb)
        return out
    elif fname == "size" or fname == "length":
        if ssg_contains(val, ",") == 1:
            return str(len(ssg_split(val, ",")))
        return str(string_length(val))
    elif fname == "relative_url":
        if ssg_starts_with(val, "http://") == 1 or ssg_starts_with(val, "https://") == 1:
            return val
        if ssg_starts_with(val, "/") == 1:
            return val
        return "/" + val
    elif fname == "absolute_url":
        if ssg_starts_with(val, "http://") == 1 or ssg_starts_with(val, "https://") == 1:
            return val
        let mut p: string = val
        if ssg_starts_with(p, "/") == 0:
            p = "/" + p
        return ctx.config.base_url + p
    elif fname == "date" or fname == "date_to_string" or fname == "date_to_xmlschema":
        if string_length(val) == 0:
            return ""
        if fname == "date_to_xmlschema":
            if ssg_contains(val, "T") == 1:
                return val
            return val + "T00:00:00Z"
        // Simple YYYY-MM-DD formatting
        parts := ssg_split(val, "-")
        if len(parts) >= 3:
            yr := parts[0]
            mo := ssg_parse_int(parts[1], 1)
            dy := parts[2]
            months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let mut mname: string = parts[1]
            if mo >= 1 and mo <= 12:
                mname = months[mo - 1]
            if farg == "%Y": return yr
            return mname + " " + dy + ", " + yr
        return val
    elif fname == "split":
        return val
    elif fname == "join":
        return ssg_replace_all(val, ",", farg)
    elif fname == "markdownify":
        md_res := md_parse_and_render(val)
        return md_res.html
    elif fname == "first":
        parts := ssg_split(val, ",")
        if len(parts) > 0: return ssg_trim(parts[0])
        return val
    elif fname == "last":
        parts := ssg_split(val, ",")
        if len(parts) > 0: return ssg_trim(parts[len(parts) - 1])
        return val
    elif fname == "append":
        return val + farg
    elif fname == "prepend":
        return farg + val
    elif fname == "remove":
        return ssg_replace_all(val, farg, "")
    elif fname == "uniq":
        parts := ssg_split(val, ",")
        seen := dict[string, int]()
        sb := sb_new_cap(string_length(val) + 16)
        let mut ui: int = 0
        let mut uc: int = 0
        while ui < len(parts):
            pt := ssg_trim(parts[ui])
            if string_length(pt) > 0 and seen.has(pt) == 0:
                seen[pt] = 1
                if uc > 0: sb_append(sb, ",")
                sb_append(sb, pt)
                uc = uc + 1
            ui = ui + 1
        out := sb_to_str(sb)
        sb_free(sb)
        return out
    elif fname == "compact":
        parts := ssg_split(val, ",")
        sb := sb_new_cap(string_length(val) + 16)
        let mut ci: int = 0
        let mut cc: int = 0
        while ci < len(parts):
            pt := ssg_trim(parts[ci])
            if string_length(pt) > 0:
                if cc > 0: sb_append(sb, ",")
                sb_append(sb, pt)
                cc = cc + 1
            ci = ci + 1
        out := sb_to_str(sb)
        sb_free(sb)
        return out
    elif fname == "sort":
        parts := ssg_split(val, ",")
        let mut arr: vector[string] = []
        let mut si: int = 0
        while si < len(parts):
            pt := ssg_trim(parts[si])
            if string_length(pt) > 0:
                arr.push(pt)
            si = si + 1
        let mut ai: int = 1
        while ai < len(arr):
            key := arr[ai]
            let mut aj: int = ai - 1
            while aj >= 0:
                if arr[aj] <= key:
                    break
                arr[aj + 1] = arr[aj]
                aj = aj - 1
            arr[aj + 1] = key
            ai = ai + 1
        sb := sb_new_cap(string_length(val) + 16)
        let mut oi: int = 0
        while oi < len(arr):
            if oi > 0: sb_append(sb, ",")
            sb_append(sb, arr[oi])
            oi = oi + 1
        out := sb_to_str(sb)
        sb_free(sb)
        return out
    elif fname == "reverse":
        parts := ssg_split(val, ",")
        sb := sb_new_cap(string_length(val) + 16)
        let mut ri: int = len(parts) - 1
        let mut rc: int = 0
        while ri >= 0:
            pt := ssg_trim(parts[ri])
            if string_length(pt) > 0:
                if rc > 0: sb_append(sb, ",")
                sb_append(sb, pt)
                rc = rc + 1
            ri = ri - 1
        out := sb_to_str(sb)
        sb_free(sb)
        return out
    elif fname == "slice":
        s_parts := ssg_split(farg, ",")
        let mut st_i: int = 0
        let mut ln_i: int = 1
        if len(s_parts) >= 1: st_i = ssg_parse_int(ssg_trim(s_parts[0]), 0)
        if len(s_parts) >= 2: ln_i = ssg_parse_int(ssg_trim(s_parts[1]), 1)
        if st_i < 0: st_i = 0
        if ln_i < 0: ln_i = 0
        if ssg_contains(val, ",") == 1:
            parts := ssg_split(val, ",")
            sb := sb_new_cap(64)
            let mut pi: int = st_i
            let mut pc: int = 0
            while pi < len(parts) and pc < ln_i:
                if pc > 0: sb_append(sb, ",")
                sb_append(sb, ssg_trim(parts[pi]))
                pi = pi + 1
                pc = pc + 1
            out := sb_to_str(sb)
            sb_free(sb)
            return out
        vlen := string_length(val)
        if st_i >= vlen: return ""
        let mut take: int = ln_i
        if st_i + take > vlen: take = vlen - st_i
        return substring(val, st_i, take)
    return val

fn _tmpl_eval_output_expr(expr_raw: string, vars: dict[string, string], ctx: RenderContext) -> string:
    parts := ssg_split(expr_raw, "|")
    if len(parts) == 0:
        return ""
    let mut val: string = _tmpl_resolve_expr(parts[0], vars, ctx)
    let mut i: int = 1
    while i < len(parts):
        val = _tmpl_apply_single_filter(val, parts[i], vars, ctx)
        i = i + 1
    return val

// ------------------------------------------------------------------------------
// Condition Evaluator ({% if cond %})
// ------------------------------------------------------------------------------

fn _tmpl_is_truthy(v: string) -> int:
    t := ssg_lower(ssg_trim(v))
    if string_length(t) == 0 or t == "false" or t == "0" or t == "null" or t == "nil":
        return 0
    return 1

fn _tmpl_eval_simple_cond(cond_raw: string, vars: dict[string, string], ctx: RenderContext) -> int:
    c := ssg_trim(cond_raw)
    if string_length(c) == 0:
        return 0
    if ssg_starts_with(c, "not ") == 1:
        inner := substring(c, 4, string_length(c) - 4)
        if _tmpl_eval_simple_cond(inner, vars, ctx) == 1:
            return 0
        return 1

    // Binary comparison operators
    ops := [" == ", " != ", " >= ", " <= ", " > ", " < ", " contains "]
    let mut oi: int = 0
    while oi < len(ops):
        op := ops[oi]
        pos := ssg_find_from(c, op, 0)
        if pos > 0:
            lhs := _tmpl_resolve_expr(substring(c, 0, pos), vars, ctx)
            rhs := _tmpl_resolve_expr(substring(c, pos + string_length(op), string_length(c) - pos - string_length(op)), vars, ctx)
            if op == " == ":
                if lhs == rhs: return 1
                return 0
            elif op == " != ":
                if lhs != rhs: return 1
                return 0
            elif op == " contains ":
                return ssg_contains(lhs, rhs)
            elif op == " > ":
                if ssg_parse_int(lhs, 0) > ssg_parse_int(rhs, 0): return 1
                return 0
            elif op == " < ":
                if ssg_parse_int(lhs, 0) < ssg_parse_int(rhs, 0): return 1
                return 0
            elif op == " >= ":
                if ssg_parse_int(lhs, 0) >= ssg_parse_int(rhs, 0): return 1
                return 0
            elif op == " <= ":
                if ssg_parse_int(lhs, 0) <= ssg_parse_int(rhs, 0): return 1
                return 0
        oi = oi + 1

    return _tmpl_is_truthy(_tmpl_resolve_expr(c, vars, ctx))

fn _tmpl_eval_cond(cond_raw: string, vars: dict[string, string], ctx: RenderContext) -> int:
    or_parts := ssg_split(cond_raw, " or ")
    let mut oi: int = 0
    while oi < len(or_parts):
        and_parts := ssg_split(or_parts[oi], " and ")
        let mut all_ok: int = 1
        let mut ai: int = 0
        while ai < len(and_parts):
            if _tmpl_eval_simple_cond(and_parts[ai], vars, ctx) == 0:
                all_ok = 0
                break
            ai = ai + 1
        if all_ok == 1:
            return 1
        oi = oi + 1
    return 0

// ------------------------------------------------------------------------------
// Helper: Find matching {% endif %} or {% endfor %} respecting nesting
// ------------------------------------------------------------------------------

fn _tmpl_find_tag_end(tmpl: string, start: int) -> int:
    return ssg_find_from(tmpl, "%}", start)

fn _tmpl_find_matching_block_end(tmpl: string, after_open: int, open_kw: string, close_kw: string, split_positions: vector[int], split_tags: vector[string]) -> int:
    tlen := string_length(tmpl)
    let mut depth: int = 1
    let mut pos: int = after_open
    while pos < tlen:
        tag_s := ssg_find_from(tmpl, "{%", pos)
        if tag_s < 0:
            return -1
        tag_e := ssg_find_from(tmpl, "%}", tag_s + 2)
        if tag_e < 0:
            return -1
        tag_body := ssg_trim(substring(tmpl, tag_s + 2, tag_e - tag_s - 2))
        if ssg_starts_with(tag_body, open_kw + " ") == 1 or tag_body == open_kw:
            depth = depth + 1
        elif tag_body == close_kw or ssg_starts_with(tag_body, close_kw + " ") == 1:
            depth = depth - 1
            if depth == 0:
                return tag_s
        elif depth == 1 and open_kw == "if":
            if ssg_starts_with(tag_body, "elif ") == 1 or ssg_starts_with(tag_body, "elsif ") == 1 or tag_body == "else":
                split_positions.push(tag_s)
                split_tags.push(tag_body)
        pos = tag_e + 2
    return -1

// ------------------------------------------------------------------------------
// Populate Loop Item Variables into Local Dict
// ------------------------------------------------------------------------------

fn _tmpl_bind_page_item(lvars: dict[string, string], var_name: string, p: PageSummary) -> void:
    lvars[var_name + ".title"] = p.title
    lvars[var_name + ".url"] = p.url
    lvars[var_name + ".date"] = p.date
    lvars[var_name + ".author"] = p.author
    lvars[var_name + ".description"] = p.description
    lvars[var_name + ".tags"] = p.tags
    lvars[var_name + ".categories"] = p.categories
    lvars[var_name + ".collection"] = p.collection
    lvars[var_name + ".slug"] = p.slug
    lvars[var_name + ".excerpt"] = p.excerpt
    lvars[var_name + ".reading_time"] = str(p.reading_time)
    lvars[var_name + ".lang"] = p.lang
    ks := p.meta.keys()
    let mut i: int = 0
    while i < len(ks):
        k := ks[i]
        lvars[var_name + "." + k] = p.meta[k]
        i = i + 1

fn _tmpl_item_field(p: PageSummary, field: string) -> string:
    if field == "title": return p.title
    elif field == "url": return p.url
    elif field == "date": return p.date
    elif field == "year":
        if string_length(p.date) >= 4: return substring(p.date, 0, 4)
        return ""
    elif field == "author": return p.author
    elif field == "description": return p.description
    elif field == "tags": return p.tags
    elif field == "categories": return p.categories
    elif field == "collection": return p.collection
    elif field == "slug": return p.slug
    elif field == "excerpt": return p.excerpt
    elif field == "lang": return p.lang
    elif field == "reading_time": return str(p.reading_time)
    if p.meta.has(field) == 1:
        return p.meta[field]
    return ""

fn _tmpl_parse_pipe_two_args(arg_raw: string, &a0: string, &a1: string) -> void:
    a0 = ""
    a1 = ""
    c := ssg_find_from(arg_raw, ",", 0)
    if c > 0:
        a0 = ssg_strip_quotes(ssg_trim(substring(arg_raw, 0, c)))
        a1 = ssg_strip_quotes(ssg_trim(substring(arg_raw, c + 1, string_length(arg_raw) - c - 1)))
    else:
        a0 = ssg_strip_quotes(ssg_trim(arg_raw))

fn _tmpl_split_pipes_outside_quotes(raw: string) -> vector[string]:
    let mut out: vector[string] = []
    rlen := string_length(raw)
    let mut start: int = 0
    let mut in_q: int = 0
    let mut q_ch: int = 0
    let mut i: int = 0
    while i < rlen:
        ch := byte_at(raw, i)
        if in_q == 1:
            if ch == q_ch:
                in_q = 0
        else:
            if ch == 34 or ch == 39:
                in_q = 1
                q_ch = ch
            elif ch == 124:
                out.push(ssg_trim(substring(raw, start, i - start)))
                start = i + 1
        i = i + 1
    out.push(ssg_trim(substring(raw, start, rlen - start)))
    return out

fn _tmpl_render_internal(tr: TemplateRegistry, tmpl: string, vars: dict[string, string], ctx: RenderContext, depth: int) -> string:
    if depth > 24:
        return tmpl
    tlen := string_length(tmpl)
    sb := sb_new_cap(tlen + 128)
    let mut pos: int = 0

    while pos < tlen:
        // Scan next {{ or {%
        n_var := ssg_find_from(tmpl, "{{", pos)
        n_tag := ssg_find_from(tmpl, "{%", pos)
        let mut next_pos: int = -1
        let mut kind: int = 0 // 1 = {{, 2 = {%
        if n_var >= 0 and (n_tag < 0 or n_var < n_tag):
            next_pos = n_var
            kind = 1
        elif n_tag >= 0:
            next_pos = n_tag
            kind = 2

        if next_pos < 0:
            sb_append_slice(sb, tmpl, pos, tlen - pos)
            break

        if next_pos > pos:
            sb_append_slice(sb, tmpl, pos, next_pos - pos)

        if kind == 1:
            end_v := ssg_find_from(tmpl, "}}", next_pos + 2)
            if end_v < 0:
                sb_append_slice(sb, tmpl, next_pos, tlen - next_pos)
                break
            expr := ssg_trim(substring(tmpl, next_pos + 2, end_v - next_pos - 2))
            // Legacy {{ include "name" ... }} support inside {{ ... }}
            if ssg_starts_with(expr, "include ") == 1:
                inc_rest := ssg_trim(substring(expr, 8, string_length(expr) - 8))
                let mut inc_name: string = inc_rest
                sp := ssg_find_from(inc_rest, " ", 0)
                if sp > 0:
                    inc_name = ssg_strip_quotes(substring(inc_rest, 0, sp))
                    inc_html := template_get_include(tr, inc_name)
                    inc_vars := _tmpl_clone_dict(vars)
                    params_str := substring(inc_rest, sp + 1, string_length(inc_rest) - sp - 1)
                    ppairs := ssg_split(params_str, " ")
                    let mut pi: int = 0
                    while pi < len(ppairs):
                        eq := ssg_find_from(ppairs[pi], "=", 0)
                        if eq > 0:
                            pk := ssg_trim(substring(ppairs[pi], 0, eq))
                            pv := _tmpl_resolve_expr(substring(ppairs[pi], eq + 1, string_length(ppairs[pi]) - eq - 1), vars, ctx)
                            inc_vars["include." + pk] = pv
                            inc_vars[pk] = pv
                        pi = pi + 1
                    sb_append(sb, _tmpl_render_internal(tr, inc_html, inc_vars, ctx, depth + 1))
                    dict_free(inc_vars)
                else:
                    inc_name = ssg_strip_quotes(inc_rest)
                    inc_html := template_get_include(tr, inc_name)
                    if ssg_contains(inc_html, "{% assign ") == 1 or ssg_contains(inc_html, "{% capture ") == 1:
                        tmp_iv := _tmpl_clone_dict(vars)
                        sb_append(sb, _tmpl_render_internal(tr, inc_html, tmp_iv, ctx, depth + 1))
                        dict_free(tmp_iv)
                    else:
                        sb_append(sb, _tmpl_render_internal(tr, inc_html, vars, ctx, depth + 1))
            elif ssg_starts_with(expr, "<") == 0:
                sb_append(sb, _tmpl_eval_output_expr(expr, vars, ctx))
            else:
                // Passthrough Hugo shortcode syntax if untouched
                sb_append_slice(sb, tmpl, next_pos, end_v + 2 - next_pos)
            pos = end_v + 2
            continue

        // {% ... %}
        end_t := ssg_find_from(tmpl, "%}", next_pos + 2)
        if end_t < 0:
            sb_append_slice(sb, tmpl, next_pos, tlen - next_pos)
            break
        tag := ssg_trim(substring(tmpl, next_pos + 2, end_t - next_pos - 2))

        // 1. {% include "card.html" title=post.title %}
        if ssg_starts_with(tag, "include ") == 1:
            inc_rest := ssg_trim(substring(tag, 8, string_length(tag) - 8))
            let mut inc_name: string = inc_rest
            sp := ssg_find_from(inc_rest, " ", 0)
            if sp > 0:
                inc_name = ssg_strip_quotes(substring(inc_rest, 0, sp))
                inc_html := template_get_include(tr, inc_name)
                inc_vars := _tmpl_clone_dict(vars)
                params_str := substring(inc_rest, sp + 1, string_length(inc_rest) - sp - 1)
                ppairs := ssg_split(params_str, " ")
                let mut pi: int = 0
                while pi < len(ppairs):
                    eq := ssg_find_from(ppairs[pi], "=", 0)
                    if eq > 0:
                        pk := ssg_trim(substring(ppairs[pi], 0, eq))
                        pv := _tmpl_resolve_expr(substring(ppairs[pi], eq + 1, string_length(ppairs[pi]) - eq - 1), vars, ctx)
                        inc_vars["include." + pk] = pv
                        inc_vars[pk] = pv
                    pi = pi + 1
                sb_append(sb, _tmpl_render_internal(tr, inc_html, inc_vars, ctx, depth + 1))
                dict_free(inc_vars)
            else:
                inc_name = ssg_strip_quotes(inc_rest)
                inc_html := template_get_include(tr, inc_name)
                if ssg_contains(inc_html, "{% assign ") == 1 or ssg_contains(inc_html, "{% capture ") == 1:
                    tmp_iv2 := _tmpl_clone_dict(vars)
                    sb_append(sb, _tmpl_render_internal(tr, inc_html, tmp_iv2, ctx, depth + 1))
                    dict_free(tmp_iv2)
                else:
                    sb_append(sb, _tmpl_render_internal(tr, inc_html, vars, ctx, depth + 1))
            pos = end_t + 2
            continue

        // 2. {% assign var = expr %}
        if ssg_starts_with(tag, "assign ") == 1:
            are := ssg_trim(substring(tag, 7, string_length(tag) - 7))
            eq := ssg_find_from(are, "=", 0)
            if eq > 0:
                ak := ssg_trim(substring(are, 0, eq))
                av_expr := ssg_trim(substring(are, eq + 1, string_length(are) - eq - 1))
                vars[ak] = _tmpl_eval_output_expr(av_expr, vars, ctx)
            pos = end_t + 2
            continue

        // 3. {% capture var %}...{% endcapture %}
        if ssg_starts_with(tag, "capture ") == 1:
            cname := ssg_trim(substring(tag, 8, string_length(tag) - 8))
            let mut sp_pos: vector[int] = []
            let mut sp_tag: vector[string] = []
            endcap := _tmpl_find_matching_block_end(tmpl, end_t + 2, "capture", "endcapture", sp_pos, sp_tag)
            if endcap >= 0:
                inner := substring(tmpl, end_t + 2, endcap - (end_t + 2))
                vars[cname] = _tmpl_render_internal(tr, inner, vars, ctx, depth + 1)
                close_end := ssg_find_from(tmpl, "%}", endcap + 2)
                pos = close_end + 2
                continue
            pos = end_t + 2
            continue

        // 4. {% if cond %} ... {% elif %} ... {% else %} ... {% endif %}
        if ssg_starts_with(tag, "if ") == 1:
            let mut sp_pos: vector[int] = []
            let mut sp_tag: vector[string] = []
            endif_pos := _tmpl_find_matching_block_end(tmpl, end_t + 2, "if", "endif", sp_pos, sp_tag)
            if endif_pos < 0:
                pos = end_t + 2
                continue
            // Evaluate branches
            let mut branch_conds: vector[string] = []
            let mut branch_bodies: vector[string] = []
            branch_conds.push(substring(tag, 3, string_length(tag) - 3))
            let mut cur_body_start: int = end_t + 2
            let mut si: int = 0
            while si < len(sp_pos):
                branch_bodies.push(substring(tmpl, cur_body_start, sp_pos[si] - cur_body_start))
                st_end := ssg_find_from(tmpl, "%}", sp_pos[si] + 2)
                cur_body_start = st_end + 2
                st_tag := sp_tag[si]
                if ssg_starts_with(st_tag, "elif ") == 1:
                    branch_conds.push(substring(st_tag, 5, string_length(st_tag) - 5))
                elif ssg_starts_with(st_tag, "elsif ") == 1:
                    branch_conds.push(substring(st_tag, 6, string_length(st_tag) - 6))
                else:
                    branch_conds.push("__ELSE__")
                si = si + 1
            branch_bodies.push(substring(tmpl, cur_body_start, endif_pos - cur_body_start))

            let mut bi: int = 0
            while bi < len(branch_conds):
                bc := branch_conds[bi]
                if bc == "__ELSE__" or _tmpl_eval_cond(bc, vars, ctx) == 1:
                    sb_append(sb, _tmpl_render_internal(tr, branch_bodies[bi], vars, ctx, depth + 1))
                    break
                bi = bi + 1

            close_end := ssg_find_from(tmpl, "%}", endif_pos + 2)
            pos = close_end + 2
            continue

        // 5. {% for item in collection [| where | sort | group_by | uniq | slice] [limit:N] [reversed] %} ... {% endfor %}
        if ssg_starts_with(tag, "for ") == 1:
            let mut sp_pos: vector[int] = []
            let mut sp_tag: vector[string] = []
            endfor_pos := _tmpl_find_matching_block_end(tmpl, end_t + 2, "for", "endfor", sp_pos, sp_tag)
            if endfor_pos < 0:
                pos = end_t + 2
                continue
            inner := substring(tmpl, end_t + 2, endfor_pos - (end_t + 2))
            for_spec := ssg_trim(substring(tag, 4, string_length(tag) - 4))
            in_idx := ssg_find_from(for_spec, " in ", 0)
            if in_idx > 0:
                loop_var := ssg_trim(substring(for_spec, 0, in_idx))
                rest := ssg_trim(substring(for_spec, in_idx + 4, string_length(for_spec) - in_idx - 4))
                pipe_segs := _tmpl_split_pipes_outside_quotes(rest)
                base_segs := ssg_split(pipe_segs[0], " ")
                col_expr := ssg_trim(base_segs[0])
                let mut limit_n: int = 1000000
                let mut reversed: int = 0
                let mut bsi: int = 1
                while bsi < len(base_segs):
                    rp := ssg_trim(base_segs[bsi])
                    if rp == "reversed": reversed = 1
                    elif ssg_starts_with(rp, "limit:") == 1: limit_n = ssg_parse_int(substring(rp, 6, string_length(rp) - 6), 1000000)
                    bsi = bsi + 1

                // Case A: Structured PageSummary collections (including __pool: dynamic group_by sublists)
                let mut idx_list: vector[int] = []
                let mut is_page_col: int = 0
                if vars.has("__pool:" + col_expr) == 1:
                    is_page_col = 1
                    pool_csv := vars["__pool:" + col_expr]
                    if string_length(pool_csv) > 0:
                        pp := ssg_split(pool_csv, ",")
                        let mut ppi: int = 0
                        while ppi < len(pp):
                            idx_list.push(ssg_parse_int(pp[ppi], 0))
                            ppi = ppi + 1
                elif col_expr == "site.posts" or col_expr == "posts":
                    idx_list = ctx.post_indices
                    is_page_col = 1
                elif col_expr == "site.pages" or col_expr == "pages":
                    idx_list = ctx.page_indices
                    is_page_col = 1
                elif col_expr == "paginator.posts":
                    idx_list = ctx.paginator_indices
                    is_page_col = 1
                elif ssg_starts_with(col_expr, "collections.") == 1:
                    cname := substring(col_expr, 12, string_length(col_expr) - 12)
                    if ctx.col_indices.has(cname) == 1:
                        idx_list = ctx.index_pools[ctx.col_indices[cname]]
                    is_page_col = 1
                elif ssg_starts_with(col_expr, "site.tags.") == 1:
                    tname := substring(col_expr, 10, string_length(col_expr) - 10)
                    if ctx.tag_indices.has(tname) == 1:
                        idx_list = ctx.index_pools[ctx.tag_indices[tname]]
                    is_page_col = 1
                elif ssg_starts_with(col_expr, "site.categories.") == 1:
                    cname := substring(col_expr, 16, string_length(col_expr) - 16)
                    if ctx.cat_indices.has(cname) == 1:
                        idx_list = ctx.index_pools[ctx.cat_indices[cname]]
                    is_page_col = 1

                if is_page_col == 1:
                    let mut cur: vector[int] = []
                    let mut ci0: int = 0
                    while ci0 < len(idx_list):
                        cur.push(idx_list[ci0])
                        ci0 = ci0 + 1

                    let mut group_field: string = ""
                    let mut psi: int = 1
                    while psi < len(pipe_segs):
                        seg := pipe_segs[psi]
                        let mut fname: string = seg
                        let mut farg: string = ""
                        colp := ssg_find_from(seg, ":", 0)
                        if colp > 0:
                            fname = ssg_lower(ssg_trim(substring(seg, 0, colp)))
                            farg = ssg_trim(substring(seg, colp + 1, string_length(seg) - colp - 1))
                        else:
                            fname = ssg_lower(ssg_trim(seg))
                            if ssg_contains(fname, " reversed") == 1:
                                reversed = 1
                                fname = ssg_trim(ssg_replace_all(fname, "reversed", ""))

                        if fname == "where":
                            let mut wf: string = ""
                            let mut wv: string = ""
                            _tmpl_parse_pipe_two_args(farg, wf, wv)
                            let mut nxt: vector[int] = []
                            let mut wi: int = 0
                            while wi < len(cur):
                                p_item := ctx.items[cur[wi]]
                                fv := _tmpl_item_field(p_item, wf)
                                if fv == wv or ((wf == "tags" or wf == "categories") and ssg_contains(fv, wv) == 1):
                                    nxt.push(cur[wi])
                                wi = wi + 1
                            cur = nxt
                        elif fname == "sort":
                            let mut sf: string = ssg_strip_quotes(farg)
                            if string_length(sf) == 0: sf = "title"
                            let mut ai: int = 1
                            while ai < len(cur):
                                ki := cur[ai]
                                kv := _tmpl_item_field(ctx.items[ki], sf)
                                let mut aj: int = ai - 1
                                while aj >= 0:
                                    if _tmpl_item_field(ctx.items[cur[aj]], sf) <= kv:
                                        break
                                    cur[aj + 1] = cur[aj]
                                    aj = aj - 1
                                cur[aj + 1] = ki
                                ai = ai + 1
                        elif fname == "reverse" or fname == "reversed":
                            reversed = 1 - reversed
                        elif fname == "uniq":
                            let mut nxt: vector[int] = []
                            seen_u := dict[string, int]()
                            let mut ui: int = 0
                            while ui < len(cur):
                                ukey := ctx.items[cur[ui]].url
                                if seen_u.has(ukey) == 0:
                                    seen_u[ukey] = 1
                                    nxt.push(cur[ui])
                                ui = ui + 1
                            cur = nxt
                        elif fname == "slice":
                            let mut sa0: string = ""
                            let mut sa1: string = ""
                            _tmpl_parse_pipe_two_args(farg, sa0, sa1)
                            s_off := ssg_parse_int(sa0, 0)
                            s_len := ssg_parse_int(sa1, len(cur))
                            let mut nxt: vector[int] = []
                            let mut si2: int = s_off
                            while si2 >= 0 and si2 < len(cur) and len(nxt) < s_len:
                                nxt.push(cur[si2])
                                si2 = si2 + 1
                            cur = nxt
                        elif fname == "limit":
                            lim_v := ssg_parse_int(ssg_strip_quotes(farg), limit_n)
                            if lim_v < limit_n: limit_n = lim_v
                        elif fname == "group_by":
                            group_field = ssg_strip_quotes(farg)
                        psi = psi + 1

                    if string_length(group_field) > 0:
                        let mut g_names: vector[string] = []
                        let mut g_pools: vector[string] = []
                        g_map := dict[string, int]()
                        let mut gi: int = 0
                        while gi < len(cur):
                            gval := _tmpl_item_field(ctx.items[cur[gi]], group_field)
                            if g_map.has(gval) == 0:
                                g_map[gval] = len(g_names)
                                g_names.push(gval)
                                g_pools.push(str(cur[gi]))
                            else:
                                slot_g := g_map[gval]
                                g_pools[slot_g] = g_pools[slot_g] + "," + str(cur[gi])
                            gi = gi + 1
                        let mut g_tot: int = len(g_names)
                        if limit_n < g_tot: g_tot = limit_n
                        let mut gki: int = 0
                        while gki < g_tot:
                            let mut gi_src: int = gki
                            if reversed == 1: gi_src = len(g_names) - 1 - gki
                            lvars := _tmpl_clone_dict(vars)
                            lvars[loop_var + ".name"] = g_names[gi_src]
                            csv_g := g_pools[gi_src]
                            lvars[loop_var + ".size"] = str(len(ssg_split(csv_g, ",")))
                            lvars["__pool:" + loop_var + ".items"] = csv_g
                            lvars["forloop.index"] = str(gki + 1)
                            lvars["forloop.index0"] = str(gki)
                            lvars["forloop.length"] = str(g_tot)
                            sb_append(sb, _tmpl_render_internal(tr, inner, lvars, ctx, depth + 1))
                            gki = gki + 1
                    else:
                        total := len(cur)
                        let mut max_c: int = total
                        if limit_n < max_c: max_c = limit_n
                        let mut li: int = 0
                        while li < max_c:
                            let mut src_i: int = cur[li]
                            if reversed == 1:
                                src_i = cur[total - 1 - li]
                            p := ctx.items[src_i]
                            lvars := _tmpl_clone_dict(vars)
                            _tmpl_bind_page_item(lvars, loop_var, p)
                            lvars["forloop.index"] = str(li + 1)
                            lvars["forloop.index0"] = str(li)
                            lvars["forloop.length"] = str(max_c)
                            if li == 0: lvars["forloop.first"] = "true"
                            else: lvars["forloop.first"] = "false"
                            if li == max_c - 1: lvars["forloop.last"] = "true"
                            else: lvars["forloop.last"] = "false"
                            sb_append(sb, _tmpl_render_internal(tr, inner, lvars, ctx, depth + 1))
                            li = li + 1
                // Case B: site.data.<dataset> or nested row array (e.g. sec.items) structured records
                elif ssg_starts_with(col_expr, "site.data.") == 1 or (ssg_find_from(col_expr, ".", 0) > 0 and vars.has("__prefix:" + substring(col_expr, 0, ssg_find_from(col_expr, ".", 0))) == 1):
                    let mut ds_key: string = ""
                    if ssg_starts_with(col_expr, "site.data.") == 1:
                        ds_key = substring(col_expr, 10, string_length(col_expr) - 10)
                    else:
                        dp := ssg_find_from(col_expr, ".", 0)
                        rn := substring(col_expr, 0, dp)
                        rr := substring(col_expr, dp + 1, string_length(col_expr) - dp - 1)
                        ds_key = vars["__prefix:" + rn] + "." + rr
                    let mut row_count: int = 0
                    if ctx.data.list_counts.has(ds_key) == 1:
                        row_count = ctx.data.list_counts[ds_key]
                    if limit_n < row_count: row_count = limit_n
                    let mut ri: int = 0
                    dkeys := ctx.data.flat.keys()
                    while ri < row_count:
                        lvars := _tmpl_clone_dict(vars)
                        row_pfx := ds_key + "[" + str(ri) + "]"
                        rec_prefix := row_pfx + "."
                        plen := string_length(rec_prefix)
                        lvars["__prefix:" + loop_var] = row_pfx
                        let mut dki: int = 0
                        while dki < len(dkeys):
                            dk := dkeys[dki]
                            if ssg_starts_with(dk, rec_prefix) == 1:
                                field := substring(dk, plen, string_length(dk) - plen)
                                lvars[loop_var + "." + field] = ctx.data.flat[dk]
                            dki = dki + 1
                        lvars["forloop.index"] = str(ri + 1)
                        lvars["forloop.index0"] = str(ri)
                        lvars["forloop.length"] = str(row_count)
                        sb_append(sb, _tmpl_render_internal(tr, inner, lvars, ctx, depth + 1))
                        ri = ri + 1
                // Case C: Simple string list (with | uniq | sort | reverse | slice pipes)
                else:
                    let mut str_items: vector[string] = []
                    if ctx.lists.has(col_expr) == 1:
                        str_items = ssg_split(ctx.lists[col_expr], "\t")
                    else:
                        raw_str := _tmpl_eval_output_expr(rest, vars, ctx)
                        if string_length(raw_str) > 0:
                            str_items = ssg_split(raw_str, ",")
                    total := len(str_items)
                    let mut max_c: int = total
                    if limit_n < max_c: max_c = limit_n
                    let mut li: int = 0
                    while li < max_c:
                        let mut val: string = ssg_trim(str_items[li])
                        if reversed == 1:
                            val = ssg_trim(str_items[total - 1 - li])
                        if string_length(val) > 0:
                            lvars := _tmpl_clone_dict(vars)
                            lvars[loop_var] = val
                            lvars["forloop.index"] = str(li + 1)
                            lvars["forloop.index0"] = str(li)
                            lvars["forloop.length"] = str(max_c)
                            sb_append(sb, _tmpl_render_internal(tr, inner, lvars, ctx, depth + 1))
                        li = li + 1

            close_end := ssg_find_from(tmpl, "%}", endfor_pos + 2)
            pos = close_end + 2
            continue

        // Skip unrecognized tags cleanly
        pos = end_t + 2

    out := sb_to_str(sb)
    sb_free(sb)
    return out

// ------------------------------------------------------------------------------
// Multi-Level Layout Inheritance Chain Renderer
// ------------------------------------------------------------------------------

fn _template_resolve_key(tr: TemplateRegistry, name: string) -> string:
    if tr.layout_bodies.has(name) == 1:
        return name
    base := ssg_path_stem(name)
    if tr.layout_bodies.has(base) == 1:
        return base
    if tr.layout_bodies.has("default") == 1:
        return "default"
    if len(tr.layout_names) > 0:
        return tr.layout_names[0]
    return ""

fn _template_v2_render_impl(tr: TemplateRegistry, layout_name: string, body_html: string, page_vars: dict[string, string], ctx: RenderContext, clone_first: int) -> string:
    let mut cur_content: string = body_html
    let mut cur_layout: string = layout_name
    if string_length(cur_layout) == 0:
        cur_layout = "default"
    let mut hops: int = 0
    while string_length(cur_layout) > 0 and cur_layout != "none" and hops < 8:
        key := _template_resolve_key(tr, cur_layout)
        let mut parent_layout: string = ""
        let mut lbody: string = ""
        if string_length(key) > 0:
            lbody = tr.layout_bodies[key]
            parent_layout = tr.layout_parents[key]
        else:
            raw := template_get_layout(tr, cur_layout)
            fm := fm_parse_document(raw)
            lbody = fm.body
            if fm.fields.has("layout") == 1:
                parent_layout = fm.fields["layout"]
        let mut vars: dict[string, string] = page_vars
        let mut owns_vars: int = 0
        if clone_first == 1 or hops > 0:
            vars = _tmpl_clone_dict(page_vars)
            owns_vars = 1
        vars["content"] = cur_content
        vars["site_name"] = ctx.config.site_name
        vars["site_tagline"] = ctx.config.site_tagline
        vars["base_url"] = ctx.config.base_url
        vars["year"] = "2026"
        cur_content = _tmpl_render_internal(tr, lbody, vars, ctx, 0)
        if owns_vars == 1:
            dict_free(vars)
        if parent_layout == cur_layout:
            break
        cur_layout = parent_layout
        hops = hops + 1
    return cur_content

fn template_v2_render(tr: TemplateRegistry, layout_name: string, body_html: string, page_vars: dict[string, string], ctx: RenderContext) -> string:
    return _template_v2_render_impl(tr, layout_name, body_html, page_vars, ctx, 1)

fn template_v2_render_owned(tr: TemplateRegistry, layout_name: string, body_html: string, page_vars: dict[string, string], ctx: RenderContext) -> string:
    return _template_v2_render_impl(tr, layout_name, body_html, page_vars, ctx, 0)
