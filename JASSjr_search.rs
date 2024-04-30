#![allow(warnings)]

use std::fs;
use std::convert::TryFrom;
use std::mem;
use std::env;
use std::collections::HashMap;
use std::io::{self, BufRead};

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
    let documents_in_collection: i32 = length_vector.len() as i32;
    let mut average_document_length: f64 = 0.0;
    for which in length_vector {
        average_document_length += f64::try_from(which).unwrap();
    }
    average_document_length /= documents_in_collection as f64;

    //read the primary keys
    let primary_keys: String = std::fs::read_to_string("docids.bin").unwrap();
    let primary_key: Vec<&str> = primary_keys.split('\n').collect();

    //open the postings list file
    let mut postingsFile = fs::File::open("postings.bin")?;

    /* Remember that the vocab is formatted as:
        one byte length, string, '\0', 4 byte where, 4 byte size
    */

    //build the vocab in memory
    let mut dictionary: HashMap<String,VocabEntry> = HashMap::new();
    let vocab_as_bytes = std::fs::read("vocab.bin")?;
    let mut offset = 0;
    while offset < vocab_as_bytes.capacity() {
        let string_length: usize = vocab_as_bytes[offset].into();
        offset += 1;

        let term = String::from_utf8(vocab_as_bytes[offset..(offset + string_length)].to_vec()).unwrap();
        offset += string_length + 1; //null terminated

        let position: i32 = i32::from_ne_bytes(<[u8;4]>::try_from(vocab_as_bytes.get(offset..(offset+4)).unwrap()).unwrap());
        offset += 4;

        let size: i32 = i32::from_ne_bytes(<[u8;4]>::try_from(vocab_as_bytes.get(offset..(offset+4)).unwrap()).unwrap()) ;
        offset += 4;

        dictionary.insert(term, VocabEntry {position: position, size: size});
    }

    //allocate buffers
    let mut rsv: Vec<f64> = Vec::with_capacity(documents_in_collection as usize);

    //set up the rsv pointers
    let mut rsv_pointers: Vec<i32> = Vec::with_capacity(documents_in_collection as usize);
    rsv_pointers = (0..documents_in_collection).collect();

    //search (one query per line)
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        //zero the accumulator array
        rsv = vec![0.0; documents_in_collection as usize];
        let mut first_term: bool = true;
        let mut query_id: i64 = 0;
        for term in line.unwrap().split_whitespace() {
            //if the first token is a number then assume a TREC query number, and skip it
            if first_term && term.parse::<i64>().is_ok() {
                query_id = term.parse::<i64>().unwrap();
                continue;
            }

            //does the term exist in the collection?
            // let term_details: VocabEntry = dictionary.get(&term);
            match dictionary.get(term) {
                Some(term_details) => {
                    //seek and read the postings list

                    //compute the IDF component of BM25 as log(N/n)
                    //if IDF == 0 then don't process this postings list as the BM25 contribution of
                    //this term will be zero

                    //process the postings list by simply adding the BM25 compontent for this document
                    //into the accumulators array
                }
                None => {
                    continue;
                }
            }
        }

        //sort the results list, tie break on docID


        //print the (at most) top 1000 documents in the results 
        //list in TREC eval format which is:
        //query-id Q0 document-id rank score run-name
    }
    
    Ok(())
}