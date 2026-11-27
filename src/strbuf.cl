// ==============================================================================
// Module:      High-Speed Mutable StringBuf & Utilities (src/strbuf.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// License:     CCFL-1.0 / CCFL v2.0
// Description: Capacity-doubling O(1)-amortized byte buffer, O(N) substring/replace,
//              FNV-1a hashing, HTML/JSON/XML escaping, and path utilities.
// ==============================================================================

import c "time.h"

model StrBuf:
    buf: ptr
    len: int
    cap: int

fn sb_new_cap(init_cap: int) -> StrBuf:
    let mut c: int = init_cap
    if c < 64:
        c = 64
    p: ptr := mem_alloc(c)
    ptr_write_u8(p, 0)
    return StrBuf(p, 0, c)

fn sb_new() -> StrBuf:
    return sb_new_cap(256)

fn sb_ensure(sb: StrBuf, extra: int) -> void:
    needed := sb.len + extra + 1
    if needed <= sb.cap:
        return
    let mut ncap: int = sb.cap * 2
    while ncap < needed:
        ncap = ncap * 2
    sb.buf = mem_realloc(sb.buf, ncap)
    sb.cap = ncap

fn sb_append_byte(sb: StrBuf, b: int) -> void:
    sb_ensure(sb, 1)
    ptr_write_u8(ptr_add(sb.buf, sb.len), b)
    sb.len = sb.len + 1
    ptr_write_u8(ptr_add(sb.buf, sb.len), 0)

fn sb_append(sb: StrBuf, s: string) -> void:
    slen := string_length(s)
    if slen <= 0:
        return
    sb_ensure(sb, slen)
    mem_copy(ptr_add(sb.buf, sb.len), str_cstr(s), slen)
    sb.len = sb.len + slen
    ptr_write_u8(ptr_add(sb.buf, sb.len), 0)

fn sb_append_slice(sb: StrBuf, s: string, start: int, count: int) -> void:
    if count <= 0:
        return
    slen := string_length(s)
    if start < 0 or start >= slen:
        return
    let mut cnt: int = count
    if start + cnt > slen:
        cnt = slen - start
    if cnt <= 0:
        return
    sb_ensure(sb, cnt)
    mem_copy(ptr_add(sb.buf, sb.len), ptr_add(str_cstr(s), start), cnt)
    sb.len = sb.len + cnt
    ptr_write_u8(ptr_add(sb.buf, sb.len), 0)

fn sb_append_int(sb: StrBuf, v: int) -> void:
    sb_append(sb, str(v))

fn sb_to_str(sb: StrBuf) -> string:
    if sb.len <= 0:
        return ""
    p: ptr := int_to_ptr(arena_alloc(sb.len + 1))
    mem_copy(p, sb.buf, sb.len)
    ptr_write_u8(ptr_add(p, sb.len), 0)
    return str_from_parts(p, sb.len)

fn sb_free(sb: StrBuf) -> void:
    if sb.buf != null:
        mem_free(sb.buf)
        sb.buf = null
    sb.len = 0
    sb.cap = 0

// ------------------------------------------------------------------------------
// Clock & Sleep Wrappers
// ------------------------------------------------------------------------------

fn ssg_clock_us() -> int:
    return clock()

fn ssg_time_sec() -> int:
    return time(null)

// ------------------------------------------------------------------------------
// Fast String Search, Replace, Split, Trim, Case, Hash & Escaping
// ------------------------------------------------------------------------------

fn ssg_find_from(hay: string, needle: string, start: int) -> int:
    hlen := string_length(hay)
    nlen := string_length(needle)
    if nlen == 0:
        if start <= hlen:
            return start
        return -1
    if start < 0 or nlen > hlen or start > hlen - nlen:
        return -1
    first_b := byte_at(needle, 0)
    let mut i: int = start
    limit := hlen - nlen
    while i <= limit:
        if byte_at(hay, i) == first_b:
            let mut ok: int = 1
            let mut j: int = 1
            while j < nlen:
                if byte_at(hay, i + j) != byte_at(needle, j):
                    ok = 0
                    break
                j = j + 1
            if ok == 1:
                return i
        i = i + 1
    return -1

fn ssg_contains(hay: string, needle: string) -> int:
    if ssg_find_from(hay, needle, 0) >= 0:
        return 1
    return 0

fn ssg_starts_with(s: string, prefix: string) -> int:
    slen := string_length(s)
    plen := string_length(prefix)
    if plen > slen:
        return 0
    let mut i: int = 0
    while i < plen:
        if byte_at(s, i) != byte_at(prefix, i):
            return 0
        i = i + 1
    return 1

fn ssg_ends_with(s: string, suffix: string) -> int:
    slen := string_length(s)
    xlen := string_length(suffix)
    if xlen > slen:
        return 0
    off := slen - xlen
    let mut i: int = 0
    while i < xlen:
        if byte_at(s, off + i) != byte_at(suffix, i):
            return 0
        i = i + 1
    return 1

fn ssg_replace_all(text: string, old_sub: string, new_sub: string) -> string:
    olen := string_length(old_sub)
    if olen == 0:
        return text
    first := ssg_find_from(text, old_sub, 0)
    if first < 0:
        return text
    sb := sb_new_cap(string_length(text) + 32)
    let mut pos: int = 0
    let mut idx: int = first
    while idx >= 0:
        if idx > pos:
            sb_append_slice(sb, text, pos, idx - pos)
        sb_append(sb, new_sub)
        pos = idx + olen
        idx = ssg_find_from(text, old_sub, pos)
    tlen := string_length(text)
    if pos < tlen:
        sb_append_slice(sb, text, pos, tlen - pos)
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn ssg_trim(text: string) -> string:
    tlen := string_length(text)
    if tlen == 0:
        return ""
    let mut start: int = 0
    while start < tlen:
        b := byte_at(text, start)
        if b != 32 and b != 9 and b != 13 and b != 10:
            break
        start = start + 1
    if start >= tlen:
        return ""
    let mut end: int = tlen - 1
    while end >= start:
        b := byte_at(text, end)
        if b != 32 and b != 9 and b != 13 and b != 10:
            break
        end = end - 1
    return substring(text, start, end - start + 1)

fn ssg_strip_quotes(s: string) -> string:
    t := ssg_trim(s)
    tlen := string_length(t)
    if tlen >= 2:
        b0 := byte_at(t, 0)
        b1 := byte_at(t, tlen - 1)
        if (b0 == 34 and b1 == 34) or (b0 == 39 and b1 == 39):
            return substring(t, 1, tlen - 2)
    return t

fn ssg_lower(s: string) -> string:
    slen := string_length(s)
    if slen == 0:
        return ""
    sb := sb_new_cap(slen + 4)
    let mut i: int = 0
    while i < slen:
        b := byte_at(s, i)
        if b >= 65 and b <= 90:
            sb_append_byte(sb, b + 32)
        else:
            sb_append_byte(sb, b)
        i = i + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn ssg_upper(s: string) -> string:
    slen := string_length(s)
    if slen == 0:
        return ""
    sb := sb_new_cap(slen + 4)
    let mut i: int = 0
    while i < slen:
        b := byte_at(s, i)
        if b >= 97 and b <= 122:
            sb_append_byte(sb, b - 32)
        else:
            sb_append_byte(sb, b)
        i = i + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn ssg_split(text: string, delim: string) -> vector[string]:
    let mut parts: vector[string] = []
    tlen := string_length(text)
    dlen := string_length(delim)
    if dlen == 0:
        parts.push(text)
        return parts
    let mut pos: int = 0
    while pos <= tlen:
        idx := ssg_find_from(text, delim, pos)
        if idx < 0:
            parts.push(substring(text, pos, tlen - pos))
            break
        parts.push(substring(text, pos, idx - pos))
        pos = idx + dlen
        if pos == tlen:
            parts.push("")
            break
    return parts

fn ssg_split_lines(text: string) -> vector[string]:
    let mut lines: vector[string] = []
    tlen := string_length(text)
    let mut start: int = 0
    let mut i: int = 0
    while i < tlen:
        if byte_at(text, i) == 10:
            let mut end: int = i
            if end > start and byte_at(text, end - 1) == 13:
                end = end - 1
            lines.push(substring(text, start, end - start))
            start = i + 1
        i = i + 1
    if start < tlen:
        let mut end: int = tlen
        if end > start and byte_at(text, end - 1) == 13:
            end = end - 1
        lines.push(substring(text, start, end - start))
    elif tlen > 0 and byte_at(text, tlen - 1) == 10:
        lines.push("")
    elif tlen == 0:
        lines.push("")
    return lines

fn ssg_slugify(text: string) -> string:
    tlen := string_length(text)
    if tlen == 0:
        return "untitled"
    sb := sb_new_cap(tlen + 4)
    let mut last_dash: int = 1
    let mut i: int = 0
    while i < tlen:
        let mut b: int = byte_at(text, i)
        if b >= 65 and b <= 90:
            b = b + 32
        if (b >= 97 and b <= 122) or (b >= 48 and b <= 57):
            sb_append_byte(sb, b)
            last_dash = 0
        elif b == 32 or b == 95 or b == 47 or b == 46 or b == 45:
            if last_dash == 0:
                sb_append_byte(sb, 45)
                last_dash = 1
        i = i + 1
    out := sb_to_str(sb)
    sb_free(sb)
    olen := string_length(out)
    if olen > 0 and byte_at(out, olen - 1) == 45:
        out = substring(out, 0, olen - 1)
    if string_length(out) == 0:
        return "untitled"
    return out

fn ssg_escape_html(s: string) -> string:
    slen := string_length(s)
    if slen == 0:
        return ""
    sb := sb_new_cap(slen + 16)
    let mut i: int = 0
    while i < slen:
        b := byte_at(s, i)
        if b == 38:
            sb_append(sb, "&amp;")
        elif b == 60:
            sb_append(sb, "&lt;")
        elif b == 62:
            sb_append(sb, "&gt;")
        elif b == 34:
            sb_append(sb, "&quot;")
        elif b == 39:
            sb_append(sb, "&#39;")
        else:
            sb_append_byte(sb, b)
        i = i + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn ssg_escape_json(s: string) -> string:
    slen := string_length(s)
    if slen == 0:
        return ""
    sb := sb_new_cap(slen + 16)
    let mut i: int = 0
    while i < slen:
        b := byte_at(s, i)
        if b == 34:
            sb_append(sb, "\\\"")
        elif b == 92:
            sb_append(sb, "\\\\")
        elif b == 10:
            sb_append(sb, "\\n")
        elif b == 13:
            sb_append(sb, "")
        elif b == 9:
            sb_append(sb, "\\t")
        elif b < 32:
            sb_append(sb, " ")
        else:
            sb_append_byte(sb, b)
        i = i + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn ssg_escape_xml(s: string) -> string:
    return ssg_escape_html(s)

fn ssg_strip_html(s: string) -> string:
    slen := string_length(s)
    if slen == 0:
        return ""
    sb := sb_new_cap(slen)
    let mut in_tag: int = 0
    let mut i: int = 0
    while i < slen:
        b := byte_at(s, i)
        if b == 60:
            in_tag = 1
        elif b == 62:
            if in_tag == 1:
                in_tag = 0
                sb_append_byte(sb, 32)
        elif in_tag == 0:
            sb_append_byte(sb, b)
        i = i + 1
    out := ssg_trim(sb_to_str(sb))
    sb_free(sb)
    return out

fn ssg_fnv1a_hash(s: string) -> string:
    // 64-bit FNV-1a encoded as 8-char lowercase hex
    let mut h: int = 1469598103934665603
    slen := string_length(s)
    let mut i: int = 0
    while i < slen:
        b := byte_at(s, i)
        h = h ^ b
        h = h * 1099511628211
        i = i + 1
    hex_chars := "0123456789abcdef"
    sb := sb_new_cap(16)
    let mut shift: int = 28
    while shift >= 0:
        nib := (h >> shift) & 15
        sb_append_byte(sb, byte_at(hex_chars, nib))
        shift = shift - 4
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn ssg_parse_int(s: string, fallback: int) -> int:
    t := ssg_trim(s)
    tlen := string_length(t)
    if tlen == 0:
        return fallback
    let mut neg: int = 0
    let mut i: int = 0
    if byte_at(t, 0) == 45:
        neg = 1
        i = 1
    elif byte_at(t, 0) == 43:
        i = 1
    if i >= tlen:
        return fallback
    let mut acc: int = 0
    let mut digits: int = 0
    while i < tlen:
        b := byte_at(t, i)
        if b >= 48 and b <= 57:
            acc = acc * 10 + (b - 48)
            digits = digits + 1
        else:
            break
        i = i + 1
    if digits == 0:
        return fallback
    if neg == 1:
        return 0 - acc
    return acc

// ------------------------------------------------------------------------------
// Path Helpers
// ------------------------------------------------------------------------------

fn ssg_path_join(a: string, b: string) -> string:
    if string_length(a) == 0:
        return b
    if string_length(b) == 0:
        return a
    let mut a_clean: string = a
    while string_length(a_clean) > 1 and byte_at(a_clean, string_length(a_clean) - 1) == 47:
        a_clean = substring(a_clean, 0, string_length(a_clean) - 1)
    let mut b_clean: string = b
    while string_length(b_clean) > 0 and byte_at(b_clean, 0) == 47:
        b_clean = substring(b_clean, 1, string_length(b_clean) - 1)
    if a_clean == "/":
        return "/" + b_clean
    return a_clean + "/" + b_clean

fn ssg_path_dirname(p: string) -> string:
    plen := string_length(p)
    let mut i: int = plen - 1
    while i >= 0:
        if byte_at(p, i) == 47:
            if i == 0:
                return "/"
            return substring(p, 0, i)
        i = i - 1
    return ""

fn ssg_path_basename(p: string) -> string:
    plen := string_length(p)
    let mut i: int = plen - 1
    while i >= 0:
        if byte_at(p, i) == 47:
            return substring(p, i + 1, plen - i - 1)
        i = i - 1
    return p

fn ssg_path_stem(p: string) -> string:
    base := ssg_path_basename(p)
    blen := string_length(base)
    let mut i: int = blen - 1
    while i >= 0:
        if byte_at(base, i) == 46:
            if i > 0:
                return substring(base, 0, i)
            return base
        i = i - 1
    return base

fn ssg_path_ext(p: string) -> string:
    base := ssg_path_basename(p)
    blen := string_length(base)
    let mut i: int = blen - 1
    while i >= 0:
        if byte_at(base, i) == 46:
            if i > 0:
                return ssg_lower(substring(base, i, blen - i))
            return ""
        i = i - 1
    return ""
