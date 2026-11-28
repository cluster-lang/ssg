// ==============================================================================
// Module:      YAML / TOML / CLD Frontmatter & Data Engine (src/frontmatter.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Parses YAML (---), TOML (+++), and .cld (===) frontmatter headers
//              including nested maps and lists, Jekyll YYYY-MM-DD filenames, and
//              recursive site/data/ (_data/) .yml/.yaml/.toml/.json datasets.
// ==============================================================================

import "src/strbuf.cl"
import "src/fs_walk.cl"

model FrontmatterData:
    fields: dict[string, string]
    list_keys: dict[string, string]
    raw_meta: string
    body: string
    body_start_line: int

model DataRegistry:
    // Flat access: site.data.nav[0].title -> "...", site.data.site.author -> "..."
    flat: dict[string, string]
    // List length for datasets like site.data.nav -> count, row prefix "site.data.nav[i]."
    list_counts: dict[string, int]

fn fm_new_empty(body: string) -> FrontmatterData:
    fm := FrontmatterData()
    fm.body = body
    fm.body_start_line = 1
    return fm

fn _fm_line_indent(raw: string) -> int:
    n := string_length(raw)
    let mut i: int = 0
    while i < n:
        b := byte_at(raw, i)
        if b == 32:
            i = i + 1
        elif b == 9:
            i = i + 2
        else:
            break
    return i

fn _fm_strip_yaml_comment(v: string) -> string:
    t := ssg_trim(v)
    tlen := string_length(t)
    if tlen == 0:
        return ""
    if byte_at(t, 0) == 34 or byte_at(t, 0) == 39:
        return ssg_strip_quotes(t)
    let mut i: int = 0
    while i < tlen:
        if byte_at(t, i) == 35 and i > 0 and byte_at(t, i - 1) == 32:
            return ssg_trim(substring(t, 0, i))
        i = i + 1
    return t

fn _fm_parse_inline_list(raw: string) -> vector[string]:
    let mut out: vector[string] = []
    t := ssg_trim(raw)
    tlen := string_length(t)
    if tlen >= 2 and byte_at(t, 0) == 91 and byte_at(t, tlen - 1) == 93:
        inner := substring(t, 1, tlen - 2)
        parts := ssg_split(inner, ",")
        let mut i: int = 0
        while i < len(parts):
            item := ssg_strip_quotes(parts[i])
            if string_length(item) > 0:
                out.push(item)
            i = i + 1
    else:
        parts := ssg_split(t, ",")
        let mut i: int = 0
        while i < len(parts):
            item := ssg_strip_quotes(parts[i])
            if string_length(item) > 0:
                out.push(item)
            i = i + 1
    return out

fn _fm_append_list_item(lists: dict[string, string], key: string, val: string) -> int:
    if lists.has(key) == 1:
        cur := lists[key]
        lists[key] = cur + "\t" + val
        return len(ssg_split(cur, "\t")) + 1
    lists[key] = val
    return 1

fn _fm_set_list(lists: dict[string, string], key: string, arr: vector[string]) -> string:
    let mut tjoined: string = ""
    let mut cjoined: string = ""
    let mut ai: int = 0
    while ai < len(arr):
        if ai > 0:
            tjoined = tjoined + "\t"
            cjoined = cjoined + ","
        tjoined = tjoined + arr[ai]
        cjoined = cjoined + arr[ai]
        ai = ai + 1
    lists[key] = tjoined
    return cjoined

fn fm_parse_yaml_lines(lines: vector[string], start_idx: int, end_idx: int, fields: dict[string, string], lists: dict[string, string]) -> void:
    let mut prefix_stack: vector[string] = []
    let mut indent_stack: vector[int] = []
    let mut cur_list_key: string = ""
    let mut cur_list_indent: int = -1

    let mut i: int = start_idx
    while i < end_idx:
        raw := lines[i]
        trimmed := ssg_trim(raw)
        if string_length(trimmed) == 0 or ssg_starts_with(trimmed, "#") == 1:
            i = i + 1
            continue

        ind := _fm_line_indent(raw)

        // Check list item: - value
        if ssg_starts_with(trimmed, "- ") == 1 or trimmed == "-":
            let mut item_raw: string = ""
            if string_length(trimmed) > 2:
                item_raw = ssg_trim(substring(trimmed, 2, string_length(trimmed) - 2))
            if string_length(cur_list_key) > 0:
                // Support "- key: val" object list items -> cur_list_key[idx].key
                col_pos := ssg_find_from(item_raw, ":", 0)
                if col_pos > 0 and ssg_find_from(item_raw, "://", 0) != col_pos:
                    cnt := _fm_append_list_item(lists, cur_list_key, "item")
                    idx := cnt - 1
                    rk := ssg_trim(substring(item_raw, 0, col_pos))
                    rv := _fm_strip_yaml_comment(substring(item_raw, col_pos + 1, string_length(item_raw) - col_pos - 1))
                    fields[cur_list_key + "[" + str(idx) + "]." + rk] = rv
                    prefix_stack.push(cur_list_key + "[" + str(idx) + "]")
                    indent_stack.push(ind + 1)
                else:
                    val := _fm_strip_yaml_comment(item_raw)
                    _fm_append_list_item(lists, cur_list_key, val)
                    fields[cur_list_key] = ssg_replace_all(lists[cur_list_key], "\t", ",")
            i = i + 1
            continue

        // Pop indentation stack to current level
        while len(indent_stack) > 0:
            if indent_stack[len(indent_stack) - 1] < ind:
                break
            indent_stack.pop()
            prefix_stack.pop()

        if cur_list_indent >= 0 and ind <= cur_list_indent:
            cur_list_key = ""
            cur_list_indent = -1

        col := ssg_find_from(trimmed, ":", 0)
        if col > 0:
            k := ssg_trim(substring(trimmed, 0, col))
            v_part := ssg_trim(substring(trimmed, col + 1, string_length(trimmed) - col - 1))
            let mut full_k: string = k
            if len(prefix_stack) > 0:
                full_k = prefix_stack[len(prefix_stack) - 1] + "." + k

            if string_length(v_part) == 0:
                cur_list_key = full_k
                cur_list_indent = ind
                prefix_stack.push(full_k)
                indent_stack.push(ind)
            elif ssg_starts_with(v_part, "[") == 1 and ssg_ends_with(v_part, "]") == 1:
                arr := _fm_parse_inline_list(v_part)
                fields[full_k] = _fm_set_list(lists, full_k, arr)
            else:
                v_clean := _fm_strip_yaml_comment(v_part)
                fields[full_k] = v_clean
                if ssg_contains(v_clean, ",") == 1 and (k == "tags" or k == "categories"):
                    _fm_set_list(lists, full_k, _fm_parse_inline_list(v_clean))
        i = i + 1

fn fm_parse_toml_lines(lines: vector[string], start_idx: int, end_idx: int, fields: dict[string, string], lists: dict[string, string]) -> void:
    let mut section: string = ""
    let mut i: int = start_idx
    while i < end_idx:
        ln := ssg_trim(lines[i])
        if string_length(ln) == 0 or ssg_starts_with(ln, "#") == 1:
            i = i + 1
            continue
        if ssg_starts_with(ln, "[") == 1 and ssg_ends_with(ln, "]") == 1:
            section = ssg_trim(substring(ln, 1, string_length(ln) - 2))
            i = i + 1
            continue
        eq := ssg_find_from(ln, "=", 0)
        if eq > 0:
            k := ssg_trim(substring(ln, 0, eq))
            v_part := ssg_trim(substring(ln, eq + 1, string_length(ln) - eq - 1))
            let mut full_k: string = k
            if string_length(section) > 0:
                full_k = section + "." + k
            if ssg_starts_with(v_part, "[") == 1 and ssg_ends_with(v_part, "]") == 1:
                arr := _fm_parse_inline_list(v_part)
                fields[full_k] = _fm_set_list(lists, full_k, arr)
            else:
                fields[full_k] = ssg_strip_quotes(v_part)
        i = i + 1

fn fm_parse_document(raw_text: string) -> FrontmatterData:
    lines := ssg_split_lines(raw_text)
    fm := FrontmatterData()
    fields := fm.fields
    lists := fm.list_keys
    n := len(lines)
    if n == 0:
        fm.body = raw_text
        fm.body_start_line = 1
        return fm

    first := ssg_trim(lines[0])
    // Case 1: Standard YAML frontmatter (--- ... ---)
    if first == "---":
        let mut end_i: int = -1
        let mut i: int = 1
        while i < n:
            if ssg_trim(lines[i]) == "---":
                end_i = i
                break
            i = i + 1
        if end_i > 0:
            fm_parse_yaml_lines(lines, 1, end_i, fields, lists)
            sb := sb_new_cap(string_length(raw_text))
            let mut bi: int = end_i + 1
            while bi < n:
                sb_append(sb, lines[bi])
                if bi + 1 < n:
                    sb_append_byte(sb, 10)
                bi = bi + 1
            fm.body = sb_to_str(sb)
            sb_free(sb)
            fm.body_start_line = end_i + 2
            list_free(lines)
            return fm

    // Case 2: Hugo TOML frontmatter (+++ ... +++)
    if first == "+++":
        let mut end_i: int = -1
        let mut i: int = 1
        while i < n:
            if ssg_trim(lines[i]) == "+++":
                end_i = i
                break
            i = i + 1
        if end_i > 0:
            fm_parse_toml_lines(lines, 1, end_i, fields, lists)
            sb := sb_new_cap(string_length(raw_text))
            let mut bi: int = end_i + 1
            while bi < n:
                sb_append(sb, lines[bi])
                if bi + 1 < n:
                    sb_append_byte(sb, 10)
                bi = bi + 1
            fm.body = sb_to_str(sb)
            sb_free(sb)
            fm.body_start_line = end_i + 2
            list_free(lines)
            return fm

    // Case 3: Native .cld frontmatter (key: val\n...\n===)
    let mut eq_idx: int = -1
    let mut scan_limit: int = n
    if scan_limit > 64:
        scan_limit = 64
    let mut i: int = 0
    while i < scan_limit:
        if ssg_trim(lines[i]) == "===":
            eq_idx = i
            break
        i = i + 1
    if eq_idx >= 0:
        fm_parse_yaml_lines(lines, 0, eq_idx, fields, lists)
        sb := sb_new_cap(string_length(raw_text))
        let mut bi: int = eq_idx + 1
        while bi < n:
            sb_append(sb, lines[bi])
            if bi + 1 < n:
                sb_append_byte(sb, 10)
            bi = bi + 1
        fm.body = sb_to_str(sb)
        sb_free(sb)
        fm.body_start_line = eq_idx + 2
        list_free(lines)
        return fm

    fm.body = raw_text
    fm.body_start_line = 1
    list_free(lines)
    return fm

// Parse Jekyll filename pattern YYYY-MM-DD-my-post-title -> (date, slug)
fn fm_extract_date_from_stem(stem: string, &out_date: string, &out_slug: string) -> void:
    out_date = ""
    out_slug = stem
    if string_length(stem) >= 12:
        // Check YYYY-MM-DD-
        if byte_at(stem, 4) == 45 and byte_at(stem, 7) == 45 and byte_at(stem, 10) == 45:
            let mut all_d: int = 1
            let mut k: int = 0
            while k < 10:
                if k != 4 and k != 7:
                    b := byte_at(stem, k)
                    if b < 48 or b > 57:
                        all_d = 0
                        break
                k = k + 1
            if all_d == 1:
                out_date = substring(stem, 0, 10)
                out_slug = substring(stem, 11, string_length(stem) - 11)

// ------------------------------------------------------------------------------
// Data Registry Loader (site/data/** or _data/**)
// ------------------------------------------------------------------------------

fn _data_json_skip_ws(raw: string, rlen: int, &pos: int) -> void:
    while pos < rlen:
        b := byte_at(raw, pos)
        if b == 32 or b == 9 or b == 10 or b == 13:
            pos = pos + 1
        else:
            break

fn _data_json_read_str(raw: string, rlen: int, &pos: int) -> string:
    if pos >= rlen or byte_at(raw, pos) != 34:
        return ""
    pos = pos + 1
    sb := sb_new_cap(64)
    while pos < rlen:
        b := byte_at(raw, pos)
        if b == 34:
            pos = pos + 1
            break
        if b == 92 and pos + 1 < rlen:
            nb := byte_at(raw, pos + 1)
            if nb == 110: sb_append_byte(sb, 10)
            elif nb == 114: sb_append_byte(sb, 13)
            elif nb == 116: sb_append_byte(sb, 9)
            else: sb_append_byte(sb, nb)
            pos = pos + 2
            continue
        sb_append_byte(sb, b)
        pos = pos + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn _data_walk_json_value(raw: string, rlen: int, &pos: int, prefix: string, flat: dict[string, string], counts: dict[string, int], depth: int) -> void:
    if depth > 32:
        return
    _data_json_skip_ws(raw, rlen, pos)
    if pos >= rlen:
        return
    ch := byte_at(raw, pos)
    if ch == 123:
        pos = pos + 1
        while pos < rlen:
            _data_json_skip_ws(raw, rlen, pos)
            if pos >= rlen or byte_at(raw, pos) == 125:
                if pos < rlen: pos = pos + 1
                break
            if byte_at(raw, pos) == 44:
                pos = pos + 1
                continue
            let mut key: string = ""
            if byte_at(raw, pos) == 34:
                key = _data_json_read_str(raw, rlen, pos)
            else:
                ks := pos
                while pos < rlen and byte_at(raw, pos) != 58 and byte_at(raw, pos) != 125:
                    pos = pos + 1
                key = ssg_trim(substring(raw, ks, pos - ks))
            _data_json_skip_ws(raw, rlen, pos)
            if pos < rlen and byte_at(raw, pos) == 58:
                pos = pos + 1
            next_prefix := prefix + "." + key
            _data_walk_json_value(raw, rlen, pos, next_prefix, flat, counts, depth + 1)
            _data_json_skip_ws(raw, rlen, pos)
            if pos < rlen and byte_at(raw, pos) == 44:
                pos = pos + 1
    elif ch == 91:
        pos = pos + 1
        let mut rec_idx: int = 0
        while pos < rlen:
            _data_json_skip_ws(raw, rlen, pos)
            if pos >= rlen or byte_at(raw, pos) == 93:
                if pos < rlen: pos = pos + 1
                break
            if byte_at(raw, pos) == 44:
                pos = pos + 1
                continue
            item_prefix := prefix + "[" + str(rec_idx) + "]"
            _data_walk_json_value(raw, rlen, pos, item_prefix, flat, counts, depth + 1)
            rec_idx = rec_idx + 1
            _data_json_skip_ws(raw, rlen, pos)
            if pos < rlen and byte_at(raw, pos) == 44:
                pos = pos + 1
        counts[prefix] = rec_idx
    elif ch == 34:
        flat[prefix] = _data_json_read_str(raw, rlen, pos)
    else:
        vs := pos
        while pos < rlen:
            b := byte_at(raw, pos)
            if b == 44 or b == 125 or b == 93 or b == 10 or b == 13 or b == 32 or b == 9:
                break
            pos = pos + 1
        val := ssg_trim(substring(raw, vs, pos - vs))
        if val != "null":
            flat[prefix] = val

fn _data_parse_simple_json_records(dataset_name: string, raw: string, flat: dict[string, string], counts: dict[string, int]) -> void:
    rlen := string_length(raw)
    if rlen == 0:
        return
    let mut pos: int = 0
    _data_walk_json_value(raw, rlen, pos, dataset_name, flat, counts, 0)

fn data_load_all(site_dir: string) -> DataRegistry:
    flat := dict[string, string]()
    counts := dict[string, int]()
    let mut dirs: vector[string] = []
    dirs.push(ssg_path_join(site_dir, "data"))
    dirs.push(ssg_path_join(site_dir, "_data"))

    let mut exts: vector[string] = []
    exts.push(".yml")
    exts.push(".yaml")
    exts.push(".toml")
    exts.push(".json")

    let mut di: int = 0
    while di < len(dirs):
        d := dirs[di]
        if fs_is_dir(d) == 1:
            scan := fs_walk_tree(d, exts)
            let mut fi: int = 0
            while fi < len(scan.abs_paths):
                ap := scan.abs_paths[fi]
                rel := scan.rel_paths[fi]
                ext := ssg_path_ext(rel)
                // Compute dataset key from relative path without extension: a/b.yml -> a.b
                stem_rel := substring(rel, 0, string_length(rel) - string_length(ext))
                ds_name := ssg_replace_all(stem_rel, "/", ".")
                raw := file_read(ap)
                if ext == ".json":
                    _data_parse_simple_json_records(ds_name, raw, flat, counts)
                elif ext == ".toml":
                    df := dict[string, string]()
                    dl := dict[string, string]()
                    fm_parse_toml_lines(ssg_split_lines(raw), 0, len(ssg_split_lines(raw)), df, dl)
                    keys := df.keys()
                    let mut ki: int = 0
                    while ki < len(keys):
                        flat[ds_name + "." + keys[ki]] = df[keys[ki]]
                        ki = ki + 1
                else:
                    // YAML dataset (supports root-level "- k: v" list OR key: val maps)
                    df := dict[string, string]()
                    dl := dict[string, string]()
                    lines := ssg_split_lines(raw)
                    // Check if YAML starts with top-level list "- "
                    let mut is_root_list: int = 0
                    let mut li: int = 0
                    while li < len(lines):
                        tl := ssg_trim(lines[li])
                        if string_length(tl) > 0 and ssg_starts_with(tl, "#") == 0:
                            if ssg_starts_with(tl, "- ") == 1:
                                is_root_list = 1
                            break
                        li = li + 1
                    if is_root_list == 1:
                        let mut synthetic: vector[string] = []
                        synthetic.push("items:")
                        let mut si: int = 0
                        while si < len(lines):
                            synthetic.push("  " + lines[si])
                            si = si + 1
                        fm_parse_yaml_lines(synthetic, 0, len(synthetic), df, dl)
                        if dl.has("items") == 1:
                            counts[ds_name] = len(ssg_split(dl["items"], "\t"))
                        keys := df.keys()
                        let mut ki: int = 0
                        while ki < len(keys):
                            k := keys[ki]
                            if ssg_starts_with(k, "items[") == 1:
                                rest := substring(k, 5, string_length(k) - 5)
                                flat[ds_name + rest] = df[k]
                            else:
                                flat[ds_name + "." + k] = df[k]
                            ki = ki + 1
                    else:
                        fm_parse_yaml_lines(lines, 0, len(lines), df, dl)
                        keys := df.keys()
                        let mut ki: int = 0
                        while ki < len(keys):
                            flat[ds_name + "." + keys[ki]] = df[keys[ki]]
                            ki = ki + 1
                        lkeys := dl.keys()
                        let mut lki: int = 0
                        while lki < len(lkeys):
                            lk := lkeys[lki]
                            arr := ssg_split(dl[lk], "\t")
                            if ssg_find_from(lk, ".", 0) < 0:
                                counts[ds_name + "." + lk] = len(arr)
                            lki = lki + 1
                fi = fi + 1
        di = di + 1
    return DataRegistry(flat, counts)
