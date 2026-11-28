// ==============================================================================
// Module:      Astro-Style .clx Component Compiler (src/clx_compiler.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Compiles .clx component & page files with --- frontmatter scripts,
//              props ({props.title} / {title}), default & named <slot />, and
//              <style scoped> with deterministic .clx-<hash> CSS scoping.
// ==============================================================================

import "src/strbuf.cl"
import "src/fs_walk.cl"
import "src/markdown.cl"

model ClxComponent:
    name: string
    script_src: string
    template_html: string
    scoped_css: string
    scope_class: string

model ClxRegistry:
    components: vector[ClxComponent]
    by_name: dict[string, int]

fn clx_registry_new() -> ClxRegistry:
    let cs: vector[ClxComponent] = []
    return ClxRegistry(cs, dict[string, int]())

fn _clx_scope_css(css_raw: string, scope_cls: string) -> string:
    // Prefix CSS selectors outside @media / comments with .clx-<hash> for strict scoping
    tlen := string_length(css_raw)
    if tlen == 0:
        return ""
    sb := sb_new_cap(tlen + 64)
    let mut pos: int = 0
    while pos < tlen:
        ob := ssg_find_from(css_raw, "{", pos)
        if ob < 0:
            sb_append_slice(sb, css_raw, pos, tlen - pos)
            break
        sel := ssg_trim(substring(css_raw, pos, ob - pos))
        cb := ssg_find_from(css_raw, "}", ob + 1)
        if cb < 0:
            sb_append_slice(sb, css_raw, pos, tlen - pos)
            break
        block := substring(css_raw, ob, cb - ob + 1)
        if ssg_starts_with(sel, "@") == 1 or ssg_starts_with(sel, ":root") == 1:
            sb_append(sb, sel + " " + block + "\n")
        else:
            sels := ssg_split(sel, ",")
            let mut si: int = 0
            while si < len(sels):
                if si > 0: sb_append(sb, ", ")
                s_item := ssg_trim(sels[si])
                sb_append(sb, "." + scope_cls + " " + s_item + ", " + s_item + "." + scope_cls)
                si = si + 1
            sb_append(sb, " " + block + "\n")
        pos = cb + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn clx_parse_component(name: string, raw: string) -> ClxComponent:
    let mut script_src: string = ""
    let mut rest: string = raw
    lines := ssg_split_lines(raw)
    if len(lines) > 0 and ssg_trim(lines[0]) == "---":
        let mut end_i: int = -1
        let mut i: int = 1
        while i < len(lines):
            if ssg_trim(lines[i]) == "---":
                end_i = i
                break
            i = i + 1
        if end_i > 0:
            sc_sb := sb_new()
            let mut si: int = 1
            while si < end_i:
                sb_append(sc_sb, lines[si])
                sb_append_byte(sc_sb, 10)
                si = si + 1
            script_src = sb_to_str(sc_sb)
            sb_free(sc_sb)

            rm_sb := sb_new()
            let mut ri: int = end_i + 1
            while ri < len(lines):
                sb_append(rm_sb, lines[ri])
                sb_append_byte(rm_sb, 10)
                ri = ri + 1
            rest = sb_to_str(rm_sb)
            sb_free(rm_sb)

    let mut scoped_css: string = ""
    scope_cls := "clx-" + ssg_fnv1a_hash(name + "|" + raw)

    // Extract <style scoped>...</style> or <style>...</style>
    let mut s_start: int = ssg_find_from(rest, "<style", 0)
    if s_start >= 0:
        tag_close := ssg_find_from(rest, ">", s_start)
        s_end := ssg_find_from(rest, "</style>", tag_close)
        if tag_close > s_start and s_end > tag_close:
            raw_css := substring(rest, tag_close + 1, s_end - tag_close - 1)
            scoped_css = _clx_scope_css(raw_css, scope_cls)
            rest = substring(rest, 0, s_start) + substring(rest, s_end + 8, string_length(rest) - (s_end + 8))

    return ClxComponent(name, script_src, ssg_trim(rest), scoped_css, scope_cls)

fn clx_load_all(site_dir: string) -> ClxRegistry:
    reg := clx_registry_new()
    let mut dirs: vector[string] = []
    dirs.push(ssg_path_join(site_dir, "components"))
    dirs.push(ssg_path_join(site_dir, "layouts"))

    let mut exts: vector[string] = []
    exts.push(".clx")

    let mut di: int = 0
    while di < len(dirs):
        d := dirs[di]
        if fs_is_dir(d) == 1:
            scan := fs_walk_tree(d, exts)
            let mut fi: int = 0
            while fi < len(scan.abs_paths):
                ap := scan.abs_paths[fi]
                cname := ssg_path_stem(ap)
                comp := clx_parse_component(cname, file_read(ap))
                reg.by_name[cname] = len(reg.components)
                reg.components.push(comp)
                fi = fi + 1
        di = di + 1
    return reg

fn _clx_eval_frontmatter_vars(script_src: string, env: dict[string, string]) -> void:
    if string_length(script_src) == 0:
        return
    lines := ssg_split_lines(script_src)
    let mut i: int = 0
    while i < len(lines):
        ln := ssg_trim(lines[i])
        if string_length(ln) == 0 or ssg_starts_with(ln, "//") == 1 or ssg_starts_with(ln, "#") == 1:
            i = i + 1
            continue
        // Support: let x = "val", x := "val", const x = "val"
        let mut s: string = ln
        if ssg_starts_with(s, "let mut ") == 1: s = substring(s, 8, string_length(s) - 8)
        elif ssg_starts_with(s, "let ") == 1: s = substring(s, 4, string_length(s) - 4)
        elif ssg_starts_with(s, "const ") == 1: s = substring(s, 6, string_length(s) - 6)
        colon_eq := ssg_find_from(s, ":=", 0)
        eq := ssg_find_from(s, "=", 0)
        if colon_eq > 0:
            k := ssg_trim(substring(s, 0, colon_eq))
            v := ssg_strip_quotes(substring(s, colon_eq + 2, string_length(s) - colon_eq - 2))
            env[k] = v
        elif eq > 0:
            k := ssg_trim(substring(s, 0, eq))
            // Handle simple prop default e.g. title: string = "Hello"
            col := ssg_find_from(k, ":", 0)
            if col > 0:
                k = ssg_trim(substring(k, 0, col))
            v := ssg_strip_quotes(substring(s, eq + 1, string_length(s) - eq - 1))
            if env.has(k) == 0:
                env[k] = v
        i = i + 1

fn _clx_parse_props_from_tag(tag_hdr: string, parent_vars: dict[string, string], env: dict[string, string]) -> void:
    // Scan key="val" and key={expr}
    tlen := string_length(tag_hdr)
    let mut pos: int = 0
    while pos < tlen:
        eq := ssg_find_from(tag_hdr, "=", pos)
        if eq < 0:
            break
        // Walk backwards for attribute name
        let mut ks: int = eq - 1
        while ks >= 0 and byte_at(tag_hdr, ks) != 32 and byte_at(tag_hdr, ks) != 9:
            ks = ks - 1
        aname := ssg_trim(substring(tag_hdr, ks + 1, eq - ks - 1))
        if eq + 1 >= tlen:
            break
        ch := byte_at(tag_hdr, eq + 1)
        if ch == 34 or ch == 39:
            end_q := ssg_find_from(tag_hdr, substring(tag_hdr, eq + 1, 1), eq + 2)
            if end_q > eq + 1:
                aval := substring(tag_hdr, eq + 2, end_q - eq - 2)
                env[aname] = aval
                env["props." + aname] = aval
                pos = end_q + 1
                continue
        elif ch == 123:
            end_b := ssg_find_from(tag_hdr, "}", eq + 2)
            if end_b > eq + 1:
                expr := ssg_trim(substring(tag_hdr, eq + 2, end_b - eq - 2))
                let mut aval: string = ssg_strip_quotes(expr)
                if parent_vars.has(expr) == 1:
                    aval = parent_vars[expr]
                env[aname] = aval
                env["props." + aname] = aval
                pos = end_b + 1
                continue
        pos = eq + 1

fn _clx_extract_named_slots(inner: string, named: dict[string, string]) -> string:
    tlen := string_length(inner)
    if tlen == 0 or ssg_contains(inner, "slot=") == 0:
        return inner
    sb := sb_new_cap(tlen + 32)
    let mut pos: int = 0
    while pos < tlen:
        op := ssg_find_from(inner, "<", pos)
        if op < 0:
            sb_append_slice(sb, inner, pos, tlen - pos)
            break
        if op > pos:
            sb_append_slice(sb, inner, pos, op - pos)
        gt := ssg_find_from(inner, ">", op + 1)
        if gt < 0:
            sb_append_slice(sb, inner, op, tlen - op)
            break
        open_tag := substring(inner, op, gt - op + 1)
        if ssg_contains(open_tag, "slot=") == 1 and ssg_starts_with(open_tag, "</") == 0:
            // Extract tag name and slot="name"
            let mut sp: int = 1
            while sp < string_length(open_tag):
                ch := byte_at(open_tag, sp)
                if ch == 32 or ch == 9 or ch == 62 or ch == 47:
                    break
                sp = sp + 1
            tname := substring(open_tag, 1, sp - 1)
            sa := ssg_find_from(open_tag, "slot=\"", 0)
            let mut sname: string = ""
            if sa >= 0:
                qe := ssg_find_from(open_tag, "\"", sa + 6)
                if qe > sa + 6:
                    sname = substring(open_tag, sa + 6, qe - (sa + 6))
            if string_length(sname) > 0:
                if ssg_ends_with(open_tag, "/>") == 1:
                    named[sname] = ""
                    pos = gt + 1
                    continue
                close_t := "</" + tname + ">"
                open_p := "<" + tname
                let mut depth: int = 1
                let mut cur: int = gt + 1
                let mut found_end: int = -1
                while cur < tlen:
                    nc := ssg_find_from(inner, close_t, cur)
                    if nc < 0:
                        break
                    no := ssg_find_from(inner, open_p, cur)
                    if no >= 0 and no < nc:
                        nb_ch := byte_at(inner, no + string_length(open_p))
                        if nb_ch == 32 or nb_ch == 62:
                            depth = depth + 1
                            cur = no + string_length(open_p)
                            continue
                    depth = depth - 1
                    if depth == 0:
                        found_end = nc
                        break
                    cur = nc + string_length(close_t)
                if found_end >= 0:
                    slot_html := substring(inner, gt + 1, found_end - (gt + 1))
                    if string_length(tname) == 8 and tname == "template":
                        named[sname] = slot_html
                    else:
                        named[sname] = substring(inner, op, found_end + string_length(close_t) - op)
                    pos = found_end + string_length(close_t)
                    continue
        sb_append_slice(sb, inner, op, gt - op + 1)
        pos = gt + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return ssg_trim(out)

fn _clx_replace_slots(tmpl: string, def_slot: string, named: dict[string, string]) -> string:
    tlen := string_length(tmpl)
    if ssg_contains(tmpl, "<slot") == 0:
        return tmpl
    sb := sb_new_cap(tlen + string_length(def_slot) + 64)
    let mut pos: int = 0
    while pos < tlen:
        idx := ssg_find_from(tmpl, "<slot", pos)
        if idx < 0:
            sb_append_slice(sb, tmpl, pos, tlen - pos)
            break
        if idx > pos:
            sb_append_slice(sb, tmpl, pos, idx - pos)
        // Ensure next char after "<slot" is whitespace, '>', or '/'
        if idx + 5 < tlen:
            nx := byte_at(tmpl, idx + 5)
            if nx != 32 and nx != 9 and nx != 62 and nx != 47:
                sb_append_slice(sb, tmpl, idx, 5)
                pos = idx + 5
                continue
        gt := ssg_find_from(tmpl, ">", idx + 5)
        if gt < 0:
            sb_append_slice(sb, tmpl, idx, tlen - idx)
            break
        tag_open := substring(tmpl, idx, gt - idx + 1)
        let mut fallback: string = ""
        let mut next_pos: int = gt + 1
        if ssg_ends_with(tag_open, "/>") == 0:
            cend := ssg_find_from(tmpl, "</slot>", gt + 1)
            if cend >= 0:
                fallback = substring(tmpl, gt + 1, cend - (gt + 1))
                next_pos = cend + 7
        let mut sname: string = ""
        ns_idx := ssg_find_from(tag_open, "name=\"", 0)
        if ns_idx >= 0:
            qe := ssg_find_from(tag_open, "\"", ns_idx + 6)
            if qe > ns_idx + 6:
                sname = substring(tag_open, ns_idx + 6, qe - (ns_idx + 6))
        if string_length(sname) > 0:
            if named.has(sname) == 1:
                sb_append(sb, named[sname])
            else:
                sb_append(sb, fallback)
        else:
            if string_length(def_slot) > 0:
                sb_append(sb, def_slot)
            else:
                sb_append(sb, fallback)
        pos = next_pos
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn _clx_render_component_rec(reg: ClxRegistry, call: ClxTagCall, parent_vars: dict[string, string], &out_css: string, depth: int) -> string:
    if depth > 16:
        return call.inner_html
    if reg.by_name.has(call.name) == 0:
        return "<div class=\"clx-missing\" data-component=\"" + ssg_escape_html(call.name) + "\">" + call.inner_html + "</div>"
    comp := reg.components[reg.by_name[call.name]]
    env := dict[string, string]()
    _clx_parse_props_from_tag(call.props, parent_vars, env)
    _clx_eval_frontmatter_vars(comp.script_src, env)

    named_slots := dict[string, string]()
    def_slot := _clx_extract_named_slots(call.inner_html, named_slots)
    let mut html: string = _clx_replace_slots(comp.template_html, def_slot, named_slots)

    // Replace {key} and {props.key} interpolations (preserving {{ ... }} Liquid tags)
    eks := env.keys()
    let mut ki: int = 0
    while ki < len(eks):
        ek := eks[ki]
        html = ssg_replace_all(html, "{" + ek + "}", ssg_escape_html(env[ek]))
        ki = ki + 1

    // Recursively expand nested .clx components inside rendered template
    if ssg_contains(html, "<") == 1:
        hlen := string_length(html)
        sb := sb_new_cap(hlen + 64)
        let mut pos: int = 0
        let mut did_expand: int = 0
        while pos < hlen:
            lt := ssg_find_from(html, "<", pos)
            if lt < 0:
                sb_append_slice(sb, html, pos, hlen - pos)
                break
            if lt > pos:
                sb_append_slice(sb, html, pos, lt - pos)
            if lt + 1 < hlen and byte_at(html, lt + 1) >= 65 and byte_at(html, lt + 1) <= 90:
                let mut sp: int = lt + 1
                while sp < hlen:
                    ch := byte_at(html, sp)
                    if ch == 32 or ch == 9 or ch == 47 or ch == 62:
                        break
                    sp = sp + 1
                cname := substring(html, lt + 1, sp - (lt + 1))
                gt := ssg_find_from(html, ">", sp)
                if reg.by_name.has(cname) == 1 and gt >= sp:
                    tag_hdr := substring(html, lt, gt - lt + 1)
                    let mut inner_sub: string = ""
                    let mut after_pos: int = gt + 1
                    if ssg_ends_with(tag_hdr, "/>") == 0:
                        close_t := "</" + cname + ">"
                        open_p := "<" + cname
                        let mut cdepth: int = 1
                        let mut cur: int = gt + 1
                        let mut found_e: int = -1
                        while cur < hlen:
                            nc := ssg_find_from(html, close_t, cur)
                            if nc < 0:
                                break
                            no := ssg_find_from(html, open_p, cur)
                            if no >= 0 and no < nc:
                                nb_ch := byte_at(html, no + string_length(open_p))
                                if nb_ch == 32 or nb_ch == 62 or nb_ch == 47:
                                    cdepth = cdepth + 1
                                    cur = no + string_length(open_p)
                                    continue
                            cdepth = cdepth - 1
                            if cdepth == 0:
                                found_e = nc
                                break
                            cur = nc + string_length(close_t)
                        if found_e >= 0:
                            inner_sub = substring(html, gt + 1, found_e - (gt + 1))
                            after_pos = found_e + string_length(close_t)
                    sub_call := ClxTagCall(cname, tag_hdr, inner_sub, "")
                    sb_append(sb, _clx_render_component_rec(reg, sub_call, env, out_css, depth + 1))
                    did_expand = 1
                    pos = after_pos
                    continue
            sb_append_byte(sb, 60)
            pos = lt + 1
        if did_expand == 1:
            html = sb_to_str(sb)
        sb_free(sb)

    if string_length(comp.scoped_css) > 0:
        out_css = out_css + "\n" + comp.scoped_css
        html = "<div class=\"" + comp.scope_class + "\">" + html + "</div>"
    return html

fn clx_render_component(reg: ClxRegistry, call: ClxTagCall, parent_vars: dict[string, string], &out_css: string) -> string:
    return _clx_render_component_rec(reg, call, parent_vars, out_css, 0)

fn clx_expand_calls(reg: ClxRegistry, calls: vector[ClxTagCall], html: string, parent_vars: dict[string, string]) -> string:
    if len(calls) == 0:
        return html
    let mut out: string = html
    let mut collected_css: string = ""
    let mut i: int = 0
    while i < len(calls):
        c := calls[i]
        rendered := clx_render_component(reg, c, parent_vars, collected_css)
        out = ssg_replace_all(out, c.placeholder_id, rendered)
        i = i + 1
    if string_length(collected_css) > 0:
        style_block := "\n<style data-clx-scoped>\n" + collected_css + "\n</style>\n</head>"
        if ssg_contains(out, "</head>") == 1:
            out = ssg_replace_all(out, "</head>", style_block)
        else:
            out = "<style data-clx-scoped>\n" + collected_css + "\n</style>\n" + out
    return out
