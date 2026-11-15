// ==============================================================================
// Cluster-SSG: Core Document Model & Binary Pipeline (src/cld.cl)
// 100% Pure Cluster Language · Zero External Dependencies
// ==============================================================================

import "std/cld.cl"

model SsgDocMeta:
    title: string
    author: string
    date: string
    layout: string
    tags: string
    slug: string
    description: string
    reading_time_min: int

model SsgDocument:
    cld: CldDoc
    source_path: string
    out_rel_path: string
    html_body: string
    compiled_page: string
    is_binary: int

fn ssg_estimate_reading_time(word_count: int) -> int:
    if word_count < 200:
        return 1
    return (word_count / 200) + 1

fn ssg_count_words(text: string) -> int:
    let tlen: int = len(text)
    if tlen == 0:
        return 0
    let mut words: int = 0
    let mut in_word: int = 0
    let mut i: int = 0
    while i < tlen:
        c := char_at(text, i)
        if c == " " or c == "\t" or c == "\n" or c == "\r":
            in_word = 0
        else:
            if in_word == 0:
                words = words + 1
                in_word = 1
        i = i + 1
    return words

fn ssg_load_cld(filepath: string, rel_out: string) -> SsgDocument:
    base_cld := cld_parse_file(filepath)
    body_html := cld_render_blocks(base_cld)
    
    // Estimate reading time from block content
    let mut total_words: int = 0
    let mut bi: int = 0
    while bi < len(base_cld.blocks):
        b := base_cld.blocks[bi]
        total_words = total_words + ssg_count_words(b.content)
        bi = bi + 1
    
    rt := ssg_estimate_reading_time(total_words)
    
    return SsgDocument(base_cld, filepath, rel_out, body_html, "", 0)

fn ssg_doc_to_binary(doc: SsgDocument) -> string:
    return cld_pack(doc.cld)

fn ssg_doc_from_binary(raw_bytes: string, filepath: string, rel_out: string) -> SsgDocument:
    base_cld := cld_unpack(raw_bytes)
    body_html := cld_render_blocks(base_cld)
    return SsgDocument(base_cld, filepath, rel_out, body_html, "", 1)
