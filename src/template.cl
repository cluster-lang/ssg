// ==============================================================================
// Cluster-SSG: Template & Layout Engine (src/template.cl)
// 100% Pure Cluster Language · Zero External Dependencies
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

// Full template rendering for an SSG document
fn template_render_page(tr: TemplateRegistry, doc: SsgDocument, site_name: string, site_tagline: string) -> string:
    layout_name := doc.cld.meta.layout
    if len(layout_name) == 0:
        layout_name = "default"
    
    raw_layout := template_get_layout(tr, layout_name)
    // 1. Resolve includes
    layout := template_resolve_includes(tr, raw_layout)
    
    // 2. Variable substitutions
    let mut res: string = layout
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
