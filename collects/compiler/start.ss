;; Starts up the compiler according to command-line flags.
;; (c) 1997-8 PLT, Rice University

;; Scheme->C compilation is the only mode really handled
;;  by the code in this collection. Other modes are handled
;;  by other collections, such as MzLib and dynext.
;; If you are interested Scheme->C part of mzc, look in
;;  driver.ss, which is the `main' file for the compiler.

;; Different compilation modes are driven by dynamically
;;  linking in appropriate libraries. This is handled
;;  by compiler.ss.

;; See doc.txt for information about the Scheme-level interface
;;  provided by this collection.

; (require-library "traceld.ss")

; On error, exit with -1 status code
(error-escape-handler (lambda () (exit -1)))

(read-case-sensitive #t)
(error-print-width 10024)

(require-library "option.ss" "compiler")

; Read argv array for arguments and input file name
(require-library "cmdline.ss")
(require-library "functio.ss")
(require-library "match.ss")
(require-library "file.ss" "dynext")
(require-library "compile.ss" "dynext")
(require-library "link.ss" "dynext")

; temp!!!!
; (require-library "errortrace.ss" "errortrace")
; !!!!!!!

(define dest-dir (make-parameter #f))

(define ld-output (make-parameter #f))

; Returns (values mode files prefixes)
;  where mode is 'compile, 'link, or 'zo
(define (parse-options argv)
  (parse-command-line
   "mzc"
   argv
   `([once-any
      [("-e" "--extension")
       ,(lambda (f) 'compile)
       (,(format "Output ~a file(s) from Scheme source(s) (default)" (append-extension-suffix "")))]
      [("-c" "--c-source")
       ,(lambda (f) 'compile-c)
       (,(format "Output only ~a file(s) from Scheme source(s)" (append-c-suffix "")))]
      [("-o" "--object")
       ,(lambda (f) 'compile-o)
       (,(format "Output ~a and ~a files from Scheme source(s) for a multi-file extension" 
		 (append-object-suffix "")
		 (append-constant-pool-suffix "")))]
      [("-l" "--link-extension")
       ,(lambda (f) 'link)
       (,(format "Link multiple ~a and ~a files into a ~a file"
		 (append-object-suffix "")
		 (append-constant-pool-suffix "")
		 (append-extension-suffix "")))]
      [("-g" "--link-glue")
       ,(lambda (f) 'glue)
       (,(format "Create the ~a glue for --link-extension, but do not link"
		 (append-object-suffix "")))]
      [("-z" "--zo")
       ,(lambda (f) 'zo)
       (,(format "Output ~a file(s) from Scheme source(s)" (append-zo-suffix "")))]
      [("--collection-extension")
       ,(lambda (f) 'collection-extension)
       ("Compile specified collection to extension")]
      [("--collection-zos")
       ,(lambda (f) 'collection-zos)
       (,(format "Compile specified collection to ~a files" (append-zo-suffix "")))]
      [("--cc")
       ,(lambda (f) 'cc)
       (,(format "Compile arbitrary file(s) for an extension: ~a -> ~a" 
		 (append-c-suffix "")
		 (append-object-suffix "")))]
      [("--ld")
       ,(lambda (f name) (ld-output name) 'ld)
       (,(format "Link arbitrary file(s) to create <extension>: ~a -> ~a" 
		 (append-object-suffix "")
		 (append-extension-suffix ""))
	,"extension")]]
     [once-each
      [("--embedded")
       ,(lambda (f) (compiler:option:compile-for-embedded #t))
       ("Compile for embedded run-time engine, with -c/-o/-g")]
      [("-p" "--prefix") 
       ,(lambda (f v) v)
       ("Add elaboration-time prefix file for -e/-c/-o/-z (allowed multiple times)" "file")]
      [("-d" "--destination") 
       ,(lambda (f d)
	  (unless (directory-exists? d)
		  (error 'mzc "the destination directory does not exist: ~s" d))
	  (dest-dir d))
       ("Output file(s) to <dir>" "dir")]
      [("-v") 
       ,(lambda (f) (compiler:option:verbose #t))
       ("Verbose mode")]
      [("--tool") 
       ,(lambda (f v) 
	  (let ([v (string->symbol v)])
	    (use-standard-compiler v)
	    (use-standard-linker v)))
       (,(format "Use pre-defined <tool> as C compiler/linker:~a" 
		 (apply string-append
			(apply append
			       (map (lambda (t)
				      (list " " (symbol->string t)))
				    (get-standard-compilers)))))
	"tool")]
      [("--compiler") 
       ,(lambda (f v) (current-extension-compiler v))
       ("Use <compiler-path> as C compiler" "compiler-path")]]
     [multi
      [("--ccf-clear") 
       ,(lambda (f) (current-extension-compiler-flags null))
       ("Clear C compiler flags (allowed multiple times)")]
      [("++ccf") 
       ,(lambda (f v) (current-extension-compiler-flags
		       (cons v (current-extension-compiler-flags))))
       ("Add C compiler flag (allowed multiple times)" "flag")]
      [("--ccf") 
       ,(lambda (f v) (current-extension-compiler-flags
		       (remove v (current-extension-compiler-flags))))
       ("Remove C compiler flag (allowed multiple times)" "flag")]]
     [once-each
      [("--linker") 
       ,(lambda (f v) (current-extension-linker v))
       ("Use <linker-path> as C linker" "linker-path")]]
     [multi
      [("--ldf-clear") 
       ,(lambda (f) (current-extension-linker-flags null))
       ("Clear C linker flags (allowed multiple times)")]
      [("++ldf") 
       ,(lambda (f v) (current-extension-linker-flags
		       (cons v (current-extension-linker-flags))))
       ("Add C linker flag (allowed multiple times)" "flag")]
      [("--ldf") 
       ,(lambda (f v) (current-extension-linker-flags
		       (remove v (current-extension-linker-flags))))
       ("Remove C linker flag (allowed multiple times)" "flag")]]
     [once-any
      [("-a" "--mrspidey")
       ,(lambda (f) 
	  (with-handlers ([void (lambda (x)
				  (error 'mzc "MrSpidey is not installed"))])
	    (collection-path "mrspidey"))
	  (compiler:option:use-mrspidey #t))
       ("Analyze whole program with MrSpidey")]
      [("-u" "--mrspidey-units")
       ,(lambda (f) 
	  (with-handlers ([void (lambda (x)
				  (error 'mzc "MrSpidey is not installed"))])
	    (collection-path "mrspidey"))
	  (compiler:option:use-mrspidey-for-units #t))
       ("Analyze top-level units with MrSpidey")]]
     [once-each
      [("--no-prop")
       ,(lambda (f) (compiler:option:propagate-constants #f))
       ("Don't propogate constants")]
      [("--no-lite")
       ,(lambda (f) (compiler:option:lightweight #f))
       ("Don't perform lightweight closure conversion")]
      [("--inline")
       ,(lambda (f d) (compiler:option:max-inline-size 
		       (with-handlers ([void
					(lambda (x)
					  (error 'mzc "bad size for --inline: ~a" d))])
			 (let ([v (string->number d)])
			   (unless (and (not (negative? v)) (exact? v) (real? v))
			     (error 'bad))
			   v))))
       ("Set the maximum inlining size" "size")]
      [("--prim")
       ,(lambda (f) (compiler:option:assume-primitives #t))
       ("Assume primitives (e.g., treat `car' as `#%car')")]
      [("--stupid")
       ,(lambda (f) (compiler:option:stupid #t))
       ("Compile despite obvious non-syntactic errors")]]
     [once-each
      [("-n" "--name") 
       ,(lambda (f name) (compiler:option:setup-prefix name))
       ("Embed <name> as an extra part of public low-level names" "name")]
      [("--dirty")
       ,(lambda (f) (compiler:option:clean-intermediate-files #f))
       ("Don't remove intermediate files")]
      [("--debug")
       ,(lambda (f) (compiler:option:debug #t))
       ("Write debugging output to dump.txt")]])
   (lambda (accum file . files)
     (values 
      (let ([l (filter symbol? accum)])
	(if (null? l)
	    'compile
	    (car l)))
      (cons file files) 
      `(begin
	 ,@(map (lambda (s) `(load ,s)) (filter string? accum))
	 (void))))
   (list "file or collection" "file or sub-collection")))

(printf "MzScheme compiler version ~a, Copyright (c) 1996-98 PLT~n"
	(version))

(define-values (mode source-files prefix)
  (parse-options argv))

(require-relative-library "compile.ss")

(define (never-embedded action)
  (when (compiler:option:compile-for-embedded)
	(error 'mzc "cannot ~a an extension for an embedded MzScheme" action)))

(case mode
  [(compile)
   (never-embedded "compile")
   ((compile-extensions prefix) source-files (dest-dir))]
  [(compile-c)
   ((compile-extensions-to-c prefix) source-files (dest-dir))]
  [(compile-o)
   ((compile-extension-parts prefix) source-files (dest-dir))]
  [(link)
   (never-embedded "link")
   (link-extension-parts source-files (or (dest-dir) (current-directory)))]
  [(glue)
   (glue-extension-parts source-files (or (dest-dir) (current-directory)))]
  [(zo)
   ((compile-zos prefix) source-files (dest-dir))]
  [(collection-extension)
   (apply compile-collection-extension source-files)]
  [(collection-zos)
   (apply compile-collection-zos source-files)]
  [(cc)
   (require-library "compile.ss" "dynext")
   (require-library "file.ss" "dynext")
   (for-each
    (lambda (file)
      (let* ([base (extract-base-filename/c file 'mzc)]
	     [dest (append-object-suffix 
		    (let-values ([(base name dir?) (split-path base)])
		      (build-path (or (dest-dir) 'same) name)))])
	(printf "\"~a\":~n" file)
	(compile-extension (not (compiler:option:verbose))
			   file
			   dest
			   null)
	(printf " [output to \"~a\"]~n" dest)))
    source-files)]
  [(ld)
   (require-library "compile.ss" "dynext")
   (require-library "link.ss" "dynext")
   (extract-base-filename/ext (ld-output) 'mzc)
   ; (for-each (lambda (file) (extract-base-filename/o file 'mzc)) source-files)
   (let ([dest (if (dest-dir)
		   (build-path (dest-dir) (ld-output))
		   (ld-output))])
     (printf "~a:~n" (let ([s (apply string-append
				     (map (lambda (n) (format " \"~a\"" n)) source-files))])
		       (substring s 1 (string-length s))))
     (link-extension (not (compiler:option:verbose))
		     source-files
		     dest)
     (printf " [output to \"~a\"]~n" dest))]
  [else (printf "bad mode: ~a~n" mode)])
