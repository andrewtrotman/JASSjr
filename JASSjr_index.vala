/*
 * JASSjr_index.vala
 * -----------------
 * Copyright (c) 2026 Vaughan Kitchen
 * Minimalistic BM25 search engine.
 */

using GLib;
using Gee;

public class Posting : Object {
    public int32 docid;
    public int32 tf;

    public Posting (int32 docid, int32 tf) {
        this.docid = docid;
        this.tf = tf;
    }
}

/*
 * One-character lookahead lexical analyser
 */
public class Lexer : Object {
    private string buffer;
    private int current;

    public void reinit (string line) {
        buffer = line;
        current = 0;
    }

    public string? next () {
        /*
         * Skip over whitespace and punctuation (but not XML tags)
         */
        while (current < buffer.length && !buffer[current].isalnum() && buffer[current] != '<')
            current++;

        // must be at end of line
        if (current >= buffer.length)
            return null;

        /*
         * A token is either an XML tag '<'..'>' or a sequence of alpha-numerics.
         */
        int start = current;
        if (buffer[current].isalnum()) {
            // TREC <DOCNO> primary keys have a hyphen in them
            while (current < buffer.length && (buffer[current].isalnum() || buffer[current] == '-'))
                current++;
        } else if (buffer[current] == '<') {
            current++;

            while (current < buffer.length && buffer[current - 1] != '>')
                current++;
        }

        /*
         * Copy and return the token
         */
        return buffer.substring (start, current - start);
    }
}

public class JASSjrIndexer : Object {
    // the in-memory index
    private HashMap<string, ArrayList<Posting>> vocab = new HashMap<string, ArrayList<Posting>>();
    // the primary keys
    private ArrayList<string> doc_ids = new ArrayList<string>();
    // hold the length of each document
    private ArrayList<int32?> doc_lengths = new ArrayList<int32?>();

    private Lexer lexer = new Lexer();

    /*
     * engage()
     * --------
     * Simple indexer for TREC WSJ collection
    */
    public void engage (string filename) throws Error {
        // open the file to index
        FileStream input = FileStream.open (filename, "rb");

        if (input == null) {
            stderr.printf ("can't open file %s\n", filename);
            return;
        }

        int32 docid = -1;
        int32 document_length = 0;
        bool push_next = false; // is the next token the primary key?

        // index line at a time where a line fits in this buffer
        char[] buffer = new char[1024 * 1024];

        while (input.gets (buffer) != null) {
            string line = (string) buffer;

            lexer.reinit (line);

            string? token;
            while ((token = lexer.next ()) != null) {
                // If we see a <DOC> tag then we're at the start of the next document
                if (token == "<DOC>") {
                    // Save the previous document length
                    if (docid != -1)
                        doc_lengths.add (document_length);

                    // Move on to the next document
                    docid++;
                    document_length = 0;

                    if ((docid % 1000) == 0)
                        stdout.printf ("%d documents indexed\n", docid);
                }

                // if the last token we saw was a <DOCNO> then the next token is the primary key
                if (push_next) {
                    doc_ids.add (token);
                    push_next = false;
                }
                if (token == "<DOCNO>")
                    push_next = true;

                // Don't index XML tags
                if (token[0] == '<')
                    continue;

                // lower case the string
                string lowercase = token.down ();

                // truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte)
                if (lowercase.length > 255)
                    lowercase = lowercase.substring (0, 255);

                // add the posting to the in-memory index
                ArrayList<Posting>? list = vocab.get (lowercase);
                // if the term isn't in the vocab yet 
                if (list == null) {
                    list = new ArrayList<Posting>();
                    list.add (new Posting (docid, 1));
                    vocab.set (lowercase, list);
                } else {
                    Posting last = list[list.size - 1];

                    // if the docno for this occurence has changed then create a new <d,tf> pair
                    if (last.docid != docid)
                        list.add (new Posting (docid, 1));
                    // else increase the tf
                    else
                        last.tf++;
                }

                // compute the document length
                document_length++;
            }
        }

        // If we didn't index any documents then we're done.
        if (docid == -1)
            return;

        // Save the final document length
        doc_lengths.add (document_length);

        // tell the user we've got to the end of parsing
        stdout.printf ("Indexed %d documents. Serialising...\n", docid + 1);

        // store the primary keys
        var docid_stream = new DataOutputStream (
            new BufferedOutputStream (
                File.new_for_path ("docids.bin").replace (
                    null, false, FileCreateFlags.NONE
                )
            )
        );

        foreach (string id in doc_ids) {
            docid_stream.put_string (id);
            docid_stream.put_byte ('\n');
        }

        // serialise the in-memory index to disk
        var postings_stream = new DataOutputStream (
            new BufferedOutputStream (
                File.new_for_path ("postings.bin").replace (
                    null, false, FileCreateFlags.NONE
                )
            )
        );
        postings_stream.set_byte_order (LITTLE_ENDIAN);
        var vocab_stream = new DataOutputStream (
            new BufferedOutputStream (
                File.new_for_path ("vocab.bin").replace (
                    null, false, FileCreateFlags.NONE
                )
            )
        );
        vocab_stream.set_byte_order (LITTLE_ENDIAN);

        foreach (string term in vocab.keys) {
            // write the postings list to one file
            ArrayList<Posting> list = vocab.get (term);
            int32 where = (int32) postings_stream.tell ();
            foreach (Posting posting in list) {
                postings_stream.put_int32 (posting.docid);
                postings_stream.put_int32 (posting.tf);
            }

            // write the vocabulary to a second file (one byte length, string, '\0', 4 byte where, 4 byte size)
            int32 size = (int32) (list.size * 2 * sizeof (int32));
            vocab_stream.put_byte ((uint8) term.length);
            vocab_stream.put_string (term);
            vocab_stream.put_byte (0);
            vocab_stream.put_int32 (where);
            vocab_stream.put_int32 (size);
        }

        // store the document lengths
        var lengths_stream = new DataOutputStream (
            new BufferedOutputStream (
                File.new_for_path ("lengths.bin").replace (
                    null, false, FileCreateFlags.NONE
                )
            )
        );
        lengths_stream.set_byte_order (LITTLE_ENDIAN);

        foreach (int32? length in doc_lengths)
            lengths_stream.put_int32 (length);
    }


    public static int main (string[] args) {
        // Make sure we have one parameter, the filename
        if (args.length != 2) {
            stdout.printf ("Usage: %s <infile.xml>\n", args[0]);
            return 0;
        }

        try {
            var indexer = new JASSjrIndexer ();
            indexer.engage (args[1]);
        } catch (Error e) {
            stderr.printf("Error: %s\n", e.message);
        }

        return 0;
    }
}
