(****************************************************************************)
(* Export HOL-Light proofs to Dedukti. *)
(****************************************************************************)

open Xprelude
open Fusion
open Xlib
open Xproof

(****************************************************************************)
(* Translation of names. *)
(****************************************************************************)

(* Dedukti valid identifiers *)
let is_valid_first_letter = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '!' | '?' -> true
  | _ -> false;;
let is_valid_non_first_letter = function
  | 'a'..'z' | 'A'..'Z' | '0'..'9' | '_' | '!' | '?' | '\'' -> true
  | _ -> false;;
let is_valid_id s =
  String.for_all is_valid_non_first_letter s
  && s <> ""
  && s.[0] <> '\''
  && s <> "_";;

(* We rename some symbols to make files smaller and more readable. *)
let valid_name = function
  | "=" -> "eq"
  | "," -> "pair"
  | "@" -> "choice"
  | "\\/" -> "or"
  | "/\\" -> "and"
  | "==>" -> "imp"
  | "!" -> "all"
  | "?" -> "ex"
  | "?!" -> "ex1"
  | "~" -> "not"
  | n ->
     (* We use String.escaped because of a bug in Dedukti 2.7. This
        can be removed once the fix is merged in the next release. *)
     if is_valid_id n then n else "{|" ^ String.escaped n ^ "|}"
;;

let name oc n = string oc (valid_name n);;

let typ_name oc n =
  string oc
    (match n with
       (* type names used also as constant names are capitalized *)
     | "sum" | "topology" | "metric" | "multiset" -> String.capitalize_ascii n
     | n -> valid_name n)
  (*match !stage with
  | Types | No_abbrev -> name oc n
  | _ -> out oc "%s_types.%a" !basename name n*)

let cst_name = name
  (*match !stage with
  | Terms | No_abbrev -> name oc n
  | _ -> out oc "%s_terms.%a" !basename name n*)
;;

let suffix s oc n = name oc (n ^ s);;

(****************************************************************************)
(* Translation of types. *)
(****************************************************************************)

let rec raw_typ oc b =
  match b with
  | Tyvar n -> name oc n
  | Tyapp(n,[]) -> typ_name oc n
  | Tyapp(n,bs) -> out oc "(%a%a)" typ_name n (list_prefix " " raw_typ) bs
;;

(* [unabbrev_typ tvs oc b] prints on [oc] the type [b]. Type variables
   not in [tvs] are replaced by [bool]. We need to do this because 1)
   types msut be explicit in Dedukti and 2) a proof of a statement may
   have more type variables than the statement itself. *)
let unabbrev_typ tvs =
  let rec typ oc b =
    match b with
    | Tyvar n ->
       if List.mem b tvs then name oc n
       else out oc "(;%a;)%a" name n typ_name "bool"
    | Tyapp(n,[]) -> typ_name oc n
    | Tyapp(n,bs) -> out oc "(%a%a)" typ_name n (list_prefix " " typ) bs
  in typ
;;

let part : int option ref = ref None;;

let typ_abbrev oc k =
  match !part with
  | None -> out oc "type%d" k
  | Some i -> out oc "type%d_%d" i k
;;

let abbrev_typ =
  let idx = ref (-1) in
  fun oc b ->
  match b with
  | Tyvar n -> name oc n
  | Tyapp(n,[]) -> typ_name oc n
  | _ ->
     (* check whether the type is already abbreviated; add a new
        abbreviation if needed *)
     let tvs, b = canonical_typ b in
     let k =
       match TypHashtbl.find_opt htbl_type_abbrev b with
       | Some (k,_) -> k
       | None ->
          let k = !idx + 1 in
          idx := k;
          let x = (k, List.length tvs) in
          TypHashtbl.add htbl_type_abbrev b x;
          k
     in
     match tvs with
     | [] -> typ_abbrev oc k
     | _ -> out oc "(%a%a)" typ_abbrev k (list_prefix " " raw_typ) tvs
;;

let typ tvs oc b = abbrev_typ oc (missing_as_bool tvs b);;

(* [decl_map_typ oc] outputs on [oc] the type abbreviations. *)
let decl_map_typ oc =
  let abbrev b (k,n) =
    out oc "def %a := " typ_abbrev k;
    for i=0 to n-1 do out oc "a%d : %a => " i typ_name "Set" done;
    (* We can use [raw_type] here because [b] is canonical. *)
    out oc "%a.\n" raw_typ b
  in
  (*List.iter abbrev
    (List.sort (fun (_,(k1,_)) (_,(k2,_)) -> k1 - k2)
       (MapTyp.fold (fun b x l -> (b,x)::l) m []))*)
  TypHashtbl.iter abbrev htbl_type_abbrev
;;

(****************************************************************************)
(* Translation of term variables. *)
(****************************************************************************)

let raw_var oc t =
  match t with
  | Var(n,_) -> name oc n
  | _ -> assert false
;;

(* [var rmap oc t] prints on [oc] the variable [t] using the name
   given by [rmap]. Fails if [t] is not a variable or if [t] is not in
   [rmap]. Variables need to be renamed in Dedukti or Lambdapi
   because, in HOL-Light, a variable is identified by both its name
   AND its type, that is, two distinct variables can have the same
   name but distinct types. *)
let var rmap oc t =
  try name oc (List.assoc t rmap)
  with Not_found -> assert false
    (*match t with
    | Var(n,_) -> out oc "%a (;not found;)" name n
    | _ -> assert false*)
;;

let raw_decl_var oc t =
  match t with
  | Var(n,b) -> out oc "%a : %a %a" name n cst_name "El" raw_typ b
  | _ -> assert false
;;

let decl_var tvs rmap oc t =
  match t with
  | Var(_,b) -> out oc "%a : %a %a" (var rmap) t cst_name "El" (typ tvs) b
  | _ -> assert false
;;

let unabbrev_decl_var tvs rmap oc t =
  match t with
  | Var(_,b) ->
     out oc "%a : %a %a" (var rmap) t cst_name "El" (unabbrev_typ tvs) b
  | _ -> assert false
;;

let decl_param tvs rmap oc v = out oc "%a -> " (decl_var tvs rmap) v;;

let unabbrev_decl_param tvs rmap oc v =
  out oc "%a -> " (unabbrev_decl_var tvs rmap) v;;

let param tvs rmap oc v = out oc "%a => " (decl_var tvs rmap) v;;

(****************************************************************************)
(* Translation of terms. *)
(****************************************************************************)

(* [raw_term oc t] prints on [oc] the term [t] as it is, including types. *)
let raw_term =
  let rec term oc t =
    match t with
    | Var(n,_) -> name oc n
    | Const(n,b) ->
       begin match List.map (subtyp b) (const_typ_vars_pos n) with
       | [] -> out oc "%a" cst_name n
       | bs -> out oc "(%a%a)" cst_name n (list_prefix " " raw_typ) bs
       end
    | Comb(_,_) ->
       let h, ts = head_args t in
       out oc "(%a%a)" term h (list_prefix " " term) ts
    | Abs(u,v) ->
       out oc "(%a => %a)" raw_decl_var u term v
  in term
;;

(* [unabbrev_term tvs rmap oc t] prints on [oc] the term [t] with type
   variables [tvs] and term variable renaming map [rmap], without
   using term abbreviations. A variable of type b not in [rmap] is
   replaced by [el b]. *)
let unabbrev_term tvs =
  let typ = typ tvs in
  let rec term rmap oc t =
    match t with
    | Var(n,b) ->
       begin
         try name oc (List.assoc t rmap)
         with Not_found -> out oc "(;%a;)(%a %a)" name n cst_name "el" typ b
       end
    | Const(n,b) ->
       begin match List.map (subtyp b) (const_typ_vars_pos n) with
       | [] -> cst_name oc n
       | bs ->
          out oc "(%a%a)" cst_name n (list_prefix " " (unabbrev_typ tvs)) bs
       end
    | Comb(_,_) ->
       let h, ts = head_args t in
       out oc "(%a%a)" (term rmap) h (list_prefix " " (term rmap)) ts
    | Abs(t,u) ->
       let rmap' = add_var rmap t in
       out oc "(%a => %a)" (unabbrev_decl_var tvs rmap') t (term rmap') u
  in term
;;

let term_abbrev oc k =
  match !part with
  | None -> out oc "term%d" k
  | Some i -> out oc "term%d_%d" i k
;;

let abbrev_term =
  let idx = ref (-1) in
  let abbrev oc t =
    (* check whether the term is already abbreviated; add a new
       abbreviation if needed *)
    let tvs, vs, bs, t = canonical_term t in
    let k =
      match TrmHashtbl.find_opt htbl_term_abbrev t with
      | Some (k,_,_) -> k
      | None ->
         let k = !idx + 1 in
         idx := k;
         let x = (k, List.length tvs, bs) in
         TrmHashtbl.add htbl_term_abbrev t x;
         k
    in
    out oc "(%a%a%a)" term_abbrev k
      (list_prefix " " raw_typ) tvs (list_prefix " " raw_var) vs
  in
  fun tvs ->
  let rec term oc t =
    match t with
    | Var(n,_) -> name oc n
    | Const(n,b) ->
       begin match List.map (subtyp b) (const_typ_vars_pos n) with
       | [] -> cst_name oc n
       | bs -> out oc "(%a%a)" cst_name n (list_prefix " " (typ tvs)) bs
       end
    | Comb(Comb(Const("=",b),u),v) ->
       out oc "(eq %a %a %a)" (typ tvs) (get_domain b) term u term v
    | _ -> abbrev oc t
  in term
;;

(* [subst_missing_as_bool] returns a type substitution mapping every
   type variable of [b] not in [yvs] to bool. *)
let subst_missing_as_bool tvs b =
  (*List.map (fun tv -> (bool_ty, tv))
    (List.filter (fun tv -> not (List.mem tv tvs)) (tyvars b))*)
  List.filter_map
    (fun tv -> if List.mem tv tvs then None else Some(bool_ty, tv))
    (tyvars b)
;;

(* [rename tvs rmap t] returns a new term obtained from [t] by applying
   [rmap] and by replacing variables not occurring in [rmap] by the
   constant [el], and type variables not occurring in [tvs] by bool. *)
let rename tvs =
  let rec rename rmap t =
    match t with
    | Var(_,b) ->
       let b = missing_as_bool tvs b in
       (try mk_var(List.assoc t rmap, b) with Not_found -> mk_el b)
    | Const(_,b) ->
       let su = subst_missing_as_bool tvs b in
       if su = [] then t else inst su t
    | Comb(u,v) -> Comb(rename rmap u, rename rmap v)
    | Abs(u,v) ->
       let rmap' = add_var rmap u in Abs(rename rmap' u,rename rmap' v)
  in rename
;;

(* [term tvs rmap oc t] prints on [oc] the term [t] with type
   variables [tvs] and term variable renaming map [rmap]. A variable
   of type [b] not in [rmap] is replaced by [el b]. *)
let term tvs rmap oc t = abbrev_term tvs oc (rename tvs rmap t);;

(* [decl_map_term oc] outputs on [oc] the term abbreviations. *)
let decl_map_term oc =
  let abbrev t (k,n,bs) =
    out oc "def %a := " term_abbrev k;
    for i=0 to n-1 do out oc "a%d : %a => " i typ_name "Set" done;
    (* We can use abbrev_typ here since [bs] are canonical. *)
    List.iteri
      (fun i b -> out oc "x%d: %a %a => " i cst_name "El" abbrev_typ b) bs;
    (* We can use [raw_term] here since [t] is canonical. *)
    out oc "%a.\n" raw_term t
  in
  (*List.iter abbrev
    (List.sort (fun (_,(k1,_,_)) (_,(k2,_,_)) -> k1 - k2)
       (MapTrm.fold (fun b x l -> (b,x)::l) m []))*)
  TrmHashtbl.iter abbrev htbl_term_abbrev
;;

(****************************************************************************)
(* Translation of proofs. *)
(****************************************************************************)

(* In a theorem, the hypotheses [t1;..;tn] are given the names
   ["h1";..;"hn"]. *)
let hyp_var ts oc t = out oc "h%d" (try 1 + index t ts with _ -> 0);;

(* Printing on [oc] of the subproof [p2] of index [i2] given:
- tvs: list of type variables of the theorem
- rmap: renaming map for term variables
- ty_su: type substitution that needs to be applied
- tm_su: term substitution that needs to be applied
- ts1: hypotheses of the theorem *)
let subproof tvs rmap ty_su tm_su ts1 i2 oc p2 =
  let typ = typ tvs in
  let term = term tvs rmap in
  let Proof(th2,_) = p2 in
  let ts2,t2 = dest_thm th2 in
  (* vs2 is the list of free term variables of th2 *)
  let vs2 = freesl (t2::ts2) in
  (* vs2 is now the application of tm_su on vs2 *)
  let vs2 = vsubstl tm_su vs2 in
  (* ts2 is now the application of tm_su on ts2 *)
  let ts2 = vsubstl tm_su ts2 in
  (* tvs2 is the list of type variables of th2 *)
  let tvs2 = type_vars_in_thm th2 in
  (* bs2 is the application of ty_su on tvs2 *)
  let bs2 = List.map (type_subst ty_su) tvs2 in
  (* tvbs2 is the type variables of bs2 *)
  let tvbs2 = tyvarsl bs2 in
  (* we remove from tvbs2 the variables of tvs *)
  let tvbs2 =
    List.fold_left
      (fun tvbs2 tv -> if List.mem tv tvs then tvbs2 else tv::tvbs2)
      [] tvbs2
  in
  (* we extend ty_su by mapping every type variable of tvbs2 to bool *)
  let ty_su =
    List.fold_left
      (fun su tv -> (bool_ty,tv)::su)
      ty_su tvbs2
  in
  match ty_su with
  | [] ->
     out oc "(thm_%d%a%a%a)" i2 (list_prefix " " typ) tvs2
       (list_prefix " " term) vs2 (list_prefix " " (hyp_var ts1)) ts2
  | _ ->
     (* vs2 is now the application of ty_su on vs2 *)
     let vs2 = List.map (inst ty_su) vs2 in
     (* ts2 is now the application of ty_su on ts2 *)
     let ts2 = List.map (inst ty_su) ts2 in
     (* bs is the list of types obtained by applying ty_su on tvs2 *)
     let bs = List.map (type_subst ty_su) tvs2 in
     out oc "(thm_%d%a%a%a)" i2 (list_prefix " " typ) bs
       (list_prefix " " term) vs2 (list_prefix " " (hyp_var ts1)) ts2
;;

(* [proof tvs rmap oc p] prints on [oc] the proof [p] for a theorem
   with type variables [tvs] and free variables renaming map [rmap]. *)
let proof tvs rmap =
  let typ = typ tvs in
  let term = term tvs rmap in
  let rec proof oc p =
    let Proof(thm,content) = p in
    let ts = hyp thm in
    let sub = subproof tvs rmap [] [] ts in
    let sub_at oc k = sub k oc (proof_at k) in
    match content with
    | Prefl(t) ->
       out oc "REFL %a %a" typ (get_eq_typ p) term t
    | Psym(k) ->
       let p = proof_at k in
       let a,x,y = get_eq_typ_args p in
       out oc "SYM %a %a %a %a" typ a term x term y (sub k) p
    | Ptrans(k1,k2) ->
       let p1 = proof_at k1 and p2 = proof_at k2 in
       let a,x,y = get_eq_typ_args p1 in
       let _,z = get_eq_args p2 in
       out oc "TRANS %a %a %a %a %a %a"
         typ a term x term y term z (sub k1) p1 (sub k2) p2
    | Pmkcomb(k1,k2) ->
       let p1 = proof_at k1 and p2 = proof_at k2 in
       let ab,s,t = get_eq_typ_args p1 in
       let a,b = match ab with Tyapp("fun",[a;b]) -> a,b | _ -> assert false in
       let u,v = get_eq_args p2 in
       out oc "MK_COMB %a %a %a %a %a %a %a %a"
         typ a typ b term s term t term u term v (sub k1) p1 (sub k2) p2
    | Pabs(k,t) ->
       let ab,f,g = get_eq_typ_args p in
       let a,b = match ab with Tyapp("fun",[a;b]) -> a,b | _ -> assert false in
       let rmap' = add_var rmap t in
       out oc "fun_ext %a %a %a %a (%a => %a)"
         typ a typ b term f term g (decl_var tvs rmap') t
         (subproof tvs rmap' [] [] ts k) (proof_at k)
    | Pbeta(t) ->
       out oc "REFL %a %a" typ (type_of t) term t
    | Passume(t) ->
       hyp_var (hyp thm) oc t
    | Peqmp(k1,k2) ->
       let p1 = proof_at k1 and p2 = proof_at k2 in
       let p,q = get_eq_args p1 in
       out oc "EQ_MP %a %a %a %a" term p term q (sub k1) p1 (sub k2) p2
    | Pdeduct(k1,k2) ->
       let p1 = proof_at k1 and p2 = proof_at k2 in
       let Proof(th1,_) = p1 and Proof(th2,_) = p2 in
       let t1 = concl th1 and t2 = concl th2 in
       let n = 1 + List.length ts in
       out oc "prop_ext %a %a (h%d : Prf %a => %a) (h%d : Prf %a => %a)"
         term t1 term t2
         n term t1 (subproof tvs rmap [] [] (ts @ [t1]) k2) p2
         n term t2 (subproof tvs rmap [] [] (ts @ [t2]) k1) p1
    | Pinst(k,[]) -> proof oc (proof_at k)
    | Pinst(k,s) ->
       out oc "%a" (subproof tvs rmap [] s ts k) (proof_at k)
    | Pinstt(k,[]) -> proof oc (proof_at k)
    | Pinstt(k,s) ->
       out oc "%a" (subproof tvs rmap s [] ts k) (proof_at k)
    | Pdef(_,n,b) ->
       let ps = const_typ_vars_pos n in
       (*out oc "(;t=%a; b=%a; ps=%a;)" term t typ b type_var_pos_list ps;*)
       begin match List.map (subtyp b) ps with
       | [] -> out oc "%a" (suffix "_def") n
       | bs -> out oc "(%a%a)" (suffix "_def") n (list_prefix " " typ) bs
       end
    | Paxiom(t) ->
       let k =
         try pos_first (fun th -> concl th = t) (axioms())
         with Not_found -> assert false
       in
       out oc "axiom_%d%a%a" k
         (list_prefix " " typ) (type_vars_in_term t)
         (list_prefix " " term) (frees t)
    | Pdeft(_,t,_,_) ->
       let k =
         try pos_first (fun th -> concl th = t) (axioms())
         with Not_found -> assert false
       in
       out oc "axiom_%d%a%a" k
         (list_prefix " " typ) (type_vars_in_term t)
         (list_prefix " " term) (frees t)
    | Ptruth -> out oc "top_intro"
    | Pconj(k1,k2) ->
       let p1 = proof_at k1 and p2 = proof_at k2 in
       let Proof(th1,_) = p1 and Proof(th2,_) = p2 in
       out oc "and_intro %a %a %a %a"
         term (concl th1) (sub k1) p1 term (concl th2) (sub k2) p2
    | Pconjunct1 k ->
       let p = proof_at k in
       let Proof(th,_) = p in
       let l,r = binop_args (concl th) in
       out oc "and_elim1 %a %a %a" term l term r (sub k) p
    | Pconjunct2 k ->
       let p = proof_at k in
       let Proof(th,_) = p in
       let l,r = binop_args (concl th) in
       out oc "and_elim2 %a %a %a" term l term r (sub k) p
    | Pmp(k1,k2) -> out oc "%a %a" sub_at k1 sub_at k2
    | Pdisch(t,k) -> out oc "%a : Prf %a => %a" (hyp_var ts) t term t sub_at k
    | Pspec(t,k) -> out oc "%a %a" sub_at k term t
    | Pgen(x,k) ->
       let rmap' = add_var rmap x in
       out oc "%a => %a"
         (decl_var tvs rmap') x (subproof tvs rmap' [] [] ts k) (proof_at k)
    | Pexists(p,t,k) ->
       out oc "ex_intro %a %a %a %a" typ (type_of t) term p term t sub_at k
    | Pdisj1(p,k) ->
       let Proof(th,_) = proof_at k in
       out oc "or_intro1 %a %a %a" term (concl th) sub_at k term p
    | Pdisj2(p,k) ->
       let Proof(th,_) = proof_at k in
       out oc "or_intro2 %a %a %a" term p term (concl th) sub_at k
    | Pdisj_cases(k1,k2,k3) ->
       let p1 = proof_at k1 in
       let Proof(th1,_) = p1 in
       let p2 = proof_at k2 in
       let Proof(th2,_) = p2 in
       let l,r = binop_args (concl th1) in
       out oc "or_elim %a %a %a %a (h0 : Prf %a => %a) (h0 : Prf %a => %a)"
         term l term r (sub k1) p1 term (concl th2)
         term l (sub k2) p2 term r sub_at k3
    | Pchoose(v,k1,k2) ->
       let p1 = proof_at k1 in
       let Proof(th1,_) = p1 in
       let p2 = proof_at k2 in
       let Proof(th2,_) = p2 in
       begin match concl th1 with
       | Comb(_,p) ->
          let rmap' = add_var rmap v in
          out oc "ex_elim %a %a %a %a (%a => h0 : Prf(%a %a) => %a)"
            typ (type_of v) term p (sub k1) p1 term (concl th2)
            (decl_var tvs rmap') v term p (var rmap') v
            (subproof tvs rmap' [] [] ts k2) p2
       | _ -> assert false
       end
  in proof
;;

(****************************************************************************)
(* Translation of type declarations and axioms. *)
(****************************************************************************)

let typ_arity oc k =
  for _ = 1 to k do out oc "%a -> " typ_name "Set" done; typ_name oc "Set";;

let decl_typ oc (n,k) =
  out oc "%a : %a.\n" typ_name n typ_arity k;;

let decl_typ_param tvs oc b = out oc "%a : %a -> " (typ tvs) b typ_name "Set";;

let typ_param tvs oc b = out oc "%a : %a => " (typ tvs) b typ_name "Set";;

let decl_sym oc (n,b) =
  let tvs = tyvars b in
  out oc "%a : %a%a %a.\n" cst_name n
    (list (decl_typ_param tvs)) tvs cst_name "El" (unabbrev_typ tvs) b
;;

let decl_def oc th =
  let t = concl th in (* definitions have no assumptions *)
  let tvs = type_vars_in_term t in
  let rmap = renaming_map tvs [] in (* definitions are closed *)
  match t with
  | Comb(Comb(Const("=",_),Const(n,_)),_) ->
     let tvs = type_vars_in_term t in
     out oc "%a : %aPrf %a.\n" (suffix "_def") n
       (list (decl_typ_param tvs)) tvs (unabbrev_term tvs rmap) t
  | _ -> assert false
;;

let decl_axioms oc ths =
  let axiom i th =
    let t = concl th in (* axioms have no assumptions *)
    let xs = frees t in
    let tvs = type_vars_in_term t in
    let rmap = renaming_map tvs xs in
    out oc "def axiom_%d : %a%aPrf %a.\n" i
      (list (decl_typ_param tvs)) tvs
      (list (unabbrev_decl_param tvs rmap)) xs
      (unabbrev_term tvs rmap) t
  in
  List.iteri axiom ths
;;

(****************************************************************************)
(* Translation of theorems. *)
(****************************************************************************)

(*let counter = ref 0;;*)

type decl =
  | Unnamed_thm
  | Axiom
  | Named_thm of string

(* [decl_theorem oc k p d] outputs on [oc] the theorem of index [k],
   proof [p] and name [n] as declaration type [d]. *)
let decl_theorem oc k p d =
  let Proof(thm,_) = p in
  (*incr counter;
  if !counter = 1000 then (log "theorem %d ...\n%!" k; counter := 0);*)
  let ts,t = dest_thm thm in
  let xs = freesl (t::ts) in
  let tvs = type_vars_in_thm thm in
  let rmap = renaming_map tvs xs in
  match d with
  | Unnamed_thm ->
     let term = term tvs rmap in
     let hyps_typ oc ts =
       List.iteri (fun i t -> out oc "h%d : Prf %a -> " (i+1) term t) ts in
     let hyps oc ts =
       List.iteri (fun i t -> out oc "h%d : Prf %a => " (i+1) term t) ts in
     out oc "thm thm_%d : %a%a%aPrf %a := %a%a%a%a.\n" k
       (list (decl_typ_param tvs)) tvs
       (list (decl_param tvs rmap)) xs hyps_typ ts term t
       (list (typ_param tvs)) tvs (list (param tvs rmap)) xs hyps ts
       (proof tvs rmap) p
  | Axiom ->
     let term = unabbrev_term tvs rmap in
     let hyps_typ oc ts =
       List.iteri (fun i t -> out oc "h%d : Prf %a -> " (i+1) term t) ts in
     out oc "thm_%d : %a%a%aPrf %a.\n" k
       (list (decl_typ_param tvs)) tvs
       (list (decl_param tvs rmap)) xs hyps_typ ts term t
  | Named_thm n ->
     let term = unabbrev_term tvs rmap in
     let hyps_typ oc ts =
       List.iteri (fun i t -> out oc "h%d : Prf %a -> " (i+1) term t) ts in
     out oc "thm thm_%s : %a%a%aPrf %a := thm_%d.\n" n
       (list (decl_typ_param tvs)) tvs
       (list (unabbrev_decl_param tvs rmap)) xs hyps_typ ts term t k
;;

(* [theorem oc k p] outputs on [oc] the proof [p] of index [k]. *)
let theorem oc k p = decl_theorem oc k p Unnamed_thm;;

(* [theorem_as_axiom oc k p] outputs on [oc] the proof [p] of index
   [k] as an axiom. *)
let theorem_as_axiom oc k p = decl_theorem oc k p Axiom;;

(* [proofs_in_interval oc x y] outputs on [oc] the proofs in interval
   [x] .. [y]. *)
let proofs_in_interval oc x y =
  for k = x to y do
    if get_use k >= 0 then theorem oc k (proof_at k)
  done

(* [proofs_in_range oc r] outputs on [oc] the theorems in range [r]. *)
let proofs_in_range oc = function
  | Only x ->
     let p = proof_at x in
     List.iter (fun k -> theorem_as_axiom oc k (proof_at k)) (deps p);
     theorem oc x p
  | All -> proofs_in_interval oc 0 (Array.length !prf_pos - 1)
  | Upto y -> proofs_in_interval oc 0 y
  | Inter(x,y) -> proofs_in_interval oc x y
;;

(****************************************************************************)
(* Generation of encoding symbols. *)
(****************************************************************************)

(*let qualify_types s =
  let re = Str.regexp "\\(Set\\|bool\\)" in
  let r = !basename ^ "_types.\1" in
  let s = Str.global_replace re r s in
  let re = Str.regexp "fun\\([^_]\\)" in
  let r = !basename ^ "_types.fun\1" in
  Str.global_replace re r s
;;

let qualify_terms s =
  let re = Str.regexp "\\(El\\|eq\\)" in
  let r = !basename ^ "_terms.\1" in
  Str.global_replace re r (qualify_types s)
;;*)

let decl_Prf = (*qualify_terms*) "injective Prf : El bool -> Type.";;

let decl_El = (*qualify_types*)
"injective El : Set -> Type.
[a, b] El (fun a b) --> El a -> El b.";;

let decl_rules = (*qualify_terms*)
"def fun_ext : a : Set -> b : Set -> f : El (fun a b) -> g : El (fun a b) ->
  (x : El a -> Prf (eq b (f x) (g x))) -> Prf (eq (fun a b) f g).
def prop_ext : p : El bool -> q : El bool ->
  (Prf p -> Prf q) -> (Prf q -> Prf p) -> Prf (eq bool p q).
def REFL : a : Set -> t : El a -> Prf (eq a t t).
def MK_COMB : a : Set -> b : Set -> s : El (fun a b) -> t : El (fun a b) ->
  u : El a -> v : El a -> Prf(eq (fun a b) s t) -> Prf(eq a u v) ->
  Prf (eq b (s u) (t v)).
def EQ_MP : p : El bool -> q : El bool -> Prf(eq bool p q) -> Prf p -> Prf q.
thm TRANS : a : Set -> x : El a -> y : El a -> z : El a ->
  Prf (eq a x y) -> Prf (eq a y z) -> Prf (eq a x z) :=
  a: Set => x: El a => y: El a => z: El a =>
  xy: Prf (eq a x y) => yz: Prf (eq a y z) =>
  EQ_MP (eq a x y) (eq a x z)
    (MK_COMB a bool (eq a x) (eq a x) y z
      (REFL (fun a bool) (eq a x)) yz) xy.

(; natural deduction rules ;)
[p, q] Prf (imp p q) --> Prf p -> Prf q.
[a, p] Prf (all a p) --> x : El a -> Prf (p x).
def top : Prf T.
def and_intro : p : El bool -> Prf p -> q : El bool -> Prf q -> Prf (and p q).
def and_elim1 : p : El bool -> q : El bool -> Prf (and p q) -> Prf p.
def and_elim2 : p : El bool -> q : El bool -> Prf (and p q) -> Prf q.
def ex_intro :
  a : Set -> p : (El a -> El bool) -> t : El a -> Prf (p t) -> Prf (ex a p).
def ex_elim : a : Set -> p : (El a -> El bool) -> Prf (ex a p)
  -> r : El bool -> (x : El a -> Prf (p x) -> Prf r) -> Prf r.
def or_intro1 : p : El bool -> Prf p -> q : El bool -> Prf (or p q).
def or_intro2 : p : El bool -> q : El bool -> Prf q -> Prf (or p q).
def or_elim : p : El bool -> q : El bool -> Prf (or p q)
  -> r : El bool -> (Prf p -> Prf r) -> (Prf q -> Prf r) -> Prf r.
";;

(****************************************************************************)
(* Dedukti file generation with type and term abbreviations. *)
(****************************************************************************)

let export basename suffix f =
  let filename = basename ^ suffix ^ ".dk" in
  log "generate %s ...\n%!" filename;
  let oc = open_out filename in
  f oc;
  close_out oc
;;

let export_types =
  let f (n,_) = match n with "bool" | "fun" -> false | _ -> true in
  fun b ->
  export b "_types"
    (fun oc ->
      out oc "\n(; type constructors ;)\n";
      list decl_typ oc (List.filter f (types())))
;;

let export_type_abbrevs b s =
  export b (s ^ "_type_abbrevs")
    (fun oc -> out oc "\n(; type abbreviations ;)\n"; decl_map_typ oc)
;;

let export_terms =
  let f (n,_) =
    match n with
    | "@" | "\\/" | "/\\" | "==>" | "!" | "?" | "?!" | "~" | "F" | "T" | "="
    | "el" -> false
    | _ -> true
  in
  fun b ->
  export b "_terms"
    (fun oc ->
      out oc "\n(; constants ;)\n";
      list decl_sym oc (List.filter f (constants())))
;;

let export_term_abbrevs b s =
  export b (s ^ "_term_abbrevs")
    (fun oc -> out oc "\n(; term abbreviations ;)\n"; decl_map_term oc)
;;

let export_axioms b =
  export b "_axioms"
    (fun oc ->
      out oc "\n(; axioms ;)\n";
      decl_axioms oc (axioms());
      out oc "\n(; definitional axioms ;)\n";
      list decl_def oc (definitions()))
;;

let export_proofs b r =
  export b "_proofs"
    (fun oc -> out oc "\n(; theorems ;)\n"; proofs_in_range oc r);;

let export_theorems b map_thid_name =
  export b "_theorems"
    (fun oc ->
      out oc "\n(; named theorems ;)\n";
      MapInt.iter
        (fun k n -> decl_theorem oc k (proof_at k) (Named_thm n))
        map_thid_name)
;;

let export_theorems_as_axioms b map_thid_name =
  export b "_opam"
    (fun oc ->
      out oc "\n(; named theorems ;)\n";
      MapInt.iter
        (fun k _ -> decl_theorem oc k (proof_at k) Axiom)
        map_thid_name)
;;

let export_proofs_part b k x y =
  part := Some k;
  export b ("_part_" ^ string_of_int k) (fun oc -> proofs_in_interval oc x y)
;;

(****************************************************************************)
(* Dedukti file generation without type and term abbreviations. *)
(****************************************************************************)

(* [theory oc] outputs on [oc] all types, constants and axioms used in
   proofs. *)
let theory oc =
  let f (n,_) = match n with "bool" | "fun" -> false | _ -> true in
  let types = List.filter f (types()) in
  let f (n,_) = match n with "=" | "el" -> false | _ -> true in
  let constants = List.filter f (constants()) in
  out oc
"(; Encoding of simple type theory ;)
Set : Type.
bool : Set.
fun : Set -> Set -> Set.
injective El : Set -> Type.
[a, b] El (fun a b) --> El a -> El b.
injective Prf : El bool -> Type.

(; HOL-Light axioms and rules ;)
el : a : Set -> El a.
eq : a : Set -> El a -> El a -> El bool.
%s
(; type constructors ;)
%a
(; constants ;)
%a
(; axioms ;)
%a
(; definitions ;)
%a\n"
decl_rules (list decl_typ) types (list decl_sym) constants
decl_axioms (axioms()) (list decl_def) (definitions())
;;

(* [export_to_dk_file_no_abbrev f r] creates a file of name [f.dk] and
   outputs to this file the proofs in range [r]. *)
let export_to_dk_file_no_abbrev f r =
  use_abbrev := false;
  (*stage := No_abbrev;*)
  update_reserved();
  update_map_const_typ_vars_pos();
  let filename = f ^ ".dk" in
  log "generate %s ...\n%!" filename;
  let oc = open_out filename in
  theory oc;
  out oc "(; theorems ;)\n";
  proofs_in_range oc r;
  close_out oc
;;
