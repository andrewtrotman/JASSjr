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

(* Compute the average document length for BM25 *)
let average_doc_length =
  float_of_int (Array.fold_left (+) 0 doc_lengths) /. float_of_int (Array.length doc_lengths)

(* Read the primary_keys *)
let primary_key =
  Array.of_list (In_channel.with_open_text "docids.bin" In_channel.input_lines)

(* Open the postings list file *)
let postings_file =
  open_in_bin "postings.bin"

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

(* Array of rsv values *)
let rsv = Array.make (Array.length doc_lengths) 0

(* Set up the rsv pointers *)
let rsv_pointers = Array.init (Array.length doc_lengths) Fun.id

(*
	MAIN()
	------
	Simple search engine ranking on BM25.
*)
let () =
  print_float average_doc_length
