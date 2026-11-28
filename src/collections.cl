// ==============================================================================
// Module:      Typed Content Collections Validator (src/collections.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Parses Astro-style Content Collection schemas from
//              site/content/config.toml or config.cl and validates every
//              document's frontmatter types before build / check.
// ==============================================================================

import "src/strbuf.cl"
import "src/document.cl"

model CollectionFieldRule:
    name: string
    kind: string      // string, int, bool, date, list, image
    required: int

model CollectionSchema:
    name: string
    rules: vector[CollectionFieldRule]

model SchemaRegistry:
    schemas: vector[CollectionSchema]
    by_name: dict[string, int]

fn _col_parse_rule_spec(col_name: string, field_name_raw: string, spec_raw: string) -> CollectionFieldRule:
    let mut fname: string = ssg_trim(field_name_raw)
    let mut req: int = 1
    if ssg_ends_with(fname, "?") == 1:
        req = 0
        fname = ssg_trim(substring(fname, 0, string_length(fname) - 1))
    let mut kind: string = ssg_lower(ssg_strip_quotes(spec_raw))
    if ssg_starts_with(kind, "optional:") == 1:
        req = 0
        kind = ssg_trim(substring(kind, 9, string_length(kind) - 9))
    if ssg_contains(kind, "?") == 1:
        req = 0
        kind = ssg_replace_all(kind, "?", "")
    if ssg_starts_with(kind, "list") == 1:
        kind = "list"
    return CollectionFieldRule(fname, ssg_trim(kind), req)

fn collections_load_schemas(site_dir: string) -> SchemaRegistry:
    let mut schemas: vector[CollectionSchema] = []
    by_name := dict[string, int]()
    let mut candidates: vector[string] = []
    candidates.push(ssg_path_join(site_dir, "content/config.toml"))
    candidates.push(ssg_path_join(site_dir, "content/config.cl"))
    candidates.push("content.config.toml")

    let mut ci: int = 0
    while ci < len(candidates):
        p := candidates[ci]
        if file_exists(p) == 1:
            raw := file_read(p)
            lines := ssg_split_lines(raw)
            let mut cur_col: string = ""
            let mut i: int = 0
            while i < len(lines):
                ln := ssg_trim(lines[i])
                if string_length(ln) == 0 or ssg_starts_with(ln, "#") == 1 or ssg_starts_with(ln, "//") == 1:
                    i = i + 1
                    continue
                if ssg_starts_with(ln, "[") == 1 and ssg_ends_with(ln, "]") == 1:
                    sec := ssg_trim(substring(ln, 1, string_length(ln) - 2))
                    if ssg_starts_with(sec, "collection.") == 1:
                        sec = substring(sec, 11, string_length(sec) - 11)
                    elif ssg_starts_with(sec, "collections.") == 1:
                        sec = substring(sec, 12, string_length(sec) - 12)
                    cur_col = sec
                    if by_name.has(cur_col) == 0:
                        let rvec: vector[CollectionFieldRule] = []
                        by_name[cur_col] = len(schemas)
                        schemas.push(CollectionSchema(cur_col, rvec))
                    i = i + 1
                    continue
                if ssg_starts_with(ln, "@schema ") == 1 or ssg_starts_with(ln, "schema ") == 1:
                    rest := ssg_trim(substring(ln, ssg_find_from(ln, " ", 0) + 1, string_length(ln) - ssg_find_from(ln, " ", 0) - 1))
                    rest = ssg_replace_all(rest, "{", "")
                    rest = ssg_replace_all(rest, ":", "")
                    cur_col = ssg_trim(rest)
                    if by_name.has(cur_col) == 0:
                        let rvec: vector[CollectionFieldRule] = []
                        by_name[cur_col] = len(schemas)
                        schemas.push(CollectionSchema(cur_col, rvec))
                    i = i + 1
                    continue
                if ln == "}" or ln == "end":
                    cur_col = ""
                    i = i + 1
                    continue
                if string_length(cur_col) > 0:
                    let mut sep: int = ssg_find_from(ln, "=", 0)
                    if sep < 0:
                        sep = ssg_find_from(ln, ":", 0)
                    if sep > 0:
                        fk := substring(ln, 0, sep)
                        fv := substring(ln, sep + 1, string_length(ln) - sep - 1)
                        fv = ssg_replace_all(fv, ",", "")
                        rule := _col_parse_rule_spec(cur_col, fk, fv)
                        sidx := by_name[cur_col]
                        sc := schemas[sidx]
                        sc.rules.push(rule)
                        schemas[sidx] = sc
                i = i + 1
            break
        ci = ci + 1
    return SchemaRegistry(schemas, by_name)

fn _col_is_valid_date(d: string) -> int:
    t := ssg_trim(d)
    if string_length(t) < 10:
        return 0
    if byte_at(t, 4) != 45 or byte_at(t, 7) != 45:
        return 0
    let mut i: int = 0
    while i < 10:
        if i != 4 and i != 7:
            b := byte_at(t, i)
            if b < 48 or b > 57:
                return 0
        i = i + 1
    return 1

fn _col_validate_fields(reg: SchemaRegistry, collection: string, abs_path: string, fields: dict[string, string], title: string, author: string, date: string, tags: string, errors: vector[string]) -> int:
    if reg.by_name.has(collection) == 0:
        return 1
    sc := reg.schemas[reg.by_name[collection]]
    let mut ok: int = 1
    let mut ri: int = 0
    while ri < len(sc.rules):
        rule := sc.rules[ri]
        let mut present: int = 0
        let mut val: string = ""
        if fields.has(rule.name) == 1:
            val = fields[rule.name]
            if string_length(ssg_trim(val)) > 0:
                present = 1
        elif rule.name == "title" and string_length(title) > 0:
            val = title; present = 1
        elif rule.name == "author" and string_length(author) > 0:
            val = author; present = 1
        elif rule.name == "date" and string_length(date) > 0:
            val = date; present = 1
        elif rule.name == "tags" and string_length(tags) > 0:
            val = tags; present = 1

        if present == 0:
            if rule.required == 1:
                errors.push(abs_path + ":1: error[SSG-SCHEMA]: collection '" + collection + "' requires field '" + rule.name + "' (" + rule.kind + ")")
                ok = 0
        else:
            if rule.kind == "date" and _col_is_valid_date(val) == 0:
                errors.push(abs_path + ":1: error[SSG-SCHEMA]: field '" + rule.name + "' expected YYYY-MM-DD date, got '" + val + "'")
                ok = 0
            elif rule.kind == "int":
                if ssg_parse_int(val, -9999999) == -9999999:
                    errors.push(abs_path + ":1: error[SSG-SCHEMA]: field '" + rule.name + "' expected int, got '" + val + "'")
                    ok = 0
            elif rule.kind == "bool":
                lv := ssg_lower(ssg_trim(val))
                if lv != "true" and lv != "false" and lv != "1" and lv != "0":
                    errors.push(abs_path + ":1: error[SSG-SCHEMA]: field '" + rule.name + "' expected bool, got '" + val + "'")
                    ok = 0
        ri = ri + 1
    return ok

fn collections_validate_doc(reg: SchemaRegistry, doc: SsgRichDoc, errors: vector[string]) -> int:
    return _col_validate_fields(reg, doc.collection, doc.abs_path, doc.fm.fields, doc.title, doc.author, doc.date, doc.tags, errors)

fn collections_validate_header(reg: SchemaRegistry, hdr: SsgPageHeader, errors: vector[string]) -> int:
    return _col_validate_fields(reg, hdr.source.collection, hdr.source.abs_path, hdr.fm_fields, hdr.title, hdr.author, hdr.date, hdr.tags, errors)
