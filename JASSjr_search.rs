#![allow(warnings)]

use std::fs;
use std::convert::TryFrom;
use std::mem;
use std::env;
use std::collections::HashMap;

const k1: f64 = 0.9; //BM25 k1 parameter
const b: f64 = 0.4; //BM25 b parameter

//where on the disk and how large (in bytes) is the postings list?
struct VocabEntry {
    position: i32,
    size: i32,
}

fn main() -> std::io::Result<()> {
    //read the doc lengths
    let lengths_as_bytes = std::fs::read("lengths.bin").unwrap();
    let mut length_vector: Vec<i32> = Vec::new();
    for length in lengths_as_bytes.chunks_exact(4) {
        length_vector.push(i32::from_ne_bytes(<[u8;4]>::try_from(length).unwrap()));
    }

    //compute average length for BM25
    let documents_in_collection: f64 = (lengths_as_bytes.len() / 4) as f64;
    let mut average_document_length: f64 = 0.0;
    for which in length_vector {
        average_document_length += f64::try_from(which).unwrap();
    }
    average_document_length /= documents_in_collection;

    //read the primary keys
    let primary_keys: String = std::fs::read_to_string("docids.bin").unwrap();
    let primary_key: Vec<&str> = primary_keys.split('\n').collect();

    //open the postings list file
    let mut postingsFile = fs::File::open("postings.bin")?;

    /* Remember that the vocab is formatted as:
        one byte length, string, '\0', 4 byte where, 4 byte size
    */

    //build the vocab in memory
    let mut vocab: HashMap<String,VocabEntry> = HashMap::new();
    let vocab_as_bytes = std::fs::read("vocab.bin")?;
    let mut offset = 0;
    while offset < vocab_as_bytes.capacity() {
        let string_length: usize = vocab_as_bytes[offset].into();
        offset += 1;

        let term = String::from_utf8(vocab_as_bytes[offset..string_length].to_vec()).unwrap();
        offset += string_length + 1; //null terminated

        let position: i32 = i32::from_ne_bytes(<[u8;4]>::try_from(vocab_as_bytes.get(offset..offset+4).unwrap()).unwrap());
        offset += 4;

        let size: i32 = i32::from_ne_bytes(<[u8;4]>::try_from(vocab_as_bytes.get(offset..offset+4).unwrap()).unwrap()) ;
        offset += 4;

        vocab.insert(term, VocabEntry {position: position, size: size});
    }

    //search (one query per line)

    //sort the results list, tie break on docID

    //print the (at most) top 1000 documents in the results 
    //list in TREC eval format which is:
    //query-id Q0 document-id rank score run-name
    
    Ok(())
}