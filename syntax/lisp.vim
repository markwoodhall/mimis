syn case ignore

" ---------------------------------------------------------------------
" Lexical variable (part 1) {{{
"
" Since the REST of lispLexVarList1 and lispLexVar1List should match
" @lispFormCluster, and lispParen* (which inside @lispFormCluster) also uses
" contains, the lispLexVarList1 and lispLexVar1List should have lower priority
" against @lispFormCluster, thus it should be defined previously.

syn region  lispLexVarList  contained matchgroup=hlLevel1 start="(" end=")" skip="|.\{-}|" contains=lispLexVarList1
syn region  lispLexVarList1 contained skipwhite skipnl matchgroup=hlLevel2 start="(" end=")" skip="|.\{-}|" contains=lispLexVarName nextgroup=lispLexVarList1

syn region  lispLexVar1List contained matchgroup=hlLevel1 start="(" end=")" skip="|.\{-}|" contains=lispLexVarName

syn match   lispLexVarName  contained skipwhite skipnl /[^()'`,"; \t]\+/ nextgroup=@lispFormCluster

hi  link    lispLexVarName  Identifier

" }}}
" ---------------------------------------------------------------------

"List cluster. Should contain all type of lists and what will appear in lists."
syn cluster lispFormCluster contains=lispParen0,@lispDefs,lispLoop,lispQuote,lispFunction,lispParamFormStart,lispString,lispNumber,lispReaderMacro,lispComment,lispKey,lispAmpersand,lispSym,lispNumber,lispEscapeSpecial,lispVar,lispMacroBuiltin,lispFunctionBuiltin,lispVarBuiltin,lispSpecialOp,lispStatement,lispAlexandriaFunc,lispAlexandriaMacro
syn cluster lispParens      contains=lispParen0,lispParen1,lispParen2,lispParen3,lispParen4,lispParen5

"Rainbow parentheses"
syn region lispParen0           matchgroup=hlLevel0 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen1
syn region lispParen1 contained matchgroup=hlLevel1 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen2
syn region lispParen2 contained matchgroup=hlLevel2 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen3
syn region lispParen3 contained matchgroup=hlLevel3 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen4
syn region lispParen4 contained matchgroup=hlLevel4 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen5
syn region lispParen5 contained matchgroup=hlLevel5 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen0

hi  link   hlLevel0   Constant
hi  link   hlLevel1   Type
hi  link   hlLevel2   String
hi  link   hlLevel3   Label
hi  link   hlLevel4   Function
hi  link   hlLevel5   Keyword

" ---------------------------------------------------------------------
" Builtins {{{

syn keyword lispVarBuiltin      *readtable* pi *read-base* short-float-negative-epsilon *print-readably* most-negative-single-float *print-miser-width* *print-right-margin* *print-array* internal-time-units-per-second *gensym-counter* *print-pretty* boole-xor least-positive-double-float *load-print* *trace-output* most-positive-short-float *terminal-io* *compile-verbose* *debug-io* boole-clr boole-c2 boole-nor least-negative-short-float least-negative-double-float *compile-print* *default-pathname-defaults* *print-length* /// most-negative-fixnum ** *standard-output* *macroexpand-hook* t *print-lines* boole-andc2 double-float-negative-epsilon least-positive-normalized-long-float least-negative-single-float *read-suppress* *random-state* nil least-positive-normalized-single-float boole-ior boole-set long-float-epsilon *standard-input* least-positive-single-float array-total-size-limit boole-orc1 *error-output* *package* *modules* multiple-values-limit array-rank-limit array-dimension-limit least-negative-normalized-short-float *query-io* lambda-parameters-limit *break-on-signals* *print-case* least-negative-normalized-single-float most-positive-double-float least-negative-normalized-long-float char-code-limit least-negative-normalized-double-float short-float-epsilon boole-1 long-float-negative-epsilon most-negative-long-float least-positive-normalized-short-float least-positive-long-float *read-eval* *print-base* *features* lambda-list-keywords boole-c1 // *print-level* *load-pathname* single-float-epsilon boole-2 most-positive-long-float *print-escape* boole-andc1 double-float-epsilon boole-orc2 call-arguments-limit *print-radix* *read-default-float-format* boole-and least-positive-short-float *debugger-hook* *print-circle* +++ boole-eqv *load-verbose* single-float-negative-epsilon *print-pprint-dispatch* most-positive-fixnum least-positive-normalized-double-float ++ *compile-file-pathname* most-negative-short-float least-negative-long-float most-positive-single-float boole-nand *load-truename* most-negative-double-float *compile-file-truename* *** *print-gensym*
syn keyword lispFunctionBuiltin pairlis acosh file-write-date macroexpand-1 terpri shadowing-import subst revappend princ unexport symbol-plist float ldiff remove-if-not set-pprint-dispatch + sbit logcount find bit-and make-condition logxor load restart-name type-of simple-string-p progn type-error-expected-type allocate-instance unbound-slot-instance read-char > complement gentemp multiple-value-prog1 sqrt gensym vector-push-extend string-right-trim truename method-qualifiers nreconc merge rplaca read-delimited-list count-if assoc pathname-directory break make-pathname sixth keywordp >= simple-vector-p sublis sin funcall sinh tan sleep nstring-upcase char-equal read stream-external-format assoc-if method-combination-error list-all-packages rest mapl file-author denominator float-radix tanh write-line cddaar input-stream-p file-length symbol-value rplacd cdr char-name streamp ffloor find-if pprint-fill fifth caar read-sequence make-symbol both-case-p delete delete-if-not find-if-not string= map-into continue invoke-restart char-not-greaterp row-major-aref char> ensure-generic-function logical-pathname logior machine-type realpart cdddar read-from-string maplist hash-table-rehash-threshold no-applicable-method bit-eqv set cddr /= progv shared-initialize write-sequence get-universal-time cos logorc2 logandc1 mapcon seventh echo-stream-input-stream position-if-not merge-pathnames inspect machine-instance char< compile-file-pathname string-downcase string-not-greaterp eq string< write-byte unwind-protect fdefinition cosh print echo-stream-output-stream rationalize caaaar expt char/= package-shadowing-symbols nstring-capitalize mismatch string-capitalize notany listen nsubstitute hash-table-rehash-size nset-difference throw print-object simple-bit-vector-p bit-not lognor slot-boundp directory equal intersection schar 1- ash pprint-indent nsubstitute-if enough-namestring import nbutlast user-homedir-pathname reduce reverse cadddr close boole find-class fround nsubst-if describe packagep member-if get-properties pprint-dispatch hash-table-p fceiling every load-time-value encode-universal-time char-downcase slot-value adjustable-array-p nreverse list-length compile-file apropos-list compute-applicable-methods file-position fresh-line make-hash-table union find-package if char-lessp pprint phase subtypep find-all-symbols realp get-setf-expansion delete-file readtablep symbol-name package-use-list random decode-universal-time symbol-package find-symbol array-dimensions elt parse-integer lisp-implementation-version output-stream-p pathname-match-p bit-xor cdaadr byte-size substitute-if stringp subseq princ-to-string finish-output initialize-instance nset-exclusive-or alpha-char-p / signal nsubst-if-not tenth vectorp float-sign char-greaterp warn nsubst remhash isqrt code-char proclaim complexp read-preserving-whitespace two-way-stream-input-stream copy-tree acons char-not-equal clrhash getf provide character simple-condition-format-arguments rationalp length catch char<= digit-char-p update-instance-for-redefined-class bit-vector-p nconc round ftruncate make-concatenated-stream logbitp remprop machine-version string/= eql ldb apropos short-site-name characterp cis remove-method integer-decode-float char= copy-readtable load-logical-pathname-translations eighth remove-if rename-file invoke-debugger mod make-list constantly rem abs y-or-n-p slot-makunbound cdaar string string-left-trim rassoc-if string-not-lessp mapcan set-macro-character standard-char-p array-in-bounds-p ceiling function-lambda-expression lognand concatenated-stream-streams hash-table-count fmakunbound broadcast-stream-streams yes-or-no-p use-package no-next-method package-error-package cerror tailp parse-namestring char-upcase byte-position bit-nor string-equal upgraded-complex-part-type maphash coerce third equalp byte make-load-form-saving-slots array-row-major-index butlast read-byte intern car get-internal-real-time macro-function nintersection make-instance nthcdr delete-duplicates get-output-stream-string digit-char make-random-state < substitute-if-not pathname-host bit-orc2 gcd software-type force-output find-method lower-case-p labels string>= aref bit-andc2 count-if-not string-lessp hash-table-size open-stream-p peek-char export macroexpand update-instance-for-different-class quote float-precision pathname make-package mapc endp fill-pointer mapcar - string> rename-package pathname-type make-string-output-stream disassemble prin1 svref read-line cadadr block store-value char>= string-not-equal rational pathnamep zerop make-broadcast-stream bit-ior cdaaar cddadr numerator change-class pprint-tab let listp let* caaar lcm locally min open bit-andc1 go hash-table-test upper-case-p deposit-field atom * copy-pprint-dispatch subst-if slot-exists-p cons pathname-version prin1-to-string remove file-namestring special-operator-p get-dispatch-macro-character room replace translate-logical-pathname shadow vector numberp readtable-case exp cdddr identity documentation function-keywords software-version sxhash subst-if-not symbol-function count write-char signum member add-method imagpart fboundp logorc1 nsubstitute-if-not array-has-fill-pointer-p tree-equal muffle-warning compiler-macro-function make-string copy-structure unread-char unintern package-used-by-list stream-element-type require position tagbody error write-string copy-seq get-macro-character unuse-package = float-digits setq floatp make-load-form rassoc-if-not <= array-displacement graphic-char-p delete-package log directory-namestring compiled-function-p string<= logandc2 gethash functionp make-echo-stream rassoc first complex delete-if subsetp pprint-tabular host-namestring wild-pathname-p function string-greaterp write class-name floor cadaar pathname-device lognot invoke-restart-interactively make-sequence translate-pathname macrolet use-value member-if-not logand find-restart bit-orc1 concatenate acos second substitute array-dimension synonym-stream-symbol upgraded-array-element-type write-to-string ed make-synonym-stream logtest type-error-datum slot-missing caaadr search nth constantp class-of caddar mask-field two-way-stream-output-stream not dpb 1+ cdaddr oddp assoc-if-not arithmetic-error-operation simple-condition-format-control adjoin fourth set-exclusive-or name-char remove-duplicates pathname-name scale-float string-upcase boundp pprint-linear file-error-pathname format print-not-readable-object sort random-state-p plusp read-char-no-hang get namestring makunbound abort interactive-stream-p invalid-method-error long-site-name make-two-way-stream logical-pathname-translations cddar symbolp values eval lisp-implementation-type copy-list flet caaddr truncate cdadar caddr arithmetic-error-operands asin integerp vector-pop package-nicknames symbol-macrolet caadr stream-error-stream char-not-lessp char-int clear-input compute-restarts bit set-dispatch-macro-character eval-when cadar max probe-file values-list conjugate typep some array-total-size copy-symbol char arrayp append cdadr make-instances-obsolete file-string-length vector-push the bit-nand array-element-type make-array cddddr map atan null minusp fill get-internal-run-time nstring-downcase nunion atanh cdar dribble make-dispatch-macro-character reinitialize-instance slot-unbound apply position-if nsublis evenp array-rank adjust-array get-decoded-time logeqv caadar ninth decode-float list copy-alist clear-output ldb-test string-trim pprint-newline ensure-directories-exist notevery integer-length stable-sort list* consp make-string-input-stream char-code compile return-from set-syntax-from-char set-difference package-name asinh alphanumericp cadr cell-error-name last multiple-value-call describe-object
syn keyword lispMacroBuiltin    pprint-pop with-condition-restarts defpackage define-setf-expander remf declaim in-package pop with-compilation-unit with-standard-io-syntax dotimes restart-case multiple-value-setq loop-finish with-package-iterator setf handler-case define-symbol-macro time restart-bind pprint-logical-block ctypecase do deftype with-hash-table-iterator or assert shiftf defmacro prog2 handler-bind pushnew do-external-symbols unless define-compiler-macro prog ecase print-unreadable-object case define-modify-macro step and defconstant do* with-open-stream decf psetq trace rotatef multiple-value-list with-input-from-string define-method-combination do-all-symbols with-slots define-condition typecase untrace push pprint-exit-if-list-exhausted ignore-errors defstruct defgeneric defsetf dolist defclass when with-output-to-string prog* ccase prog1 psetf with-open-file return incf defun defmethod defvar etypecase nth-value check-type formatter cond call-method with-simple-restart do-symbols with-accessors loop defparameter
syn keyword lispStatement       defvar defconstant defparameter define-symbol-macro deftype defpackage defstruct defun defclass defgeneric defsetf defmacro defmethod define-method-combination define-condition define-setf-expander define-compiler-macro define-modify-macro cond if let let* progn prog1 prog2 lambda unwind-protect when unless with-output-to-string ignore-errors dotimes dolist declare block break case ccase compiler-let ctypecase declaim destructuring-bind do do* ecase etypecase eval-when flet flet* go handler-case handler-bind in-package labels letf locally loop macrolet multiple-value-bind multiple-value-prog1 proclaim prog prog* progv restart-case restart-bind return return-from setf setq symbol-macrolet tagbody the typecase with-accessors with-compilation-unit with-condition-restarts with-hash-table-iterator with-input-from-string with-open-file with-open-stream with-package-iterator with-simple-restart with-slots with-standard-io-syntax
syn keyword lispSpecialOp       progn multiple-value-prog1 progv unwind-protect throw load-time-value if catch labels quote block let let* locally go tagbody setq function macrolet flet symbol-macrolet eval-when the return-from multiple-value-call

syn keyword lispAlexandriaFunc  ends-with-subseq curry read-stream-content-into-string copy-hash-table non-negative-single-float-p circular-list simple-program-error copy-array subfactorial hash-table-keys non-positive-double-float-p alist-hash-table maphash-keys simple-reader-error copy-file non-negative-long-float-p positive-single-float-p conjoin multiple-value-compose assoc-value ensure-function emptyp non-negative-double-float-p ensure-symbol first-elt non-negative-rational-p mappend maphash-values negative-double-float-p write-byte-vector-into-file compose parse-ordinary-lambda-list make-gensym-list format-symbol hash-table-plist copy-sequence featurep make-gensym lastcar rassoc-value negative-real-p hash-table-alist negative-float-p lerp symbolicate positive-real-p rotate positive-float-p non-negative-real-p positive-fixnum-p starts-with plist-alist of-type ensure-cons binomial-coefficient plist-hash-table mean set-equal non-positive-float-p factorial length= map-iota negative-long-float-p proper-list-length circular-list-p negative-fixnum-p positive-double-float-p ensure-list read-file-into-string non-positive-short-float-p setp hash-table-values negative-integer-p starts-with-subseq median type= extremum non-positive-rational-p proper-list-p map-permutations circular-tree-p remove-from-plist last-elt non-positive-long-float-p positive-short-float-p negative-single-float-p make-circular-list non-positive-real-p random-elt sequence-of-length-p non-negative-fixnum-p map-derangements map-combinations map-product disjoin gaussian-random non-negative-integer-p parse-body negative-short-float-p simple-parse-error non-negative-short-float-p non-positive-single-float-p non-negative-float-p copy-stream positive-rational-p clamp flatten read-file-into-byte-vector iota required-argument non-positive-fixnum-p variance ends-with non-positive-integer-p shuffle delete-from-plist read-stream-content-into-byte-vector count-permutations positive-long-float-p write-string-into-file standard-deviation make-keyword rcurry ensure-car alist-plist negative-rational-p simple-style-warning positive-integer-p
syn keyword lispAlexandriaMacro removef nconcf nunionf once-only maxf nth-value-or destructuring-ccase unionf destructuring-case whichever remove-from-plistf delete-from-plistf minf ensure-gethash switch with-unique-names named-lambda when-let deletef eswitch cswitch reversef define-constant appendf xor destructuring-ecase ensure-functionf unwind-protect-case nreversef when-let* doplist if-let ignore-some-conditions with-output-to-file coercef with-input-from-file with-gensyms multiple-value-prog2

hi  link    lispFunctionBuiltin Function
hi  link    lispMacroBuiltin    Macro
hi  link    lispVarBuiltin      Identifier
hi  link    lispSpecialOp       Conditional
hi  link    lispStatement       Keyword
hi  link    lispAlexandriaFunc  Function
hi  link    lispAlexandriaMacro Function

" }}}
" ---------------------------------------------------------------------
" Atoms {{{

"Add & as keyword and exclude : from keywords"
syn iskeyword @,48-57,_,192-255,+,-,*,/,%,<,=,>,$,?,!,@-@,94,&

syn keyword lispAmpersand   &allow-other-keys &aux &body &environment &key &optional &rest &whole

"Keywords"
syn match lispKey           /[()'`,"; \t:]:[^()'`,"; \t:]\+/

"Package name"
"Note that we excluded : from iskeyword, so builtins can be matched with nextgroup"
syn match lispSym           /\([^()'`,"; \t:]\+:\{1,2}\)\?[^()'`,"; \t:]\+/ contained contains=lispPackageName,lispVarBuiltin,lispFunctionBuiltin,lispMacroBuiltin,lispSpecialOp,lispStatement,lispAlexandriaFunc,lispAlexandriaMacro,lispVar,lispConstant,@lispDefs,lispLoop
syn match lispPackageName   /[^()'`,"; \t:]\+:\{1,2}/ contained nextgroup=lispVar,lispConstantlispVar,lispConstant,@lispDefs,lispLoop,lispVarBuiltin,lispFunctionBuiltin,lispMacroBuiltin,lispSpecialOp,lispStatement,lispAlexandriaFunc,lispAlexandriaMacro

"Variable"
syn match lispVar           /\<\*[^()'`,"; \t]\+\*\>/
syn match lispConstant      /\<+[^()'`,"; \t]\+\>/

"Numbers"
syn match lispNumber        "\<-\=\(\.\d\+\|\d\+\(\.\d*\)\=\)\([dDeEfFlL][-+]\=\d\+\)\=\>"
syn match lispNumber        "\<-\=\(\d\+/\d\+\)\>"
syn match lispNumber        !#x\x\+!
syn match lispNumber        !#o\o\+!
syn match lispNumber        !#b[01]\+!

"Escaped specials"
syn match lispEscapeSpecial !#|[^()'`,"; \t]\+|#!
syn match lispEscapeSpecial !#\\[ -}\~]!
syn match lispEscapeSpecial !#[':][^()'`,"; \t]\+!
syn match lispEscapeSpecial !#([^()'`,"; \t]\+)!
syn match lispEscapeSpecial !#\\\%(Space\|Newline\|Tab\|Page\|Rubout\|Linefeed\|Return\|Backspace\)!
syn match lispEscapeSpecial "\<+[a-zA-Z_][a-zA-Z_0-9-]*+\>"

hi  link  lispAmpersand     Label
hi  link  lispKey           Special
hi  link  lispPackageName   Typedef
hi  link  lispVar           Identifier
hi  link  lispConstant      Constant

hi  link  lispNumber        Number
hi  link  lispEscapeSpecial Character

" }}}
" ---------------------------------------------------------------------
" Reader macros {{{

"FIXME: This is not strictly a 'reader macro'..."
syn match   lispReaderMacro /'\|`\|\(,@\?\)\|\(#['*+\-.:<=ABCOPRSX\\]\?\)/ nextgroup=@lispFormCluster

"Quote, comma functions"
syn match   lispQuote     /'[^()'`,"; \t]\+/  contains=lispReaderMacro
syn match   lispFunction  /#'[^()'`,"; \t]\+/ contains=lispReaderMacro

"String"
syn region  lispString start=+"+ skip=+\\\\\|\\"+ end=+"+ contains=@Spell

"Comments"
syn cluster lispCommentGroup            contains=@Spell
syn match   lispComment       ";.*$"    contains=@lispCommentGroup
syn match   lispTripleComment ";;;.*$"  contains=@lispCommentGroup
syn match   lispQuadraComment ";;;;.*$" contains=@lispCommentGroup
syn region  lispCommentRegion           start="#|"      end="|#"        contains=lispCommentRegion,@lispCommentGroup
syn region  lispComment                 start="#+nil"   end="\ze)"      contains=@lispCommentGroup
syn match   lispComment '^\s*#+nil.*$'  contains=@lispCommentGroup

hi  link    lispReaderMacro             Operator
hi  link    lispQuote                   Special
hi  link    lispFunction                Function

hi  link    lispString                  String

hi  link    lispCommentRegion           Comment
hi  link    lispComment                 Comment
hi  link    lispTripleComment           SpecialComment
hi  link    lispQuadraComment           SpecialComment

" }}}
" ---------------------------------------------------------------------
" Lexical variable (part 2) {{{
"
" lispLexVarDef and lispLexVar1Def should take precedence of lispSym, so it
" should be putted later

syn keyword lispLexVarDef   skipwhite skipnl nextgroup=lispLexVarList  let let* when-let* if-let* prog prog*
syn keyword lispLexVar1Def  skipwhite skipnl nextgroup=lispLexVar1List dolist dotimes do-symbols do-all-symbols with-slots with-accessors

hi  link    lispLexVarDef   Keyword
hi  link    lispLexVar1Def  Keyword

" }}}
" ---------------------------------------------------------------------
" Lambda List {{{

syn keyword lispLambdaListDef contained skipwhite skipnl nextgroup=lispLambdaListParen0,lispNilLambdaList lambda multiple-value-bind destructuring-bind
hi  link    lispLambdaListDef Keyword

syn keyword lispFuncDef             contained skipwhite skipnl nextgroup=lispFuncName defun defmacro defmethod defgeneric
syn match   lispFuncName            contained skipwhite skipnl /[^()'`,"; \t]\+/ nextgroup=lispDefLambdaListParen0,lispNilLambdaList
syn match   lispNilLambdaList       contained skipwhite skipnl /nil/             nextgroup=lispDocString
syn region  lispDefLambdaListParen0 contained skipwhite skipnl matchgroup=hlLevel1 start="(" end=")" skip="|.\{-}|" contains=@lispLambdaListOperators,lispLambdaListParen1 nextgroup=lispDocString

hi  link    lispFuncDef             Keyword
hi  link    lispFuncName            Function
hi  link    lispNilLambdaList       Identifier
hi  link    lispDefLambdaListParen0 Identifier

syn region  lispLambdaListParen0 contained matchgroup=hlLevel1 start="(" end=")" skip="|.\{-}|" contains=@lispLambdaListOperators,lispLambdaListParen1
syn region  lispLambdaListParen1 contained matchgroup=hlLevel2 start="(" end=")" skip="|.\{-}|" contains=@lispLambdaListOperators,lispLambdaListParen2
syn region  lispLambdaListParen2 contained matchgroup=hlLevel3 start="(" end=")" skip="|.\{-}|" contains=@lispLambdaListOperators,lispLambdaListParen3
syn region  lispLambdaListParen3 contained matchgroup=hlLevel4 start="(" end=")" skip="|.\{-}|" contains=@lispLambdaListOperators,lispLambdaListParen4
syn region  lispLambdaListParen4 contained matchgroup=hlLevel5 start="(" end=")" skip="|.\{-}|" contains=@lispLambdaListOperators,lispLambdaListParen5
syn region  lispLambdaListParen5 contained matchgroup=hlLevel6 start="(" end=")" skip="|.\{-}|" contains=@lispLambdaListOperators,lispLambdaListParen0

hi link     lispLambdaListParen0 Identifier
hi link     lispLambdaListParen1 Identifier
hi link     lispLambdaListParen2 Identifier
hi link     lispLambdaListParen3 Identifier
hi link     lispLambdaListParen4 Identifier
hi link     lispLambdaListParen5 Identifier

"&optional"
syn keyword lispLambdaListOptional      contained skipwhite skipnl &optional nextgroup=lispLambdaListOptionalList,lispLambdaListOptionalSym
syn match   lispLambdaListOptionalSym   contained skipwhite skipnl /[^()'`,"; \t&]\+/ nextgroup=lispLambdaListOptionalList,lispLambdaListOptionalSym
syn region  lispLambdaListOptionalList  contained skipwhite skipnl matchgroup=hlLevel2 start="(" end=")" skip="|.\{-}|" contains=lispLambdaListOptionalList1 nextgroup=lispLambdaListOptionalList,lispLambdaListOptionalSym
syn match   lispLambdaListOptionalList1 contained skipwhite skipnl /[^()'`,"; \t]\+/ nextgroup=lispLambdaListOptionalList2
syn match   lispLambdaListOptionalList2 contained skipwhite skipnl /[^()'`,"; \t]\+/ contains=@lispFormCluster nextgroup=lispLambdaListOptionalList3
syn region  lispLambdaListOptionalList2 contained skipwhite skipnl matchgroup=hlLevel3 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen4 nextgroup=lispLambdaListOptionalList3
syn match   lispLambdaListOptionalList3 contained /[^()'`,"; \t&]\+/

hi  link    lispLambdaListOptional      Label
hi  link    lispLambdaListOptionalSym   Identifier
hi  link    lispLambdaListOptionalList1 Identifier
hi  link    lispLambdaListOptionalList3 Identifier

"&key"
syn keyword lispLambdaListKey           contained skipwhite skipnl &key nextgroup=lispLambdaListKeySym,lispLambdaListKeyList
syn match   lispLambdaListKeySym        contained skipwhite skipnl /[^()'`,"; \t&]\+/ nextgroup=lispLambdaListKeySym,lispLambdaListKeyList
syn region  lispLambdaListKeyList       contained skipwhite skipnl matchgroup=hlLevel2 start="(" end=")" skip="|.\{-}|" contains=lispLambdaListKeyList1 nextgroup=lispLambdaListKeySym,lispLambdaListKeyList
syn match   lispLambdaListKeyList1      contained skipwhite skipnl /[^()'`,"; \t]\+/ nextgroup=lispLambdaListKeyList2
syn region  lispLambdaListKeyList1      contained skipwhite skipnl matchgroup=hlLevel3 start="(" end=")" skip="|.\{-}|" contains=lispLambdaListKeyList11 nextgroup=lispLambdaListKeyList2
syn match   lispLambdaListKeyList11     contained skipwhite skipnl /[^()'`,"; \t]\+/ nextgroup=lispLambdaListKeyList12
syn match   lispLambdaListKeyList12     contained /[^()'`,"; \t]\+/
syn match   lispLambdaListKeyList2      contained skipwhite skipnl /[^()'`,"; \t]\+/ contains=@lispFormCluster nextgroup=lispLambdaListKeyList3
syn region  lispLambdaListKeyList2      contained skipwhite skipnl matchgroup=hlLevel3 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen4 nextgroup=lispLambdaListKeyList3
syn match   lispLambdaListKeyList3      contained /[^()'`,"; \t&]\+/

hi  link    lispLambdaListKey           Label
hi  link    lispLambdaListKeySym        Identifier
hi  link    lispLambdaListKeyList1      Identifier
hi  link    lispLambdaListKeyList11     Special
hi  link    lispLambdaListKeyList12     Identifier
hi  link    lisplambdalistkeylist3      Identifier

"&aux"
syn keyword lispLambdaListAux           contained skipwhite skipnl &aux nextgroup=lispLambdaListAuxSym,lispLambdaListAuxList
syn match   lispLambdaListAuxSym        contained skipwhite skipnl /[^()'`,"; \t&]\+/ nextgroup=lispLambdaListAuxSym,lispLambdaListAuxList
syn region  lispLambdaListAuxList       contained skipwhite skipnl matchgroup=hlLevel2 start="(" end=")" skip="|.\{-}|" contains=lispLambdaListAuxList1 nextgroup=lispLambdaListAuxSym,lispLambdaListAuxList
syn match   lispLambdaListAuxList1      contained skipwhite skipnl /[^()'`,"; \t]\+/ nextgroup=lispLambdaListAuxList2
syn match   lispLambdaListAuxList2      contained /[^()'`,"; \t]\+/ contains=@lispFormCluster
syn region  lispLambdaListAuxList2      contained matchgroup=hlLevel3 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen4

hi  link    lispLambdaListAux           Label
hi  link    lispLambdaListAuxSym        Identifier
hi  link    lispLambdaListAuxList1      Identifier

syn cluster lispLambdaListOperators     contains=lispAmpersand,lispLambdaListOptional,lispLambdaListKey,lispLambdaListAux

" }}}
" ---------------------------------------------------------------------
" Definition Forms {{{

syn match   lispDef /def[^()'`,"; \t]\+/

syn keyword lispVarDef   defvar defparameter defconstant define-symbol-macro contained skipwhite skipnl nextgroup=lispVarName
syn match   lispVarName  /[^()'`,"; \t]\+/ contained skipwhite skipnl nextgroup=lispVarVal

syn keyword lispConstantDef defconstant contained skipwhite skipnl nextgroup=lispConstantName
syn match   lispConstantName /[^()'`,"; \t]\+/ contained skipwhite skipnl nextgroup=lispVarVal

syn match   lispVarVal   /[^()'`,"; \t]\+/ contained skipwhite skipnl nextgroup=lispDocStringlispVarVal
syn region  lispVarVal   contained matchgroup=hlLevel3 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen4 nextgroup=lispDocString

syn region  lispDocString start=/"/ skip=/\\\\\|\\"/ end=/"/ contained contains=@Spell

syn keyword lispClassDef       defclass contained skipwhite skipnl nextgroup=lispClassName
syn match   lispClassName      /[^()',"; \t]\+/ contained skipwhite skipnl nextgroup=lispSuperClassList
syn match   lispSuperClassList /(\_[^()]*)/     contained

syn keyword lispTypeDef  deftype defpackage defstruct contained skipwhite skipnl nextgroup=lispTypeName
syn match   lispTypeName contained /[^()',"; \t]\+/

syn cluster lispDefs contains=lispDef,lispFuncDef,lispVarDef,lispClassDef,lispTypeDef,lispLambdaListDef,lispLexVarDef,lispLexVar1Def

hi  link    lispDef            Keyword
hi  link    lispVarDef         Keyword
hi  link    lispConstantDef    Keyword
hi  link    lispClassDef       Keyword
hi  link    lispTypeDef        Keyword

hi  link    lispVarName        Identifier
hi  link    lispConstantName   Constant
hi  link    lispClassName      Typedef
hi  link    lispSuperClassList Typedef
hi  link    lispParamFormStart Macro
hi  link    lispTypeName       Typedef

hi  link    lispDocString      SpecialComment

" }}}
" ---------------------------------------------------------------------
" Loop {{{

syn match   lispLoopAnyAtom       skipwhite skipnl contained nextgroup=@lispLoopCluster /[^()',"; \t]*\_s\+/

syn match   lispLoopKey           skipwhite skipnl contained nextgroup=@lispLoopCluster /\<:[^()'`,"; \t]\+/
syn match   lispLoopAmpersand     skipwhite skipnl contained nextgroup=@lispLoopCluster /&[^()'`,"; \t]\+/
syn match   lispLoopPackage       skipwhite skipnl contained nextgroup=@lispLoopCluster /\<[^()'`,"; \t]\+::\+/
syn match   lispLoopPackage       skipwhite skipnl contained nextgroup=@lispLoopCluster /\<[^()'`,"; \t]\+:\+/
syn match   lispLoopVar           skipwhite skipnl contained nextgroup=@lispLoopCluster /\<\*[^()'`,"; \t]\*\>/
syn match   lispLoopConstant      skipwhite skipnl contained nextgroup=@lispLoopCluster /\<+[^()'`,"; \t]+\>/
syn match   lispLoopNumber        skipwhite skipnl contained nextgroup=@lispLoopCluster "\<-\=\(\.\d\+\|\d\+\(\.\d*\)\=\)\([dDeEfFlL][-+]\=\d\+\)\=\>"
syn match   lispLoopNumber        skipwhite skipnl contained nextgroup=@lispLoopCluster "\<-\=\(\d\+/\d\+\)\>"
syn match   lispLoopNumber        skipwhite skipnl contained nextgroup=@lispLoopCluster !#x\x\+!
syn match   lispLoopNumber        skipwhite skipnl contained nextgroup=@lispLoopCluster !#o\o\+!
syn match   lispLoopNumber        skipwhite skipnl contained nextgroup=@lispLoopCluster !#b[01]\+!
syn match   lispLoopEscapeSpecial skipwhite skipnl contained nextgroup=@lispLoopCluster "\*\w[a-z_0-9-]*\*"
syn match   lispLoopEscapeSpecial skipwhite skipnl contained nextgroup=@lispLoopCluster !#|[^()'`,"; \t]\+|#!
syn match   lispLoopEscapeSpecial skipwhite skipnl contained nextgroup=@lispLoopCluster !#\\[ -}\~]!
syn match   lispLoopEscapeSpecial skipwhite skipnl contained nextgroup=@lispLoopCluster !#[':][^()'`,"; \t]\+!
syn match   lispLoopEscapeSpecial skipwhite skipnl contained nextgroup=@lispLoopCluster !#([^()'`,"; \t]\+)!
syn match   lispLoopEscapeSpecial skipwhite skipnl contained nextgroup=@lispLoopCluster !#\\\%(Space\|Newline\|Tab\|Page\|Rubout\|Linefeed\|Return\|Backspace\)!
syn match   lispLoopEscapeSpecial skipwhite skipnl contained nextgroup=@lispLoopCluster "\<+[a-zA-Z_][a-zA-Z_0-9-]*+\>"
syn match   lispLoopReaderMacro   skipwhite skipnl contained nextgroup=@lispLoopCluster /'\|`\|\(,@\?\)\|\(#['*+\-.:<=ABCOPRSX\\]\?\)/
syn match   lispLoopQuote         skipwhite skipnl contained nextgroup=@lispLoopCluster /'[^()'`,"; \t]\+/  contains=lispReaderMacro
syn match   lispLoopFunction      skipwhite skipnl contained nextgroup=@lispLoopCluster /#'[^()'`,"; \t]\+/ contains=lispReaderMacro
syn region  lispLoopString        skipwhite skipnl contained nextgroup=@lispLoopCluster start=+"+ skip=+\\\\\|\\"+ end=+"+ contains=@Spell
syn match   lispLoopComment       skipwhite skipnl contained nextgroup=@lispLoopCluster ";.*\n"         contains=@lispCommentGroup
syn match   lispLoopTripleComment skipwhite skipnl contained nextgroup=@lispLoopCluster ";;;.*\n"       contains=@lispCommentGroup
syn match   lispLoopQuadraComment skipwhite skipnl contained nextgroup=@lispLoopCluster ";;;;.*\n"      contains=@lispCommentGroup
syn region  lispLoopCommentRegion skipwhite skipnl contained nextgroup=@lispLoopCluster                 start="#|"      end="|#"        contains=lispCommentRegion,@lispCommentGroup
syn region  lispLoopComment       skipwhite skipnl contained nextgroup=@lispLoopCluster                 start="#+nil"   end="\ze)"      contains=@lispCommentGroup
syn match   lispLoopComment       skipwhite skipnl contained nextgroup=@lispLoopCluster '^\s*#+nil.*$'  contains=@lispCommentGroup

syn region  lispLoopParen0        skipwhite skipnl contained nextgroup=@lispLoopCluster matchgroup=hlLevel1 start="(" end=")" skip="|.\{-}|" contains=@lispFormCluster,lispParen1

syn keyword lispLoopKeywords      skipwhite skipnl contained nextgroup=@lispLoopCluster named initially finally for as with do collect collecting append appending nconc nconcing into count counting sum summing maximize return loop-finish maximizing minimize minimizing doing thereis always never if when unless repeat while until by = and it else end from upfrom above below to upto downto downfrom in on then across being each the hash-key hash-keys of using hash-value hash-values symbol symbols present-symbol present-symbols external-symbol external-symbols fixnum float of-type
syn keyword lispLoop              skipwhite skipnl contained nextgroup=@lispLoopCluster loop cl-loop

syn cluster lispLoopCluster       contains=lispLoopKeywords,lispLoopParen0,lispLoopKey,lispLoopAmpersand,lispLoopPackage,lispLoopVar,lispLoopNumber,lispLoopEscapeSpecial,lispLoopReaderMacro,lispLoopQuote,lispLoopFunction,lispLoopString,lispLoopComment,lispLoopCommentRegion,lispLoopAnyAtom

hi  link    lispLoopKey           Special
hi  link    lispLoopAmpersand     Label
hi  link    lispLoopPackage       Typedef
hi  link    lispLoopVar           Identifier
hi  link    lispLoopConstant      Constant
hi  link    lispLoopCommentRegion Comment
hi  link    lispLoopComment       Comment
hi  link    lispLoopTripleComment SpecialComment
hi  link    lispLoopQuadraComment SpecialComment
hi  link    lispLoopNumber        Number
hi  link    lispLoopEscapeSpecial Character
hi  link    lispLoopString        String
hi  link    lispLoopReaderMacro   Operator
hi  link    lispLoopQuote         Operator
hi  link    lispLoopFunction      Function

hi  link    lispLoop              Repeat
hi  link    lispLoopKeywords      Label

" }}}
" ---------------------------------------------------------------------
" Synchronization: {{{

syn sync lines=100

let b:current_syntax = "common-lisp"
" ---------------------------------------------------------------------
" vim: ts=8 nowrap fdm=marker
