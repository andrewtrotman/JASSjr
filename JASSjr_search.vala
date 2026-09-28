/*
 * JASSjr_search.vala
 * ------------------
 * Copyright (c) 2026 Vaughan Kitchen
 * Minimalistic BM25 search engine.
 */

using GLib;
using Gee;

const double K1 = 0.9; // BM25 k1 parameter
const double B = 0.4; // BM25 b parameter

class VocabEntry {
    // where on the disk and how large (in bytes) is the postings list?
    public uint32 where;
    public uint32 size;

    public VocabEntry (uint32 where, uint32 size) {
        this.where = where;
        this.size = size;
    }
}

class JASSjrSearch {
    HashMap<string, VocabEntry> vocab = new HashMap<string, VocabEntry> (); // the vocab
    string[] docids; // the list of global IDs (i.e. primary keys)
    uint32[] lengths;
    double average_length;
    uint8[] postings_buffer; // the postings list once loaded from disk
    double[] scores; // array of rsv values
    double*[] rsv_pointers;

    FileInputStream postings_file;

    public JASSjrSearch () throws Error {
        /*
         * Read the document lengths
         */
        uint8[] lengths_data;
        FileUtils.get_data ("lengths.bin", out lengths_data);
        lengths = (uint32[]) lengths_data;
        lengths.length = lengths_data.length / (int)sizeof(uint32);

        /*
         * Compute the average document length for BM25
         */
        foreach (uint32 length in lengths)
            average_length += length;
        average_length /= lengths.length;

        /*
         * Read the primary_keys
         */
        string docids_data;
        FileUtils.get_contents ("docids.bin", out docids_data);
        docids = docids_data.strip ().split ("\n");

        /*
         * Open the postings list file
         */
        postings_file = File.new_for_path ("postings.bin").read ();

        /*
         * Build the vocabulary in memory
         */
         var vocab_stream = new DataInputStream (
            File.new_for_path ("vocab.bin").read ()
        );
        vocab_stream.set_byte_order (LITTLE_ENDIAN);

        try {
            while (true) {
                int length = vocab_stream.read_byte ();

                string term = (string) vocab_stream.read_bytes (length + 1).get_data ();

                uint32 where = vocab_stream.read_uint32 ();
                uint32 size = vocab_stream.read_uint32 ();

                vocab[term] = new VocabEntry (where, size);
            }
        } catch (IOError e) {}

        /*
         * Allocate buffers
         */
        postings_buffer = new uint8[lengths.length * 2 * sizeof(uint32)];
        scores = new double[lengths.length];

        /*
         * Set up the rsv pointers
         */
        rsv_pointers = new double*[lengths.length];
        for (int i = 0; i < scores.length; i++)
            rsv_pointers[i] = &scores[i];
    }

    public void engage () throws Error {
        /*
         * Search (one query per line)
         */
        string? query;
        while ((query = stdin.read_line ()) != null) {
            /*
             * Zero the accumulator array.
             */
            for (int i = 0; i < scores.length; i++)
                scores[i] = 0;

            string[] tokens = query.strip ().split (" ");

            bool first = true;
            int64 query_id = 0;

            foreach (string token in tokens) {
                /*
                 * If the first token is a number then assume a TREC query number, and skip it
                */
                if (first && token[0].isdigit ()) {
                    query_id = int64.parse (token);
                    first = false;
                    continue;
                }
                first = false;

                /*
                 * Does the term exist in the collection?
                 */
                VocabEntry? entry = vocab.get (token);
                if (entry == null)
                    continue;

                /*
                 * if IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero.
                 */
                uint32 postings_count = entry.size / 8;
                if (postings_count == lengths.length)
                    continue;

                /*
                 * Compute the IDF component of BM25 as log(N/n).
                 */
                double idf = Math.log ((double) lengths.length / postings_count);

                /*
                 * Seek and read the postings list
                 */
                postings_file.seek ((int64) entry.where, SeekType.SET);

                size_t bytes_read;
                postings_file.read_all (postings_buffer[0:entry.size], out bytes_read);

                unowned uint32[] postings = (uint32[]) postings_buffer;
                postings.length = (int) (bytes_read / sizeof(uint32));

                /*
                 * Process the postings list by simply adding the BM25 component for this document into the accumulators array
                 */
                for (int position = 0; position < postings.length; position += 2) {
                    uint32 docid = postings[position];
                    uint32 tf = postings[position + 1];

                    scores[docid] += idf * ((tf * (K1 + 1.0)) / (tf + K1 * (1.0 - B + B * (lengths[docid] / average_length))));
                }
            }

            /*
             * Sort the results list
             */
            Posix.qsort (rsv_pointers, rsv_pointers.length, sizeof (double*), (ap, bp) => {
                var a = *(double**) ap;
                var b = *(double**) bp;

                return *a > *b ? -1 : *a < *b ? 1 : (int) ((int64) b - (int64) a);
            });

            /*
             * Print the (at most) top 1000 documents in the results list in TREC eval format which is:
             * query-id Q0 document-id rank score run-name
             */
            int limit = int.min (1000, rsv_pointers.length);
            for (int position = 0; *rsv_pointers[position] != 0.0 && position < limit; position++) {
                uint64 docid = ((uint64) rsv_pointers[position] - (uint64) scores) / sizeof(double);

                stdout.printf ("%" + int64.FORMAT + " Q0 %s %d %.4f JASSjr\n", query_id, docids[docid], position + 1, scores[docid]);
            }
        }
    }
}

int main (string[] args) {
    try {
        var engine = new JASSjrSearch ();
        engine.engage ();
    }
    catch (Error e) {
        stderr.printf ("Error: %s\n", e.message);
        return 1;
    }

    return 0;
}
