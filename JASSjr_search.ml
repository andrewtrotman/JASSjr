(*
  JASSJR_SEARCH.ML
  ----------------
  Copyright (c) 2026 Vaughan Kitchen
  Minimalistic BM25 search engine.
*)

(*
  CONSTANTS
  ---------
*)
let k1 = 0.9 (* BM25 k1 parameter *)
let b = 0.4 (* BM25 b parameter *)

(*
  CLASS VOCAB_ENTRY
  -----------------
*)
type vocab_entry = {
  where : int32;
  size : int32;
}

(* Helper from Stdio/Base *)
let iter_lines (ic : in_channel) (f : string -> unit) : unit =
  In_channel.fold_lines (fun () line -> f line) () ic

(* Read the document lengths *)
let doc_lengths =
  In_channel.with_open_bin "lengths.bin" (fun ic ->
    let size = in_channel_length ic in
    let count = size / 4 in
    let buf = Bytes.create size in
    really_input ic buf 0 size;

    Array.init count (fun i ->
      Int32.to_int (Bytes.get_int32_ne buf (i * 4))
    )
  )

let documents_in_collection = Array.length doc_lengths

(* Compute the average document length for BM25 *)
let average_document_length =
  float_of_int (Array.fold_left (+) 0 doc_lengths) /. float_of_int documents_in_collection

(* Read the primary_keys *)
let primary_key =
  Array.of_list (In_channel.with_open_text "docids.bin" In_channel.input_lines)

(* Open the postings list file *)
let postings_file = open_in_bin "postings.bin"

(* Build the vocabulary in memory *)
let vocab =
  let ic = open_in_bin "vocab.bin" in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let file_size = in_channel_length ic in
      let data = really_input_string ic file_size |> Bytes.of_string in
      let dictionary = Hashtbl.create 100000 in

      let pos = ref 0 in

      while !pos < file_size do
        let string_length = Bytes.get_uint8 data !pos in
        let token = Bytes.sub_string data (!pos + 1) string_length in
        (* +1 for the length and + 1 for the '\0' *)
        let where = Bytes.get_int32_ne data (!pos + string_length + 2) in
        let size = Bytes.get_int32_ne data (!pos + string_length + 6) in

        Hashtbl.replace dictionary token { where; size };

        pos := !pos + string_length + 10
      done;

      dictionary
    )

(* Allocate buffers *)
let postings_buffer = Bytes.create (documents_in_collection * 8)

(* Array of rsv values *)
let rsv = Array.make documents_in_collection 0.0

(* Set up the rsv pointers *)
let rsv_pointers = Array.init documents_in_collection Fun.id

let extract_query_id line =
  match String.index_opt line ' ' with
  | Some pos ->
    (match int_of_string_opt (String.take_first pos line) with
    | Some id -> (id, String.drop_first (pos + 1) line)
    | None -> (0, line))
  | None -> (0, line)

(*
  MAIN()
  ------
  Simple search engine ranking on BM25.
*)
let () =
  (* Search (one query per line) *)
  iter_lines stdin (fun line ->
    (* Zero the accumulator array. *)
    for position = 0 to documents_in_collection - 1 do
      rsv.(position) <- 0.0;
    done;

    (* If the first token is a number then assume a TREC query number, and skip it *)
    let query_id, query = extract_query_id (String.trim line) in
    let tokens = String.split_on_char ' ' query in
    List.iter (fun token ->
      (* Does the term exist in the collection? *)
      match Hashtbl.find_opt vocab token with
      | Some term_details when term_details.size <> 0l ->
        (* Seek and read postings list *)
        let size = Int32.to_int term_details.size in
        let where = Int32.to_int term_details.where in

        seek_in postings_file where;
        really_input postings_file postings_buffer 0 size;

        let postings = size / 8 in

        (* Compute the IDF component of BM25 as log(N/n).
           if IDF == 0 then don't process this postings list as the BM25 contribution of this term will be zero. *)
        if postings <> documents_in_collection then begin
          let idf = log (float_of_int documents_in_collection /. float_of_int postings) in

          (* Process the postings list by simply adding the BM25 component for this document into the accumulators array *)
          for which = 0 to postings - 1 do
            let offset = which * 8 in

            let d =
              Bytes.get_int32_ne postings_buffer offset
              |> Int32.to_int
            in

            let tf =
              Bytes.get_int32_ne postings_buffer (offset + 4)
              |> Int32.to_int
            in

            rsv.(d) <- rsv.(d) +. idf *. ((float_of_int tf *. (k1 +. 1.)) /. (float_of_int tf +. k1 *. (1. -. b +. b *. (float_of_int doc_lengths.(d) /. average_document_length))))
          done
        end
      | _ -> ()
    ) tokens;

    (* Sort the results list *)
    Array.sort (fun a b ->
      let cmp = Float.compare rsv.(b) rsv.(a) in
      if cmp <> 0 then cmp else Int.compare b a
    ) rsv_pointers;

    (* Print the (at most) top 1000 documents in the results list in TREC eval format which is:
       query-id Q0 document-id rank score run-name *)
    let position = ref 0 in
    while !position < min 1000 (Array.length rsv_pointers) && rsv.(rsv_pointers.(!position)) <> 0.0 do
      let docid = rsv_pointers.(!position) in

      Printf.printf "%d Q0 %s %d %.4f JASSjr\n%!" query_id primary_key.(docid) (!position + 1) rsv.(docid);

      incr position
    done
  )
