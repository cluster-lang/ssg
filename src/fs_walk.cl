// ==============================================================================
// Module:      Native Recursive Filesystem Walker & Incremental Cache (src/fs_walk.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Zero-shell POSIX opendir/readdir recursive scanning, cached mkdir_p,
//              full static asset mirroring, and FNV-1a incremental build manifest.
// ==============================================================================

import "src/strbuf.cl"

extern fn dlopen(filename: ptr, flags: i32) -> ptr
extern fn dlsym(handle: ptr, symbol: ptr) -> ptr
extern fn open(pathname: ptr, flags: i32, mode: i32) -> i32
extern fn close(fd: i32) -> i32
extern fn lseek(fd: i32, offset: int, whence: i32) -> int
extern fn read(fd: i32, buf: ptr, count: int) -> int
extern fn write(fd: i32, buf: ptr, count: int) -> int
extern fn inotify_init1(flags: i32) -> i32
extern fn inotify_add_watch(fd: i32, pathname: ptr, mask: i32) -> i32
extern fn poll(fds: ptr, nfds: int, timeout: i32) -> i32
extern fn usleep(usec: i32) -> i32

fn _fs_write_pollfd(buf: ptr, idx: int, fd: i32) -> void:
    off := idx * 8
    ptr_write_u8(ptr_add(buf, off), fd & 255)
    ptr_write_u8(ptr_add(buf, off + 1), (fd >> 8) & 255)
    ptr_write_u8(ptr_add(buf, off + 2), (fd >> 16) & 255)
    ptr_write_u8(ptr_add(buf, off + 3), (fd >> 24) & 255)
    // events = POLLIN (1), revents = 0
    ptr_write_u8(ptr_add(buf, off + 4), 1)
    ptr_write_u8(ptr_add(buf, off + 5), 0)
    ptr_write_u8(ptr_add(buf, off + 6), 0)
    ptr_write_u8(ptr_add(buf, off + 7), 0)

fn fs_poll_fd2(fd0: i32, fd1: i32, timeout_ms: i32) -> int:
    buf := mem_alloc(16)
    _fs_write_pollfd(buf, 0, fd0)
    let mut nfds: int = 1
    if fd1 >= 0:
        _fs_write_pollfd(buf, 1, fd1)
        nfds = 2
    rc := poll(buf, nfds, timeout_ms)
    let mut mask: int = 0
    if rc > 0:
        r0 := ptr_read_u8(ptr_add(buf, 6))
        if (r0 & 1) != 0:
            mask = mask | 1
        if nfds == 2:
            r1 := ptr_read_u8(ptr_add(buf, 14))
            if (r1 & 1) != 0:
                mask = mask | 2
    mem_free(buf)
    return mask

fn _fs_inotify_add_rec(ifd: i32, dir_path: string) -> void:
    if ifd < 0 or fs_is_dir(dir_path) == 0:
        return
    // IN_MODIFY(2) | IN_ATTRIB(4) | IN_MOVED_TO(128) | IN_CREATE(256) | IN_DELETE(512) = 902
    inotify_add_watch(ifd, str_cstr(dir_path), 902)
    entries := fs_list_dir(dir_path)
    let mut i: int = 0
    while i < len(entries):
        name := entries[i]
        if ssg_starts_with(name, ".") == 0:
            full := ssg_path_join(dir_path, name)
            if fs_is_dir(full) == 1:
                _fs_inotify_add_rec(ifd, full)
        i = i + 1

fn fs_inotify_open(dirs: vector[string]) -> i32:
    // IN_NONBLOCK = 2048
    ifd := inotify_init1(2048)
    if ifd < 0:
        return -1
    let mut i: int = 0
    while i < len(dirs):
        _fs_inotify_add_rec(ifd, dirs[i])
        i = i + 1
    return ifd

fn fs_inotify_drain(ifd: i32, dirs: vector[string]) -> int:
    if ifd < 0:
        return 0
    buf := mem_alloc(4096)
    let mut changed: int = 0
    while 1 == 1:
        nr := read(ifd, buf, 4096)
        if nr <= 0:
            break
        changed = 1
    mem_free(buf)
    if changed == 1:
        let mut i: int = 0
        while i < len(dirs):
            _fs_inotify_add_rec(ifd, dirs[i])
            i = i + 1
    return changed

fn ssg_read_file_arena(path: string) -> string:
    fd := open(str_cstr(path), 0, 0)
    if fd < 0:
        return ""
    sz := lseek(fd, 0, 2)
    if sz <= 0:
        close(fd)
        return ""
    lseek(fd, 0, 0)
    p: ptr := int_to_ptr(arena_alloc(sz + 1))
    let mut tot: int = 0
    while tot < sz:
        nr := read(fd, ptr_add(p, tot), sz - tot)
        if nr <= 0:
            break
        tot = tot + nr
    close(fd)
    ptr_write_u8(ptr_add(p, tot), 0)
    return str_from_parts(p, tot)

fn ssg_write_file_raw(path: string, data: string) -> int:
    fd := open(str_cstr(path), 577, 420)
    if fd < 0:
        return file_write(path, data)
    dlen := string_length(data)
    let mut tot: int = 0
    if dlen > 0:
        p := str_cstr(data)
        while tot < dlen:
            nw := write(fd, ptr_add(p, tot), dlen - tot)
            if nw <= 0:
                break
            tot = tot + nw
    close(fd)
    return tot

fn ssg_write_file_sb(path: string, sb: StrBuf) -> int:
    fd := open(str_cstr(path), 577, 420)
    if fd < 0:
        return -1
    let mut tot: int = 0
    if sb.len > 0 and sb.buf != null:
        while tot < sb.len:
            nw := write(fd, ptr_add(sb.buf, tot), sb.len - tot)
            if nw <= 0:
                break
            tot = tot + nw
    close(fd)
    return tot

model ZlibCodec:
    lib_handle: ptr
    fn_gzopen: ptr
    fn_gzwrite: ptr
    fn_gzclose: ptr
    ready: int

fn ssg_zlib_init() -> ZlibCodec:
    h := dlopen(str_cstr("libz.so.1"), 1)
    if h == null:
        h = dlopen(str_cstr("libz.so"), 1)
    if h == null:
        return ZlibCodec(null, null, null, null, 0)
    f_open := dlsym(h, str_cstr("gzopen"))
    f_write := dlsym(h, str_cstr("gzwrite"))
    f_close := dlsym(h, str_cstr("gzclose"))
    if f_open == null or f_write == null or f_close == null:
        return ZlibCodec(h, null, null, null, 0)
    return ZlibCodec(h, f_open, f_write, f_close, 1)

fn ssg_gzip_write(z: ZlibCodec, dst_gz_path: string, data: string) -> int:
    if z.ready == 0:
        return -1
    gzf := int_to_ptr(call_ptr2(z.fn_gzopen, ptr_to_int(str_cstr(dst_gz_path)), ptr_to_int(str_cstr("wb9"))))
    if gzf == null:
        return -1
    dlen := string_length(data)
    let mut rc: int = 0
    if dlen > 0:
        nw := call_ptr3(z.fn_gzwrite, ptr_to_int(gzf), ptr_to_int(str_cstr(data)), dlen)
        if nw <= 0:
            rc = -1
    call_ptr1(z.fn_gzclose, ptr_to_int(gzf))
    return rc

fn ssg_ensure_dir(dir_path: string, dir_cache: dict[string, int]) -> void:
    if string_length(dir_path) == 0 or dir_path == ".":
        return
    if dir_cache.has(dir_path) == 1:
        return
    if fs_is_dir(dir_path) == 0:
        fs_mkdir_p(dir_path)
    dir_cache[dir_path] = 1

fn fs_remove_rf(target_path: string) -> int:
    if string_length(target_path) == 0 or target_path == "/" or target_path == ".":
        return -1
    if fs_is_dir(target_path) == 1:
        entries := fs_list_dir(target_path)
        let mut i: int = 0
        while i < len(entries):
            full := ssg_path_join(target_path, entries[i])
            fs_remove_rf(full)
            i = i + 1
        return fs_remove(target_path)
    if file_exists(target_path) == 1:
        return fs_remove(target_path)
    return 0

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
                let mut matched: int = 0
                let mut ei: int = 0
                while ei < len(exts):
                    if ssg_ends_with(name, exts[ei]) == 1:
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
    rc := fs_copy_file(src_path, dst_path)
    if rc != 0:
        data := file_read(src_path)
        file_write(dst_path, data)
        return string_length(data)
    return fs_read_bytes_len(dst_path)

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
                sb_append(sb, str(fs_mtime_ns(ap)))
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
