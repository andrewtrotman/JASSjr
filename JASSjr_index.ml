(*
  JASSJR_INDEX.ML
  ---------------
  Copyright (c) 2026 Vaughan Kitchen
  Minimalistic BM25 search engine.
*)

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

let tokenise filename =
  In_channel.with_open_text filename (fun ic ->
    let rec next_line () =
      match In_channel.input_line ic with
      | Some line ->
          let lexer = { input = line; pos = 0 } in
          let rec next_token () =
            match lex_get_next lexer with
            | Some token ->
                print_endline token;
                next_token ()
            | None -> next_line ()
          in
          next_token ()
      | None -> ()
    in
    next_line ())

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
  end else
  tokenise Sys.argv.(1)
