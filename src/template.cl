// ==============================================================================
// Module:      Legacy Template Facade (src/template.cl)
// Project:     Cluster SSG (Unifying Jekyll + Hugo + Astro in Pure .cl)
// Description: Compatibility wrapper routing legacy template calls through template_v2.cl.
// ==============================================================================

import "src/template_v2.cl"
import "src/document.cl"

fn template_render_page(tr: TemplateRegistry, doc: SsgDocument, site_name: string, site_tagline: string) -> string:
    vars := dict[string, string]()
    vars["title"] = doc.cld.meta.title
    vars["author"] = doc.cld.meta.author
    vars["date"] = doc.cld.meta.date
    vars["description"] = doc.cld.meta.description
    vars["tags"] = doc.cld.meta.tags
    vars["slug"] = doc.cld.meta.slug

    lists := dict[string, string]()
    let items: vector[PageSummary] = []
    let p_idx: vector[int] = []
    let pg_idx: vector[int] = []
    let pgn_idx: vector[int] = []
    let pools: vector[vector[int]] = []
    col_i := dict[string, int]()
    tag_i := dict[string, int]()
    cat_i := dict[string, int]()
    dreg := DataRegistry(dict[string, string](), dict[string, int]())
    cfg := config_default()
    cfg.site_name = site_name
    cfg.site_tagline = site_tagline

    ctx := RenderContext(vars, lists, items, p_idx, pg_idx, pgn_idx, pools, col_i, tag_i, cat_i, dreg, cfg)
    let mut ln: string = doc.cld.meta.layout
    if string_length(ln) == 0:
        ln = "default"
    return template_v2_render(tr, ln, doc.html_body, vars, ctx)
