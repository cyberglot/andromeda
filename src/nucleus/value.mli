(** Runtime values and results *)

(** The values are "finished" or "computed" results. They are inert pieces
    of data.

    At the moment the only kind of value is a pair [(e,t)] where [e] is a
    term and [t] is a type. Such a value (in a given context [ctx]) indicates
    that the judgemnet [ctx |- e : t] is derivable. *)
type value =
  | Judge of Tt.term * Tt.ty
  | Closure of closure

(** A closure *)
and closure = value -> result

(** A result of computation at the moment is necessarily just a pure value
    because we do not have any operations in the language. But when we do,
    they will be results as well (and then handlers will handle them). *)
and result =
  | Return of value
  | Operation of string * value * closure

val as_judge : loc:Location.t -> value -> Tt.term * Tt.ty
val as_closure : loc:Location.t -> value -> closure

val return_judge : Tt.term -> Tt.ty -> result

(** [fresh x t] generates a fresh name [y] from name [x] and returns [y] and
    the judgment that [y] has type [t]. *)
val fresh: loc:Location.t -> Name.t -> Tt.ty -> Name.t * value

val bind: result -> closure -> result

(** Pretty-print a value. *)
val print : ?max_level:int -> Name.t list -> value -> Format.formatter -> unit

(** Pretty-print a judgement. *)
val print_judge : ?max_level:int -> Name.t list -> Tt.term * Tt.ty -> Format.formatter -> unit

(** Ugly-print a closure. *)
val print_closure : ?max_level:int -> Name.t list -> closure -> Format.formatter -> unit

(** Check that a result is a value and return it, or complain. *)
val to_value : loc:Location.t -> result -> value