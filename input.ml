(** Abstract syntax of input files. *)

(** Abstract syntax of terms as given by the user. *)

type universe =
  | Type of int
  | Fib of int

type eqsort =
  | Ju
  | Pr

type operation_tag =
  | Inhabit
  | Coerce


type 'a term = 'a term' * Common.position
and 'a term' =
  | Var of 'a
  | Type
  | Lambda of Common.variable * 'a term option * 'a term
  | Pi of Common.variable * 'a term * 'a term
  | App of 'a term * 'a term
  | Sigma of Common.variable * 'a term * 'a term
  | Pair of 'a term * 'a term
  | Proj of string * 'a term
  | Ascribe of 'a term * 'a term
  | Operation of operation_tag * 'a term list
  | Handle of 'a term * 'a handler
  | Equiv of eqsort * 'a term * 'a term * 'a term


and 'a handler_body = 'a term

and 'a handler =
   (operation_tag * 'a term list * 'a handler_body) list

type 'a toplevel = 'a toplevel' * Common.position
and 'a toplevel' =
  | TopDef of Common.variable * 'a term
  | TopParam of Common.variable list * 'a term
  | Context
  | Help
  | Quit

let string_of_tag = function
  | Inhabit -> "Inhabit"
  | Coerce -> "Coerce"

let string_of_eqsort = function
  | Ju -> "Ju"
  | Pr -> "Pr"

let string_of_term string_of_var =
  let rec loop = function (term, loc) ->
  begin
    match term with
    | Var x -> string_of_var x
    | Type -> "Type"
    | Lambda(x,None,t2) ->
      "Lambda(" ^ x ^ "," ^ "_" ^ "," ^ (loop t2) ^ ")"
    | Lambda(x,Some t1,t2) ->
        "Lambda(" ^ x ^ "," ^ (loops [t1;t2]) ^ ")"
    | Pi(x,t1,t2) ->
        "Pi(" ^ x ^ "," ^ (loops [t1;t2]) ^ ")"
    | Sigma(x,t1,t2) ->
        "Sigma(" ^ x ^ "," ^ (loops [t1;t2]) ^ ")"
    | App(t1,t2) ->
        "App(" ^ (loops [t1;t2]) ^ ")"
    | Pair(t1,t2) ->
        "Pair(" ^ (loops [t1;t2]) ^ ")"
    | Proj(s1, t2) ->
        "Proj(\"" ^ s1 ^ "\"," ^ (loop t2) ^ ")"
    | Ascribe(t1,t2) ->
        "Ascribe(" ^ (loops [t1;t2]) ^ ")"
    | Operation(tag,terms) ->
        "Operation(" ^ (string_of_tag tag) ^ "," ^ (loops terms) ^ ")"
    | Handle(term, cases) ->
        "Handle(" ^ (loop term) ^ "," ^ (String.concat "|" (List.map
         string_of_case cases)) ^ ")"
    | Equiv(o,t1,t2,t3) ->
        "Equiv(" ^ (string_of_eqsort o) ^ "," ^ loops [t1; t2; t3] ^ ")"
   end

     and loops terms = (String.concat "," (List.map loop terms))

     and string_of_case (tag, terms, c) =
          (string_of_tag tag) ^ "(" ^ (loops terms) ^ ") => " ^ (loop c)
  in
    loop

let printI term = print_endline (string_of_term (fun s -> s) term)

(********************************************)
(** Desugaring of input syntax to internal  *)
(********************************************)

(** [index ~loc x xs] finds the location of [x] in the list [xs]. *)
let index ~loc x =
  let rec index k = function
    | [] -> Error.typing ~loc "unknown identifier %s" x
    | y :: ys -> if x = y then k else index (k + 1) ys
  in
    index 0

(** [doTerm xs e] converts an expression of type [Common.variable expr] to type
    [Common.debruijn expr] by
    replacing names in [e] with de Bruijn indices. Here [xs] is the list of names
    currently in scope (e., Context.names) *)
let rec doTerm xs (e, loc) =
  (match e with
    | Var x -> Var (index ~loc x xs)
    | Type  -> Type
    | Pi (x, t1, t2) -> Pi (x, doTerm xs t1, doTerm (x :: xs) t2)
    | Sigma (x, t1, t2) -> Sigma (x, doTerm xs t1, doTerm (x :: xs) t2)
    | Lambda (x, None  , e) -> Lambda (x, None, doTerm (x :: xs) e)
    | Lambda (x, Some t, e) -> Lambda (x, Some (doTerm xs t), doTerm (x :: xs) e)
    | App (e1, e2)   -> App (doTerm xs e1, doTerm xs e2)
    | Pair (e1, e2)   -> Pair (doTerm xs e1, doTerm xs e2)
    | Proj (s1, e2) -> Proj (s1, doTerm xs e2)
    | Ascribe (e, t) -> Ascribe (doTerm xs e, doTerm xs t)
    | Operation (optag, terms) -> Operation (optag, List.map (doTerm xs) terms)
    | Handle (term, h) -> Handle (doTerm xs term, handler xs h)
    | Equiv (o, t1, t2, t3) -> Equiv (o, doTerm xs t1, doTerm xs t2, doTerm xs t3)
  ),
  loc

(*
and doComputation xs (c, loc) =
  (match c with
    | Return e -> Return (doTerm xs e)
    | Let (x, term1, c2) -> Let (x, doTerm xs term1, doComputation (x::xs) c2)),
  loc
  *)

and handler xs lst = List.map (handler_case xs) lst
(*
and handler_case xs (optag, terms, c) =
  (optag, List.map (doTerm xs) terms, doComputation xs c)
*)
and handler_case xs (optag, terms, c) =
  (optag, List.map (doTerm xs) terms, doTerm xs c)


  (* Based on similar shift code in Syntax *)

let rec shift ?(c=0) d (e, loc) =
  (match e with
  | Var m -> if (m < c) then Var m else Var(m+d)
  | Type  -> Type
  | Pi (x, t1, t2) -> Pi(x, shift ~c d t1, shift ~c:(c+1) d t2)
  | Sigma (x, t1, t2) -> Sigma(x, shift ~c d t1, shift ~c:(c+1) d t2)
  | Lambda (x, None, e) -> Lambda (x, None, shift ~c:(c+1) d e)
  | Lambda (x, Some t, e) -> Lambda (x, Some (shift ~c d t), shift ~c:(c+1) d e)
  | App (e1, e2) -> App(shift ~c d e1, shift ~c d e2)
  | Pair (e1, e2) -> Pair(shift ~c d e1, shift ~c d e2)
  | Proj (s1, e2) -> Proj(s1, shift ~c d e2)
  | Ascribe (e1, t2) -> Ascribe (shift ~c d e1, shift ~c d t2)
  | Operation (optag, terms) -> Operation (optag, List.map (shift ~c d) terms)
  | Handle (term, h) -> Handle (shift ~c d term, List.map (shift_handler_case ~c d) h)
  | Equiv (o, t1, t2, t3) -> Equiv (o, shift ~c d t1, shift ~c d t2, shift ~c d t3)),
  loc

and shift_handler_case ?(c=0) d (optag, terms, term) =
  (* Correct only because we have no pattern matching ! *)
  (optag, List.map (shift ~c d) terms, shift ~c d term)

let print =
  let to_string = string_of_term string_of_int  in
  function term -> print_endline (to_string term)



