;; Starts up the compiler according to command-line flags.
;; (c) 1997-2001 PLT

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

(module start mzscheme

  ;; On error, exit with 1 status code
  (error-escape-handler (lambda () (exit 1)))

  (error-print-width 512)

  (require (prefix compiler:option: "option.ss"))
  (require "compiler.ss")

  ;; Read argv array for arguments and input file name
  (require (lib "cmdline.ss")
	   (lib "list.ss")
	   (lib "file.ss" "dynext")
	   (lib "compile.ss" "dynext")
	   (lib "link.ss" "dynext")
	   (lib "pack.ss" "setup"))

  (define dest-dir (make-parameter #f))
  (define auto-dest-dir (make-parameter #f))

  (define ld-output (make-parameter #f))

  (define exe-output (make-parameter #f))
  (define exe-embedded-flags (make-parameter '("-mvq-")))
  (define exe-embedded-libraries (make-parameter null))

  (define module-mode (make-parameter #f))

  (define plt-output (make-parameter #f))
  (define plt-name (make-parameter "archive"))
  (define plt-files-replace (make-parameter #f))
  (define plt-setup-collections (make-parameter null))

  ;; Returns (values mode files prefixes)
  ;;  where mode is 'compile, 'link, or 'zo
  (define (parse-options argv)
    (parse-command-line
     "mzc"
     argv
     `([help-labels
	"-------------------------------- mode flags ---------------------------------"]
       [once-any
	[("-e" "--extension")
	 ,(lambda (f) 'compile)
	 (,(format "Output ~a file(s) from Scheme source(s) (default)" (append-extension-suffix "")))]
	[("-c" "--c-source")
	 ,(lambda (f) 'compile-c)
	 (,(format "Output ~a file(s) from Scheme source(s)" (append-c-suffix "")))]
	[("-o" "--object")
	 ,(lambda (f) 'compile-o)
	 (,(format "Output ~a/~a from Scheme source(s) for a multi-file extension" 
		   (append-object-suffix "")
		   (append-constant-pool-suffix "")))]
	[("-l" "--link-extension")
	 ,(lambda (f) 'link)
	 (,(format "Link multiple ~a and ~a files into a ~a file"
		   (append-object-suffix "")
		   (append-constant-pool-suffix "")
		   (append-extension-suffix "")))]
	[("-g" "--link-glue")
	 ,(lambda (f) 'link-glue)
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
	  "extension")]
	[("--exe")
	 ,(lambda (f name) (exe-output name) 'exe)
	 (,(format "Embed module in MzScheme to create <exe>")
	  "exe")]
	[("--gui-exe")
	 ,(lambda (f name) (exe-output name) 'gui-exe)
	 (,(format "Embed module in MrEd to create <exe>")
	  "exe")]
	[("--plt")
	 ,(lambda (f name) (plt-output name) 'plt)
	 (,(format "Create .plt <archive> with files/dirs relative to PLTHOME")
	  "archive")]]
       [once-each
	[("-m" "--module")
	 ,(lambda (f) (module-mode #t))
	 ("Skip eval of top-level syntax, etc. for -e/-c/-o/-z")]
	[("--embedded")
	 ,(lambda (f) (compiler:option:compile-for-embedded #t))
	 ("Compile for embedded run-time engine, with -c/-o/-g")]
	[("-p" "--prefix") 
	 ,(lambda (f v) v)
	 ("Add elaboration-time prefix file for -e/-c/-o/-z" "file")]
	[("-n" "--name") 
	 ,(lambda (f name) (compiler:option:setup-prefix name))
	 ("Use <name> as extra part of public low-level names" "name")]]
       [once-any
	[("-d" "--destination") 
	 ,(lambda (f d)
	    (unless (directory-exists? d)
	      (error 'mzc "the destination directory does not exist: ~s" d))
	    (dest-dir d))
	 ("Output -e/-c/-o/-l/-g/-z file(s) to <dir>" "dir")]
	[("--auto-dir")
	 ,(lambda (f)
	    (auto-dest-dir #t))
	 (,(format "Output -z to \"compiled\", -e to ~s"
		   (build-path "compiled" "native" (system-library-subpath))))]]

       [help-labels
	"------------------- compiler/linker configuration flags ---------------------"]
       [once-each
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
	[("++ccf") 
	 ,(lambda (f v) (current-extension-compiler-flags
			 (append (current-extension-compiler-flags)
				 (list v))))
	 ("Add C compiler flag" "flag")]
	[("--ccf") 
	 ,(lambda (f v) (current-extension-compiler-flags
			 (remove v (current-extension-compiler-flags))))
	 ("Remove C compiler flag" "flag")]
	[("--ccf-clear") 
	 ,(lambda (f) (current-extension-compiler-flags null))
	 ("Clear C compiler flags")]
	[("--ccf-show") 
	 ,(lambda (f) 
	    (printf "C compiler flags: ~s~n" (current-extension-compiler-flags)))
	 ("Show C compiler flags")]]
       [once-each
	[("--linker") 
	 ,(lambda (f v) (current-extension-linker v))
	 ("Use <linker-path> as C linker" "linker-path")]]
       [multi
	[("++ldf") 
	 ,(lambda (f v) (current-extension-linker-flags
			 (append (current-extension-linker-flags)
				 (list v))))
	 ("Add C linker flag" "flag")]
	[("--ldf") 
	 ,(lambda (f v) (current-extension-linker-flags
			 (remove v (current-extension-linker-flags))))
	 ("Remove C linker flag" "flag")]
	[("--ldf-clear") 
	 ,(lambda (f) (current-extension-linker-flags null))
	 ("Clear C linker flags")]
	[("--ldf-show") 
	 ,(lambda (f) 
	    (printf "C linker flags: ~s~n" (current-extension-linker-flags)))
	 ("Show C linker flags")]]
       [help-labels
	"-------------------- .zo compiler configuration flags -----------------------"]
       [multi
	[("++zof") 
	 ,(lambda (f v) (compiler:option:zo-compiler-flags
			 (append (compiler:option:zo-compiler-flags)
				 (list (string->symbol v)))))
	 ("Add .zo compiler flag (see `compile-file' docs)" "flag")]
	[("--zof") 
	 ,(lambda (f v) (compiler:option:zo-compiler-flags
			 (remove (string->symbol v) (compiler:option:zo-compiler-flags))))
	 ("Remove .zo compiler flag" "flag")]
	[("--zof-clear") 
	 ,(lambda (f) (compiler:option:zo-compiler-flags null))
	 ("Clear .zo compiler flags")]
	[("--zof-show") 
	 ,(lambda (f) 
	    (printf ".zo compiler flags: ~s~n" (compiler:option:zo-compiler-flags)))
	 ("Show .zo compiler flags")]]
       [help-labels
	"--------------------- executable configuration flags ------------------------"]
       [multi
	[("++lib")
	 ,(lambda (f l c) (exe-embedded-libraries
			   (append (exe-embedded-libraries)
				   (list (list l c)))))
	 ("Embed <lib> from <collect> in --[gui-]exe executable" "lib" "collect")]
	[("++exf") 
	 ,(lambda (f v) (exe-embedded-flags
			 (append (exe-embedded-flags)
				 (list v))))
	 ("Add flag to embed in --[gui-]exe executable" "flag")]
	[("--exf") 
	 ,(lambda (f v) (exe-embedded-flags
			 (remove v (exe-embedded-flags))))
	 ("Remove flag to embed in --[gui-]exe executable" "flag")]
	[("--exf-clear") 
	 ,(lambda (f) (exe-embedded-flags null))
	 ("Clear flags to embed in --[gui-]exe executable")]
	[("--exf-show") 
	 ,(lambda (f) 
	    (printf "Flags to embed: ~s~n" (exe-embedded-flags)))
	 ("Show flag to embed in --[gui-]exe executable")]]
       [help-labels
	"----------------------------- .plt archive flags ----------------------------"]
       [once-each
	[("--plt-name")
	 ,(lambda (f n) (plt-name n))
	 ("Set the printed <name> describing the archive" "name")]
	[("--replace")
	 ,(lambda (f) (plt-files-replace #t))
	 ("Files in archive replace existing files when unpacked")]]
       [multi
	[("++setup")
	 ,(lambda (f c) (plt-setup-collections
			 (append (plt-setup-collections)
				 (list c))))
	 ("Setup <collect> after the archive is unpacked" "collect")]]
       [help-labels
	"----------------------- compiler optimization flags -------------------------"]

       [once-each
	[("--no-prop")
	 ,(lambda (f) (compiler:option:propagate-constants #f))
	 ("Don't propagate constants")]
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
	 ("Assume primitive bindings at top-level")]
	[("--stupid")
	 ,(lambda (f) (compiler:option:stupid #t))
	 ("Compile despite obvious non-syntactic errors")]
	[("--unsafe-disable-interrupts")
	 ,(lambda (f) (compiler:option:disable-interrupts #t))
	 ("Ignore threads, breaks, and stack overflow")]
	[("--unsafe-skip-tests")
	 ,(lambda (f) (compiler:option:unsafe #t))
	 ("Skip run-time tests for some primitive operations")]
	[("--unsafe-fixnum-arithmetic")
	 ,(lambda (f) (compiler:option:fixnum-arithmetic #t))
	 ("Assume fixnum arithmetic yields a fixnum")]]
       [help-labels
	"-------------------------- miscellaneous flags ------------------------------"]
       [once-each
	[("-v") 
	 ,(lambda (f) (compiler:option:verbose #t))
	 ("Verbose mode")]
	[("--save-temps")
	 ,(lambda (f) (compiler:option:clean-intermediate-files #f))
	 ("Keep intermediate files")]
	[("--debug")
	 ,(lambda (f) (compiler:option:debug #t))
	 ("Write debugging output to dump.txt")]])
     (lambda (accum file . files)
       (let ([mode (let ([l (filter symbol? accum)])
		     (if (null? l)
			 'compile
			 (car l)))])
	 (values 
	  mode
	  (cons file files)
	  (let ([prefixes (filter string? accum)])
	    (unless (memq mode '(compile compile-c compile-o zo))
	      (unless (null? prefixes)
		(error 'mzc "prefix files are not useful in ~a mode" mode)))
	    (if (module-mode)
		(begin
		  (when (compiler:option:assume-primitives)
		    (error 'mzc "--prim is not useful with -m or --module"))
		  (unless (null? prefixes)
		    (error 'mzc "prefix files not allowed with -m or --module"))
		  #f)
		`(begin
		   ,(if (compiler:option:assume-primitives) '(require mzscheme) '(void))
		   (require (lib "cffi.ss" "compiler"))
		   (require-for-syntax mzscheme)
		   ,@(map (lambda (s) `(load ,s)) prefixes)
		   (void)))))))
     (list "file/directory/collection" "file/directory/sub-collection")))

  (printf "MzScheme compiler (mzc) version ~a, Copyright (c) 1996-2001 PLT~n"
	  (version))

  (define-values (mode source-files prefix)
    (parse-options (namespace-variable-binding 'argv)))

  (when (auto-dest-dir)
    (unless (memq mode '(zo compile))
      (error 'mzc "--auto-dir works only with -z, --zo, -e, or --extension (or default mode)")))

  (define (never-embedded action)
    (when (compiler:option:compile-for-embedded)
      (error 'mzc "cannot ~a an extension for an embedded MzScheme" action)))
  
  (case mode
    [(compile)
     (never-embedded "compile")
     ((compile-extensions prefix) source-files (if (auto-dest-dir)
						   'auto
						   (dest-dir)))]
    [(compile-c)
     ((compile-extensions-to-c prefix) source-files (dest-dir))]
    [(compile-o)
     ((compile-extension-parts prefix) source-files (dest-dir))]
    [(link)
     (never-embedded "link")
     (link-extension-parts source-files (or (dest-dir) (current-directory)))]
    [(link-glue)
     (glue-extension-parts source-files (or (dest-dir) (current-directory)))]
    [(zo)
     ((compile-zos prefix) source-files (if (auto-dest-dir)
					    'auto
					    (dest-dir)))]
    [(collection-extension)
     (apply compile-collection-extension source-files)]
    [(collection-zos)
     (apply compile-collection-zos source-files)]
    [(cc)
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
     (extract-base-filename/ext (ld-output) 'mzc)
     ;; (for-each (lambda (file) (extract-base-filename/o file 'mzc)) source-files)
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
    [(exe gui-exe)
     (unless (= 1 (length source-files))
       (error 'mzc "expected a single module source file to embed; given: ~e"
	      source-files))
     ((dynamic-require '(lib "embed.ss" "compiler") 'make-embedding-executable)
      (exe-output)
      (eq? mode 'gui-exe) 
      (compiler:option:verbose)
      (cons
       `(#%mzc: (file ,(car source-files)))
       (map (lambda (l)
	      `(#t (lib ,@l)))
	    (exe-embedded-libraries)))
      null
      `(require ,(string->symbol
		  (format
		   "#%mzc:~a"
		   (let-values ([(base name dir?) (split-path (car source-files))])
		     (regexp-replace "[.].?.?.?$" name "")))))
      (let ([flags (exe-embedded-flags)])
	(if (eq? mode 'gui-exe) 
	    (cons "-Z" flags)
	    flags)))
     (printf " [output to \"~a\"]~n" (exe-output))]
    [(plt)
     (pack (plt-output) (plt-name)
	   source-files
	   (map list (plt-setup-collections))
	   std-filter #t 
	   (if (plt-files-replace)
	       'file-replace
	       'file))
       (printf " [output to \"~a\"]~n" (plt-output))]
    [else (printf "bad mode: ~a~n" mode)]))
