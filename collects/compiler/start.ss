
; (require-library "traceld.ss")

; On error, exit with -1 status code
(error-escape-handler (lambda () (exit -1)))

(read-case-sensitive #t)

(require-library "option.ss" "compiler")

; Read argv array for arguments and input file name
(require-library "cmdline.ss")
(require-library "functio.ss")
(require-library "file.ss" "dynext")

(define dest-dir (make-parameter #f))

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
       (,(format "Compile specified collection to ~a files" (append-zo-suffix "")))]]
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
      [("--cc") 
       ,(lambda (f v) (current-extension-compiler v))
       ("Use <compiler> as C compiler" "compiler")]]
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
      [("-a" "--mrspidey")
       ,(lambda (f) 
	  (with-handlers ([void (lambda (x)
				  (error 'mzc "MrSpidey is not installed"))])
	    (collection-path "mrspidey"))
	  (compiler:option:use-mrspidey #t))
       ("Analyze with MrSpidey")]
      [("--no-prop")
       ,(lambda (f) (compiler:option:propagate-constants #f))
       ("Don't propogate constants")]
      [("--prim")
       ,(lambda (f) (compiler:option:assume-primitives #t))
       ("Assume primitives (e.g., treat `car' as `#%car')")]
      [("--stupid")
       ,(lambda (f) (compiler:option:stupid #t))
       ("Compile despite obvious non-syntactic errors")]]
     [once-any
      [("--va")
       ,(lambda (f) (compiler:option:vehicles 'vehicles:automatic))
       ("Try to optimize function vehicle selection during compilation (default)")]
      [("--vm") 
       ,(lambda (f v) 
	  (unless (string->number v)
	      (error 'mzc "monolith argument must be a number"))
	  (let ([num (string->number v)])
	    (unless (and (integer? num)
			 (positive? num)
			 (<= num max-monoliths))
		    (error 'mzc:compile "monoliths must be a number between 1 and ~a"
			   max-monoliths))
	    (compiler:option:monoliths num)))
       ("Use <n> monolithic vehicles during compilation" "n")]
      [("--vf")
       ,(lambda (f) (compiler:option:vehicles 'vehicles:function))
       ("Use per-function vehicles during compilation")]
      [("--vu")
       ,(lambda (f) (compiler:option:vehicles 'vehicles:unit))
       ("Use per-unit vehicles during compilation")]]
     [once-each
      [("--seed") 
       ,(lambda (f v) 
	  (unless (string->number v)
		  (error 'mzc "random number seed must be a number"))
	  (let ([num (string->number v)])
	    (unless (and (integer? num)
			 (< (abs num) (expt 2 30)))
		    (error 'mzc "random number seed must be a smallish number"))
	    (compiler:option:seed num)))
       ("Seed monolith randomizer (with --vm)" "seed")]
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

(printf "MzScheme compiler version ~a, Copyright (c) 1996-98 Sebastian Good.~n"
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
  [else (printf "bad mode: ~a~n" mode)])
