(** Runtime environment *)

type t

(** The empty environment *)
val empty : t

(** List of constants with their arities. *)
val constants : t -> (Name.ident * int) list

(** Known bound variables *)
val bound_names : t -> Name.ident list

(** Variable names already used in the environment *)
val used_names : t -> Name.ident list

(** Lookup a constant. *)
val lookup_constant : Name.ident -> t -> Tt.constsig option

(** Lookup a free variable by its de Bruijn index *)
val lookup_bound : Syntax.bound -> t -> Value.value

(** Return all beta hints in the environment *)
val beta_hints : Pattern.hint_key -> t -> Pattern.beta_hint list

(** Return all eta hints in the environment *)
val eta_hints : Pattern.hint_key -> t -> Pattern.eta_hint list

(** Return all general hints in the environment *)
val general_hints : Pattern.general_key -> t -> Pattern.general_hint list

(** Return all general hints in the environment *)
val inhabit_hints : Pattern.hint_key -> t -> Pattern.inhabit_hint list

(** [add_fresh ~loc env x t] generates a fresh atom [y] from identifier [x]. Return [y] and
    the environment updated with [x] bound to [y:t]. *)
val add_fresh: loc:Location.t -> t -> Name.ident -> Judgement.ty -> Name.atom * t

(** Add a constant of a given signature to the environment.
    Fails if the constant is already bound. *)
val add_constant : Name.ident -> Tt.constsig -> t -> t

(** Add a beta hint to the environment. *)
val add_betas : (string list * (Pattern.hint_key * Pattern.beta_hint)) list -> t -> t

(** Add an eta hint to the environment. *)
val add_etas : (string list * (Pattern.hint_key * Pattern.eta_hint)) list -> t -> t

(** Add a general hint to the environment. *)
val add_generals :
  (string list *
   (Pattern.general_key * Pattern.general_hint)) list ->
  t -> t

(** Add an inhabit hint to the environment. *)
val add_inhabits : (string list * (Pattern.hint_key * Pattern.inhabit_hint)) list -> t -> t

(** Remove all hints with one of the given tags *)
val unhint : string list -> t -> t

(** Add a bound variable with given name to the environment. *)
val add_bound : Name.ident -> Value.value -> t -> t

(** Add a file to the list of files included. *)
val add_file : string -> t -> t

(** Check whether a file has already been included. Files are compared by
    their basenames *)
val included : string -> t -> bool

(** Print free variables in the environment *)
val print : t -> Format.formatter -> unit
