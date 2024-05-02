#![allow(non_upper_case_globals)]

use std::convert::TryFrom;
use std::collections::HashMap;
use std::io::{BufRead,SeekFrom,Seek,Read};

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
    for which in &length_vector {
        average_document_length += *which as f64;
    }
    average_document_length /= documents_in_collection as f64;

    //read the primary keys
    let primary_keys: String = std::fs::read_to_string("docids.bin").unwrap();
    let primary_key: Vec<&str> = primary_keys.split('\n').collect();

    //open the postings list file
    let mut postings_file = std::fs::File::open("postings.bin")?;

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
    let mut rsv: Vec<f64> = vec![0.0; documents_in_collection as usize];

    //set up the rsv pointers
    let mut rsv_pointers: Vec<i32> = (0..documents_in_collection).collect();

    //search (one query per line)
    let stdin = std::io::stdin();
    for line in stdin.lock().lines() {
        //zero the accumulator array, initialise the rsv pointers
        for i in 0..documents_in_collection {
            rsv[i as usize] = 0.0;
            rsv_pointers[i as usize] = i;
        }
        let mut first_term: bool = true;
        let mut query_id: i64 = 0;
        for term in line.unwrap().split_whitespace() {
            //if the first token is a number then assume a TREC query number, and skip it
            if first_term && term.parse::<i64>().is_ok() {
                query_id = term.parse::<i64>().unwrap();
                first_term = false;
                continue;
            }

            //does the term exist in the collection?
            match dictionary.get(term) {
                Some(term_details) => {
                    //seek and read the postings list
                    let mut current_list_as_bytes: Vec<u8> = vec![0;term_details.size as usize];
                    let _ = postings_file.seek(SeekFrom::Start(term_details.position as u64));
                    postings_file.read_exact(&mut current_list_as_bytes)?;
                    let mut current_list: Vec<i32> = Vec::with_capacity(current_list_as_bytes.len()/4);
                    for posting in current_list_as_bytes.chunks_exact(4) {
                       current_list.push(i32::from_ne_bytes(<[u8;4]>::try_from(posting).unwrap()));
                    }
                    let postings: i32 = current_list_as_bytes.len() as i32 / 8;

                    /*
                      Compute the IDF component of BM25 as log(N/n).
                      If IDF == 0 then don't process this postings list as the BM25 contribution of
                      this term will be zero .
                    */
                    if documents_in_collection == postings {
                        continue;
                    }
                    let idf: f64 = (documents_in_collection as f64 / postings as f64).ln();

                    /*
                      Process the postings list by simply adding the BM25 component for this document
                      into the accumulators array
                    */
                    for posting in current_list.chunks_exact(2) {
                        let d: f64 = posting[0] as f64;
                        let tf: f64 = posting[1] as f64;
                        rsv[d as usize] += idf * ((tf * (k1 + 1.0)) / (tf + k1 * (1.0 - b + b * (length_vector[d as usize] as f64 / average_document_length))));
                    }
                }
                None => {
                    continue;
                }
            }
        }

        //sort the results list, tie break on docID
        rsv_pointers.sort_by(|x,y| rsv[*y as usize].partial_cmp(&rsv[*x as usize]).unwrap());

        /* 
          Print the (at most) top 1000 documents in the results 
          list in TREC eval format which is:
          query-id Q0 document-id rank score run-name
        */
        for (i,r) in rsv_pointers.iter().enumerate() {
            if rsv[*r as usize] == 0.0 || i == 1000 {
                break;
            }
            println!("{} Q0 {} {} {:.4} JASSjr", query_id, primary_key[rsv_pointers[i as usize] as usize], i+1, rsv[*r as usize]);
        }
    }
    
    Ok(())
}