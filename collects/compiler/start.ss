
; (require-library "traceld.ss")

(error-print-width 200)

; On error, exit with -1 status code
(error-escape-handler (lambda () (exit -1)))

; Read argv array for arguments and input file name
(require-library "cmdline.ss")
(require-library "options.ss" "compiler")

(define-values (source-files prefix-files)
  (parse-options argv))

(require-library "load.ss" "compiler")

(printf (compiler:banner))

(compiler:load-prefixes prefix-files)

(map

 (lambda (source-file)
   (define source-directory 
     (let-values ([(base file dir?)
		   (split-path (path->complete-path source-file))])
	 base))
   (s:compile source-file source-directory 'same))

 source-files)

