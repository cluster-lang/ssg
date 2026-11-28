// ==============================================================================
// Module:      Native CSS/JS Minifier, Fingerprinting & Image Optimizer (src/assets.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Zero-dependency pure-.cl CSS/JS minifier, CSS @import inliner,
//              content-hashed filenames (name.<8hex>.css), HTML reference rewriter,
//              PNG/GIF/JPEG/SVG width/height CLS eliminator, and --compress sidecars.
// ==============================================================================

import "src/strbuf.cl"
import "src/fs_walk.cl"

model AssetManifest:
    // Logical asset URL ("/static/style.css") -> hashed output URL ("/static/style.8f3a1c2b.css")
    url_map: dict[string, string]
    img_dims: dict[string, string]
    bytes_written: int
    files_copied: int

fn asset_manifest_new() -> AssetManifest:
    return AssetManifest()

// ------------------------------------------------------------------------------
// Pure-.cl CSS Minifier & @import Resolver
// ------------------------------------------------------------------------------

fn assets_bundle_css_imports(css: string, base_dir: string, depth: int) -> string:
    if depth > 6 or ssg_contains(css, "@import") == 0:
        return css
    lines := ssg_split_lines(css)
    sb := sb_new_cap(string_length(css) + 64)
    let mut i: int = 0
    while i < len(lines):
        ln := ssg_trim(lines[i])
        if ssg_starts_with(ln, "@import ") == 1:
            q1 := ssg_find_from(ln, "\"", 0)
            let mut inc_path: string = ""
            if q1 > 0:
                q2 := ssg_find_from(ln, "\"", q1 + 1)
                if q2 > q1:
                    inc_path = substring(ln, q1 + 1, q2 - q1 - 1)
            else:
                sq1 := ssg_find_from(ln, "'", 0)
                if sq1 > 0:
                    sq2 := ssg_find_from(ln, "'", sq1 + 1)
                    if sq2 > sq1:
                        inc_path = substring(ln, sq1 + 1, sq2 - sq1 - 1)
            if string_length(inc_path) > 0:
                full_p := ssg_path_join(base_dir, inc_path)
                if file_exists(full_p) == 1:
                    sub := assets_bundle_css_imports(file_read(full_p), ssg_path_dirname(full_p), depth + 1)
                    sb_append(sb, sub)
                    sb_append_byte(sb, 10)
                    i = i + 1
                    continue
        sb_append(sb, lines[i])
        sb_append_byte(sb, 10)
        i = i + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn assets_minify_css(css: string) -> string:
    clen := string_length(css)
    if clen == 0:
        return ""
    sb := sb_new_cap(clen)
    let mut i: int = 0
    let mut prev_space: int = 0
    let mut in_str: int = 0
    let mut str_q: int = 0
    while i < clen:
        b := byte_at(css, i)
        if in_str == 1:
            sb_append_byte(sb, b)
            if b == 92 and i + 1 < clen:
                i = i + 1
                sb_append_byte(sb, byte_at(css, i))
            elif b == str_q:
                in_str = 0
            i = i + 1
            continue
        if b == 34 or b == 39:
            in_str = 1
            str_q = b
            sb_append_byte(sb, b)
            prev_space = 0
            i = i + 1
            continue
        // Skip /* ... */ comments
        if b == 47 and i + 1 < clen and byte_at(css, i + 1) == 42:
            end_c := ssg_find_from(css, "*/", i + 2)
            if end_c >= 0:
                i = end_c + 2
                continue
            break
        if b == 32 or b == 9 or b == 10 or b == 13:
            if prev_space == 0 and sb.len > 0:
                last_b := ptr_read_u8(ptr_add(sb.buf, sb.len - 1))
                // Don't emit space right after punctuation
                if last_b != 123 and last_b != 125 and last_b != 58 and last_b != 59 and last_b != 44:
                    sb_append_byte(sb, 32)
                    prev_space = 1
            i = i + 1
            continue
        // Trim space right before { } : ; ,
        if (b == 123 or b == 125 or b == 58 or b == 59 or b == 44) and prev_space == 1 and sb.len > 0:
            sb.len = sb.len - 1
            ptr_write_u8(ptr_add(sb.buf, sb.len), 0)
        sb_append_byte(sb, b)
        prev_space = 0
        i = i + 1
    out := ssg_trim(sb_to_str(sb))
    sb_free(sb)
    return out

fn assets_minify_js(js: string) -> string:
    jlen := string_length(js)
    if jlen == 0:
        return ""
    sb := sb_new_cap(jlen)
    let mut i: int = 0
    let mut in_str: int = 0
    let mut str_q: int = 0
    let mut prev_ws: int = 0
    while i < jlen:
        b := byte_at(js, i)
        if in_str == 1:
            sb_append_byte(sb, b)
            if b == 92 and i + 1 < jlen:
                i = i + 1
                sb_append_byte(sb, byte_at(js, i))
            elif b == str_q:
                in_str = 0
            i = i + 1
            continue
        if b == 34 or b == 39 or b == 96:
            in_str = 1
            str_q = b
            sb_append_byte(sb, b)
            prev_ws = 0
            i = i + 1
            continue
        // Strip /* ... */
        if b == 47 and i + 1 < jlen and byte_at(js, i + 1) == 42:
            end_c := ssg_find_from(js, "*/", i + 2)
            if end_c >= 0:
                i = end_c + 2
                continue
            break
        // Strip // ... (skip http:// or https:// or regex edge cases: only at line start or after ws/;/{/})
        if b == 47 and i + 1 < jlen and byte_at(js, i + 1) == 47:
            let mut safe_comment: int = 0
            if i == 0:
                safe_comment = 1
            else:
                pb := byte_at(js, i - 1)
                if pb == 32 or pb == 9 or pb == 10 or pb == 59 or pb == 123 or pb == 125:
                    safe_comment = 1
            if safe_comment == 1:
                while i < jlen and byte_at(js, i) != 10:
                    i = i + 1
                continue
        if b == 32 or b == 9 or b == 13 or b == 10:
            if prev_ws == 0 and sb.len > 0:
                if b == 10:
                    sb_append_byte(sb, 10)
                else:
                    sb_append_byte(sb, 32)
                prev_ws = 1
            i = i + 1
            continue
        sb_append_byte(sb, b)
        prev_ws = 0
        i = i + 1
    out := ssg_trim(sb_to_str(sb))
    sb_free(sb)
    return out

fn assets_minify_html(html: string) -> string:
    hlen := string_length(html)
    if hlen == 0:
        return ""
    sb := sb_new_cap(hlen)
    let mut i: int = 0
    let mut prev_ws: int = 0
    while i < hlen:
        // Preserve <pre> and <script> and <style> verbatim
        if byte_at(html, i) == 60:
            sub := substring(html, i, hlen - i)
            if ssg_starts_with(sub, "<pre") == 1:
                e := ssg_find_from(html, "</pre>", i)
                if e > i:
                    sb_append_slice(sb, html, i, e + 6 - i)
                    i = e + 6
                    prev_ws = 0
                    continue
            if ssg_starts_with(sub, "<script") == 1:
                e := ssg_find_from(html, "</script>", i)
                if e > i:
                    sb_append_slice(sb, html, i, e + 9 - i)
                    i = e + 9
                    prev_ws = 0
                    continue
        b := byte_at(html, i)
        if b == 32 or b == 9 or b == 10 or b == 13:
            if prev_ws == 0:
                sb_append_byte(sb, 32)
                prev_ws = 1
            i = i + 1
            continue
        sb_append_byte(sb, b)
        prev_ws = 0
        i = i + 1
    out := ssg_trim(sb_to_str(sb))
    sb_free(sb)
    return out

// ------------------------------------------------------------------------------
// Pure-.cl Image Dimension Inspector & CLS Attribute Injector
// ------------------------------------------------------------------------------

fn _assets_read_u16_be(s: string, off: int) -> int:
    return (byte_at(s, off) << 8) | byte_at(s, off + 1)

fn _assets_read_u32_be(s: string, off: int) -> int:
    return (byte_at(s, off) << 24) | (byte_at(s, off + 1) << 16) | (byte_at(s, off + 2) << 8) | byte_at(s, off + 3)

fn _assets_read_u16_le(s: string, off: int) -> int:
    return byte_at(s, off) | (byte_at(s, off + 1) << 8)

fn assets_probe_image_dims(img_path: string, &w_out: int, &h_out: int) -> int:
    w_out = 0
    h_out = 0
    if file_exists(img_path) == 0:
        return 0
    ext := ssg_path_ext(img_path)
    if ext == ".svg":
        txt := file_read(img_path)
        vw := ssg_find_from(txt, "width=\"", 0)
        vh := ssg_find_from(txt, "height=\"", 0)
        if vw > 0 and vh > 0:
            w_out = ssg_parse_int(substring(txt, vw + 7, 10), 0)
            h_out = ssg_parse_int(substring(txt, vh + 8, 10), 0)
            if w_out > 0 and h_out > 0:
                return 1
        return 0
    data := file_read(img_path)
    dlen := string_length(data)
    // PNG: 8-byte magic + IHDR chunk (width at 16, height at 20, 4-byte BE)
    if ext == ".png" and dlen >= 24:
        if byte_at(data, 0) == 137 and byte_at(data, 1) == 80 and byte_at(data, 2) == 78:
            w_out = _assets_read_u32_be(data, 16)
            h_out = _assets_read_u32_be(data, 20)
            if w_out > 0 and h_out > 0:
                return 1
    // GIF: GIF87a/GIF89a, 2-byte LE at 6 and 8
    if ext == ".gif" and dlen >= 10:
        if byte_at(data, 0) == 71 and byte_at(data, 1) == 73 and byte_at(data, 2) == 70:
            w_out = _assets_read_u16_le(data, 6)
            h_out = _assets_read_u16_le(data, 8)
            if w_out > 0 and h_out > 0:
                return 1
    // JPEG: SOI (FF D8), scan SOF0 (C0) / SOF1 (C1) / SOF2 (C2) markers
    if (ext == ".jpg" or ext == ".jpeg") and dlen >= 12:
        if byte_at(data, 0) == 255 and byte_at(data, 1) == 216:
            let mut pos: int = 2
            while pos + 9 < dlen:
                if byte_at(data, pos) != 255:
                    pos = pos + 1
                    continue
                marker := byte_at(data, pos + 1)
                if marker == 255:
                    pos = pos + 1
                    continue
                if marker == 192 or marker == 193 or marker == 194:
                    h_out = _assets_read_u16_be(data, pos + 5)
                    w_out = _assets_read_u16_be(data, pos + 7)
                    if w_out > 0 and h_out > 0:
                        return 1
                    return 0
                if marker == 217 or marker == 218:
                    break
                if pos + 3 >= dlen:
                    break
                seg_len := _assets_read_u16_be(data, pos + 2)
                if seg_len < 2:
                    break
                pos = pos + 2 + seg_len
    // WebP: RIFF....WEBP + VP8X (extended), VP8 (lossy), VP8L (lossless)
    if ext == ".webp" and dlen >= 30:
        if byte_at(data, 0) == 82 and byte_at(data, 1) == 73 and byte_at(data, 2) == 70 and byte_at(data, 3) == 70 and byte_at(data, 8) == 87 and byte_at(data, 9) == 69 and byte_at(data, 10) == 66 and byte_at(data, 11) == 80:
            c0 := byte_at(data, 12)
            c1 := byte_at(data, 13)
            c2 := byte_at(data, 14)
            c3 := byte_at(data, 15)
            // VP8X: 24-bit width-1 at 24..26, height-1 at 27..29
            if c0 == 86 and c1 == 80 and c2 == 56 and c3 == 88 and dlen >= 30:
                w_out = (byte_at(data, 24) | (byte_at(data, 25) << 8) | (byte_at(data, 26) << 16)) + 1
                h_out = (byte_at(data, 27) | (byte_at(data, 28) << 8) | (byte_at(data, 29) << 16)) + 1
                if w_out > 0 and h_out > 0:
                    return 1
            // VP8L: signature 0x2F at 20, packed 14-bit width-1 / height-1 at 21..24
            elif c0 == 86 and c1 == 80 and c2 == 56 and c3 == 76 and dlen >= 25 and byte_at(data, 20) == 47:
                b0 := byte_at(data, 21)
                b1 := byte_at(data, 22)
                b2 := byte_at(data, 23)
                b3 := byte_at(data, 24)
                w_out = (b0 | ((b1 & 63) << 8)) + 1
                h_out = (((b1 >> 6) | (b2 << 2) | ((b3 & 15) << 10))) + 1
                if w_out > 0 and h_out > 0:
                    return 1
            // VP8 : frame tag at 20..22, keyframe signature 9D 01 2A at 23..25, width/height at 26..29
            elif c0 == 86 and c1 == 80 and c2 == 56 and c3 == 32 and dlen >= 30 and byte_at(data, 23) == 157 and byte_at(data, 24) == 1 and byte_at(data, 25) == 42:
                w_out = _assets_read_u16_le(data, 26) & 16383
                h_out = _assets_read_u16_le(data, 28) & 16383
                if w_out > 0 and h_out > 0:
                    return 1
    return 0

// ------------------------------------------------------------------------------
// Static Asset Pipeline Runner + Fingerprinting + Pre-compression
// ------------------------------------------------------------------------------

fn assets_process_all(site_dir: string, dist_dir: string, minify: int, hash_assets: int, compress: int, dir_cache: dict[string, int]) -> AssetManifest:
    man := asset_manifest_new()
    z := ssg_zlib_init()
    let mut static_roots: vector[string] = []
    static_roots.push(ssg_path_join(site_dir, "static"))
    static_roots.push(ssg_path_join(site_dir, "assets"))
    static_roots.push(ssg_path_join(site_dir, "public"))

    let empty_exts: vector[string] = []
    let mut ri: int = 0
    while ri < len(static_roots):
        root := static_roots[ri]
        if fs_is_dir(root) == 1:
            root_base := ssg_path_basename(root)
            scan := fs_walk_tree(root, empty_exts)
            let mut fi: int = 0
            while fi < len(scan.abs_paths):
                ap := scan.abs_paths[fi]
                rel := scan.rel_paths[fi]
                ext := ssg_path_ext(rel)
                let mut url_prefix: string = "/" + root_base + "/"
                if root_base == "public":
                    url_prefix = "/"
                orig_url := url_prefix + rel

                if ext == ".css" or ext == ".js":
                    let mut content: string = file_read(ap)
                    if ext == ".css":
                        content = assets_bundle_css_imports(content, ssg_path_dirname(ap), 0)
                        if minify == 1:
                            content = assets_minify_css(content)
                    else:
                        if minify == 1:
                            content = assets_minify_js(content)

                    let mut out_rel: string = rel
                    if hash_assets == 1:
                        h8 := ssg_fnv1a_hash(content)
                        stem_part := substring(rel, 0, string_length(rel) - string_length(ext))
                        out_rel = stem_part + "." + h8 + ext
                    let mut dst_sub: string = out_rel
                    if root_base != "public":
                        dst_sub = root_base + "/" + out_rel
                    dst_path := ssg_path_join(dist_dir, dst_sub)
                    ssg_ensure_dir(ssg_path_dirname(dst_path), dir_cache)
                    file_write(dst_path, content)
                    man.url_map[orig_url] = "/" + dst_sub
                    man.bytes_written = man.bytes_written + string_length(content)
                    man.files_copied = man.files_copied + 1
                    if compress == 1:
                        if ssg_gzip_write(z, dst_path + ".gz", content) != 0:
                            sys_run("gzip -kf -9 \"" + dst_path + "\" 2>/dev/null || true")
                else:
                    let mut dst_sub: string = rel
                    if root_base != "public":
                        dst_sub = root_base + "/" + rel
                    dst_path := ssg_path_join(dist_dir, dst_sub)
                    copied_sz := fs_copy_file_raw(ap, dst_path, dir_cache)
                    man.url_map[orig_url] = "/" + dst_sub
                    let mut iw: int = 0
                    let mut ih: int = 0
                    if assets_probe_image_dims(ap, iw, ih) == 1:
                        man.img_dims["/" + dst_sub] = str(iw) + "x" + str(ih)
                    man.bytes_written = man.bytes_written + copied_sz
                    man.files_copied = man.files_copied + 1
                fi = fi + 1
        ri = ri + 1
    return man

fn _assets_inject_img_dims(html: string, man: AssetManifest) -> string:
    if ssg_contains(html, "<img") == 0:
        return html
    dk := man.img_dims.keys()
    ndk := len(dk)
    list_free(dk)
    if ndk == 0:
        return html
    hlen := string_length(html)
    sb := sb_new_cap(hlen + 64)
    let mut pos: int = 0
    while pos < hlen:
        idx := ssg_find_from(html, "<img", pos)
        if idx < 0:
            sb_append_slice(sb, html, pos, hlen - pos)
            break
        sb_append_slice(sb, html, pos, idx - pos)
        end_tag := ssg_find_from(html, ">", idx)
        if end_tag < 0:
            sb_append_slice(sb, html, idx, hlen - idx)
            break
        tag := substring(html, idx, end_tag - idx + 1)
        let mut out_tag: string = tag
        if ssg_contains(tag, "width=") == 0 and ssg_contains(tag, "height=") == 0:
            s_idx := ssg_find_from(tag, "src=\"", 0)
            if s_idx >= 0:
                q_end := ssg_find_from(tag, "\"", s_idx + 5)
                if q_end > s_idx + 5:
                    src_u := substring(tag, s_idx + 5, q_end - (s_idx + 5))
                    if man.img_dims.has(src_u) == 1:
                        wh := man.img_dims[src_u]
                        x_pos := ssg_find_from(wh, "x", 0)
                        if x_pos > 0:
                            w_s := substring(wh, 0, x_pos)
                            h_s := substring(wh, x_pos + 1, string_length(wh) - x_pos - 1)
                            let mut ins: string = " width=\"" + w_s + "\" height=\"" + h_s + "\""
                            if ssg_contains(tag, "loading=") == 0:
                                ins = ins + " loading=\"lazy\" decoding=\"async\""
                            tlen := string_length(tag)
                            if tlen >= 2 and byte_at(tag, tlen - 2) == 47:
                                out_tag = substring(tag, 0, tlen - 2) + ins + " />"
                            else:
                                out_tag = substring(tag, 0, tlen - 1) + ins + ">"
        sb_append(sb, out_tag)
        pos = end_tag + 1
    out := sb_to_str(sb)
    sb_free(sb)
    return out

fn assets_rewrite_html_urls(html: string, man: AssetManifest) -> string:
    if man.files_copied == 0:
        return _assets_inject_img_dims(html, man)
    let mut out: string = html
    keys := man.url_map.keys()
    let mut i: int = 0
    while i < len(keys):
        k := keys[i]
        v := man.url_map[k]
        if k != v and ssg_contains(out, k) == 1:
            out = ssg_replace_all(out, k, v)
        i = i + 1
    list_free(keys)
    return _assets_inject_img_dims(out, man)
