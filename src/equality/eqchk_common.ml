(** Types for pattern matching *)
module Patt =
struct

  type is_type_normal' =
    | TypeConstructor of Ident.t * argument list
    | TypeFreeMeta of Nonce.t * is_term' list

  and is_type' =
    | TypeAddMeta of int
    | TypeCheckMeta of int
    | TypeNormal of is_type_normal'

  and is_term_normal' =
    | TermConstructor of Ident.t * argument list
    | TermFreeMeta of Nonce.t * is_term' list
    | TermAtom of Nonce.t
    | TermBound of int

  and is_term' =
    | TermAddMeta of int
    | TermCheckMeta of int
    | TermNormal of is_term_normal'

  and argument =
    | Arg_Abstract of Name.t * argument
    | Arg_NotAbstract of argument'

  and argument' =
    | ArgumentIsType of is_type'
    | ArgumentIsTerm of is_term'

  (** the exported types also record how many meta-variables we're capturing. *)
  type is_term = is_term' * int
  type is_type = is_type' * int

end

(** Sets of integers to indicate where the heads are. *)
module IntSet = Set.Make(struct
                          type t = int
                          let compare = Stdlib.compare
                        end)

(** Maps of atoms to deal with bound variables *)
let cmp_atom atm1 atm2 =
   Nonce.compare (Nucleus.atom_nonce atm1) (Nucleus.atom_nonce atm2)

module BoundMap =
  Map.Make
    (struct
      type t = Nucleus.is_atom
      let compare = cmp_atom
    end)

(** We index rules by the heads of expressions, which can be identifiers or meta-variables (nonces). *)
type symbol =
  | Ident of Ident.t
  | Nonce of Nonce.t

exception Equality_fail of string

exception Invalid_rule of string

exception Normalization_fail of string

exception Fatal_error of string

(** A tag to indicate that a term or a type is normalized *)
type 'a normal = Normal of 'a

let print_symbol ~penv sym ppf =
  match sym with
  | Ident x -> Ident.print ~opens:penv.Nucleus.opens ~parentheses:false x ppf
  | Nonce n -> Nonce.print ~questionmark:false ~parentheses:false n ppf

let compare_symbol x y =
  match x, y with
  | Ident _, Nonce _ -> -1
  | Ident i, Ident j -> Ident.compare i j
  | Nonce n, Nonce m -> Nonce.compare n m
  | Nonce _, Ident _ -> 1

module SymbolMap = Map.Make(
                   struct
                     type t = symbol
                     let compare = compare_symbol
                   end)

(** Is an exposed premise an object premise? *)
let rec is_object_premise = function
  | Nucleus_types.(NotAbstract (BoundaryIsType _ | BoundaryIsTerm _)) -> true
  | Nucleus_types.(NotAbstract (BoundaryEqType _ | BoundaryEqTerm _)) -> false
  | Nucleus_types.Abstract (_, _, prem) -> is_object_premise prem

(** The head symbol of an exposed term. *)
let head_symbol_term e =
  let rec fold = function
    | Nucleus_types.TermBoundVar _ -> assert false
    | Nucleus_types.(TermAtom {atom_nonce=n; _}) -> Nonce n
    | Nucleus_types.TermConstructor (c, _) -> Ident c
    | Nucleus_types.(TermMeta (MetaFree {meta_nonce;_}, _)) -> Nonce meta_nonce
    | Nucleus_types.(TermMeta (MetaBound _, _)) -> raise (Fatal_error "head symbol of a bound term metavariable does not exist")
    | Nucleus_types.TermConvert (e, _, _) -> fold e
  in
  fold e


(** The head symbol of an exposed type. *)
let head_symbol_type = function
  | Nucleus_types.TypeConstructor (c, _) -> Ident c
  | Nucleus_types.(TypeMeta (MetaFree {meta_nonce=n;_}, _)) -> Nonce n
  | Nucleus_types.(TypeMeta (MetaBound _, _)) -> raise (Fatal_error "head symbol of a bound type metavariable does not exist")

(** Apply rap to a list of arguments *)
let rap_apply rap args =
  let rec fold rap args =
  match rap, args with
  | rap, [] -> rap
  | Nucleus.RapMore (_bdry, f), arg :: args -> fold (f arg) args
  | Nucleus.RapDone _, _::_ -> raise (Fatal_error "Applying the rule to too many arguments")
  in
  try
    fold rap args
  with
  | Nucleus.Error err -> raise (Fatal_error "Nucleus error")

(** Apply rap to a list of arguments, return the judgement *)
let rap_fully_apply rap args =
  let rec fold rap args =
  match rap, args with
  | Nucleus.RapDone jdg, [] -> jdg
  | Nucleus.RapMore (_bdry, f), arg :: args ->
    ();
    let tmp = f (arg) in
    fold tmp args
  | Nucleus.RapDone _, _::_ -> raise (Fatal_error "Applying the rule to too many arguments")
  | Nucleus.RapMore _, [] -> raise (Fatal_error "Applying the rule to too few arguments")
  in
  try
    Some (fold rap args)
  with
  | Nucleus.Error _ -> None

(** Automagically compute the heads of a pattern *)

let arg_is_head abstr =
  let rec fold = function
    | Patt.Arg_Abstract (_, abstr) -> fold abstr
    | Patt.Arg_NotAbstract jdg ->
      begin
      match jdg with
        | Patt.(ArgumentIsType (TypeAddMeta _ | TypeCheckMeta _)) -> false
        | Patt.(ArgumentIsType (TypeNormal _)) -> true
        | Patt.(ArgumentIsTerm (TermAddMeta _ | TermCheckMeta _)) -> false
        | Patt.(ArgumentIsTerm (TermNormal _)) -> true
      end
  in fold abstr

let term_is_head = function
  | Patt.(TermAddMeta _ | TermCheckMeta _) -> false
  | Patt.TermNormal _ -> true

let heads_args args =
  let rec fold hs i = function
    | [] -> hs
    | arg :: args ->
       if arg_is_head arg then
         fold (IntSet.add i hs) (i+1) args
       else
         fold hs (i+1) args
  in
  fold IntSet.empty 0 args

let heads_terms es =
  let rec fold hs i = function
    | [] -> hs
    | e :: es ->
       if term_is_head e then
         fold (IntSet.add i hs) (i+1) es
       else
         fold hs (i+1) es
  in
  fold IntSet.empty 0 es

let heads_term_normal = function
  | Patt.TermAtom _ -> IntSet.empty

  | Patt.TermConstructor (_, args) -> heads_args args

  | Patt.TermFreeMeta (_, es) -> heads_terms es

  | Patt.TermBound v -> IntSet.empty

let heads_term = function
  | Patt.TermAddMeta _ -> IntSet.empty
  | Patt.TermCheckMeta _ -> IntSet.empty
  | Patt.TermNormal patt -> heads_term_normal patt

let heads_type_normal = function
  | Patt.TypeConstructor (_, args) -> heads_args args
  | Patt.TypeFreeMeta (_, es) -> heads_terms es

let heads_type = function
  | Patt.TypeAddMeta _ -> IntSet.empty
  | Patt.TypeCheckMeta _ -> IntSet.empty
  | Patt.TypeNormal patt -> heads_type_normal patt
