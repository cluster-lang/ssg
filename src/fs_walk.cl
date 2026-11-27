// ==============================================================================
// Module:      Native Recursive Filesystem Walker & Incremental Cache (src/fs_walk.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Zero-shell POSIX opendir/readdir recursive scanning, cached mkdir_p,
//              full static asset mirroring, and FNV-1a incremental build manifest.
// ==============================================================================

import "src/strbuf.cl"

fn ssg_ensure_dir(dir_path: string, dir_cache: dict[string, int]) -> void:
    if string_length(dir_path) == 0 or dir_path == ".":
        return
    if dir_cache.has(dir_path) == 1:
        return
    if fs_is_dir(dir_path) == 0:
        sys_run("mkdir -p \"" + dir_path + "\"")
    dir_cache[dir_path] = 1

fn _fs_walk_rec(base_dir: string, rel_dir: string, exts: vector[string], out_abs: vector[string], out_rel: vector[string]) -> void:
    cur_dir := base_dir
    if string_length(rel_dir) > 0:
        cur_dir = ssg_path_join(base_dir, rel_dir)
    if fs_is_dir(cur_dir) == 0:
        return
    entries := fs_list_dir(cur_dir)
    let mut i: int = 0
    while i < len(entries):
        name := entries[i]
        if ssg_starts_with(name, ".") == 1:
            i = i + 1
            continue
        full := ssg_path_join(cur_dir, name)
        let mut next_rel: string = name
        if string_length(rel_dir) > 0:
            next_rel = rel_dir + "/" + name
        if fs_is_dir(full) == 1:
            _fs_walk_rec(base_dir, next_rel, exts, out_abs, out_rel)
        else:
            if len(exts) == 0:
                out_abs.push(full)
                out_rel.push(next_rel)
            else:
                ext := ssg_path_ext(name)
                let mut matched: int = 0
                let mut ei: int = 0
                while ei < len(exts):
                    if ext == exts[ei]:
                        matched = 1
                        break
                    ei = ei + 1
                if matched == 1:
                    out_abs.push(full)
                    out_rel.push(next_rel)
        i = i + 1

model FsScanResult:
    abs_paths: vector[string]
    rel_paths: vector[string]

fn fs_walk_tree(root_dir: string, exts: vector[string]) -> FsScanResult:
    let mut abs_p: vector[string] = []
    let mut rel_p: vector[string] = []
    _fs_walk_rec(root_dir, "", exts, abs_p, rel_p)
    return FsScanResult(abs_p, rel_p)

fn fs_walk_all(root_dir: string) -> FsScanResult:
    let empty_exts: vector[string] = []
    return fs_walk_tree(root_dir, empty_exts)

fn fs_read_bytes_len(path: string) -> int:
    if file_exists(path) == 0:
        return 0
    content := file_read(path)
    return string_length(content)

fn fs_copy_file_raw(src_path: string, dst_path: string, dir_cache: dict[string, int]) -> int:
    if file_exists(src_path) == 0:
        return 0
    parent := ssg_path_dirname(dst_path)
    if string_length(parent) > 0:
        ssg_ensure_dir(parent, dir_cache)
    // Use POSIX cp to preserve binary files with NUL bytes (PNG/WOFF2/WebP/ICO) cleanly
    rc := sys_run("cp -f \"" + src_path + "\" \"" + dst_path + "\"")
    if rc != 0:
        data := file_read(src_path)
        file_write(dst_path, data)
        return string_length(data)
    return fs_read_bytes_len(src_path)

fn fs_max_source_signature(dirs: vector[string]) -> string:
    sb := sb_new_cap(1024)
    let empty_exts: vector[string] = []
    let mut di: int = 0
    while di < len(dirs):
        d := dirs[di]
        if fs_is_dir(d) == 1:
            scan := fs_walk_tree(d, empty_exts)
            let mut fi: int = 0
            while fi < len(scan.abs_paths):
                ap := scan.abs_paths[fi]
                sb_append(sb, ap)
                sb_append_byte(sb, 61)
                sb_append(sb, ssg_fnv1a_hash(file_read(ap)))
                sb_append_byte(sb, 10)
                fi = fi + 1
        di = di + 1
    out := ssg_fnv1a_hash(sb_to_str(sb))
    sb_free(sb)
    return out

// ------------------------------------------------------------------------------
// Incremental Build Cache (.ssg_cache/manifest.tsv)
// ------------------------------------------------------------------------------

model SsgBuildCache:
    cache_path: string
    prev_hashes: dict[string, string]
    next_hashes: dict[string, string]
    global_sig: string
    prev_global_sig: string

fn ssg_cache_load(cache_dir: string, global_sig: string) -> SsgBuildCache:
    manifest := ssg_path_join(cache_dir, "manifest.tsv")
    prev := dict[string, string]()
    next := dict[string, string]()
    let mut prev_gsig: string = ""
    if file_exists(manifest) == 1:
        raw := file_read(manifest)
        lines := ssg_split_lines(raw)
        let mut i: int = 0
        while i < len(lines):
            ln := ssg_trim(lines[i])
            if string_length(ln) > 0:
                cols := ssg_split(ln, "\t")
                if len(cols) >= 2:
                    if cols[0] == "__GLOBAL__":
                        prev_gsig = cols[1]
                    else:
                        prev[cols[0]] = cols[1]
            i = i + 1
    return SsgBuildCache(manifest, prev, next, global_sig, prev_gsig)

fn ssg_cache_is_dirty(c: SsgBuildCache, key: string, content_hash: string, out_path: string) -> int:
    c.next_hashes[key] = content_hash
    if c.prev_global_sig != c.global_sig:
        return 1
    if file_exists(out_path) == 0:
        return 1
    if c.prev_hashes.has(key) == 0:
        return 1
    if c.prev_hashes[key] != content_hash:
        return 1
    return 0

fn ssg_cache_save(c: SsgBuildCache, cache_dir: string, dir_cache: dict[string, int]) -> void:
    ssg_ensure_dir(cache_dir, dir_cache)
    sb := sb_new_cap(2048)
    sb_append(sb, "__GLOBAL__\t")
    sb_append(sb, c.global_sig)
    sb_append_byte(sb, 10)
    keys := c.next_hashes.keys()
    let mut i: int = 0
    while i < len(keys):
        k := keys[i]
        sb_append(sb, k)
        sb_append_byte(sb, 9)
        sb_append(sb, c.next_hashes[k])
        sb_append_byte(sb, 10)
        i = i + 1
    file_write(c.cache_path, sb_to_str(sb))
    sb_free(sb)
