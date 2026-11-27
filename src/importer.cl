// ==============================================================================
// Module:      Jekyll / Hugo / Markdown Native Importer (src/importer.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Zero-Python importer migrating Jekyll (_posts, _layouts, _includes,
//              _data, _config.yml), Hugo (content, layouts, data, static, hugo.toml),
//              and plain Markdown folders cleanly into Cluster-SSG projects.
// ==============================================================================

import "src/strbuf.cl"
import "src/fs_walk.cl"
import "src/config.cl"

model ImportReport:
    pages_imported: int
    posts_imported: int
    layouts_imported: int
    components_imported: int
    data_imported: int
    assets_copied: int

fn importer_run(src_root: string, target_root: string) -> ImportReport:
    if fs_is_dir(src_root) == 0:
        println("Error: source directory does not exist: " + src_root)
        return ImportReport(0, 0, 0, 0, 0, 0)

    dir_cache := dict[string, int]()
    site_dir := ssg_path_join(target_root, "site")
    ssg_ensure_dir(ssg_path_join(site_dir, "pages"), dir_cache)
    ssg_ensure_dir(ssg_path_join(site_dir, "posts"), dir_cache)
    ssg_ensure_dir(ssg_path_join(site_dir, "layouts"), dir_cache)
    ssg_ensure_dir(ssg_path_join(site_dir, "components"), dir_cache)
    ssg_ensure_dir(ssg_path_join(site_dir, "data"), dir_cache)
    ssg_ensure_dir(ssg_path_join(site_dir, "static"), dir_cache)

    let empty_exts: vector[string] = []
    scan := fs_walk_tree(src_root, empty_exts)

    let mut pages: int = 0
    let mut posts: int = 0
    let mut layouts: int = 0
    let mut comps: int = 0
    let mut datas: int = 0
    let mut assets: int = 0

    let mut i: int = 0
    while i < len(scan.abs_paths):
        ap := scan.abs_paths[i]
        rel := scan.rel_paths[i]
        ext := ssg_path_ext(rel)
        rel_l := ssg_lower(rel)

        // Skip build outputs and VCS dirs
        if ssg_starts_with(rel_l, "_site/") == 1 or ssg_starts_with(rel_l, "dist/") == 1 or ssg_starts_with(rel_l, "node_modules/") == 1:
            i = i + 1
            continue

        if rel == "_config.yml" or rel == "hugo.toml" or rel == "config.toml":
            fs_copy_file_raw(ap, ssg_path_join(target_root, ssg_path_basename(rel)), dir_cache)
            i = i + 1
            continue

        if ssg_starts_with(rel_l, "_layouts/") == 1 or ssg_starts_with(rel_l, "layouts/") == 1:
            base := ssg_path_basename(rel)
            if ssg_starts_with(rel_l, "layouts/partials/") == 1:
                fs_copy_file_raw(ap, ssg_path_join(site_dir, "components/" + base), dir_cache)
                comps = comps + 1
            else:
                fs_copy_file_raw(ap, ssg_path_join(site_dir, "layouts/" + base), dir_cache)
                layouts = layouts + 1
            i = i + 1
            continue

        if ssg_starts_with(rel_l, "_includes/") == 1 or ssg_starts_with(rel_l, "includes/") == 1 or ssg_starts_with(rel_l, "components/") == 1:
            sub := rel
            sl := ssg_find_from(rel, "/", 0)
            if sl > 0: sub = substring(rel, sl + 1, string_length(rel) - sl - 1)
            fs_copy_file_raw(ap, ssg_path_join(site_dir, "components/" + sub), dir_cache)
            comps = comps + 1
            i = i + 1
            continue

        if ssg_starts_with(rel_l, "_data/") == 1 or ssg_starts_with(rel_l, "data/") == 1:
            sub := rel
            sl := ssg_find_from(rel, "/", 0)
            if sl > 0: sub = substring(rel, sl + 1, string_length(rel) - sl - 1)
            fs_copy_file_raw(ap, ssg_path_join(site_dir, "data/" + sub), dir_cache)
            datas = datas + 1
            i = i + 1
            continue

        if ssg_starts_with(rel_l, "static/") == 1 or ssg_starts_with(rel_l, "assets/") == 1 or ssg_starts_with(rel_l, "public/") == 1:
            sub := rel
            sl := ssg_find_from(rel, "/", 0)
            if sl > 0: sub = substring(rel, sl + 1, string_length(rel) - sl - 1)
            fs_copy_file_raw(ap, ssg_path_join(site_dir, "static/" + sub), dir_cache)
            assets = assets + 1
            i = i + 1
            continue

        if ext == ".md" or ext == ".markdown" or ext == ".cld" or ext == ".clx":
            if ssg_contains(rel_l, "_posts/") == 1 or ssg_starts_with(rel_l, "posts/") == 1 or ssg_starts_with(rel_l, "content/posts/") == 1 or ssg_starts_with(rel_l, "blog/") == 1:
                dst := ssg_path_join(site_dir, "posts/" + ssg_path_basename(rel))
                fs_copy_file_raw(ap, dst, dir_cache)
                posts = posts + 1
            else:
                let mut sub: string = rel
                if ssg_starts_with(rel_l, "content/") == 1:
                    sub = substring(rel, 8, string_length(rel) - 8)
                elif ssg_starts_with(rel_l, "pages/") == 1:
                    sub = substring(rel, 6, string_length(rel) - 6)
                dst := ssg_path_join(site_dir, "pages/" + sub)
                fs_copy_file_raw(ap, dst, dir_cache)
                pages = pages + 1
        elif ext == ".css" or ext == ".js" or ext == ".png" or ext == ".jpg" or ext == ".jpeg" or ext == ".svg" or ext == ".webp" or ext == ".woff2" or ext == ".ico":
            fs_copy_file_raw(ap, ssg_path_join(site_dir, "static/" + rel), dir_cache)
            assets = assets + 1
        i = i + 1

    return ImportReport(pages, posts, layouts, comps, datas, assets)
