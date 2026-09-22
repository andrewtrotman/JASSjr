(*
  JASSJR_INDEX.ML
  ---------------
  Copyright (c) 2026 Vaughan Kitchen
  Minimalistic BM25 search engine.
*)

(* a postings list is an ordered pair of <docid,tf> integers *)
type posting = {
  d : int;
  mutable tf : int;
}

let vocab = Hashtbl.create 0 (* the in-memory index *)
let doc_ids : string list ref = ref [] (* the primary keys *)
let doc_lengths : int list ref = ref [] (* hold the length of each document *)

type lexer = {
  input : string;
  mutable pos : int;
}

let is_alnum = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' -> true
  | _ -> false

(*
  LEX_GET_NEXT()
  --------------
  One-character lookahead lexical analyser
*)
let lex_get_next lex =
  let s = lex.input in
  let len = String.length s in

  (* Skip over whitespace and punctuation (but not XML tags) *)
  while lex.pos < len && not (is_alnum s.[lex.pos]) && s.[lex.pos] <> '<' do
    lex.pos <- lex.pos + 1
  done;

  (* A token is either an XML tag '<'..'>' or a sequence of alpha-numerics. *)
  if lex.pos >= len then
    None
  else
    let start = lex.pos in
    if is_alnum s.[lex.pos] then begin
      lex.pos <- lex.pos + 1;
      while lex.pos < len && (is_alnum s.[lex.pos] || s.[lex.pos] = '-') do
        lex.pos <- lex.pos + 1
      done;
      Some (String.sub s start (lex.pos - start))
    end else if s.[lex.pos] = '<' then begin
      lex.pos <- lex.pos + 1;
      while lex.pos < len && s.[lex.pos - 1] <> '>' do
        lex.pos <- lex.pos + 1
      done;
      Some (String.sub s start (lex.pos - start))
    end else
      None

let truncate s max_len =
  if String.length s <= max_len then
    s
  else
    String.sub s 0 max_len

(*
  MAIN()
  ------
  Simple indexer for TREC WSJ collection
*)
let () =
  (* Make sure we have one paramter, the filename *)
  if Array.length Sys.argv <> 2 then begin
    Printf.eprintf "Usage: %s <infile.xml>\n" Sys.argv.(0);
    exit 1
  end;

  let docid = ref (-1) in
  let document_length = ref 0 in
  let push_next = ref false in (* is the next token the primary key? *)

  (* open the file to index *)
  In_channel.with_open_text Sys.argv.(1) (fun ic ->
    let rec next_line () =
      match In_channel.input_line ic with
      | Some line ->
          let lexer = { input = line; pos = 0 } in
          let rec next_token () =
            match lex_get_next lexer with
            | Some token ->
                (* If we see a <DOC> tag then we're at the start of the next document *)
                if token = "<DOC>" then begin
                  (* Save the previous document length *)
                  doc_lengths := !document_length :: !doc_lengths;

                  (* Move on to the next document *)
                  docid := !docid + 1;
                  document_length := 0;

                  if !docid mod 1000 = 0 then Printf.printf "%d documents indexed\n" !docid
                end;

                (* if the last token we saw was a <DOCNO> then the next token is the primary key *)
                if !push_next then begin
                  doc_ids := token :: !doc_ids;
                  push_next := false
                end;
                if token = "<DOCNO>" then push_next := true;

                (* Don't index XML tags *)
                if token.[0] <> '<' then begin
                  (* lower case the string *)
                  let lowercase = String.lowercase_ascii token in

                  (* truncate any long tokens at 255 charactes (so that the length can be stored first and in a single byte) *)
                  let lowercase = truncate lowercase 255 in

                  (* add the posting to the in-memory index *)
                  match Hashtbl.find_opt vocab lowercase with
                  (* if the term isn't in the vocab yet *)
                  | None ->
                      Hashtbl.add vocab lowercase [{ d = !docid; tf = 1 }]
                  (* if the docno for this occurence is the same then increase the tf *)
                  | Some ({ d; tf } as posting :: postings) when d = !docid ->
                      posting.tf <- tf + 1
                  (* else create a new <d,tf> pair *)
                  | Some postings ->
                      Hashtbl.replace vocab token ({ d = !docid; tf = 1 } :: postings);

                  (* Compute the document length *)
                  document_length := !document_length + 1
                end;

                next_token ()
            | None -> next_line ()
          in
          next_token ()
      | None -> ()
    in
    next_line ())
