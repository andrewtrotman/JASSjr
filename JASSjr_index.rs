/*
	JASSjr_index.rs
	---------------
	Copyright (c) 2024 Katelyn Harlan
	Minimalistic BM25 search engine.
*/

use std::io::{BufRead, BufReader, BufWriter, Write, Seek};
use std::fs::File;
use std::convert::TryFrom;
use std::env;
use std::collections::HashMap;

/*
  main()
  ------
  Simple indexer for TREC WSJ collection
*/
fn main() -> std::io::Result<()> {
    /*
      Make sure we have one parameter, the filename
    */
    let args: Vec<_> = env::args().collect();
    if args.len() != 2 {
        println!("Usage: {} <infile.xml>", args[0]);
        std::process::exit(1);
    }

    let mut vocab: HashMap<String,Vec<(i32,i32)>> = HashMap::new();
    let mut doc_ids: Vec<String> = Vec::new();
    let mut doc_lengths: Vec<i32> = Vec::new();

    let mut docid = -1;
    let mut document_length = 0;
    let mut push_next = false; // is the next token the primary key?

    {
        /*
          Open the file to index
        */
        let file = File::open(&args[1])?;
        let mut reader = BufReader::new(file);
        let mut buffer = String::new();
        let mut token = String::new();

        while reader.read_line(&mut buffer)? > 0 {
            let mut chars = buffer.chars();
            while let Some(c) = chars.next() {
                /*
                  A token is either an XML tag '<'..'>' or a sequence of alphanumerics
                */
                if !c.is_alphanumeric() {
                    //TREC <DOCNO> primary keys have a hyphen in them
                    if c == '-' && token.len() > 0 {
                        token.push(c);
                        continue;
                    }
                    if token.len() <= 0 && c != '<' {
                        continue;
                    }
                    //We are in a closing tag, not ending a token
                    if c == '/' && token.starts_with('<') {
                        token.push(c);
                        continue;
                    }
                    //We are at the end of a tag
                    if c == '>' && token.starts_with('<'){
                        token.push(c);
                    }

                    /*
                      If we see a <DOC> tag then we're at the start of the next document
                    */
                    if token == "<DOC>" {
                        /*
                          Save the previous document length
                        */
                        if docid != -1 {
                            doc_lengths.push(document_length);
                        }
                        /*
                          Move on to the next document
                        */
                        docid +=1;
                        document_length = 0;
                        if docid % 1000 == 0 {
                            println!("{} documents indexed", docid);
                        }
                    }
                    /*
                      If the last token we saw was a <DOCNO> then the next token is the primary key
                    */
                    if push_next {
                        doc_ids.push(token.clone());
                        push_next = false;
                    }
                    if token == "<DOCNO>" {
                        push_next = true;
                    }

                    /*
                      Don't index XML tags
                    */
                    if !token.starts_with('<') && token.len() > 0 {
                        /*
                          Lowercase the string
                        */
                        token = token.to_lowercase();

                        /*
                          Truncate long tokens at 255 characters (so that the length can be stored first and in a single byte)
                        */
                        token.truncate(255);
                        
                        /*
                          Add the posting to the in-memory index
                        */
                        if vocab.contains_key(&token) {
                            let posting_list: &mut Vec<(i32,i32)> = vocab.get_mut(&token).unwrap();
                            let num_postings = posting_list.len() -1;
                            if posting_list[num_postings].0 == docid { //increase the tf
                                posting_list[num_postings].1 += 1;
                            } else { //if the docno for this occurrence has changed then create a new <d,tf> pair
                                posting_list.push((docid,1));
                            }
                        }else { //if the term isn't in the vocab yet
                            let posting_list = vec![(docid,1)];
                            vocab.insert(token.clone(), posting_list);
                        }

                        /*
                          Compute the document length
                        */
                        document_length +=1;
                    }
                    token.clear();
                    if c == '<' {
                        token.push(c);
                    }       
                }else {
                    token.push(c);
                }
            }
            buffer.clear();
        }
    }

    /*
      If we didn't index any documents then we're done
    */
    if docid == -1 {
        return Ok(());
    }

    /*
      Tell the user we've got to the end of parsing
    */
    println!("Indexed {} documents. Serialising...", docid+1);

    /*
      Save the final document length
    */
    doc_lengths.push(document_length);

    /*
      Store the primary keys
    */
    {
        let mut writer = BufWriter::new(File::create("docids.bin")?);
        for id in doc_ids {
           writer.write_all(id.as_bytes())?;
           writer.write_all(b"\n")?;
        }
        writer.flush()?;
    }

    /*
      Serialise the in-memory index to disk
    */
    {
        let mut postings_writer = BufWriter::new(File::create("postings.bin")?);
        let mut vocab_writer = BufWriter::new(File::create("vocab.bin")?);
        for (term, postings_list) in &vocab {
            /*
              Write the postings list to one file
            */
            let offset: i32 = i32::try_from(postings_writer.stream_position()?).unwrap();
            for posting in postings_list {
                postings_writer.write_all(&posting.0.to_ne_bytes())?;
                postings_writer.write_all(&posting.1.to_ne_bytes())?;
            }
            /*
              Write the vocabulary to second file (one byte length, string, '\0', 4 byte where, 4 byte size)
            */
            vocab_writer.write_all(&[u8::try_from(term.len()).unwrap()])?;
            vocab_writer.write_all(term.as_bytes())?;
            vocab_writer.write_all(b"\0")?;
            vocab_writer.write_all(&offset.to_ne_bytes())?;
            vocab_writer.write_all(&i32::try_from(&postings_list.len() * 2 * 4).unwrap().to_ne_bytes())?;
        }
        postings_writer.flush()?;
        vocab_writer.flush()?;
    }

    /*
      Store the document lengths
    */
    {
        let mut writer = BufWriter::new(File::create("lengths.bin")?);
        for length in &doc_lengths {
            writer.write_all(&length.to_ne_bytes())?;
        }
        writer.flush()?;
    }

    Ok(())
}