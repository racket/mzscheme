
; (require-library "traceld.ss")

(error-print-width 200)

; On error, exit with -1 status code
(error-escape-handler (lambda () (exit -1)))

; Read argv array for arguments and input file name
(require-library "cmdline.ss")
(require-library "options.ss" "compiler")

(define-values (mode source-files prefix-files)
  (parse-options argv))

(printf "MzScheme compiler version 4.x, Copyright (c) 1996-8 Sebastian Good.~n")

(case mode
  [(compile)
   (require-library "load.ss" "compiler")
   (compiler:load-prefixes prefix-files)
   (map
    (lambda (source-file)
      (define source-directory 
	(let-values ([(base file dir?)
		      (split-path (path->complete-path source-file))])
		    base))
      (s:compile source-file source-directory 'same))
    source-files)]
  [(link)
   (require-library "ld.ss" "compiler")
   (link-multi-file-extension source-files (current-directory))]
  [(zo)
   (require-library "zo.ss" "compiler")
   (require-library "file.ss" "mzscheme" "dynext")
   (let ([file-bases (map
		      (lambda (file)
			(extract-base-filename/ss file 'mzc))
		      source-files)])
     (let ([n (make-namespace)])
       (parameterize ([current-namespace n]) 
	  (map load prefix-files)
	  (for-each
	   (lambda (f b)
	     (let ([zo (append-zo-suffix b)])
	       (compile-to-zo f zo)))
	   source-files file-bases))))]
  [(collection-extension collection-zos)
   (require-library "collection.ss" "make")
   (let* ([cp source-files]
	  [dir (apply collection-path cp)])
     (current-directory dir)
     (current-load-relative-directory dir)
     (let ([info (apply require-library "info.ss" cp)])
       (let ([sses (filter
		    (lambda (s)
		      (regexp-match "\\.(ss|scm)$" s))
		    (directory-list))])
	 (make-collection-extension 
	  (info 'name)
	  (info 'compile-prefix)
	  (remove*
	   (info 'compile-omit-files)
	   sses)
	  (case mode
	    [(collection-extension) #()]
	    [(collection-zos) #("zo")])))))]
  [else (printf "bad mode: ~a~n" mode)])

			   





