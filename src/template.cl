// ==============================================================================
// Module:      Template & Layout Engine (template.cl)
// Project:     Cluster SSG (Static Site Generator & Binary Wire Engine)
// Author:      Zaid Alamgir (ZK Company)
// License:     MIT License
// Description: Layout inheritance, variable substitution, and partial inclusion pipeline.
// ==============================================================================

import "std/cld.cl"
import "src/document.cl"

model TemplateRegistry:
    layout_names: vector[string]
    layout_contents: vector[string]
    include_names: vector[string]
    include_contents: vector[string]

fn template_new() -> TemplateRegistry:
    let l_names: vector[string] = []
    let l_conts: vector[string] = []
    let i_names: vector[string] = []
    let i_conts: vector[string] = []
    return TemplateRegistry(l_names, l_conts, i_names, i_conts)

fn template_register_layout(tr: TemplateRegistry, name: string, content: string) -> void:
    tr.layout_names.push(name)
    tr.layout_contents.push(content)

fn template_register_include(tr: TemplateRegistry, name: string, content: string) -> void:
    tr.include_names.push(name)
    tr.include_contents.push(content)

fn template_get_layout(tr: TemplateRegistry, name: string) -> string:
    let mut i: int = 0
    while i < len(tr.layout_names):
        if tr.layout_names[i] == name:
            return tr.layout_contents[i]
        i = i + 1
    // Fallback: return default layout or first layout if available
    if len(tr.layout_contents) > 0:
        return tr.layout_contents[0]
    ob := "{" + "{"
    cb := "}" + "}"
    return "<!DOCTYPE html><html><body>" + ob + " content " + cb + "</body></html>"

fn template_get_include(tr: TemplateRegistry, name: string) -> string:
    let mut i: int = 0
    while i < len(tr.include_names):
        if tr.include_names[i] == name:
            return tr.include_contents[i]
        i = i + 1
    return "<!-- Include not found: " + name + " -->"

// Replace {{ include "name" }}
fn template_resolve_includes(tr: TemplateRegistry, layout: string) -> string:
    let llen: int = len(layout)
    ob := "{" + "{"
    cb_sp := "\" " + "}" + "}"
    cb_raw := "\"" + "}" + "}"
    tag_start := ob + " include \""
    let tlen: int = len(tag_start)
    
    let mut out: string = ""
    let mut i: int = 0
    while i < llen:
        if i + tlen <= llen:
            sub := substring(layout, i, tlen)
            if sub == tag_start:
                // Find closing quote and braces: " }}
                let mut name_end: int = -1
                let mut ci: int = i + tlen
                while ci < llen:
                    if char_at(layout, ci) == "\"" and ci + 3 <= llen:
                        if substring(layout, ci, 4) == cb_sp or substring(layout, ci, 3) == cb_raw:
                            name_end = ci
                            break
                    ci = ci + 1
                
                if name_end > i + tlen:
                    inc_name := substring(layout, i + tlen, name_end - (i + tlen))
                    inc_html := template_get_include(tr, inc_name)
                    out = out + inc_html
                    // Skip past closing
                    if substring(layout, name_end, 4) == cb_sp:
                        i = name_end + 4
                    else:
                        i = name_end + 3
                    continue
        out = out + char_at(layout, i)
        i = i + 1
    return out

fn template_eval_conditional(tmpl: string, key: string, is_present: int) -> string:
    op_b := "{" + "%"
    cl_b := "%" + "}"
    tag_open := op_b + " if " + key + " " + cl_b
    tag_close := op_b + " endif " + cl_b
    if cld_contains(tmpl, tag_open) == 0 or cld_contains(tmpl, tag_close) == 0:
        return tmpl
    
    let tlen: int = len(tmpl)
    let olen: int = len(tag_open)
    let clen: int = len(tag_close)
    let mut out: string = ""
    let mut i: int = 0
    let mut chunk_start: int = 0
    
    while i < tlen:
        if i + olen <= tlen and substring(tmpl, i, olen) == tag_open:
            if i > chunk_start:
                out = out + substring(tmpl, chunk_start, i - chunk_start)
            let mut close_idx: int = -1
            let mut ci: int = i + olen
            while ci + clen <= tlen:
                if substring(tmpl, ci, clen) == tag_close:
                    close_idx = ci
                    break
                ci = ci + 1
            if close_idx != -1:
                if is_present == 1:
                    inner := substring(tmpl, i + olen, close_idx - (i + olen))
                    out = out + inner
                i = close_idx + clen
                chunk_start = i
                continue
        i = i + 1
    if chunk_start < tlen:
        out = out + substring(tmpl, chunk_start, tlen - chunk_start)
    return out

// Full template rendering for an SSG document
fn template_render_page(tr: TemplateRegistry, doc: SsgDocument, site_name: string, site_tagline: string) -> string:
    layout_name := doc.cld.meta.layout
    if len(layout_name) == 0:
        layout_name = "default"
    
    raw_layout := template_get_layout(tr, layout_name)
    // 1. Resolve includes
    layout := template_resolve_includes(tr, raw_layout)
    
    // 2. Evaluate conditionals ({% if author %} ... {% endif %})
    let mut res: string = layout
    let mut has_author: int = 0
    if len(doc.cld.meta.author) > 0: has_author = 1
    res = template_eval_conditional(res, "author", has_author)

    let mut has_tags: int = 0
    if len(doc.cld.meta.tags) > 0: has_tags = 1
    res = template_eval_conditional(res, "tags", has_tags)

    let mut has_desc: int = 0
    if len(doc.cld.meta.description) > 0: has_desc = 1
    res = template_eval_conditional(res, "description", has_desc)

    // 3. Variable substitutions
    res = cld_template_replace(res, "content", doc.html_body)
    res = cld_template_replace(res, "title", doc.cld.meta.title)
    res = cld_template_replace(res, "author", doc.cld.meta.author)
    res = cld_template_replace(res, "date", doc.cld.meta.date)
    res = cld_template_replace(res, "description", doc.cld.meta.description)
    res = cld_template_replace(res, "tags", doc.cld.meta.tags)
    res = cld_template_replace(res, "slug", doc.cld.meta.slug)
    res = cld_template_replace(res, "site_name", site_name)
    res = cld_template_replace(res, "site_tagline", site_tagline)
    res = cld_template_replace(res, "year", "2026")
    return res
