#![allow(warnings)]

use std::fs;
use std::convert::TryFrom;
use std::mem;

const k1: f64 = 0.9; //BM25 k1 parameter
const b: f64 = 0.4; //BM25 b parameter

//where on the disk and how large (in bytes) is the postings list?
struct VocabEntry {
    offset: i32,
    size: i32,
}

fn main() -> std::io::Result<()> {
    //read the doc lengths
    let lengths_as_bytes = std::fs::read("lengths.bin").unwrap();

    // let length_vector: Vec<i32> = lengths_as_bytes.chunks_exact(8);

    // let length_vector: Vec<i32> = Vec::new();
    // for length in lengths_as_bytes.chunks_exact(8) {
    //     length_vector.push(mem::transmute::<[u8;4], i32>(length[0..8]));
    // }

    // for byte_pair in bytes.chunks_exact(2) {
    //     let short = u16::from_le_bytes([byte_pair[0], byte_pair[1]]);
    //     println!("{:x}", short);
    // }

    //compute average length for BM25
    //read the primary keys
    //open the postings list file
    //build the vocab in memory

    //search (one query per line)

    //sort the results list, tie break on docID

    //print the (at most) top 1000 documents in the results 
    //list in TREC eval format which is:
    //query-id Q0 document-id rank score run-name
    
    Ok(())
}