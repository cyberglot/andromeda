let (>>=) = Runtime.bind
let return = Runtime.return

(** Matching *)

exception Match_fail

let add_var (v : Runtime.value) vs = v :: vs

let as_is_term jdg =
  match Nucleus.as_not_abstract jdg with
  | None -> raise Match_fail
  | Some (Nucleus.JudgementIsTerm e) -> e
  | Some Nucleus.(JudgementIsType _ | JudgementEqType _ | JudgementEqTerm _) -> raise Match_fail

let rec collect_pattern sgn xvs {Location.thing=p';loc} v =
  match p', v with
  | Rsyntax.Patt_Anonymous, _ -> xvs

  | Rsyntax.Patt_Var, v ->
     add_var v xvs

  | Rsyntax.Patt_As (p1, p2), v ->
     let xvs = collect_pattern sgn xvs p1 v in
     collect_pattern sgn xvs p2 v

  | Rsyntax.Patt_MLConstructor (tag, ps), Runtime.Tag (tag', vs) ->
     if not (Runtime.equal_tag tag tag')
     then
       raise Match_fail
     else
       collect_patterns sgn xvs ps vs

  | Rsyntax.Patt_TTConstructor (c, ps), Runtime.Judgement abstr ->
     begin match Nucleus.as_not_abstract abstr with
     | None -> raise Match_fail
     | Some jdg -> collect_constructor sgn xvs c ps jdg
     end

  | Rsyntax.Patt_GenAtom p, (Runtime.Judgement abstr as v) ->
     let e = as_is_term abstr in
     begin match Nucleus.invert_is_term sgn e with
     | Nucleus.Stump_TermAtom a ->
        collect_pattern sgn xvs p v
     | Nucleus.(Stump_TermConstructor _ | Stump_TermMeta _ | Stump_TermConvert _) ->
        raise Match_fail
     end

  | Rsyntax.Patt_IsType p, (Runtime.Judgement abstr as v) ->
     begin match Nucleus.as_not_abstract abstr with
     | None -> raise Match_fail
     | Some (Nucleus.JudgementIsType _) -> collect_pattern sgn xvs p v
     | Some Nucleus.(JudgementIsTerm _ | JudgementEqType _ | JudgementEqTerm _) -> raise Match_fail
     end

  | Rsyntax.Patt_IsTerm (p1, p2), (Runtime.Judgement abstr as v) ->
     (* By computing [e] first, we make sure that we're actually matching against
        a term judgement. If you change the order of evaluation, then it could
        happen that [p1] will match against [jdg] even though [jdg] is not a term
        judgement. *)
     let e = as_is_term abstr in
     let xvs = collect_pattern sgn xvs p1 v  in
     begin match p2 with
     | {Location.thing=Rsyntax.Patt_Anonymous;_} -> xvs
     | _ ->
        let t = Nucleus.type_of_term sgn e in
        let t_abstr = Nucleus.(abstract_not_abstract (JudgementIsType t)) in
        collect_judgement sgn xvs p2 t_abstr
     end

  | Rsyntax.Patt_EqType (pt1, pt2), Runtime.Judgement abstr ->
     begin match Nucleus.as_not_abstract abstr with
     | None | Some Nucleus.(JudgementIsTerm _ | JudgementIsType _ | JudgementEqTerm _) ->
        raise Match_fail
     | Some (Nucleus.JudgementEqType eq) ->
        begin match Nucleus.invert_eq_type eq with
        | Nucleus.Stump_EqType (_asmp, t1, t2) ->
           let t1_abstr = Nucleus.(abstract_not_abstract (JudgementIsType t1))
           and t2_abstr = Nucleus.(abstract_not_abstract (JudgementIsType t2)) in
           let xvs = collect_judgement sgn xvs pt1 t1_abstr in
           collect_judgement sgn xvs pt2 t2_abstr
        end
     end

  | Rsyntax.Patt_EqTerm (pe1, pe2, pt), Runtime.Judgement abstr ->
     begin match Nucleus.as_not_abstract abstr with
     | None | Some Nucleus.(JudgementIsTerm _ | JudgementIsType _ | JudgementEqType _) ->
        raise Match_fail
     | Some (Nucleus.JudgementEqTerm eq) ->
        begin match Nucleus.invert_eq_term eq with
        | Nucleus.Stump_EqTerm (_asmp, e1, e2, t) ->
           let e1_abstr = Nucleus.(abstract_not_abstract (JudgementIsTerm e1))
           and e2_abstr = Nucleus.(abstract_not_abstract (JudgementIsTerm e2))
           and t_abstr = Nucleus.(abstract_not_abstract (JudgementIsType t)) in
           let xvs = collect_judgement sgn xvs pe1 e1_abstr in
           let xvs = collect_judgement sgn xvs pe2 e2_abstr in
           collect_judgement sgn xvs pt t_abstr
        end
     end

  | Rsyntax.Patt_Abstract (xopt, p1, p2), Runtime.Judgement abstr ->
     begin match Nucleus.invert_judgement_abstraction abstr with
     | Nucleus.Stump_NotAbstract _ -> raise Match_fail
     | Nucleus.Stump_Abstract (a, abstr') ->
        let t_abstr = Nucleus.(abstract_not_abstract (JudgementIsType (type_of_atom a))) in
        let xvs = collect_judgement sgn xvs p1 t_abstr in
        let xvs =
          match xopt with
          | None -> xvs
          | Some _ ->
             let a_abstr = Nucleus.(abstract_not_abstract (JudgementIsTerm (form_is_term_atom a))) in
             add_var (Runtime.mk_judgement a_abstr) xvs
        in
        collect_judgement sgn xvs p2 abstr'
     end

  | Rsyntax.Patt_Tuple ps, Runtime.Tuple vs ->
     collect_patterns sgn xvs ps vs

  (* mismatches *)
  | Rsyntax.Patt_MLConstructor _,
    Runtime.(Judgement _ | Boundary _ | Closure _ | Handler _ | Ref _ | Dyn _ | Tuple _ | String _)

  | Rsyntax.(Patt_Abstract _ | Patt_TTConstructor _ | Patt_GenAtom _ | Patt_IsType _ | Patt_IsTerm _ | Patt_EqType _ | Patt_EqTerm _),
    Runtime.(Boundary _ | Closure _ | Handler _ | Tag _ | Ref _ | Dyn _ | Tuple _ | String _)

  | Rsyntax.Patt_Tuple _,
    Runtime.(Judgement _ | Boundary _ | Closure _ | Handler _ | Tag _ | Ref _ | Dyn _ | String _) ->
     Runtime.(error ~loc (InvalidPatternMatch v))

and collect_judgement sgn xvs p abstr =
  collect_pattern sgn xvs p (Runtime.mk_judgement abstr)

and collect_constructor sgn xvs c ps = function
  | Nucleus.JudgementIsType t ->
     begin match Nucleus.invert_is_type t with
     | Nucleus.Stump_TypeConstructor (c', args) ->
        if Ident.equal c c' then
          let args = List.map Runtime.mk_judgement args in
          collect_patterns sgn xvs ps args
        else
          raise Match_fail
     | Nucleus.Stump_TypeMeta _ -> raise Match_fail
     end

  | Nucleus.JudgementIsTerm e ->
     let rec collect e =
       begin match Nucleus.invert_is_term sgn e with
       | Nucleus.Stump_TermConvert (e, _) ->
          collect e

       | Nucleus.Stump_TermConstructor (c', args) ->
          if Ident.equal c c' then
            let args = List.map Runtime.mk_judgement args in
            collect_patterns sgn xvs ps args
          else
            raise Match_fail

       | Nucleus.(Stump_TermAtom _ | Stump_TermMeta _) ->
          raise Match_fail
       end
     in
     collect e

  | Nucleus.(JudgementEqType eq)  -> raise Match_fail

  | Nucleus.JudgementEqTerm _ -> raise Match_fail

and collect_patterns sgn xvs ps vs =
  match ps, vs with

  | [], [] -> xvs

  | p::ps, v::vs ->
     let xvs = collect_pattern sgn xvs p v in
     collect_patterns sgn xvs ps vs

  | [], _::_ | _::_, [] ->
     (* This should never happen because desugaring checks arities of constructors and patterns. *)
     assert false


let match_pattern' sgn p v =
  try
    let xvs = collect_pattern sgn [] p v in
    Some xvs
  with
    Match_fail -> None

let top_match_pattern p v =
  let (>>=) = Runtime.top_bind in
  Runtime.top_get_env >>= fun env ->
  let sgn = Runtime.get_signature env in
  let r = match_pattern' sgn p v in
  Runtime.top_return r

let match_pattern p v =
  (* collect values of pattern variables *)
  Runtime.get_env >>= fun env ->
  let sgn = Runtime.get_signature env in
  let r = match_pattern' sgn p v in
  return r

let collect_boundary_pattern sgn xvs pttrn bdry =
  failwith "pattern matching of boundaries not implemented"

let match_op_pattern ~loc ps p_bdry vs bdry =
  Runtime.get_env >>= fun env ->
  let sgn = Runtime.get_signature env in
  let r =
    begin
      try
        let xvs = collect_patterns sgn [] ps vs in
        let xvs =
          match p_bdry with
          | None -> xvs
          | Some p ->
             begin match bdry with
             | Some t -> collect_boundary_pattern sgn xvs p t
             | None -> xvs
             end
        in
        Some xvs
      with Match_fail -> None
    end in
  return r
